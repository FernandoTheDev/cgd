module ctfe.context;

import std.stdio;

import frontend.parser.ast : Node;
import frontend.semantic.symbol;
import ctfe;

class CTFELimitException : Exception
{
    this(string message) { super(message); }
}

class CTFEContext
{
    // todas as funções puras compiladas
    VM[dstring] functions;
    SymbolFn[dstring] symbols;

    size_t depth;
    size_t remainingInstructions;

    void consumeInstruction()
    {
        import std.exception : enforce;
        if (!remainingInstructions) throw new CTFELimitException("Limite de instruções em tempo de compilação.");
        remainingInstructions--;
    }

    Node call(dstring name, CGDValue[] params)
    {
        remainingInstructions = 10_000_000;
        return CTFECompile.cgdValueToNode(callValue(name, params));
    }

    CGDValue callValue(dstring name, CGDValue[] params)
    {
        import std.exception : enforce;
        if (depth >= 128) throw new CTFELimitException("Limite de recursão em tempo de compilação.");
        enforce(name in functions, "Função indisponível na avaliação em tempo de compilação.");
        depth++;
        scope(exit) depth--;
        VM vm;
        vm.instructions = functions[name].instructions;
        vm.ctfe = this;
        size_t locals = 0;
        foreach (instruction; vm.instructions)
            if (instruction.opCode == VMOpCode.Store || instruction.opCode == VMOpCode.Load)
            {
                enforce(instruction.param < 100_000, "Limite de variáveis locais na avaliação em tempo de compilação excedido.");
                if (instruction.param >= locals) locals = instruction.param + 1;
            }
        vm.context.vars = new CGDValue[locals];
        vm.context.params = params;
        vmHandle(&vm);
        return vm.context.ret[0];
    }
}
