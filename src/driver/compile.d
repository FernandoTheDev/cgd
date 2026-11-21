module driver.compile;
import std.typecons : Tuple;

import std.stdio : writeln, writefln, wrt = write;
import std.process;
import std.format;
import std.file;
import std.conv;
import std.path;

import opt.pass_manager;
import driver.toolchain;
import frontend.semantic.pipeline;
import frontend.validation;
import middle.lowering;
import middle.async_ir : AsyncLimitException;
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

    timer.start("Carregamento de módulos");
    new ModuleLoader(diag).load(program, filename);
    timer.show();
    verificar_erros(diag);
    validateStructure(program, diag);
    verificar_erros(diag);
    timer.start("Análise semântica");
    SemanticResult semantic = analyzeSemantics(program, diag);
    timer.show();
    verificar_erros(diag);

    if (args.checkOnly)
        return;
    if (args.opt)
    {
        CTFEContext ctfeContext = new CTFEContext;
        prepareCTFE(ctfeContext, semantic.pureFunctions);
        timer.start("Otimização até ponto fixo");
        OptimizationStats stats = optimize(program, ctfeContext);
        if (args.showDebug)
            writefln("Otimização: %d iteração(ões), %d dobras, %d eliminações",
                    stats.iterations, stats.folded, stats.removed);
        timer.show();
    }

    // Lowering traduz operações da linguagem para a API C do runtime.
    // Resolução, contratos e diagnósticos já pertencem à análise semântica.
    timer.start("Realizando o lowering da AST");
    new CgdLowering(diag).lowering(program);
    timer.show();
    verificar_erros(diag);

    if (args.showDebug)
        program.print();

    BackendC cg = new BackendC();
    timer.start("Gerando código C");
    dstring code;
    try
        code = cg.compile(program);
    catch (AsyncLimitException failure)
    {
        diag.errorCode(failure.position, asyncBudget);
        verificar_erros(diag);
        return;
    }
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
    bool[Node] nativeVisited;
    void nativeLibraries(Node node)
    {
        if (node is null || node in nativeVisited)
            return;
        nativeVisited[node] = true;
        if (cast(ModuleUnit) node && !cg.isReachable(node))
            return;
        if (ClassDecl declaration = cast(ClassDecl) node)
        {
            if (!cg.isReachable(declaration))
                return;
            if (declaration.foreignLibrary.length && declaration.foreignLibrary != "cgd-runtime")
                args.linkFlags ~= "-l" ~ declaration.foreignLibrary.to!string;
        }
        foreach (Node child; childNodes(node))
            nativeLibraries(child);
    }

    nativeLibraries(program);
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
