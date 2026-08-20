// resolve os simbolos
module frontend.semantic.sema1;

import std.exception;
import std.format;
import std.stdio;

import frontend.semantic;
import frontend.parser;
import frontend.lexer;
import frontend;
import errors;
import utils;

class Sema1
{
private:
    Context context;
    Diagnostics err;

    void analyze(Node node)
    {
        switch (node.kind)
        {
            case NodeKind.FnDecl:
                return analyzeFnDecl(as!FnDecl(node));
            default:
                return;
        }
    }

    void analyzeFnDecl(FnDecl node)
    {
        dstring name = node.fn;
        if (Symbol* sym = context.get(name))
        {
            err.error(node.pos, format("%s '%s' já existe.", ternary(sym.isFn(), "A função", "O simbolo"), name));
            alreadyDeclaredHere(name, getPosFromSymbol(sym), err);
        }
        // writeln(node.args);
        context.set(name, new SymbolFn(node));
    }

    void addStdFunctions()
    {
        context.set("escreva", new SymbolFn(
            new FnDecl("escreva", [], new TypeExprNamed("vazio", Position.init), [], 0, Position.init), true));
    }

public:
    this(Context context, Diagnostics err)
    {
        this.context = context;
        this.err = err;
    }

    void analyze(Program program)
    {
        context.push();
        addStdFunctions();
        foreach (Node node; program.body)
            analyze(node);
    }
}
