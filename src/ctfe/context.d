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

    if (type.length >= 2 && type[$ - 2 .. $] == "[]"d)
    {
        enforce(value.type == CGDTypeKind.Vetor, "Contrato de vetor não satisfeito na CTFE.");
        dstring elemType = type[0 .. $ - 2];
        foreach (CGDValue el; value.arr)
            validateCTFEValue(el, elemType);
        return;
    }

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
        case "cf32":
        case "cf64":
        case "cfloat":
        case "cdouble":
            compatible = value.type == CGDTypeKind.Inteiro || value.type == CGDTypeKind.Real;
            break;
        case "inteiro":
        case "longo":
        case "ci8":
        case "cu8":
        case "ci16":
        case "cu16":
        case "ci32":
        case "cu32":
        case "ci64":
        case "cu64":
        case "cshort":
        case "cushort":
        case "cint":
        case "cuint":
        case "clong":
        case "culong":
        case "csize":
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
        case "cbool":
            compatible = value.type == CGDTypeKind.Logico;
            break;
        default:
            compatible = false;
            break;
    }
    enforce(compatible, "Contrato de tipo não satisfeito/representável na CTFE.");
}

private string encodeCTFEKey(dstring fnName, const CGDValue[] params)
{
    import std.conv : to;
    import std.format : format;

    string encodeVal(const CGDValue v)
    {
        final switch (v.type)
        {
            case CGDTypeKind.Inteiro:
                return format("I:%d", v.i);
            case CGDTypeKind.Real:
                ulong bits = *cast(const ulong*)&v.d;
                return format("D:%x", bits);
            case CGDTypeKind.Logico:
                return v.b1 ? "B:1" : "B:0";
            case CGDTypeKind.Texto:
                return format("S:%d:%s", v.s.length, v.s.to!string);
            case CGDTypeKind.Vetor:
                string res = format("A:%d:[", v.arr.length);
                foreach (size_t i, const CGDValue el; v.arr)
                {
                    if (i > 0)
                        res ~= ",";
                    res ~= encodeVal(el);
                }
                return res ~ "]";
        }
    }

    string key = fnName.to!string ~ "(";
    foreach (size_t i, const CGDValue p; params)
    {
        if (i > 0)
            key ~= ";";
        key ~= encodeVal(p);
    }
    return key ~ ")";
}

class CTFEContext
{
    // Chaves de identidade emitidas pela resolução, sem colisão por nome.
    VMInstruction[][dstring] bytecode;
    FnDecl[dstring] declarations;
    CGDValue[string] memoCache;
    size_t cacheHits;
    size_t cacheMisses;

    size_t depth;
    size_t liveSlots;
    size_t remainingInstructions;

    void invalidateCache()
    {
        memoCache = null;
        cacheHits = 0;
        cacheMisses = 0;
    }

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

        string cacheKey = encodeCTFEKey(name, params);
        if (CGDValue* cached = cacheKey in memoCache)
        {
            cacheHits++;
            return *cached;
        }
        cacheMisses++;

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
        if (memoCache.length < 16_384)
            memoCache[cacheKey] = vm.context.ret[0];
        return vm.context.ret[0];
    }
}
