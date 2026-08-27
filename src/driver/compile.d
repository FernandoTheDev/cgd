module driver.compile;

import std.stdio : writeln, writefln, wrt = write;
import core.stdc.stdlib : exit;
import std.datetime.stopwatch;
import std.exception;
import std.algorithm;
import std.process;
import std.format;
import std.getopt;
import std.array;
import std.file;
import std.conv;
import std.path;

import opt.constant_folding;
import middle.lowering;
import opt.dead_code;
import driver.args;
import driver.time;
import frontend;
import backend;
import errors;
import utils;
import ctfe;


pragma(inline, true)
bool which(string c) => executeShell(format("which %s", c)).status == 0;

void compile(CGDArguments args, string filename)
{
    // .delegua => 8
    if (filename.length < 9)
        cgd_erro(format("Arquivo inválido: %s", filename));

    if (extension(filename) != ".delegua")
        cgd_erro(format("Extensao de arquivo inválida: %s", filename));

    if (!exists(filename))
        cgd_erro(format("Arquivo não encontrado: %s", filename));

    if (!isFile(filename))
        cgd_erro(format("Isso não é um arquivo: %s", filename));

    Timer timer = Timer(args.showPerf);

    timer.start("Lendo arquivo");
    string source = readText(filename);
    timer.show();
    
    Diagnostics diag = new Diagnostics;
    Program program;

    try {
        Lexer lexer = new Lexer(source, filename, diag);
        timer.start("Fazendo a geração de tokens");
        Token[] tokens = lexer.tokenizer();
        timer.show();

        verificar_erros(diag);

        Parser parser = new Parser(tokens, diag);
        timer.start("Fazendo a geração da AST");
        program = parser.parse();
        timer.show();
        
        verificar_erros(diag);
    } catch (Exception e) {
        verificar_erros(diag);
        writeln("Ocorreu um erro interno no compilador");
        writeln(e);
        return;
    }

    Context context = new Context;
    TypeRegistry registry = new TypeRegistry;
    TypeResolver resolver = new TypeResolver(registry);

    Sema1 sema1 = new Sema1(context, diag);
    timer.start("Semantica 1");
    sema1.analyze(program);
    timer.show();
    verificar_erros(diag);

    Sema2 sema2 = new Sema2(registry);
    timer.start("Semantica 2");
    sema2.analyze(program);
    timer.show();

    Sema3 sema3 = new Sema3(context, registry, resolver, diag);
    timer.start("Semantica 3");
    sema3.analyze(program);
    timer.show();
    verificar_erros(diag);

    CTFEContext ctfeContext = new CTFEContext;
    timer.start("Anlise de pureza nas funções");
    new PurityAnalysis(context, diag, ctfeContext).analysis(program);
    timer.show();
    verificar_erros(diag);

    if (args.opt)
    {
        timer.start("Otimização");
        enum MAX = 20;
        for (size_t iter; iter++ < MAX;)
        {
            new CgdConstantFolding(program, context, ctfeContext).opt();
            new CgdDeadCode(program, context).remove();
        }
        timer.show();
    }

    // reescreve partes do programa
    // o backend deve se manter burro
    // operações como BinaryExpr virarão CallExpr diretamente
    // além desse caso muitos outros serão reescritos
    timer.start("Realizando o lowering da AST");
    new CgdLowering(diag).lowering(program);
    timer.show();
    verificar_erros(diag);

    if (args.showDebug)
        program.print();

    BackendC cg = new BackendC();
    timer.start("Gerando código C");
    dstring code = cg.compile(program);
    timer.show();

    if (args.showDebug)
        writeln(code);

    string cSource = code.to!string; // UTF-32 -> UTF-8
    //                                                          .delegua
    string output = args.output == "" ? baseName(filename)[0 .. $ - 8] : args.output;
    string outc = output ~ ".c";
    
    timer.start("Escrevendo o arquivo '.c'");
    write(outc, cSource);
    timer.show();

    string cc = environment.get("CC");
    string[] cCompilers = ["tcc", "gcc", "clang"].filter!(c => which(c)).array;

    if (cc == "" && cCompilers.length > 0)
        cc = cCompilers[0];
    else if (cc == "")
    {
        writefln("Não foi possível encontrar um compilador C. Tentativas: tcc, gcc e clang");
        return;
    }

    string command = format("%s %s -o %s %s lib/libdelegua_rt.o $(pkg-config --libs bdw-gc) -rdynamic",
        cc,
        outc,
        output,
        args.opt ? "-O2" : "-g -O0"
    );

    if (args.showDebug)
        writefln("Command: %s", command);

    timer.start("Compilando");
    auto exec = executeShell(command);
    timer.show();

    // if (exec.status != 0)
    wrt(exec.output);
}
