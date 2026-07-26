// resolve todos os nodes
module frontend.semantic.sema3;

import std.exception;
import std.format;
import std.stdio;

import frontend.semantic;
import frontend.parser;
import frontend.lexer;
import frontend;
import errors;
import utils;

class Sema3
{
private:
    Context context;
    TypeRegistry registry;
    TypeResolver resolver;
    Diagnostics err;

    Node analyze(Node node)
    {
        d_enforce(node !is null, "Node nulo recebido.", node.pos, err);
        if (node.type_sema !is null)
            return node;

        switch (node.kind)
        {
        case NodeKind.VarDecl:
            return analyzeVarDecl(as!VarDecl(node));

        case NodeKind.BinaryExpr:
            return analyzeBinaryExpr(as!BinaryExpr(node));

        case NodeKind.FnDecl:
            return analyzeFnDecl(as!FnDecl(node));

        case NodeKind.IfStmt:
            return analyzeIfStmt(as!IfStmt(node));

        case NodeKind.CallExpr:
            return analyzeCallExpr(as!CallExpr(node));

        case NodeKind.ReturnStmt:
            return analyzeReturnStmt(as!ReturnStmt(node));

        case NodeKind.Identifier:
            return analyzeIdentifier(as!Identifier(node));

        case NodeKind.TypeOfExpr:
            return analyzeTypeOfExpr(node);

        case NodeKind.StringLit:
        case NodeKind.IntLit:
        case NodeKind.DoubleLit:
            node.type_sema = resolver.resolver(node.type_expr);
            return node;

        default:
            err.error(node.pos, "Node desconhecido.");
            return node;
        }
    }

    Node analyzeTypeOfExpr(Node node)
    {
        TypeOfExpr toe = as!TypeOfExpr(node);
        toe.value = analyze(toe.value);
        return analyze(new StringLit(toe.value.type_sema.toStr(), node.pos));
    }

    Node analyzeIdentifier(Identifier node)
    {
        Symbol* sym = context.get(node.value);
        d_enforce(sym !is null, "Variavel inexistente.", node.pos, err);
        node.type_sema = (cast(SymbolVar*) sym).node.type_sema;
        return node;
    }

    Node analyzeIfStmt(IfStmt node)
    {
        // se tiver expresão então tem um If
        if (node.expr !is null)
            node.expr = analyze(node.expr);

        for (uint i; i < node.body.length; i++)
            node.body[i] = analyze(node.body[i]);

        if (node._else !is null)
            node._else = as!IfStmt(analyzeIfStmt(node._else));

        return node;
    }

    Node analyzeCallExpr(CallExpr node)
    {
        dstring getName(Node n)
        {
            switch (n.kind)
            {
            case NodeKind.Identifier:
                return (as!Identifier(n)).value;
            case NodeKind.StringLit:
                return (as!StringLit(n)).value;
            default:
                return "";
            }
        }

        dstring name = getName(node.fn);
        d_enforce(name != "", "Nome inválido para a função.", node.pos, err);

        Symbol* sym = context.get(name);
        d_enforce(sym !is null, "Função inexistente.", node.pos, err);
        node.type_sema = (cast(SymbolFn*) sym).node.type_sema;

        for (uint i; i < node.args.length; i++)
            node.args[i] = analyze(node.args[i]);

        return node;
    }

    Node analyzeReturnStmt(ReturnStmt node)
    {
        if (node.val !is null)
            node.val = analyze(node.val);
        return node;
    }

    Node analyzeFnDecl(FnDecl node)
    {
        context.push();
        node.type_sema = resolver.resolver(node.type_expr);
        
        for (uint i; i < node.args.length; i++)
        {
            FnArg arg = node.args[i];
            if (arg.value !is null)
                arg.value = analyze(arg.value);
            arg.type_sema = resolver.resolver(arg.type_expr);
            context.set(arg.name, new SymbolParam(arg));
        }

        for (uint i; i < node.body.length; i++)
            node.body[i] = analyze(node.body[i]);
            
        context.pop();
        return node;
    }

    Node analyzeBinaryExpr(BinaryExpr node)
    {
        node.left = analyze(node.left);
        node.right = analyze(node.right);

        TypeSema l = node.left.type_sema;
        TypeSema r = node.right.type_sema;

        if (!l.isComp(r))
        {
            // ERR, tipos invalidos
            err.error(node.pos, format("Tipos incompativeis, '%s' com '%s'.", l.toStr(), r.toStr()));
            node.type_sema = new TypeSemaBuiltin(TypeSemaBase.Any);
            return node;
        }

        TypeSema type = l.promote(r);
        node.left.type_sema = type;
        node.right.type_sema = type;

        switch (node.op)
        {
            case TokenKind.EEquals:
            case TokenKind.LEquals:
            case TokenKind.GEquals:
            case TokenKind.LThan:
            case TokenKind.GThan:
                type = new TypeSemaBuiltin(TypeSemaBase.Logico);
                break;
            default:
                break;
        }

        node.type_sema = type;
        return node;
    }

    Node analyzeVarDecl(VarDecl node)
    {
        // TODO: validar melhor
        node.value = analyze(node.value);
        node.type_sema = node.value.type_sema;
        context.set(node.name, new SymbolVar(node));
        return node;
    }

public:
    this(Context context, TypeRegistry registry, TypeResolver resolver, Diagnostics err)
    {
        this.context = context;
        this.registry = registry;
        this.resolver = resolver;
        this.err = err;
    }

    void analyze(Program program)
    {
        context.cursor = 0; // reseta o cursor em -1 e faz context.enter() indo pra 0
        foreach (ref Node node; program.body)
            node = analyze(node);
    }
}
