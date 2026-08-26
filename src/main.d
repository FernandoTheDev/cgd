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
        writefln("Flag invalida: %s\n", e.msg[20..$]);
        cli_ajuda();
        return;
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

    compile(arguments, args[1]);
}
