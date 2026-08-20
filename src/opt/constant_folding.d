module opt.constant_folding;

import std.algorithm;
import std.stdio;
import std.array;

import frontend.semantic.context;
import frontend.semantic.symbol;
import frontend.lexer.token;
import frontend.parser.ast;
import utils;
import ctfe;

final class CgdConstantFolding
{
private:
    CTFEContext ctfe;
    Program program;
    Context context;

    Node getConstant(Node n)
    {
        // writeln("get: ", n);
        if (n is null) goto end;

        switch (n.kind)
        {
            case NodeKind.Identifier:
                Identifier id = as!Identifier(n);
                Symbol* sym = context.get(id.value);

                // writeln(id.value);
                // writeln(sym);

                if (sym is null) 
                    goto end;

                SymbolVar symv = cast(SymbolVar)*sym;
                if (symv is null) 
                    goto end;

                sym.uses--;
                return getConstant(symv.node.value);

            // constantes
            case NodeKind.IntLit:
            case NodeKind.DoubleLit:
            case NodeKind.BoolLit:
            case NodeKind.StringLit:
                return n;

            case NodeKind.BinaryExpr:
                return foldBinary(as!BinaryExpr(n));

            case NodeKind.CallExpr:
                return opt(n);

            default:
                break;
        }

    end:
        return null;
    }

    Node foldBinary(BinaryExpr expr)
    {
        Node l = getConstant(expr.left);
        Node r = getConstant(expr.right);

        if (l is null || r is null)
            return null;

        // promoção: int op double → double
        if (l.kind == NodeKind.IntLit && r.kind == NodeKind.DoubleLit)
            l = new DoubleLit(cast(double)(as!IntLit(l)).value, l.pos);
        else if (l.kind == NodeKind.DoubleLit && r.kind == NodeKind.IntLit)
            r = new DoubleLit(cast(double)(as!IntLit(r)).value, r.pos);

        if (l.kind != r.kind)
            return null;

        Node fold(T)(string op)
        {
            static if (is(T == IntLit))
            {
                if (op == "/" && (as!IntLit(r)).value == 0) 
                    return null;
            }
            else static if (is(T == DoubleLit))
                if (op == "/" && (as!DoubleLit(r)).value == 0.0) 
                    return null;

            switch (op)
            {
                static foreach (OP; [
                        "+", "-", "*", "/", "<", ">", "<=", ">=", "=="
                    ])
                {
                case OP:
                        return new T(
                            mixin("(as!T(l)).value " ~ OP ~ " (as!T(r)).value"),
                            expr.pos
                        );
                    }
                default:
                    return null;
            }
        }

        string op;
        switch (expr.op) with (TokenKind)
        {
            case Plus:    op = "+";  break;
            case Minus:   op = "-";  break;
            case Star:    op = "*";  break;
            case Slash:   op = "/";  break;
            case LThan:   op = "<";  break;
            case GThan:   op = ">";  break;
            case LEquals: op = "<="; break;
            case GEquals: op = ">="; break;
            case EEquals: op = "=="; break;
            default:
                return null;
        }

        if (l.kind == NodeKind.StringLit && r.kind == NodeKind.StringLit)
        {
            dstring s1 = (cast(StringLit) l).value;
            dstring s2 = (cast(StringLit) r).value;
            if (op == "+")  return new StringLit(s1 ~ s2, l.pos);
            if (op == "==") return new BoolLit(s1 == s2, l.pos);
        }

        if (l.kind == NodeKind.IntLit)
            return fold!IntLit(op);

        if (l.kind == NodeKind.DoubleLit)
            return fold!DoubleLit(op);

        return null;
    }

    Node opt(Node node)
    {
        if (node is null) return node;

        switch (node.kind)
        {
            case NodeKind.Program:
                foreach (ref Node child; (as!Program(node)).body)
                    child = opt(child);
                return node;

            case NodeKind.FnDecl:
                foreach (ref Node child; (as!FnDecl(node)).body)
                    child = opt(child);
                return node;

            case NodeKind.VarDecl:
                VarDecl var = as!VarDecl(node);
                Node folded = getConstant(var.value);
                
                if (folded !is null)
                {
                    var.value = folded;
                    var.type_sema = folded.type_sema;
                }
                
                return node;

            case NodeKind.ReturnStmt:
                ReturnStmt ret = as!ReturnStmt(node);
                
                Node folded = getConstant(ret.val);
                if (folded !is null)
                    ret.val = folded;
                
                return node;

            case NodeKind.CallExpr:
                CallExpr call = as!CallExpr(node);

                dstring name = (cast(Identifier) call.fn).value;
                bool allArgsIsFromComptime = true;
                
                foreach (ref Node child; call.args)
                {
                    Node fold = getConstant(child);
                    if (fold !is null)
                        child = fold;
                    else
                    {
                        child = opt(child);
                        allArgsIsFromComptime = false;
                    }
                }

                // writeln(name, " ", allArgsIsFromComptime);
                // writeln(allArgsIsFromComptime);
                // writeln(ctfe.functions);

                if (allArgsIsFromComptime && name in ctfe.functions)
                {
                    // writeln("CTFE\n");
                    CGDValue[] params = call.args.map!(arg => CTFECompile.nodeToCgdValue(arg)).array;
                    ctfe.functions[name].context.params = params;
                    
                    vmHandle(&ctfe.functions[name]);
                    node = CTFECompile.cgdValueToNode(ctfe.functions[name].context.ret[0]);

                    ctfe.functions[name].pc = 0;

                    Symbol* sym = context.get(name);
                    sym.uses--;
                }
                
                return node;

            case NodeKind.IfStmt:
                IfStmt ifs = as!IfStmt(node);
                
                Node constant = getConstant(ifs.expr);
                if (constant)
                {
                    ifs.opt = true;
                    ifs.expr = constant;
                }
                
                foreach (ref Node child; ifs.body)
                    child = opt(child);
                
                if (ifs._else !is null)
                    ifs._else = cast(IfStmt) opt(ifs._else);
                
                return node;

            case NodeKind.AssignStmt:
                AssignStmt assign = as!AssignStmt(node);
                Node folded = getConstant(assign.value);
                
                if (folded !is null)
                {
                    assign.value = folded;
                    assign.type_sema = folded.type_sema;

                    dstring name = as!Identifier(assign.left).value;
                    Symbol* sym = context.get(name);
                    
                    if (sym)
                    {
                        SymbolVar* symv = cast(SymbolVar*) sym;
                        symv.node.value = folded;
                    }
                }
                
                return node;

            default:
                return node;
        }
    }

public:
    this(Program program, Context context, CTFEContext ctfe)
    {
        this.program = program;
        this.context = context;
        this.ctfe = ctfe;
    }

    void opt()
    {
        opt(program);
    }
}
