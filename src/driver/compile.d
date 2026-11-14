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
import frontend.modules;
import backend;
import errors;
import utils;
import ctfe;


pragma(inline, true)
bool which(string c)
{
    if (c.canFind('/')) return exists(c) && isFile(c);
    foreach (dir; environment.get("PATH").split(":"))
        if (exists(buildPath(dir, c)) && isFile(buildPath(dir, c))) return true;
    return false;
}

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
        cgd_erro("Falha no frontend: " ~ e.msg);
    }

    new ModuleLoader(diag).load(program,filename);
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
    string[] cCompilers = ["clang", "gcc", "tcc"].filter!(c => which(c)).array;

    if (cc == "" && cCompilers.length > 0)
        cc = cCompilers[0];
    else if (cc == "")
    {
        cgd_erro("Não foi possível encontrar um compilador C. Tentativas: tcc, gcc e clang");
    }

    string runtimeRoot = dirName(thisExePath());
    string runtimeObject = buildPath(runtimeRoot, "lib", "libdelegua_rt.o");
    if (!exists(runtimeObject)) cgd_erro("Runtime ausente. Execute ./build-runtime antes de compilar.");
    auto pkg = execute(["pkg-config", "--cflags", "--libs", "bdw-gc"]);
    if (pkg.status) cgd_erro("Não foi possível localizar bdw-gc: " ~ pkg.output);
    string[] command = [cc, "-std=c99", "-Werror=implicit-function-declaration", "-Werror=return-type", "-Werror=incompatible-pointer-types",
        "-I", runtimeRoot, outc, "-o", output, args.opt ? "-O2" : "-O0", runtimeObject];
    command ~= pkg.output.split();
    command ~= ["-rdynamic", "-ldl", "-lm"];
    if (args.showDebug) writeln(command);
    timer.start("Compilando");
    auto exec = execute(command);
    timer.show();
    if (exec.status) cgd_erro("O compilador C falhou:\n" ~ exec.output);
    wrt(exec.output);
}
