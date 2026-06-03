module main;

import std.exception;
import std.format;
import std.getopt;
import std.stdio;
import std.file;
import std.path;

import middle.opt.constant_folding;
import frontend.semantic;
import frontend.parser;
import frontend.lexer;
import middle.codegen;
import frontend;
import errors;
import utils;
import cli;

void verificar_erros(Diagnostics d)
{
    bool err;
    if (d.hasErrors())
        err = true;
    d.report();
    import core.stdc.stdlib : exit;

    if (err)
        exit(1);
}

void main(string[] args)
{
    cgd_validar(args.length > 1, "Esperado ao menos um argumento.");

    bool ajuda, versao, da, dt, opt;
    try
        getopt(args,
            "a|ajuda", &ajuda,
            "v|versao", &versao,
            "dt|debug-tokens", &dt,
            "da|debug-ast", &da,
            "O|opt", &opt);

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

    if (dt)
        foreach (ref Token tk; tokens)
            tk.print();

    Parser parser = new Parser(tokens, diag);
    Program program = parser.parse();
    verificar_erros(diag);

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
    }

    if (da)
        program.print();

    CodeGen cg = new CodeGen(program);
    string code = cg.generate();
    writeln(code);
}
