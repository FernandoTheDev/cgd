module driver.compile;
import std.typecons : Tuple;

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

import opt.pass_manager;
import driver.toolchain;
import frontend.flow;
import frontend.validation;
import frontend.static_safety;
import middle.lowering;
import opt.dead_code;
import driver.args;
import driver.time;
import frontend;
import frontend.modules;
import backend;
import errors;
import utils;
import ctfe;

void compile(CGDArguments args, string filename)
{
    if (extension(filename) != ".delegua")
        cgd_erro(format("Extensao de arquivo inválida: %s", filename));

    if (!exists(filename))
        cgd_erro(format("Arquivo não encontrado: %s", filename));

    if (!isFile(filename))
        cgd_erro(format("Isso não é um arquivo: %s", filename));

    Timer timer = Timer(args.showPerf);

    timer.start("Lendo arquivo");
    if (getSize(filename) > 4 * 1024 * 1024)
        cgd_erro("Fonte excede o limite de 4 MiB por arquivo.");
    string source = cast(string) std.file.read(filename);
    timer.show();

    Diagnostics diag = new Diagnostics;
    Program program;

    try
    {
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
    }
    catch (Exception e)
    {
        verificar_erros(diag);
        cgd_erro("Falha no frontend: " ~ e.msg);
    }

    new ModuleLoader(diag).load(program, filename);
    verificar_erros(diag);
    validateStructure(program, diag);
    verificar_erros(diag);
    Context context = new Context;
    TypeRegistry registry = new TypeRegistry;
    TypeResolver resolver = new TypeResolver(registry, diag);

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

    timer.start("Verificações estáticas de segurança");
    new StaticSafety(diag).analyze(program);
    timer.show();
    verificar_erros(diag);

    CTFEContext ctfeContext = new CTFEContext;
    timer.start("Anlise de pureza nas funções");
    new PurityAnalysis(context, diag, ctfeContext).analysis(program);
    timer.show();
    verificar_erros(diag);

    timer.start("Análise de fluxo");
    new FlowAnalysis(diag).analyze(program);
    timer.show();
    verificar_erros(diag);

    if (args.checkOnly)
        return;
    if (args.opt)
    {
        timer.start("Otimização até ponto fixo");
        OptimizationStats stats = optimize(program, context, ctfeContext);
        if (args.showDebug)
            writefln("Otimização: %d iteração(ões), %d dobras, %d eliminações",
                    stats.iterations, stats.folded, stats.removed);
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

    if (args.emitC)
        return;
    CToolchain toolchain = CToolchain.discover(args);
    string[] command = toolchain.command(absolutePath(outc), absolutePath(output), args.opt, toolchain.gcFlags());
    if (args.showDebug)
        writeln(command);
    timer.start("Compilando");
    Tuple!(int, "status", string, "output") result = execute(command);
    timer.show();
    if (result.status)
        cgd_erro("O compilador C falhou:\n" ~ result.output);
    wrt(result.output);
}
