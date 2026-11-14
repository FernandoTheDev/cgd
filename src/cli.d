module cli;

import driver.args;
import std.format;
import std.getopt;
import std.stdio;
import env;

enum Flag[] FLAGS = [
    Flag("", "explicar", "explain", "Explica um código de diagnóstico sem compilar"),
    Flag("a", "ajuda", "showHelp", "Exibe esta mensagem de ajuda"),
    Flag("v", "versao", "showVersion", "Exibe a versão atual do compilador"),
    Flag("d", "depurar", "showDebug", "Ativa o modo de depuração do compilador"),
    Flag("o", "otimizar", "opt", "Ativa a otimização do compilador"),
    Flag("t", "tempo", "showPerf", "Exibe o tempo de execução de cada passe"),
    Flag("s", "saida", "output", "Define o caminho do arquivo de saída"),
    Flag("", "verificar", "checkOnly", "Analisa sem gerar C ou executável"),
    Flag("", "emitir-c", "emitC", "Gera somente C99, sem toolchain/runtime do alvo"),
    Flag("", "diagnosticos", "diagnostics", "Formato: texto ou json (JSON Lines em stderr)"),
    Flag("", "cc", "cc", "Executável do compilador C; alternativa a CC"),
    Flag("", "target", "target", "Triple do alvo passado ao Clang (--target)"),
    Flag("", "sysroot", "sysroot", "Raiz dos headers/bibliotecas do alvo"),
    Flag("", "runtime-root", "runtimeRoot", "Raiz dos headers do runtime"),
    Flag("", "runtime-object", "runtimeObject", "Objeto do runtime compilado para o alvo"),
    Flag("", "pkg-config", "pkgConfig", "Executável pkg-config do alvo"),
    Flag("", "cflag", "cFlags", "Argumento adicional de C (repetível, sem shell)"),
    Flag("", "ldflag", "linkFlags", "Argumento adicional de link (repetível, sem shell)"),
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
    foreach (Flag flag; FLAGS)
    {
        string pattern = flag.curta.length ? flag.curta ~ "|" ~ flag.longa : flag.longa;
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
    writeln("    cgd [arquivo] [flags]");
    writeln("    cgd --formatar arquivo.delegua");
    writeln("    cgd --verificar-formatacao arquivo.delegua");
    writeln("    cgd --lsp --stdio\n");
    writeln("FLAGS:");
    foreach (Flag flag; FLAGS)
        writefln("    -%-4s --%-10s  %s", flag.curta, flag.longa, flag.descricao);
    writeln();
}

void cli_versao()
{
    writefln("CGD - Compilador Geral Delégua v%s", VERSION);
}
