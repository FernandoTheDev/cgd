module cli;

import driver.args;
import std.format;
import std.getopt;
import std.stdio;
import env;


enum Flag[] FLAGS = [
    Flag("a", "ajuda",        "showHelp",    "Exibe esta mensagem de ajuda"),
    Flag("v", "versao",       "showVersion", "Exibe a versão atual do compilador"),
    Flag("o", "otimizar",     "opt",         "Ativa a otimização do compilador"),
    Flag("t", "tempo",        "showPerf",    "Exibe o tempo de execução de cada passe"),
    Flag("s", "saida",        "output",      "Define o caminho do arquivo de saída"),
];

private struct Flag
{
    string curta;
    string longa;
    string campo;
    string descricao;
}

GetoptResult cli_parse(ref string[] args, ref CGDArguments arguments)
{
    mixin(generateGetoptCall());
}

private string generateGetoptCall()
{
    string code = "return getopt(args";
    foreach (flag; FLAGS)
    {
        string pattern = flag.curta.length
            ? flag.curta ~ "|" ~ flag.longa
            : flag.longa;
        code ~= format(`, "%s", &arguments.%s`, pattern, flag.campo);
    }
    code ~= ");";
    return code;
}

void cli_ajuda()
{
    cli_versao();
    writeln();
    writeln("USO:");
    writeln("    cgd [arquivo] [flags]\n");
    writeln("FLAGS:");
    foreach (flag; FLAGS)
        writefln("    -%-4s --%-10s  %s", flag.curta, flag.longa, flag.descricao);
    writeln();
}

void cli_versao()
{
    writefln("CGD - Compilador Geral Delégua v%s", VERSION);
}
