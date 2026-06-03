// resolve todos os nodes
module frontend.semantic.sema3;

import utils;
import std.stdio;
import std.exception;
import frontend;
import frontend.parser;
import frontend.semantic;

class Sema3
{
private:
    Context context;
    TypeRegistry registry;
    TypeResolver resolver;

    void analyze(Node node)
    {
        enforce(node !is null, "Node nulo recebido.");
        if (node.type_sema !is null)
            return;

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

        case NodeKind.StringLit:
        case NodeKind.IntLit:
        case NodeKind.FloatLit:
        case NodeKind.DoubleLit:
            node.type_sema = resolver.resolver(node.type_expr);
            return;

        default:
            writeln("Node Desconhecido: ", node);
            return;
        }
    }

    void analyzeIdentifier(Identifier node)
    {
        Symbol* sym = context.get(node.value);
        enforce(sym !is null, "Variavel inexistente.");
        node.type_sema = (cast(SymbolVar*)(*sym)).node.type_sema;
    }

    void analyzeIfStmt(IfStmt node)
    {
        // se tiver expresão então tem um If
        if (node.expr !is null)
            analyze(node.expr);

        for (uint i; i < node.body.length; i++)
            analyze(node.body[i]);

        if (node._else !is null)
            analyzeIfStmt(node._else);
    }

    void analyzeCallExpr(CallExpr node)
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
        enforce(name != "", "Nome inválido para a função.");

        Symbol* sym = context.get(name);
        enforce(sym !is null, "Função inexistente.");
        node.type_sema = (cast(SymbolFn)(*sym)).node.type_sema;

        for (uint i; i < node.args.length; i++)
            analyze(node.args[i]);
    }

    void analyzeReturnStmt(ReturnStmt node)
    {
        if (node.val !is null)
            analyze(node.val);
    }

    void analyzeFnDecl(FnDecl node)
    {
        context.push();
        node.type_sema = resolver.resolver(node.type_expr);
        for (uint i; i < node.args.length; i++)
        {
            FnArg arg = node.args[i];
            if (arg.value !is null)
                analyze(arg.value);
            arg.type_sema = resolver.resolver(arg.type_expr);
            context.set(arg.name, new SymbolParam(arg));
        }
        for (uint i; i < node.body.length; i++)
            analyze(node.body[i]);
        context.pop();
    }

    void analyzeBinaryExpr(BinaryExpr node)
    {
        // TODO: melhorar
        analyze(node.left);
        analyze(node.right);
        node.type_sema = node.left.type_sema;
    }

    void analyzeVarDecl(VarDecl node)
    {
        // TODO: validar melhor
        analyze(node.value);
        node.type_sema = node.value.type_sema;
        context.set(node.name, new SymbolVar(node));
    }

public:
    this(Context context, TypeRegistry registry, TypeResolver resolver)
    {
        this.context = context;
        this.registry = registry;
        this.resolver = resolver;
    }

    void analyze(Program program)
    {
        context.cursor = 0; // reseta o cursor em -1 e faz context.enter() indo pra 0
        foreach (Node node; program.body)
            analyze(node);
    }
}
