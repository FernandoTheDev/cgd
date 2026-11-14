module frontend.analysis;

import frontend;
import frontend.modules;
import frontend.validation;
import frontend.static_safety;
import frontend.flow;
import std.algorithm : filter;
import std.array : array;

struct AnalysisResult
{
    Program program;
    Token[] tokens;
    Diagnostics diagnostics;
    Context context;
}

/// API sem exit, codegen, processos externos ou avaliação CTFE. Buffers abertos
/// prevalecem sobre disco. Um resultado pertence exclusivamente a esta revisão.
AnalysisResult analyzeSource(string source, string filename, string[string] overlays = null)
{
    AnalysisResult result;
    result.diagnostics = new Diagnostics;
    if (source.length > 4 * 1024 * 1024)
    {
        result.diagnostics.error(null, "Fonte excede 4 MiB.", "E1004");
        return result;
    }
    try
    {
        Lexer lexer = new Lexer(source, filename, result.diagnostics);
        lexer.includeComments = true;
        result.tokens = lexer.tokenizer();
        if (result.diagnostics.hasErrors())
            return result;
        Parser parser = new Parser(result.tokens.filter!((Token t) => t.kind != TokenKind.Comment)
                .array, result.diagnostics);
        parser.recoverIncomplete = true;
        result.program = parser.parse();
        Diagnostics diagnostics = new Diagnostics;
        diagnostics.registerSource(filename, source);
        scope (exit)
            result.diagnostics.merge(diagnostics);
        new ModuleLoader(diagnostics, overlays).load(result.program, filename);
        if (diagnostics.hasErrors() || !validateStructure(result.program, diagnostics))
            return result;
        result.context = new Context;
        TypeRegistry registry = new TypeRegistry;
        new Sema1(result.context, diagnostics).analyze(result.program);
        if (diagnostics.hasErrors())
            return result;
        new Sema2(registry).analyze(result.program);
        new Sema3(result.context, registry, new TypeResolver(registry, diagnostics), diagnostics).analyze(
                result.program);
        if (diagnostics.hasErrors())
            return result;
        new StaticSafety(diagnostics).analyze(result.program);
        new FlowAnalysis(diagnostics).analyze(result.program);

    }
    catch (Exception error)
    {
        result.diagnostics.error(null, error.msg, "E9001");
    }
    return result;
}
