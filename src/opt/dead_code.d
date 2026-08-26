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
            
            if (ret) 
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
                return context.get(fn.fn).uses > 0 ? node : null;

            case NodeKind.VarDecl:
                Symbol* sym = context.get((cast(VarDecl) node).name);
                if (sym is null) return node;
                long uses = sym.uses;
                // writefln("var: %s = %d", (cast(SymbolVar*)sym).node.name, uses);
                return uses > 0 ? node : null;

            case NodeKind.AssignStmt:
                AssignStmt assign = cast(AssignStmt) node;
                return context.get((cast(Identifier)assign.left).value).uses > 0 ? node : null;

            case NodeKind.IfStmt:
                IfStmt ifstmt = cast(IfStmt) node;
                ifstmt.body = remove(ifstmt.body);
                
                if (ifstmt.expr is null)
                    return new BlockStmt(ifstmt.body, ifstmt.pos);

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
