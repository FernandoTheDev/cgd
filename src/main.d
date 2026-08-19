module main;

import std.stdio : writeln, writefln;
import std.exception;
import std.process;
import std.format;
import std.getopt;
import std.file;
import std.conv;
import std.path;

import middle.opt.constant_folding;
import core.stdc.stdlib : exit;
import frontend.semantic;
import backend.c.codegen;
import frontend.parser;
import backend.compile;
import frontend.lexer;
import frontend;
import errors;
import utils;
import cli;

void verificar_erros(Diagnostics d)
{
    if (!d.hasErrors()) return;
    d.report();
    exit(1);
}

void main(string[] args)
{
    cgd_validar(args.length > 1, "Esperado ao menos um argumento.");

    bool ajuda, versao, opt;
    try
        getopt(args,
            "a|ajuda", &ajuda,
            "v|versao", &versao,
            "O|opt", &opt
        );
    catch (GetOptException e)
    {
        writefln("Flag invalida: %s\n", e.msg);
        return;
    }

    if (ajuda)
    {
        cli_ajuda();
        return;
    }

    if (versao)
    {
        cli_versao();
        return;
    }

    string filename = args[1];

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
        writefln("%s", e.msg);
        writefln("%s", e.file);
        writefln("%d", e.line);
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

    if (opt)
    {
        new CgdConstantFolding(program, context).opt();
        program.print();
    }

    BackendC cg = new BackendC();
    dstring code = cg.compile(program);
    writeln(code);

    string cSource = code.to!string; // UTF-32 -> UTF-8

    string output = baseName(filename)[0 .. $ - 8]; // .delegua
    string outc = output ~ ".c";
    write(outc, cSource);

    string command = format("gcc %s -o %s -g -O0 lib/libdelegua_rt.o $(pkg-config --libs bdw-gc) -rdynamic",
        outc, output);
    writefln("Command: %s", command);
    auto exec = executeShell(command);
    writeln(exec.output);
    // executeShell(format("rm %s", outc));
}
