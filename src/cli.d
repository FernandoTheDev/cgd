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
    Flag("d", "depurar", "showDebug", "Ativa o modo de depuração interna do compilador"),
    Flag("g", "depuracao", "debugInfo", "Emite símbolos de depuração (-g) no executável"),
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
    Flag("", "recurso", "features", "Habilita um recurso condicional para Compilacao.temRecurso (repetível)"),
    Flag("", "gc", "gcBackend", "Backend de GC: cgd (padrão, sem libgc) ou boehm (referência)"),
    Flag("", "opcoes-memoria", "memOpts", "Controle de otimizações híbridas: padrao, nenhuma ou lista (ans,stack,det,fusao,devirt)"),
    Flag("", "relatorio-memoria", "memReport", "Exibe relatório de decisões de memória híbrida e ANS"),
    Flag("", "relatorio-memoria-json", "memReportPath", "Salva relatório JSON de decisões de memória híbrida em arquivo"),
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
    writeln("    cgd [arquivo.delegua] [flags]");
    writeln("    cgd iniciar <nome> [--tipo aplicativo|servidor|tui|gtk|sdl|biblioteca]");
    writeln("    cgd compilar [arquivo] [--modo desenvolvimento|producao] [--depuracao]");
    writeln("    cgd rodar [arquivo] [-- argumentos...]");
    writeln("    cgd testar [--filtro texto]");
    writeln("    cgd verificar [arquivo]");
    writeln("    cgd formatar [caminho] [--verificar]");
    writeln("    cgd limpar");
    writeln("    cgd projeto [validar|informacoes]");
    writeln("    cgd depurar [arquivo]");
    writeln("    cgd dap --stdio");
    writeln("    cgd documentar [--bibliotecas] [--formato markdown|html] [--saida dir] [--validar]");
    writeln("    cgd --formatar arquivo.delegua");
    writeln("    cgd --verificar-formatacao arquivo.delegua");
    writeln("    cgd --lsp --stdio\n");
    writeln("FLAGS:");
    foreach (Flag flag; FLAGS)
        if (flag.curta != "")
            writefln("    -%-4s --%-10s  %s", flag.curta, flag.longa, flag.descricao);
        else
            writefln("    %4s --%-10s  %s", flag.curta, flag.longa, flag.descricao);
    writeln();
}

void cli_versao()
{
    writefln("CGD - Compilador Geral Delégua v%s", VERSION);
}
