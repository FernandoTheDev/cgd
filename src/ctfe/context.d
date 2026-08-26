module ctfe.context;

import std.stdio;

import frontend.parser.ast : Node;
import frontend.semantic.symbol;
import ctfe;

class CTFEContext
{
    // todas as funções puras compiladas
    VM[dstring] functions;
    SymbolFn[dstring] symbols;

    Node call(dstring name, CGDValue[] params)
    {
        this.functions[name].context.params = params;
        vmHandle(&functions[name]);

        Node node = CTFECompile.cgdValueToNode(this.functions[name].context.ret[0]);
        this.functions[name].pc = 0;

        return node;
    }

    CGDValue callValue(dstring name, CGDValue[] params)
    {
        VM vm;
        vm.instructions = this.functions[name].instructions; // reusa o bytecode
        vm.ctfe = this;
        vm.context.vars = new CGDValue[256]; // vars locais NOVAS pra esse frame
        vm.context.params = params; // args recebidos
        vm.stack = []; // pilha NOVA e vazia
        vm.pc = 0;

        vmHandle(&vm);
        symbols[name].uses--;

        return vm.context.ret[0];
    }
}
