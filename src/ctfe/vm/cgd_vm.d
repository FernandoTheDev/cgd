module ctfe.vm.cgd_vm;

import std.traits : EnumMembers;
import core.checkedint : adds, subs, muls, negs;
import std.exception;
import std.stdio;

import backend.c.utils : formatD;
import ctfe.context;

enum CGDTypeKind : ubyte
{
    Inteiro,
    Texto,
    Real,
    Logico,
}

struct CGDValue
{
    CGDTypeKind type;
    union {
        long i;
        dstring s;
        double d;
        bool b1;
    }

    static CGDValue inteiro(long n) => CGDValue(CGDTypeKind.Inteiro, i: n);
    static CGDValue real_(double n) => CGDValue(CGDTypeKind.Real, d: n);
    static CGDValue logico(bool n) => CGDValue(CGDTypeKind.Logico, b1: n);
    static CGDValue texto(dstring n) => CGDValue(CGDTypeKind.Texto, s: n);
}

enum VMOpCode : ubyte
{
    LoadParam,
    Load,
    Store,

    Push,

    Jmp,
    Jz,
    Jnz,

    Add,
    Sub,
    Mul,
    Div,
    IDiv,
    Le,
    Lt,
    Mod,
    Gt,
    Ge,
    Eq,
    Neq,

    BAnd,
    BOr,
    BXor,
    Shl,
    Shr,

    Neg,
    Not,
    BNot,

    Call,
    Ret,

    Halt,
}

struct VMInstruction
{
    VMOpCode opCode;
    size_t param; // para LoadParam
    union {
        CGDValue value; // para constantes de comptime
        dstring str;
    }

    static VMInstruction instr(VMOpCode op) => VMInstruction(op);
    static VMInstruction instr(VMOpCode op, size_t param) => VMInstruction(op, param);
    static VMInstruction instr(VMOpCode op, CGDValue value) => VMInstruction(op, value: value);
    static VMInstruction instr(VMOpCode op, dstring s) => VMInstruction(op, str: s);
}

struct VMContext
{
    CGDValue[] params;
    CGDValue[] vars = new CGDValue[256];
    CGDValue[1] ret;
}

struct VM
{
    VMContext context;
    VMInstruction[] instructions;
    CTFEContext ctfe;

    CGDValue[] stack;
    size_t pc;
    bool executing, halted;

    pragma(inline, true)
    CGDValue pop()
    {
        enforce(stack.length > 0, "Stack underflow.");
        CGDValue value = stack[stack.length - 1UL];
        stack.length--;
        return value;
    }

    pragma(inline, true)
    void push(CGDValue value) nothrow
    {
        stack ~= value;
    }
}

alias VMHandleFn = void function(VMInstruction*, VM*);

enum OpCodes = EnumMembers!VMOpCode;
const VMHandleFn[OpCodes.length] handlers = [
    &vmLoadParam,
    &vmLoad,
    &vmStore,

    &vmPush,

    &vmJmp,
    &vmJz,
    &vmJnz,

    &vmAdd,
    &vmSub,
    &vmMul,
    &vmDiv,
    &vmIDiv,
    &vmLe,
    &vmLt,
    &vmMod,
    &vmGt,
    &vmGe,
    &vmEq,
    &vmNeq,

    &vmBAnd,
    &vmBOr,
    &vmBXor,
    &vmShl,
    &vmShr,

    &vmNeg,
    &vmNot,
    &vmBNot,

    &vmCall,
    &vmRet,

    &vmHalt,
];

// validação
static foreach (size_t i, VMOpCode op; OpCodes)
    static assert(handlers[i] !is null, "Handler ausente para o opcode: " ~ op.stringof);

void vmLoadParam(VMInstruction* instr, VM* vm)
{
    vm.push(vm.context.params[instr.param]);
    vmHandle(vm);
}

void vmLoad(VMInstruction* instr, VM* vm)
{
    vm.push(vm.context.vars[instr.param]);
    vmHandle(vm);
}

void vmStore(VMInstruction* instr, VM* vm)
{
    vm.context.vars[instr.param] = vm.pop();
    vmHandle(vm);
}

void vmPush(VMInstruction* instr, VM* vm)
{
    vm.push(instr.value);
    vmHandle(vm);
}

void vmCall(VMInstruction* instr, VM* vm)
{
    // numero de argumentos
    long numArgs = vm.pop().i;
    dstring name = instr.str;

    CGDValue[] args;
    foreach (i; 0..numArgs)
        args ~= vm.pop();

    size_t pc = vm.pc;
    vm.push(vm.ctfe.callValue(name, args));
    vm.pc = pc;

    vmHandle(vm);
}

void vmRet(VMInstruction* instr, VM* vm)
{
    if (vm.stack.length > 0)
        vm.context.ret[0] = vm.pop();
    vm.halted = true;
    // vmHandle(vm);
}

void vmJmp(VMInstruction* instr, VM* vm)
{
    vm.pc = instr.param;
    vmHandle(vm);
}

void vmJz(VMInstruction* instr, VM* vm)
{
    CGDValue cond = vm.pop();
    if (!isTruthy(cond))
        vm.pc = instr.param;
    vmHandle(vm);
}

void vmJnz(VMInstruction* instr, VM* vm)
{
    CGDValue cond = vm.pop();
    if (isTruthy(cond))
        vm.pc = instr.param;
    vmHandle(vm);
}

pragma(inline, true)
private long coerceToInteiro(CGDValue v)
{
    final switch (v.type)
    {
        case CGDTypeKind.Inteiro: return v.i;
        case CGDTypeKind.Real:    return cast(long) v.d;
        case CGDTypeKind.Logico:  return v.b1 ? 1 : 0;
        case CGDTypeKind.Texto:
            throw new Exception("operador bitwise nao suporta Texto");
    }
}

pragma(inline, true)
private bool isTruthy(CGDValue v)
{
    final switch (v.type)
    {
        case CGDTypeKind.Logico:  return v.b1;
        case CGDTypeKind.Inteiro:
        case CGDTypeKind.Real:
        case CGDTypeKind.Texto: return true;
    }
}

void vmAdd(VMInstruction* instr, VM* vm)
{
    CGDValue right = vm.pop();
    CGDValue left = vm.pop();
    promote(left, right);

    final switch (left.type)
    {
        case CGDTypeKind.Inteiro:
            bool overflow;
            auto result = adds(left.i, right.i, overflow);
            enforce(!overflow, "Overflow inteiro em tempo de compilação.");
            vm.push(CGDValue.inteiro(result));
            break;

        case CGDTypeKind.Real:
            vm.push(CGDValue.real_(left.d + right.d));
            break;

        case CGDTypeKind.Texto:
            vm.push(CGDValue.texto(left.s ~ right.s));
            break;

        case CGDTypeKind.Logico:
            throw new Exception("operador + nao suportado entre Logico e Logico");
    }

    vmHandle(vm);
}

void vmSub(VMInstruction* instr, VM* vm)
{
    CGDValue right = vm.pop();
    CGDValue left = vm.pop();
    promote(left, right);

    final switch (left.type)
    {
        case CGDTypeKind.Inteiro:
            bool overflow;
            auto result = subs(left.i, right.i, overflow);
            enforce(!overflow, "Overflow inteiro em tempo de compilação.");
            vm.push(CGDValue.inteiro(result));
            break;

        case CGDTypeKind.Real:
            vm.push(CGDValue.real_(left.d - right.d));
            break;

        case CGDTypeKind.Texto:
            throw new Exception("operador - nao suportado para Texto");

        case CGDTypeKind.Logico:
            throw new Exception("operador - nao suportado para Logico");
    }

    vmHandle(vm);
}

void vmMul(VMInstruction* instr, VM* vm)
{
    CGDValue right = vm.pop();
    CGDValue left = vm.pop();
    promote(left, right);

    final switch (left.type)
    {
        case CGDTypeKind.Inteiro:
            bool overflow;
            auto result = muls(left.i, right.i, overflow);
            enforce(!overflow, "Overflow inteiro em tempo de compilação.");
            vm.push(CGDValue.inteiro(result));
            break;

        case CGDTypeKind.Real:
            vm.push(CGDValue.real_(left.d * right.d));
            break;

        case CGDTypeKind.Texto:
            throw new Exception("operador * nao suportado para Texto");

        case CGDTypeKind.Logico:
            throw new Exception("operador * nao suportado para Logico");
    }

    vmHandle(vm);
}

void vmDiv(VMInstruction* instr, VM* vm)
{
    CGDValue right = vm.pop();
    CGDValue left = vm.pop();
    promote(left, right);

    final switch (left.type)
    {
        case CGDTypeKind.Inteiro:
            enforce(right.i != 0, "Divisão por zero em tempo de compilação.");
            enforce(left.i != long.min || right.i != -1, "Overflow na divisão em tempo de compilação.");
            vm.push(left.i % right.i == 0 ? CGDValue.inteiro(left.i / right.i)
                : CGDValue.real_(cast(double)left.i / right.i));
            break;

        case CGDTypeKind.Real:
            enforce(right.d != 0, "Divisão por zero em tempo de compilação.");
            vm.push(CGDValue.real_(left.d / right.d));
            break;

        case CGDTypeKind.Texto:
            throw new Exception("operador / nao suportado para Texto");

        case CGDTypeKind.Logico:
            throw new Exception("operador / nao suportado para Logico");
    }

    vmHandle(vm);
}

void vmIDiv(VMInstruction* instr, VM* vm)
{
    auto right = vm.pop(), left = vm.pop();
    promote(left, right);
    if (left.type == CGDTypeKind.Inteiro)
    {
        enforce(right.i != 0 && (left.i != long.min || right.i != -1), "Divisão inteira inválida em tempo de compilação.");
        vm.push(CGDValue.inteiro(left.i / right.i));
    }
    else if (left.type == CGDTypeKind.Real)
    {
        auto result = left.d / right.d;
        enforce(right.d != 0 && result >= cast(double)long.min && result < 9223372036854775808.0,
            "Divisão inteira fora do intervalo em tempo de compilação.");
        vm.push(CGDValue.inteiro(cast(long)result));
    }
    else throw new Exception("Divisão inteira exige números.");
    vmHandle(vm);
}

void vmMod(VMInstruction* instr, VM* vm)
{
    CGDValue right = vm.pop();
    CGDValue left = vm.pop();
    promote(left, right);

    final switch (left.type)
    {
        case CGDTypeKind.Inteiro:
            enforce(right.i != 0, "Módulo por zero em tempo de compilação.");
            vm.push(CGDValue.inteiro(left.i == long.min && right.i == -1 ? 0 : left.i % right.i));
            break;

        case CGDTypeKind.Real:
            vm.push(CGDValue.real_(left.d % right.d));
            break;

        case CGDTypeKind.Texto:
            throw new Exception("operador % nao suportado para Texto");

        case CGDTypeKind.Logico:
            throw new Exception("operador % nao suportado para Logico");
    }

    vmHandle(vm);
}

void vmLt(VMInstruction* instr, VM* vm)
{
    CGDValue right = vm.pop();
    CGDValue left = vm.pop();
    promote(left, right);

    final switch (left.type)
    {
        case CGDTypeKind.Inteiro:
            vm.push(CGDValue.logico(left.i < right.i));
            break;

        case CGDTypeKind.Real:
            vm.push(CGDValue.logico(left.d < right.d));
            break;

        case CGDTypeKind.Texto:
            throw new Exception("operador < nao suportado para Texto");

        case CGDTypeKind.Logico:
            throw new Exception("operador < nao suportado para Logico");
    }

    vmHandle(vm);
}

void vmLe(VMInstruction* instr, VM* vm)
{
    CGDValue right = vm.pop();
    CGDValue left = vm.pop();
    promote(left, right);

    final switch (left.type)
    {
        case CGDTypeKind.Inteiro:
            vm.push(CGDValue.logico(left.i <= right.i));
            break;

        case CGDTypeKind.Real:
            vm.push(CGDValue.logico(left.d <= right.d));
            break;

        case CGDTypeKind.Texto:
            throw new Exception("operador <= nao suportado para Texto");

        case CGDTypeKind.Logico:
            throw new Exception("operador <= nao suportado para Logico");
    }

    vmHandle(vm);
}

void vmGt(VMInstruction* instr, VM* vm)
{
    CGDValue right = vm.pop();
    CGDValue left = vm.pop();
    promote(left, right);

    final switch (left.type)
    {
        case CGDTypeKind.Inteiro:
            vm.push(CGDValue.logico(left.i > right.i));
            break;

        case CGDTypeKind.Real:
            vm.push(CGDValue.logico(left.d > right.d));
            break;

        case CGDTypeKind.Texto:
            throw new Exception("operador > nao suportado para Texto");

        case CGDTypeKind.Logico:
            throw new Exception("operador > nao suportado para Logico");
    }

    vmHandle(vm);
}

void vmGe(VMInstruction* instr, VM* vm)
{
    CGDValue right = vm.pop();
    CGDValue left = vm.pop();
    promote(left, right);

    final switch (left.type)
    {
        case CGDTypeKind.Inteiro:
            vm.push(CGDValue.logico(left.i >= right.i));
            break;

        case CGDTypeKind.Real:
            vm.push(CGDValue.logico(left.d >= right.d));
            break;

        case CGDTypeKind.Texto:
            throw new Exception("operador >= nao suportado para Texto");

        case CGDTypeKind.Logico:
            throw new Exception("operador >= nao suportado para Logico");
    }

    vmHandle(vm);
}

void vmEq(VMInstruction* instr, VM* vm)
{
    CGDValue right = vm.pop();
    CGDValue left = vm.pop();
    promote(left, right);

    final switch (left.type)
    {
        case CGDTypeKind.Inteiro:
            vm.push(CGDValue.logico(left.i == right.i));
            break;

        case CGDTypeKind.Real:
            vm.push(CGDValue.logico(left.d == right.d));
            break;

        case CGDTypeKind.Texto:
            vm.push(CGDValue.logico(left.s == right.s));
            break;

        case CGDTypeKind.Logico:
            vm.push(CGDValue.logico(left.b1 == right.b1));
            break;
    }

    vmHandle(vm);
}

void vmNeq(VMInstruction* instr, VM* vm)
{
    CGDValue right = vm.pop();
    CGDValue left = vm.pop();
    promote(left, right);

    final switch (left.type)
    {
        case CGDTypeKind.Inteiro:
            vm.push(CGDValue.logico(left.i != right.i));
            break;

        case CGDTypeKind.Real:
            vm.push(CGDValue.logico(left.d != right.d));
            break;

        case CGDTypeKind.Texto:
            vm.push(CGDValue.logico(left.s != right.s));
            break;

        case CGDTypeKind.Logico:
            vm.push(CGDValue.logico(left.b1 != right.b1));
            break;
    }

    vmHandle(vm);
}

void vmBAnd(VMInstruction* instr, VM* vm)
{
    CGDValue right = vm.pop();
    CGDValue left = vm.pop();

    long l = coerceToInteiro(left);
    long r = coerceToInteiro(right);

    vm.push(CGDValue.inteiro(l & r));
    vmHandle(vm);
}

void vmBOr(VMInstruction* instr, VM* vm)
{
    CGDValue right = vm.pop();
    CGDValue left = vm.pop();

    long l = coerceToInteiro(left);
    long r = coerceToInteiro(right);

    vm.push(CGDValue.inteiro(l | r));
    vmHandle(vm);
}

void vmBXor(VMInstruction* instr, VM* vm)
{
    CGDValue right = vm.pop();
    CGDValue left = vm.pop();

    long l = coerceToInteiro(left);
    long r = coerceToInteiro(right);

    vm.push(CGDValue.inteiro(l ^ r));
    vmHandle(vm);
}

void vmShl(VMInstruction* instr, VM* vm)
{
    CGDValue right = vm.pop();
    CGDValue left = vm.pop();

    long l = coerceToInteiro(left);
    long r = coerceToInteiro(right);
    enforce(r >= 0 && r < 64, "Deslocamento deve estar entre 0 e 63.");

    vm.push(CGDValue.inteiro(l << r));
    vmHandle(vm);
}

void vmShr(VMInstruction* instr, VM* vm)
{
    CGDValue right = vm.pop();
    CGDValue left = vm.pop();

    long l = coerceToInteiro(left);
    long r = coerceToInteiro(right);
    enforce(r >= 0 && r < 64, "Deslocamento deve estar entre 0 e 63.");

    vm.push(CGDValue.inteiro(l >> r));
    vmHandle(vm);
}

void vmNeg(VMInstruction* instr, VM* vm)
{
    CGDValue v = vm.pop();

    final switch (v.type)
    {
        case CGDTypeKind.Inteiro:
            enforce(v.i != long.min, "Overflow na negação em tempo de compilação.");
            vm.push(CGDValue.inteiro(-v.i));
            break;

        case CGDTypeKind.Real:
            vm.push(CGDValue.real_(-v.d));
            break;

        case CGDTypeKind.Texto:
            throw new Exception("operador unario - nao suportado para Texto");

        case CGDTypeKind.Logico:
            throw new Exception("operador unario - nao suportado para Logico");
    }

    vmHandle(vm);
}

void vmNot(VMInstruction* instr, VM* vm)
{
    CGDValue v = vm.pop();

    final switch (v.type)
    {
        case CGDTypeKind.Logico:
            vm.push(CGDValue.logico(!v.b1));
            break;

        case CGDTypeKind.Inteiro:
        case CGDTypeKind.Real:
        case CGDTypeKind.Texto:
            vm.push(CGDValue.logico(!isTruthy(v)));
            break;
    }

    vmHandle(vm);
}

void vmBNot(VMInstruction* instr, VM* vm)
{
    CGDValue v = vm.pop();
    long l = coerceToInteiro(v);

    vm.push(CGDValue.inteiro(~l));
    vmHandle(vm);
}

void vmHalt(VMInstruction* instr, VM* vm)
{
    vm.halted = true;
}

pragma(inline, true)
void vmHandle(VM* vm)
{
    if (vm.executing) return;
    vm.executing = true;
    scope(exit) vm.executing = false;
    while (!vm.halted)
    {
        vm.ctfe.consumeInstruction();
        enforce(vm.pc < vm.instructions.length, "Bytecode inválido: fim inesperado da função.");
        VMInstruction instr = vm.instructions[vm.pc++];
        handlers[instr.opCode](&instr, vm);
    }
}

pragma(inline, true)
void promote(ref CGDValue left, ref CGDValue right)
{
    // Nunca promove pra Texto implicitamente em operação binária mista —
    // isso é decisão de mais alto nível (concatenação/interpolação), não
    // coerção aritmética/lógica. Se um dos dois já é Texto, os dois viram Texto,
    // mas de forma simétrica e explícita.
    if (left.type == CGDTypeKind.Texto || right.type == CGDTypeKind.Texto)
    {
        if (left.type != CGDTypeKind.Texto)  left = toTexto(left);
        if (right.type != CGDTypeKind.Texto) right = toTexto(right);
        return;
    }

    final switch (left.type)
    {
        case CGDTypeKind.Inteiro:
            final switch (right.type)
            {
                case CGDTypeKind.Inteiro:
                    return;

                case CGDTypeKind.Real:
                    left = CGDValue.real_(cast(double) left.i);
                    return;

                case CGDTypeKind.Logico:
                    right = CGDValue.inteiro(right.b1 ? 1 : 0);
                    return;

                case CGDTypeKind.Texto:
                    return;
            }

        case CGDTypeKind.Real:
            final switch (right.type)
            {
                case CGDTypeKind.Inteiro:
                    right = CGDValue.real_(cast(double) right.i);
                    return;

                case CGDTypeKind.Real:
                    return;

                case CGDTypeKind.Logico:
                    right = CGDValue.real_(right.b1 ? 1.0 : 0.0);
                    return;

                case CGDTypeKind.Texto:
                    return;
            }

        case CGDTypeKind.Logico:
            final switch (right.type)
            {
                case CGDTypeKind.Inteiro:
                    left = CGDValue.inteiro(left.b1 ? 1 : 0);
                    return;

                case CGDTypeKind.Real:
                    left = CGDValue.real_(left.b1 ? 1.0 : 0.0);
                    return;

                case CGDTypeKind.Logico:
                    return;

                case CGDTypeKind.Texto:
                    return;
            }

        case CGDTypeKind.Texto:
            return;
    }
}

private CGDValue toTexto(ref CGDValue v)
{
    final switch (v.type)
    {
        case CGDTypeKind.Inteiro: return CGDValue.texto(formatD("%d", v.i));
        case CGDTypeKind.Real:    return CGDValue.texto(formatD("%f", v.d));
        case CGDTypeKind.Logico:  return CGDValue.texto(v.b1 ? "verdadeiro" : "falso");
        case CGDTypeKind.Texto:   return v;
    }
}

