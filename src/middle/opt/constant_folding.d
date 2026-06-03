module middle.opt.constant_folding;

import frontend.lexer.token;
import frontend.parser.ast;
import frontend.semantic.context;
import frontend.semantic.symbol;
import utils;

class CgdConstantFolding
{
private:
    Program program;
    Context context;

    // tenta recuperar o valor constante de um Node
    Node getConstant(Node n)
    {
        if (n is null)
            return null;

        switch (n.kind)
        {
        case NodeKind.Identifier:
            Identifier id = as!Identifier(n);
            Symbol* sym = context.get(id.value);
            if (sym is null)
                return null;
            SymbolVar symv = cast(SymbolVar)*sym;
            if (symv is null)
                return null;
            return getConstant(symv.node.value); // recursivo: var pode apontar pra outra var
        case NodeKind.IntLit:
        case NodeKind.DoubleLit:
        case NodeKind.StringLit:
            // case NodeKind.BoolLit:
            return n;
        case NodeKind.BinaryExpr:
            return foldBinary(as!BinaryExpr(n));
        default:
            return null;
        }
    }

    // tenta dobrar uma BinaryExpr em um literal, retorna null se não for possível
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

        // helper local que aplica o operador via mixin de string
        Node fold(T)(string op)
        {
            // divisão por zero
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

        // mapeia TokenKind → operador string
        string op;
        switch (expr.op)
        {
        case TokenKind.Plus:
            op = "+";
            break;
        case TokenKind.Minus:
            op = "-";
            break;
        case TokenKind.Star:
            op = "*";
            break;
        case TokenKind.Slash:
            op = "/";
            break;
        case TokenKind.LThan:
            op = "<";
            break;
        case TokenKind.GThan:
            op = ">";
            break;
        case TokenKind.LEquals:
            op = "<=";
            break;
        case TokenKind.GEquals:
            op = ">=";
            break;
        case TokenKind.EEquals:
            op = "==";
            break;
        default:
            return null;
        }

        if (l.kind == NodeKind.IntLit)
            return fold!IntLit(op);

        if (l.kind == NodeKind.DoubleLit)
            return fold!DoubleLit(op);

        return null;
    }

    void opt(Node node)
    {
        if (node is null)
            return;

        switch (node.kind)
        {
        case NodeKind.Program:
            foreach (child; (as!Program(node)).body)
                opt(child);
            break;

        case NodeKind.FnDecl:
            foreach (child; (as!FnDecl(node)).body)
                opt(child);
            break;

        case NodeKind.VarDecl:
            VarDecl var = as!VarDecl(node);
            Node folded = getConstant(var.value);
            if (folded !is null)
            {
                var.value = folded;
                var.type_sema = folded.type_sema;
            }
            break;

        case NodeKind.ReturnStmt:
            ReturnStmt ret = as!ReturnStmt(node);
            Node folded = getConstant(ret.val);
            if (folded !is null)
                ret.val = folded;
            break;

        case NodeKind.IfStmt:
            IfStmt ifs = as!IfStmt(node);
            ifs.expr = getConstant(ifs.expr);
            ifs.opt = true;
            foreach (child; ifs.body)
                opt(child);
            if (ifs._else !is null)
                opt(ifs._else);
            break;

        default:
            break;
        }
    }

public:
    this(Program program, Context context)
    {
        this.program = program;
        this.context = context;
    }

    void opt()
    {
        opt(program);
    }
}
