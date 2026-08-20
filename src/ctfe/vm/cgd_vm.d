module ctfe.vm.cgd_vm;

import std.exception;
import std.traits : EnumMembers;

enum CGDTypeKind : ubyte
{
    Inteiro,
    // Real,
    // Texto,
}

struct CGDValue 
{
    CGDTypeKind type;
    union {
        long i;
        // double d;
    }

    static CGDValue inteiro(long n) => CGDValue(CGDTypeKind.Inteiro, n);
}

enum VMOpCode : ubyte 
{
    LoadParam,
    Load,
    Store,
    PushInt,
    // PushReal,
    // PushText,
    // PushBool,
    Add,
    Sub,
    Mul,
    Div,
    Ret,
    Halt,
}

struct VMInstruction 
{
    VMOpCode opCode;
    union {
        size_t param; // para LoadParam
        CGDValue value; // para constantes de comptime
    }

    static VMInstruction instr(VMOpCode op) => VMInstruction(op);
    static VMInstruction instr(VMOpCode op, size_t param) => VMInstruction(op, param: param);
    static VMInstruction instr(VMOpCode op, CGDValue value) => VMInstruction(op, value: value);
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

    CGDValue[] stack;
    size_t pc;

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
    &vmPushInt,
    &vmAdd,
    &vmSub,
    &vmMul,
    &vmDiv,
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

void vmAdd(VMInstruction* instr, VM* vm)
{
    CGDValue right = vm.pop();
    CGDValue left = vm.pop();

    if (left.type == right.type)
    {
        if (left.type == CGDTypeKind.Inteiro)
            vm.push(CGDValue.inteiro(left.i + right.i));
    }

    vmHandle(vm);
}

void vmSub(VMInstruction* instr, VM* vm)
{
    CGDValue right = vm.pop();
    CGDValue left = vm.pop();

    if (left.type == right.type)
    {
        if (left.type == CGDTypeKind.Inteiro)
            vm.push(CGDValue.inteiro(left.i - right.i));
    }

    vmHandle(vm);
}

void vmMul(VMInstruction* instr, VM* vm)
{
    CGDValue right = vm.pop();
    CGDValue left = vm.pop();

    if (left.type == right.type)
    {
        if (left.type == CGDTypeKind.Inteiro)
            vm.push(CGDValue.inteiro(left.i * right.i));
    }

    vmHandle(vm);
}

void vmDiv(VMInstruction* instr, VM* vm)
{
    CGDValue right = vm.pop();
    CGDValue left = vm.pop();

    if (left.type == right.type)
    {
        if (left.type == CGDTypeKind.Inteiro)
            vm.push(CGDValue.inteiro(left.i / right.i));
    }

    vmHandle(vm);
}

void vmPushInt(VMInstruction* instr, VM* vm)
{
    vm.push(instr.value);
    vmHandle(vm);
}

void vmRet(VMInstruction* instr, VM* vm)
{
    if (vm.stack.length > 0)
        vm.context.ret[0] = vm.pop();
    vmHandle(vm);
}

void vmHalt(VMInstruction* instr, VM* vm)
{
    // fim da VM
}

pragma(inline, true)
void vmHandle(VM* vm)
{
    VMInstruction instr = vm.instructions[vm.pc++];
    handlers[instr.opCode](&instr, vm);
}


