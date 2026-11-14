module main;

import std.stdio : writeln, writefln;
import std.getopt;

import driver.compile;
import driver.args;
import utils;
import cli;

void main(string[] args)
{
    cgd_validar(args.length > 1, "Esperado ao menos um argumento.");
    CGDArguments arguments;

    try
        cli_parse(args, arguments);
    catch (GetOptException e)
    {
        cgd_erro("Flag inválida: " ~ e.msg);
    }

    if (arguments.showHelp)
    {
        cli_ajuda();
        return;
    }

    if (arguments.showVersion)
    {
        cli_versao();
        return;
    }

    try
        compile(arguments, args[1]);
    catch (Exception e)
        cgd_erro("Falha na compilação: " ~ e.msg);
}

version (D_Coverage) shared static this()
{
    import core.runtime : dmd_coverDestPath;
    import std.process : environment;
    import std.file : exists, mkdirRecurse;

    string dir = environment.get("COVDIR", "");
    if (dir.length && !dir.exists)
        mkdirRecurse(dir);
    if (dir.length)
        dmd_coverDestPath(dir);
}
