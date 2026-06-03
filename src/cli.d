module cli;

import std.stdio;
import std.format;
import env;

private immutable string[string] DESCRICOES_FLAGS = [
    "a": "Exibe esta mensagem de ajuda",
    "v": "Exibe a versão atual do compilador",
    "da": "Ativa o modo de depuração da AST",
    "dt": "Ativa o modo de depuração dos tokens",
    "O": "Ativa a otimização do compilador",
];

private struct Flag
{
    string curta;
    string longa;
    string descricao;
}

private immutable Flag[] FLAGS = [
    Flag("-a",   "--ajuda",        DESCRICOES_FLAGS["a"]),
    Flag("-v",   "--versao",       DESCRICOES_FLAGS["v"]),
    Flag("--da", "--debug-ast",    DESCRICOES_FLAGS["da"]),
    Flag("--dt", "--debug-tokens", DESCRICOES_FLAGS["dt"]),
    Flag("-O",   "--opt", DESCRICOES_FLAGS["O"]),
];

void cli_ajuda()
{
    cli_versao();
    writeln();
    writeln("USO:");
    writeln("    cgd [arquivo] [flags]\n");
    writeln("FLAGS:");
    foreach (flag; FLAGS)
        writefln("    %-4s  %-16s  %s", flag.curta, flag.longa, flag.descricao);
    writeln();
}

void cli_versao()
{
    writefln("CGD - Compilador Geral Delégua v%s", VERSION);
}
