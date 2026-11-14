module opt.dead_code;

import std.algorithm;
import std.stdio;
import std.array;

import frontend.semantic.context;
import frontend.semantic.symbol;
import frontend.lexer.token;
import frontend.parser.ast;
import utils;
import ctfe;

final class CgdDeadCode
{
private:
    Program program;
    Context context;

    Node[] remove(Node[] body)
    {
        Node[] newBody;
        bool ret;
        foreach (Node child; body)
        {
            Node res = remove(child);

            if (res is null)
                continue;

            if (ret && res.kind!=NodeKind.FnDecl && res.kind!=NodeKind.ClassDecl)
                continue;

            if (res.kind == NodeKind.ReturnStmt)
                ret = true;

            newBody ~= res;
        }
        return newBody;
    }

    Node remove(Node node)
    {
        if (node is null) return node;

        switch (node.kind)
        {
            case NodeKind.Program:
                Program prog = cast(Program) node;
                prog.body = remove(prog.body);
                return node;

            case NodeKind.FnDecl:
                FnDecl fn = cast(FnDecl) node;
                fn.body = remove(fn.body);
                return node;

            case NodeKind.VarDecl:
            case NodeKind.AssignStmt:
                // Inicializadores e escritas podem ter efeitos, validar ou lançar erros.
                return node;

            case NodeKind.IfStmt:
                IfStmt ifstmt = cast(IfStmt) node;
                ifstmt.body = remove(ifstmt.body);

                if (ifstmt.expr is null) return node;

                if (ifstmt._else !is null)
                    ifstmt._else = cast(IfStmt) remove(cast(Node) ifstmt._else);

                if (ifstmt.expr.kind == NodeKind.BoolLit)
                {
                    if ((cast(BoolLit) ifstmt.expr).value)
                        return new BlockStmt(ifstmt.body, ifstmt.pos);
                    else
                    {
                        if (ifstmt._else is null) return null;
                        return cast(Node) ifstmt._else;
                    }
                }

                return node;

            default:
                return node;
        }
    }

public:
    this(Program program, Context context)
    {
        this.program = program;
        this.context = context;
    }

    void remove()
    {
        remove(program);
    }
}
