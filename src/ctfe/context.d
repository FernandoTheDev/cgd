module ctfe.context;
import frontend.parser.ast : FnDecl, FnArg;

import frontend.parser.ast : Node;
import ctfe.compile;
import ctfe.vm.cgd_vm;

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
    // Chaves de identidade emitidas pela resolução, sem colisão por nome.
    VMInstruction[][dstring] bytecode;
    FnDecl[dstring] declarations;

    size_t depth;
    size_t liveSlots;
    size_t remainingInstructions;

    void consumeInstruction()
    {
        import std.exception : enforce;

        if (!remainingInstructions)
            throw new CTFELimitException("Limite de instruções em tempo de compilação.");
        remainingInstructions--;
    }

    Node call(dstring name, CGDValue[] params, size_t budget = 10_000_000)
    {
        remainingInstructions = budget;
        return CTFECompile.cgdValueToNode(callValue(name, params));
    }

    CGDValue callValue(dstring name, CGDValue[] params)
    {
        import std.exception : enforce;

        if (depth >= 128)
            throw new CTFELimitException("Limite de recursão em tempo de compilação.");
        enforce(name in bytecode, "Função indisponível na avaliação em tempo de compilação.");
        FnDecl* declaration = name in declarations;
        enforce(declaration !is null, "Identidade da função ausente na CTFE.");
        FnDecl functionNode = *declaration;
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
        vm.instructions = bytecode[name];
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
        if (locals > 100_000 - liveSlots)
            throw new CTFELimitException("Limite de slots ativos na avaliação em tempo de compilação.");
        liveSlots += locals;
        scope (exit)
            liveSlots -= locals;
        vm.context.vars = new CGDValue[locals];
        vm.context.params = params;
        vmHandle(&vm);
        enforce(vm.returned, "Retorno implícito nulo exige execução nativa.");
        if (functionNode.type_expr !is null)
            validateCTFEValue(vm.context.ret[0], functionNode.type_expr.toStr());
        return vm.context.ret[0];
    }
}
