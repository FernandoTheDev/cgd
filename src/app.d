import std.stdio, std.file, std.getopt;
import frontend, common.reporter, env, cli;

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

        // foreach (ref Token token; tokens)
        //     token.print();

        Program program = new Parser(tokens, error).parseProgram();
        program.print();
        //
    }
    catch (Exception e)
    {
        error.printDiagnostics();
        // writeln(e);
    }
}
