module ctfe.vm.cgd_vm;

import std.traits : EnumMembers;
import core.checkedint : adds, subs, muls, negs;
import std.exception;
import std.stdio;

import ctfe.context;

enum CGDTypeKind : ubyte
{
    Inteiro,
    Texto,
    Real,
    Logico,
    Vetor,
}

struct CGDValue
{
    CGDTypeKind type;
    union
    {
        long i;
        dstring s;
        double d;
        bool b1;
        CGDValue[] arr;
    }

    static CGDValue inteiro(long n)
    {
        CGDValue v;
        v.type = CGDTypeKind.Inteiro;
        v.i = n;
        return v;
    }

    static CGDValue real_(double n)
    {
        CGDValue v;
        v.type = CGDTypeKind.Real;
        v.d = n;
        return v;
    }

    static CGDValue logico(bool n)
    {
        CGDValue v;
        v.type = CGDTypeKind.Logico;
        v.b1 = n;
        return v;
    }

    static CGDValue texto(dstring n)
    {
        CGDValue v;
        v.type = CGDTypeKind.Texto;
        v.s = n;
        return v;
    }

    static CGDValue vetor(CGDValue[] elems)
    {
        CGDValue v;
        v.type = CGDTypeKind.Vetor;
        v.arr = elems;
        return v;
    }
}

enum VMOpCode : ubyte
{
    LoadParam,
    Load,
    Store,
    Validate,

    Push,

    Jmp,
    Jz,
    Jnz,

    Add,
    Sub,
    Mul,
    Div,
    IDiv,
    Pow,
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

    MakeArray,
    IndexGet,
    Dup,

    Call,
    Ret,

    Halt,
    Drop,
}

struct VMInstruction
{
    VMOpCode opCode;
    size_t param; // para LoadParam
    union
    {
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
    CGDValue[] vars;
    CGDValue[1] ret;
}

struct VM
{
    VMContext context;
    VMInstruction[] instructions;
    CTFEContext ctfe;

    CGDValue[] stack;
    size_t pc;
    bool executing, halted, returned;

    pragma(inline, true) CGDValue pop()
    {
        enforce(stack.length > 0, "Stack underflow.");
        CGDValue value = stack[stack.length - 1UL];
        stack[$ - 1] = CGDValue.init;
        stack.length--;
        return value;
    }

    pragma(inline, true) void push(CGDValue value)
    {
        if (stack.length >= 16_384)
            throw new CTFELimitException("Limite de operandos na avaliação em tempo de compilação.");
        if (value.type == CGDTypeKind.Texto && value.s.length > 1_048_576)
            throw new CTFELimitException("Limite de texto na avaliação em tempo de compilação.");
        stack ~= value;
    }
}

alias VMHandleFn = void function(VMInstruction*, VM*);

enum VMOpCode[] OpCodes = [EnumMembers!VMOpCode];
const VMHandleFn[OpCodes.length] handlers = [
    &vmLoadParam, &vmLoad, &vmStore, &vmValidate, &vmPush, &vmJmp, &vmJz, &vmJnz, &vmAdd,
    &vmSub, &vmMul, &vmDiv, &vmIDiv, &vmPow, &vmLe, &vmLt, &vmMod, &vmGt, &vmGe, &vmEq, &vmNeq,
    &vmBAnd, &vmBOr, &vmBXor, &vmShl, &vmShr, &vmNeg, &vmNot, &vmBNot, &vmMakeArray, &vmIndexGet,
    &vmDup, &vmCall, &vmRet, &vmHalt, &vmDrop,
];

// validação
static foreach (size_t i, VMOpCode op; OpCodes)
    static assert(handlers[i]!is null, "Handler ausente para o opcode: " ~ op.stringof);

void vmDrop(VMInstruction* instr, VM* vm)
{
    vm.pop();
}

void vmValidate(VMInstruction* instr, VM* vm)
{
    enforce(vm.stack.length > 0, "CTFE: validação sem valor.");
    validateCTFEValue(vm.stack[$ - 1], instr.str);
}

void vmLoadParam(VMInstruction* instr, VM* vm)
{
    vm.push(vm.context.params[instr.param]);
}

void vmLoad(VMInstruction* instr, VM* vm)
{
    vm.push(vm.context.vars[instr.param]);
}

void vmStore(VMInstruction* instr, VM* vm)
{
    vm.context.vars[instr.param] = vm.pop();
}

void vmPush(VMInstruction* instr, VM* vm)
{
    vm.push(instr.value);
}

void vmCall(VMInstruction* instr, VM* vm)
{
    // numero de argumentos
    long numArgs = vm.pop().i;
    dstring name = instr.str;

    CGDValue[] args;
    foreach (long i; 0 .. numArgs)
        args ~= vm.pop();

    size_t pc = vm.pc;
    vm.push(vm.ctfe.callValue(name, args));
    vm.pc = pc;

}

void vmRet(VMInstruction* instr, VM* vm)
{
    enforce(vm.stack.length > 0, "CTFE: retorno sem valor representável.");
    vm.context.ret[0] = vm.pop();
    vm.returned = true;
    vm.halted = true;
    // vmHandle(vm);
}

void vmJmp(VMInstruction* instr, VM* vm)
{
    vm.pc = instr.param;
}

void vmJz(VMInstruction* instr, VM* vm)
{
    CGDValue cond = vm.pop();
    if (!isTruthy(cond))
        vm.pc = instr.param;
}

void vmJnz(VMInstruction* instr, VM* vm)
{
    CGDValue cond = vm.pop();
    if (isTruthy(cond))
        vm.pc = instr.param;
}

pragma(inline, true) private long coerceToInteiro(CGDValue v)
{
    final switch (v.type)
    {
        case CGDTypeKind.Inteiro:
            return v.i;
        case CGDTypeKind.Real:
            import std.math : isFinite;

            enforce(isFinite(v.d) && v.d >= cast(double) long.min && v.d < 9223372036854775808.0,
                    "Conversão bit a bit fora do intervalo em CTFE.");
            return cast(long) v.d;
        case CGDTypeKind.Logico:
            return v.b1 ? 1 : 0;
        case CGDTypeKind.Texto:
        case CGDTypeKind.Vetor:
            throw new Exception("operador bitwise nao suporta Texto/Vetor");
    }
}

pragma(inline, true) private bool isTruthy(CGDValue v)
{
    final switch (v.type)
    {
        case CGDTypeKind.Logico:
            return v.b1;
        case CGDTypeKind.Inteiro:
        case CGDTypeKind.Real:
        case CGDTypeKind.Texto:
        case CGDTypeKind.Vetor:
            return true;
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
            long result = adds(left.i, right.i, overflow);
            enforce(!overflow, "Overflow inteiro em tempo de compilação.");
            vm.push(CGDValue.inteiro(result));
            break;

        case CGDTypeKind.Real:
            vm.push(CGDValue.real_(left.d + right.d));
            break;

        case CGDTypeKind.Texto:
            if (left.s.length > 1_048_576
                    || right.s.length > 1_048_576 - left.s.length)
                throw new CTFELimitException(
                        "Limite de texto na avaliação em tempo de compilação.");
            vm.push(CGDValue.texto(left.s ~ right.s));
            break;

        case CGDTypeKind.Logico:
        case CGDTypeKind.Vetor:
            throw new Exception("operador + nao suportado para este tipo");
    }

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
            long result = subs(left.i, right.i, overflow);
            enforce(!overflow, "Overflow inteiro em tempo de compilação.");
            vm.push(CGDValue.inteiro(result));
            break;

        case CGDTypeKind.Real:
            vm.push(CGDValue.real_(left.d - right.d));
            break;

        case CGDTypeKind.Texto:
        case CGDTypeKind.Vetor:
            throw new Exception("operador - nao suportado para Texto/Vetor");

        case CGDTypeKind.Logico:
            throw new Exception("operador - nao suportado para Logico");
    }

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
            long result = muls(left.i, right.i, overflow);
            enforce(!overflow, "Overflow inteiro em tempo de compilação.");
            vm.push(CGDValue.inteiro(result));
            break;

        case CGDTypeKind.Real:
            vm.push(CGDValue.real_(left.d * right.d));
            break;

        case CGDTypeKind.Texto:
        case CGDTypeKind.Vetor:
            throw new Exception("operador * nao suportado para Texto/Vetor");

        case CGDTypeKind.Logico:
            throw new Exception("operador * nao suportado para Logico");
    }

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
            vm.push(left.i % right.i == 0 ? CGDValue.inteiro(left.i / right.i) : CGDValue.real_(
                    cast(double) left.i / right.i));
            break;

        case CGDTypeKind.Real:
            enforce(right.d != 0, "Divisão por zero em tempo de compilação.");
            vm.push(CGDValue.real_(left.d / right.d));
            break;

        case CGDTypeKind.Texto:
        case CGDTypeKind.Vetor:
            throw new Exception("operador / nao suportado para Texto/Vetor");

        case CGDTypeKind.Logico:
            throw new Exception("operador / nao suportado para Logico");
    }

}

void vmIDiv(VMInstruction* instr, VM* vm)
{
    CGDValue right = vm.pop(), left = vm.pop();
    promote(left, right);
    if (left.type == CGDTypeKind.Inteiro)
    {
        enforce(right.i != 0 && (left.i != long.min || right.i != -1),
                "Divisão inteira inválida em tempo de compilação.");
        vm.push(CGDValue.inteiro(left.i / right.i));
    }
    else if (left.type == CGDTypeKind.Real)
    {
        double result = left.d / right.d;
        enforce(right.d != 0 && result >= cast(double) long.min && result < 9223372036854775808.0,
                "Divisão inteira fora do intervalo em tempo de compilação.");
        vm.push(CGDValue.inteiro(cast(long) result));
    }
    else
        throw new Exception("Divisão inteira exige números.");
}

void vmPow(VMInstruction* instr, VM* vm)
{
    import std.math : pow, isFinite;

    CGDValue right = vm.pop();
    CGDValue left = vm.pop();
    promote(left, right);
    if (left.type == CGDTypeKind.Inteiro && right.i >= 0 && right.i <= 62)
    {
        long acc = 1;
        long base = left.i;
        long exp = right.i;
        while (exp > 0)
        {
            if (exp & 1)
            {
                bool ov;
                acc = muls(acc, base, ov);
                enforce(!ov, "Overflow na potência inteira em CTFE.");
            }
            exp >>= 1;
            if (exp > 0)
            {
                bool ov;
                base = muls(base, base, ov);
                enforce(!ov, "Overflow na potência inteira em CTFE.");
            }
        }
        vm.push(CGDValue.inteiro(acc));
        return;
    }
    if (left.type == CGDTypeKind.Inteiro || left.type == CGDTypeKind.Real)
    {
        double lv = left.type == CGDTypeKind.Real ? left.d : cast(double) left.i;
        double rv = right.type == CGDTypeKind.Real ? right.d : cast(double) right.i;
        double res = pow(lv, rv);
        enforce(isFinite(res), "Potência não finita em CTFE.");
        vm.push(CGDValue.real_(res));
        return;
    }
    throw new Exception("operador ** exige números em CTFE.");
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
            throw new Exception("Módulo real não é suportado pelo runtime.");

        case CGDTypeKind.Texto:
        case CGDTypeKind.Vetor:
            throw new Exception("operador % nao suportado para Texto/Vetor");

        case CGDTypeKind.Logico:
            throw new Exception("operador % nao suportado para Logico");
    }

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
            vm.push(CGDValue.logico(left.s < right.s));
            break;

        case CGDTypeKind.Logico:
        case CGDTypeKind.Vetor:
            throw new Exception("operador < nao suportado para Logico/Vetor");
    }

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
            vm.push(CGDValue.logico(left.s <= right.s));
            break;

        case CGDTypeKind.Logico:
        case CGDTypeKind.Vetor:
            throw new Exception("operador <= nao suportado para Logico/Vetor");
    }

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
            vm.push(CGDValue.logico(left.s > right.s));
            break;

        case CGDTypeKind.Logico:
        case CGDTypeKind.Vetor:
            throw new Exception("operador > nao suportado para Logico/Vetor");
    }

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
            vm.push(CGDValue.logico(left.s >= right.s));
            break;

        case CGDTypeKind.Logico:
        case CGDTypeKind.Vetor:
            throw new Exception("operador >= nao suportado para Logico/Vetor");
    }

}

void vmEq(VMInstruction* instr, VM* vm)
{
    CGDValue right = vm.pop();
    CGDValue left = vm.pop();
    bool numericLeft = left.type == CGDTypeKind.Inteiro || left.type == CGDTypeKind.Real;
    bool numericRight = right.type == CGDTypeKind.Inteiro || right.type == CGDTypeKind.Real;
    if (left.type != right.type && !(numericLeft && numericRight))
    {
        vm.push(CGDValue.logico(false));
        return;
    }
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

        case CGDTypeKind.Vetor:
            throw new Exception("Comparação direta de vetores preservada para runtime.");
    }

}

void vmNeq(VMInstruction* instr, VM* vm)
{
    CGDValue right = vm.pop();
    CGDValue left = vm.pop();
    bool numericLeft = left.type == CGDTypeKind.Inteiro || left.type == CGDTypeKind.Real;
    bool numericRight = right.type == CGDTypeKind.Inteiro || right.type == CGDTypeKind.Real;
    if (left.type != right.type && !(numericLeft && numericRight))
    {
        vm.push(CGDValue.logico(true));
        return;
    }
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

        case CGDTypeKind.Vetor:
            throw new Exception("Comparação direta de vetores preservada para runtime.");
    }

}

void vmBAnd(VMInstruction* instr, VM* vm)
{
    CGDValue right = vm.pop();
    CGDValue left = vm.pop();

    long l = coerceToInteiro(left);
    long r = coerceToInteiro(right);

    vm.push(CGDValue.inteiro(l & r));
}

void vmBOr(VMInstruction* instr, VM* vm)
{
    CGDValue right = vm.pop();
    CGDValue left = vm.pop();

    long l = coerceToInteiro(left);
    long r = coerceToInteiro(right);

    vm.push(CGDValue.inteiro(l | r));
}

void vmBXor(VMInstruction* instr, VM* vm)
{
    CGDValue right = vm.pop();
    CGDValue left = vm.pop();

    long l = coerceToInteiro(left);
    long r = coerceToInteiro(right);

    vm.push(CGDValue.inteiro(l ^ r));
}

void vmShl(VMInstruction* instr, VM* vm)
{
    CGDValue right = vm.pop();
    CGDValue left = vm.pop();
    enforce(left.type == CGDTypeKind.Inteiro && right.type == CGDTypeKind.Inteiro,
            "Deslocamento esquerdo exige inteiros, como no runtime.");

    long l = coerceToInteiro(left);
    long r = coerceToInteiro(right);
    enforce(r >= 0 && r < 64, "Deslocamento deve estar entre 0 e 63.");

    vm.push(CGDValue.inteiro(l << r));
}

void vmShr(VMInstruction* instr, VM* vm)
{
    CGDValue right = vm.pop();
    CGDValue left = vm.pop();

    long l = coerceToInteiro(left);
    long r = coerceToInteiro(right);
    enforce(r >= 0 && r < 64, "Deslocamento deve estar entre 0 e 63.");

    vm.push(CGDValue.inteiro(l >> r));
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
        case CGDTypeKind.Vetor:
            throw new Exception("operador unario - nao suportado para Texto/Vetor");

        case CGDTypeKind.Logico:
            throw new Exception("operador unario - nao suportado para Logico");
    }

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
        case CGDTypeKind.Vetor:
            vm.push(CGDValue.logico(!isTruthy(v)));
            break;
    }

}

void vmBNot(VMInstruction* instr, VM* vm)
{
    CGDValue v = vm.pop();
    enforce(v.type == CGDTypeKind.Inteiro, "Negação bit a bit exige inteiro, como no runtime.");
    long l = coerceToInteiro(v);

    vm.push(CGDValue.inteiro(~l));
}

void vmMakeArray(VMInstruction* instr, VM* vm)
{
    size_t count = instr.param;
    if (count > 4096)
        throw new CTFELimitException("Limite de elementos de vetor constante na CTFE excedido.");
    CGDValue[] elems = new CGDValue[count];
    foreach_reverse (size_t i; 0 .. count)
        elems[i] = vm.pop();
    vm.push(CGDValue.vetor(elems));
}

void vmIndexGet(VMInstruction* instr, VM* vm)
{
    CGDValue idxVal = vm.pop();
    CGDValue container = vm.pop();
    enforce(idxVal.type == CGDTypeKind.Inteiro, "Índice em CTFE exige inteiro.");
    long idx = idxVal.i;
    if (container.type == CGDTypeKind.Vetor)
    {
        long len = cast(long) container.arr.length;
        if (idx < 0)
            idx += len;
        enforce(idx >= 0 && idx < len, "Índice fora dos limites em vetor constante CTFE.");
        vm.push(container.arr[cast(size_t) idx]);
        return;
    }
    if (container.type == CGDTypeKind.Texto)
    {
        long len = cast(long) container.s.length;
        if (idx < 0)
            idx += len;
        enforce(idx >= 0 && idx < len, "Índice fora dos limites em texto constante CTFE.");
        dchar ch = container.s[cast(size_t) idx];
        vm.push(CGDValue.texto([ch].idup));
        return;
    }
    throw new Exception("Indexação em CTFE exige vetor ou texto.");
}

void vmDup(VMInstruction* instr, VM* vm)
{
    enforce(vm.stack.length > 0, "CTFE: pilha vazia em Dup.");
    vm.push(vm.stack[$ - 1]);
}

void vmHalt(VMInstruction* instr, VM* vm)
{
    vm.halted = true;
}

pragma(inline, true) void vmHandle(VM* vm)
{
    if (vm.executing)
        return;
    vm.executing = true;
    scope (exit)
        vm.executing = false;
    while (!vm.halted)
    {
        vm.ctfe.consumeInstruction();
        enforce(vm.pc < vm.instructions.length, "Bytecode inválido: fim inesperado da função.");
        VMInstruction instr = vm.instructions[vm.pc++];
        handlers[instr.opCode](&instr, vm);
    }
}

pragma(inline, true) void promote(ref CGDValue left, ref CGDValue right)
{
    if (left.type == CGDTypeKind.Vetor || right.type == CGDTypeKind.Vetor)
        return;
    // A formatação de valores mistos usa o runtime; não aproxime sua representação.
    if ((left.type == CGDTypeKind.Texto || right.type == CGDTypeKind.Texto) && left.type != right.type)
        throw new Exception("Conversão textual mista preservada para execução nativa.");

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
                case CGDTypeKind.Vetor:
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
                case CGDTypeKind.Vetor:
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
                case CGDTypeKind.Vetor:
                    return;
            }

        case CGDTypeKind.Texto:
        case CGDTypeKind.Vetor:
            return;
    }
}
