module main;

import std.stdio : writeln, writefln;
import std.getopt;

import driver.compile;
import driver.args;
import driver.project;
import driver.docgen;
import dap.server;
import utils;
import cli;
import errors;

void main(string[] args)
{
    if (args.length >= 2)
    {
        switch (args[1])
        {
            case "iniciar":
                runInitCommand(args[2 .. $]);
                return;
            case "compilar":
                runBuildCommand(args[2 .. $]);
                return;
            case "rodar":
                runRunCommand(args[2 .. $]);
                return;
            case "testar":
                runTestCommand(args[2 .. $]);
                return;
            case "limpar":
                runCleanCommand(args[2 .. $]);
                return;
            case "verificar":
                runCheckCommand(args[2 .. $]);
                return;
            case "formatar":
                runFormatCommand(args[2 .. $]);
                return;
            case "projeto":
                runProjectCommand(args[2 .. $]);
                return;
            case "depurar":
                runDebugCliCommand(args[2 .. $]);
                return;
            case "dap":
                runDapServer(args[2 .. $]);
                return;
            case "documentar":
                runDocumentCommand(args[2 .. $]);
                return;
            default:
                break;
        }
    }
    if (args.length >= 2 && args[1] == "--lsp" && (args.length == 2 || (args.length == 3 && args[2] == "--stdio")))
    {
        import lsp.server : runLanguageServer;

        runLanguageServer();
        return;
    }
    if (args.length == 3 && (args[1] == "--formatar" || args[1] == "--verificar-formatacao"))
    {
        import frontend.formatter : formatDelegua;
        import std.file : readText, write;
        import core.stdc.stdlib : exit;

        try
        {
            string source = readText(args[2]);
            string formatted = formatDelegua(source);
            if (args[1] == "--verificar-formatacao")
                exit(source == formatted ? 0 : 1);
            write(args[2], formatted);
        }
        catch (Exception error)
            cgd_erro("Falha ao formatar: " ~ error.msg);
        return;
    }
    cgd_validar(args.length > 1, "Esperado ao menos um argumento.");
    CGDArguments arguments;
    foreach (size_t i, string arg; args)
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
        const(MessageSpec)* specification = lookupMessage(arguments.explain);
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
