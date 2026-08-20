// resolve todos os nodes
module frontend.semantic.sema3;

import std.exception;
import std.format;
import std.stdio;

import frontend.semantic;
import frontend.parser;
import ctfe.ctfe_flags;
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
        if (node.type_sema !is null || node.kind == NodeKind.NaN) return node;

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

            case NodeKind.AssignStmt:
                return analyzeAssignStmt(as!AssignStmt(node));

            case NodeKind.StringLit:
            case NodeKind.IntLit:
            case NodeKind.DoubleLit:
            case NodeKind.BoolLit:
                node.type_sema = resolver.resolver(node.type_expr);
                return node;

            default:
                err.error(node.pos, "Node desconhecido.");
                return node;
        }
    }

    Node analyzeAssignStmt(AssignStmt node)
    {
        if (node.left.kind != NodeKind.Identifier)
        {
            err.error(node.pos, "Atribuição inválida: o lado esquerdo da operação deve ser uma variável.");
            return node;
        }

        Identifier var = as!Identifier(node.left);
        dstring name = var.value;

        Symbol* sym = context.get(name);
        if (sym is null || !sym.isVar())
        {
            err.error(var.pos, format("A variavel '%s' não existe.", name));
            return node;
        }

        SymbolVar* symv = cast(SymbolVar*) sym;

        if (symv.isConstant)
        {
            err.error(var.pos, format("A variavel '%s' não pode ser reatribuída pois é uma constante.", name));
            alreadyDeclaredHere(name, symv.node.pos, err);
            return node;
        }

        node.value = analyze(node.value);

        if (!checkTypes(node.pos, symv.node.type_sema, node.value.type_sema))
            alreadyDeclaredHere(name, symv.node.pos, err);

        return node;
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
        
        if (sym is null)
        {
            err.warning(node.pos, "Simbolo não encontrado.");
            return node;
        }

        if (sym.isFn())
        {
            err.error(node.pos, "Não é possível usar o nome de uma função como identificador solto.");
            alreadyDeclaredHere(node.value, (cast(SymbolFn*) sym).node.pos, err);
        }

        sym.uses++;
        node.type_sema = (cast(SymbolVar*) sym).node.type_sema;
        return node;
    }

    Node analyzeIfStmt(IfStmt node)
    {
        // se tiver expresão então tem um If
        if (node.expr !is null)
            node.expr = analyze(node.expr);

        for (size_t i; i < node.body.length; i++)
            node.body[i] = analyze(node.body[i]);

        if (node._else !is null)
            node._else = as!IfStmt(analyzeIfStmt(node._else));

        return node;
    }

    Node analyzeCallExpr(CallExpr node)
    {
        // dstring getName(Node n)
        // {
        //     switch (n.kind)
        //     {
        //     case NodeKind.Identifier:
        //         return (as!Identifier(n)).value;
        //     case NodeKind.StringLit:
        //         return (as!StringLit(n)).value;
        //     default:
        //         return "";
        //     }
        // }

        dstring name = (as!Identifier(node.fn)).value;
        Symbol* sym = context.get(name);
        
        if (sym is null)
            err.error(node.pos, format("A função '%s' não existe.", name));

        sym.uses++;
        SymbolFn* symf = cast(SymbolFn*) sym;
        node.type_sema = symf.node.type_sema;

        for (uint i; i < node.args.length; i++)
        {
            node.args[i] = analyze(node.args[i]);
            
            if (symf.node.args.length < 1) 
                continue;
            
            FnArg arg = symf.node.args[i];
            if (!checkTypes(node.args[i].pos, arg.type_sema, node.args[i].type_sema))
                alreadyDeclaredHere(arg.name, arg.pos, err);
        }

        return node;
    }

    Node analyzeReturnStmt(ReturnStmt node)
    {
        if (node.val !is null) node.val = analyze(node.val);
        return node;
    }

    Node analyzeFnDecl(FnDecl node)
    {
        context.push();
        node.type_sema = resolver.resolver(node.type_expr);

        // if (node.ctfe_flags & CTFEFlags.Pure)
        //     writefln("Função pura detectada: %s", node.fn);
        
        for (uint i; i < node.args.length; i++)
        {
            FnArg arg = node.args[i];
            if (arg.value !is null) arg.value = analyze(arg.value);
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

        if (!checkTypes(node.pos, l, r))
        {
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
                type = new TypeSemaBuiltin(TypeSemaBase.Bool);
                break;
            default:
                break;
        }

        node.type_sema = type;
        return node;
    }

    Node analyzeVarDecl(VarDecl node)
    {
        node.value = analyze(node.value);

        dstring name = node.name;
        if (Symbol* sym = context.get(name))
        {
            err.error(node.pos, format("%s '%s' já existe.", ternary(sym.isVar(), "A variavel", "O simbolo"), name));
            alreadyDeclaredHere(name, getPosFromSymbol(sym), err);
        }

        TypeSema valueType = node.value.type_sema;
        // writeln(name, ": ", valueType.toStr());
        // writeln(node.type_sema, "\n");
        
        if (node.type_expr !is null)
        {
            updateType(node, resolver); // atualiza o tipo semantico para fazer o checkTypes
            if (checkTypes(node.pos, node.type_sema, valueType))
                node.type_sema = valueType; // é compativel? pode ter havido cast implicito, atualiza
        }
        else
            node.type_sema = valueType; // inferencia

        context.set(node.name, new SymbolVar(node, node.isConst));
        return node;
    }

    pragma(inline, true)
    bool checkTypes(Position pos, TypeSema t1, TypeSema t2)
    {
        bool comp = t1.isComp(t2);
        if (!comp)
            err.error(pos, format("Incompatibilidade de tipo: era esperado '%s' mas foi recebido '%s'.",
                t1.toStr(), t2.toStr()));
        return comp;
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
