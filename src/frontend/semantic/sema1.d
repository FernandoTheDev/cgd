// resolve os simbolos
module frontend.semantic.sema1;

import utils;
import std.exception;
import frontend;
import frontend.parser;
import frontend.lexer;
import frontend.semantic;
import errors;

class Sema1
{
private:
    Context context;
    Diagnostics err;

    void analyze(Node node)
    {
        switch (node.kind)
        {
        case NodeKind.VarDecl:
            return analyzeVarDecl(as!VarDecl(node));
        case NodeKind.FnDecl:
            return analyzeFnDecl(as!FnDecl(node));
        default:
            return;
        }
    }

    void analyzeVarDecl(VarDecl node)
    {
        dstring name = node.name;
        d_enforce(context.get(name) is null, "A variavel ja existe.", node.pos, err);
        context.set(name, new SymbolVar(node));
    }

    void analyzeFnDecl(FnDecl node)
    {
        dstring name = node.fn;
        d_enforce(context.get(name) is null, "A função ja existe.", node.pos, err);
        context.set(name, new SymbolFn(node));
    }

    void addStdFunctions()
    {
        context.set("escreva", new SymbolFn(
            new FnDecl("escreva", [], new TypeExprNamed("vazio", Position.init), [], Position.init), true));
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
