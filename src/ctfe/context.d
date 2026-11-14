module ctfe.context;
import frontend.parser.ast : FnDecl, FnArg;

import std.stdio;

import frontend.parser.ast : Node;
import frontend.semantic.symbol;
import ctfe;

class CTFELimitException : Exception
{
    this(string message)
    {
        super(message);
    }
}

/// Mesmo conjunto primitivo aceito pelos descritores do runtime; tipos sem
/// representação na VM fazem fallback em vez de contornar o contrato.
void validateCTFEValue(CGDValue value, dstring type)
{
    import std.exception : enforce;

    bool compatible;
    switch (type)
    {
        case "qualquer":
        case "Objeto":
            compatible = true;
            break;
        case "numero":
        case "número":
        case "real":
        case "decimal":
            compatible = value.type == CGDTypeKind.Inteiro || value.type == CGDTypeKind.Real;
            break;
        case "inteiro":
        case "longo":
            compatible = value.type == CGDTypeKind.Inteiro;
            break;
        case "texto":
            compatible = value.type == CGDTypeKind.Texto;
            break;
        case "logico":
        case "lógico":
        case "booleano":
        case "binario":
        case "binário":
            compatible = value.type == CGDTypeKind.Logico;
            break;
        default:
            compatible = false;
            break;
    }
    enforce(compatible, "Contrato de tipo não satisfeito/representável na CTFE.");
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

        if (!remainingInstructions)
            throw new CTFELimitException("Limite de instruções em tempo de compilação.");
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

        if (depth >= 128)
            throw new CTFELimitException("Limite de recursão em tempo de compilação.");
        enforce(name in functions, "Função indisponível na avaliação em tempo de compilação.");
        SymbolFn* symbol = name in symbols;
        enforce(symbol !is null, "Identidade da função ausente na CTFE.");
        FnDecl functionNode = (*symbol).node;
        enforce(params.length == functionNode.args.length, "Aridade/defaults exigem execução nativa.");
        foreach (size_t i, FnArg arg; functionNode.args)
        {
            enforce(!arg.rest, "Parâmetro variável exige execução nativa.");
            if (arg.type_expr !is null)
                validateCTFEValue(params[i], arg.type_expr.toStr());
        }
        depth++;
        scope (exit)
            depth--;
        VM vm;
        vm.instructions = functions[name].instructions;
        vm.ctfe = this;
        size_t locals = 0;
        foreach (VMInstruction instruction; vm.instructions)
            if (instruction.opCode == VMOpCode.Store || instruction.opCode == VMOpCode.Load)
            {
                enforce(instruction.param < 100_000,
                        "Limite de variáveis locais na avaliação em tempo de compilação excedido.");
                if (instruction.param >= locals)
                    locals = instruction.param + 1;
            }
        vm.context.vars = new CGDValue[locals];
        vm.context.params = params;
        vmHandle(&vm);
        enforce(vm.returned, "Retorno implícito nulo exige execução nativa.");
        if (functionNode.type_expr !is null)
            validateCTFEValue(vm.context.ret[0], functionNode.type_expr.toStr());
        return vm.context.ret[0];
    }
}
