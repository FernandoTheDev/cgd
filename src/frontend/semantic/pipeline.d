module frontend.semantic.pipeline;

import frontend;
import frontend.semantic.async_validation;
import frontend.semantic.routine_validation;
import frontend.semantic.static_safety;
import frontend.semantic.flow;
import frontend.semantic.purity;

struct SemanticResult
{
    Context context;
    TypeRegistry registry;
    FnDecl[] pureFunctions;
}

/// Única ordem de análise para CLI e ferramentas. Não otimiza nem executa código.
SemanticResult analyzeSemantics(Program program, Diagnostics diagnostics)
{
    SemanticResult result;
    result.context = new Context;
    result.registry = new TypeRegistry;
    new DeclarationAnalysis(result.context, result.registry, diagnostics).analyze(program);
    if (diagnostics.hasErrors())
        return result;

    new SemanticAnalyzer(result.context, result.registry, new TypeResolver(result.registry, diagnostics), diagnostics)
        .analyze(program);
    if (diagnostics.hasErrors())
        return result;
    validateAsyncFeatures(program, diagnostics);
    if (diagnostics.hasErrors())
        return result;
    validateRoutines(program, diagnostics);
    if (diagnostics.hasErrors())
        return result;
    new StaticSafety(diagnostics).analyze(program);
    if (diagnostics.hasErrors())
        return result;
    result.pureFunctions = new PureFunctionAnalysis(diagnostics).analyze(program);
    new FlowAnalysis(diagnostics).analyze(program);
    return result;
}
