module main;

import std.stdio;
import std.file;
import std.exception;
import frontend;
import frontend.lexer;
import frontend.parser;
import frontend.semantic;
import middle.codegen;

void main(string[] args)
{
    // TODO: validar
    string filename = args[1];
    string source = readText(filename);

    Lexer lexer = new Lexer(source, filename);
    Token[] tokens = lexer.tokenizer();

    // foreach (ref Token tk; tokens)
    //     tk.print();

    Parser parser = new Parser(tokens);
    Program program = parser.parse();

    Context context = new Context;
    TypeRegistry registry = new TypeRegistry;
    TypeResolver resolver = new TypeResolver(registry);

    Sema1 sema1 = new Sema1(context);
    sema1.analyze(program);

    Sema2 sema2 = new Sema2(registry);
    sema2.analyze(program);

    Sema3 sema3 = new Sema3(context, registry, resolver);
    sema3.analyze(program);

    // program.print();

    CodeGen cg = new CodeGen(program);
    string code = cg.generate();
    writeln(code);
}
