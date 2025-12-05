import std.stdio, std.file, std.getopt;
import frontend, common.reporter, env, cli;
import core.stdc.stdlib : exit;

void checkErrors(DiagnosticError erro)
{
    if (erro.hasErrors() || erro.hasWarnings())
    {
        erro.printDiagnostics();
        // fecha o programa com código 1 caso haja erros
        if (erro.hasErrors())
            exit(1);
        erro.clear();
    }
}

void main(string[] __args)
{
    DiagnosticError error = new DiagnosticError();
    try
    {
        if (__args.length < 1)
            return;

        string file = __args[1];
        string src = readText(file);
        Token[] tokens = new Lexer(file, src, ".", error).tokenize();

        Program program = new Parser(tokens, error).parseProgram();

        Context ctx = new Context();
        Semantic1 sema1 = new Semantic1(ctx, error);
        sema1.analyze(program);
        checkErrors(error);

        Semantic2 sema2 = new Semantic2(ctx, error);
        sema2.analyze(program);
        checkErrors(error);

        Semantic3 sema3 = new Semantic3(ctx, error);
        sema3.analyze(program);
        checkErrors(error);

        program.print();

        ctx.dumpScope(ctx.currentScope, 0);
        ctx.dumpScope(ctx.globalScope, 0);
    }
    catch (Exception e)
    {
        error.printDiagnostics();
        writeln(e);
    }
}
