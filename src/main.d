module main;

import std.stdio : writeln, writefln;
import std.getopt;

import driver.compile;
import driver.args;
import utils;
import cli;
import errors;

void main(string[] args)
{
    cgd_validar(args.length > 1, "Esperado ao menos um argumento.");
    CGDArguments arguments;
    foreach (i, arg; args)
        if (arg == "--diagnosticos=json" || (arg == "--diagnosticos" && i + 1 < args.length && args[i + 1] == "json"))
            diagnosticFormat = DiagnosticFormat.json;

    try
        cli_parse(args, arguments);
    catch (GetOptException e)
    {
        cgd_erro("Flag inválida: " ~ e.msg);
    }

    if (arguments.diagnostics == "json")
        diagnosticFormat = DiagnosticFormat.json;
    else if (arguments.diagnostics != "texto")
        cgd_erro("Formato de diagnóstico inválido; use texto ou json.");
    if (arguments.checkOnly && arguments.emitC)
        cgd_erro("Escolha --verificar ou --emitir-c.");
    if (arguments.showDebug && diagnosticFormat == DiagnosticFormat.json)
        cgd_erro("--depurar não pode ser combinado com diagnósticos JSON.");

    if (arguments.explain.length)
    {
        auto specification = lookupMessage(arguments.explain);
        if (specification is null)
            cgd_erro("Código de diagnóstico desconhecido: " ~ arguments.explain);
        writeln(arguments.explain, ": ", specification.message);
        writeln(specification.explanation);
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

    cgd_validar(args.length == 2, "Informe exatamente um arquivo .delegua. Use --ajuda para consultar as opções.");
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
