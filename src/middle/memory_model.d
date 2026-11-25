module middle.memory_model;

import frontend.parser.ast;
import std.array : appender, join, split;
import std.conv : to;
import std.format : format;
import std.json : JSONValue;
import std.string : strip, toLower;

/// Domínio de armazenamento decidido estaticamente pelo compilador.
enum StorageDomain : ubyte
{
    ManagedHeap,
    StackLocal,
    DeterministicHeap,
    ScalarNative,
    ValueNative,
}

/// Estado de escape de uma alocação local.
enum EscapeState : ubyte
{
    NoEscape,
    ArgEscape,
    GlobalEscape,
}

/// Modo de posse inferido para valores/alocações.
enum OwnershipMode : ubyte
{
    SharedGC,
    ExclusiveLocal,
    BorrowedRead,
    BorrowedMut,
}

/// Tipo escalar exato suportado pela Especialização Nativa Automática (ANS).
enum AnsScalarType : ubyte
{
    None,
    Int64,
    Float64,
    Bool,
    Void,
}

/// Configuração de isolamento das otimizações híbridas (para ablação científica A/B/C/D/E).
struct MemoryOptConfig
{
    bool enableAns = true;
    bool enableStackAlloc = true;
    bool enableDetFree = true;
    bool enableCollectionFusion = true;
    bool enableDevirt = true;
    bool enableSafepoints = true;

    static MemoryOptConfig disabled()
    {
        MemoryOptConfig cfg;
        cfg.enableAns = false;
        cfg.enableStackAlloc = false;
        cfg.enableDetFree = false;
        cfg.enableCollectionFusion = false;
        cfg.enableDevirt = false;
        cfg.enableSafepoints = true;
        return cfg;
    }

    static MemoryOptConfig fromSpec(string spec)
    {
        string trimmed = spec.strip().toLower();
        if (!trimmed.length || trimmed == "padrao" || trimmed == "padrão" || trimmed == "tudo"
                || trimmed == "all")
            return MemoryOptConfig.init;
        if (trimmed == "nenhuma" || trimmed == "desativado" || trimmed == "off" || trimmed == "none")
            return MemoryOptConfig.disabled();

        MemoryOptConfig cfg = MemoryOptConfig.init;
        bool sawPositive = false;
        string[] tokens = trimmed.split(",");
        foreach (string raw; tokens)
        {
            string tok = raw.strip();
            if (!tok.length)
                continue;
            if (tok[0] != '-' && (tok.length < 4 || tok[0 .. 4] != "sem-"))
                sawPositive = true;
        }
        if (sawPositive)
            cfg = MemoryOptConfig.disabled();

        foreach (string raw; tokens)
        {
            string tok = raw.strip();
            if (!tok.length)
                continue;
            bool turnOn = true;
            if (tok[0] == '-')
            {
                turnOn = false;
                tok = tok[1 .. $];
            }
            else if (tok.length > 4 && tok[0 .. 4] == "sem-")
            {
                turnOn = false;
                tok = tok[4 .. $];
            }

            switch (tok)
            {
                case "ans":
                    cfg.enableAns = turnOn;
                    break;
                case "stack":
                case "pilha":
                    cfg.enableStackAlloc = turnOn;
                    break;
                case "det":
                case "deterministico":
                case "determinístico":
                    cfg.enableDetFree = turnOn;
                    break;
                case "fusion":
                case "fusao":
                case "fusão":
                    cfg.enableCollectionFusion = turnOn;
                    break;
                case "devirt":
                case "desvirtualizacao":
                    cfg.enableDevirt = turnOn;
                    break;
                case "safepoints":
                    cfg.enableSafepoints = turnOn;
                    break;
                default:
                    break;
            }
        }
        return cfg;
    }
}

/// Resumo interprocedimental de efeitos, escape e elegibilidade ANS por função.
struct FunctionMemorySummary
{
    FnDecl fn;
    bool isRecursive;
    bool mayThrow;
    bool maySuspend;
    bool allocatesManaged;
    bool returnsFresh;
    bool[] paramEscapes;
    bool[] paramMutated;
    bool ansEligible;
    AnsScalarType ansReturnType = AnsScalarType.None;
    AnsScalarType[] ansParamTypes;
    string ansRejectReason;
}

/// Decisão de alocação e liberação para uma declaração de variável local.
struct LocalAllocPlan
{
    VarDecl decl;
    StorageDomain domain = StorageDomain.ManagedHeap;
    EscapeState escape = EscapeState.GlobalEscape;
    OwnershipMode ownership = OwnershipMode.SharedGC;
    ClassDecl stackClass;
    size_t stackSlots;
    bool freeAtScopeExit;
    string reason;
}

/// Plano unificado de gerenciamento híbrido de memória compartilhado entre análise e codegen.
final class MemoryPlan
{
public:
    MemoryOptConfig config;
    FunctionMemorySummary[FnDecl] fnSummaries;
    LocalAllocPlan[VarDecl] localPlans;
    bool[ClassDecl] classesWithSubclasses;

    // Telemetria de decisões efetivamente aplicadas durante análise e emissão de código C
    size_t ansFunctionsCount;
    size_t ansCallSitesCount;
    size_t stackObjectsCount;
    size_t detFreeVarsCount;
    size_t fusedTuplesCount;
    size_t preSizedArraysCount;
    size_t devirtCallSitesCount;
    size_t globalRootsRegistered;
    size_t conservativeFallbacksCount;

    string[] ansFunctionNames;
    string[] stackObjectNames;
    string[] detFreeVarNames;

    this(MemoryOptConfig cfg = MemoryOptConfig.init)
    {
        this.config = cfg;
    }

    bool isAnsFunction(FnDecl fn) const
    {
        if (!config.enableAns || fn is null)
            return false;
        const(FunctionMemorySummary)* summary = fn in fnSummaries;
        return summary !is null && summary.ansEligible;
    }

    const(FunctionMemorySummary)* summaryOf(FnDecl fn) const
    {
        if (fn is null)
            return null;
        return fn in fnSummaries;
    }

    const(LocalAllocPlan)* localPlanOf(VarDecl decl) const
    {
        if (decl is null)
            return null;
        return decl in localPlans;
    }

    string toTextReport() const
    {
        string[] lines;
        lines ~= "=== Relatório de Memória Híbrida e Especialização (CGD) ===";
        lines ~= format("  Opções ativas: ans=%s stack=%s det=%s fusao=%s devirt=%s safepoints=%s",
                config.enableAns, config.enableStackAlloc, config.enableDetFree,
                config.enableCollectionFusion, config.enableDevirt, config.enableSafepoints);
        lines ~= format("  Funções especializadas automaticamente (ANS): %s", ansFunctionsCount);
        lines ~= format("  Chamadas diretas unboxed (ANS): %s", ansCallSitesCount);
        lines ~= format("  Objetos promovidos para stack local: %s", stackObjectsCount);
        lines ~= format("  Alocações com liberação determinística: %s", detFreeVarsCount);
        lines ~= format("  Tuplas fundidas sem vetor temporário: %s", fusedTuplesCount);
        lines ~= format("  Vetores pré-dimensionados: %s", preSizedArraysCount);
        lines ~= format("  Chamadas de método desvirtualizadas: %s", devirtCallSitesCount);
        lines ~= format("  Raízes globais/IC registradas no GC: %s", globalRootsRegistered);
        lines ~= format("  Fallbacks conservadores (heap GC): %s", conservativeFallbacksCount);
        if (ansFunctionNames.length)
            lines ~= "  ANS: " ~ ansFunctionNames.join(", ");
        if (stackObjectNames.length)
            lines ~= "  Stack: " ~ stackObjectNames.join(", ");
        if (detFreeVarNames.length)
            lines ~= "  Liberação determinística: " ~ detFreeVarNames.join(", ");
        return lines.join("\n") ~ "\n";
    }

    string toJsonReport() const
    {
        JSONValue[string] root;
        JSONValue[string] opts;
        opts["ans"] = JSONValue(config.enableAns);
        opts["stack"] = JSONValue(config.enableStackAlloc);
        opts["detFree"] = JSONValue(config.enableDetFree);
        opts["collectionFusion"] = JSONValue(config.enableCollectionFusion);
        opts["devirt"] = JSONValue(config.enableDevirt);
        opts["safepoints"] = JSONValue(config.enableSafepoints);
        root["opcoes"] = JSONValue(opts);
        root["funcoesANS"] = JSONValue(cast(long) ansFunctionsCount);
        root["chamadasANS"] = JSONValue(cast(long) ansCallSitesCount);
        root["objetosStack"] = JSONValue(cast(long) stackObjectsCount);
        root["liberacoesDeterministicas"] = JSONValue(cast(long) detFreeVarsCount);
        root["tuplasFundidas"] = JSONValue(cast(long) fusedTuplesCount);
        root["vetoresPreDimensionados"] = JSONValue(cast(long) preSizedArraysCount);
        root["chamadasDesvirtualizadas"] = JSONValue(cast(long) devirtCallSitesCount);
        root["raizesGlobaisRegistradas"] = JSONValue(cast(long) globalRootsRegistered);
        root["fallbacksConservadores"] = JSONValue(cast(long) conservativeFallbacksCount);

        JSONValue[] ansArr;
        foreach (string n; ansFunctionNames)
            ansArr ~= JSONValue(n);
        root["listaANS"] = JSONValue(ansArr);

        JSONValue[] stkArr;
        foreach (string n; stackObjectNames)
            stkArr ~= JSONValue(n);
        root["listaStack"] = JSONValue(stkArr);

        JSONValue[] detArr;
        foreach (string n; detFreeVarNames)
            detArr ~= JSONValue(n);
        root["listaDeterministicas"] = JSONValue(detArr);

        return JSONValue(root).toPrettyString() ~ "\n";
    }
}
