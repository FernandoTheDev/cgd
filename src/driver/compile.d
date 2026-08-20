module driver.compile;

import std.stdio : writeln, writefln;
import core.stdc.stdlib : exit;
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
import opt.dead_code;
import driver.args;
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

    string source = readText(filename);
    Diagnostics diag = new Diagnostics;

    Lexer lexer = new Lexer(source, filename, diag);
    Token[] tokens = lexer.tokenizer();
    verificar_erros(diag);

    Program program;

    try {
        Parser parser = new Parser(tokens, diag);
        program = parser.parse();
        verificar_erros(diag);
    } catch (Exception e) {
        verificar_erros(diag);
        writeln("Ocorreu um erro interno no compilador.");
        writeln(e);
        return;
    }

    Context context = new Context;
    TypeRegistry registry = new TypeRegistry;
    TypeResolver resolver = new TypeResolver(registry);

    Sema1 sema1 = new Sema1(context, diag);
    sema1.analyze(program);
    verificar_erros(diag);

    Sema2 sema2 = new Sema2(registry);
    sema2.analyze(program);

    Sema3 sema3 = new Sema3(context, registry, resolver, diag);
    sema3.analyze(program);
    verificar_erros(diag);

    CTFEContext ctfeContext = new CTFEContext;
    new PurityAnalysis(context, diag, ctfeContext).analysis(program);
    verificar_erros(diag);

    if (args.opt)
    {
        enum MAX = 20;
        for (size_t iter; iter++ < MAX;)
        {
            new CgdConstantFolding(program, context, ctfeContext).opt();
            new CgdDeadCode(program, context).remove();
        }
    }

    if (args.showDebug)
        program.print();

    BackendC cg = new BackendC();
    dstring code = cg.compile(program);

    if (args.showDebug)
        writeln(code);

    string cSource = code.to!string; // UTF-32 -> UTF-8

    string output = baseName(filename)[0 .. $ - 8]; // .delegua
    string outc = output ~ ".c";
    write(outc, cSource);

    string cc = environment.get("CC");
    string[] cCompilers = ["tcc", "gcc", "clang"].filter!(c => which(c)).array;

    if (cc == "" && cCompilers.length > 0)
        cc = cCompilers[0];
    else if (cc == "")
    {
        writefln("Não foi possível encontrar um compilador C. Tentativas: tcc, gcc e clang.");
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

    auto exec = executeShell(command);
    if (exec.status != 0)
        writeln(exec.output);
}
