module middle.lowering;

import backend.c.utils : formatD;
import std.stdio;

import frontend.parser;
import frontend.lexer;
import frontend;
import utils;

final class CgdLowering
{
private:
    const dstring[TokenKind] opToFn = [
        TokenKind.Plus:    "delegua_op_add",
        TokenKind.Minus:   "delegua_op_sub",
        TokenKind.Star:    "delegua_op_mul",
        TokenKind.Slash:   "delegua_op_div",
        TokenKind.Modulo:  "delegua_op_mod",

        TokenKind.EEquals: "delegua_op_eq",

        TokenKind.LEquals: "delegua_op_le",
        TokenKind.LThan:   "delegua_op_lt",

        TokenKind.GEquals: "delegua_op_ge",
        TokenKind.GThan:   "delegua_op_gt",

        TokenKind.BITOr:   "delegua_op_bor",
        TokenKind.BITAnd:  "delegua_op_bnd",
        TokenKind.BITNot:  "delegua_op_bnt",
        TokenKind.BITXor:  "delegua_op_bxr",
        TokenKind.BITSL:   "delegua_op_shl",
        TokenKind.BITSR:   "delegua_op_shr",

        TokenKind.Bang:    "delegua_op_not",
    ];

    Diagnostics err;

    Node[] loweringBody(Node[] body, bool isExpr = false)
    {
        Node[] nodes;
        foreach (Node child; body)
        {
            Node node = isExpr ? loweringExpr(child) : loweringStmt(child);
            if (node !is null) nodes ~= node;
        }
        return nodes;
    }

    Node loweringStmt(Node node)
    {
        switch (node.kind)
        {
            case NodeKind.FnDecl:
                FnDecl fn = cast(FnDecl) node;
                fn.body = loweringBody(fn.body);
                return node;

            case NodeKind.VarDecl:
                VarDecl var = cast(VarDecl) node;
                var.value = loweringExpr(var.value);
                return node;

            case NodeKind.AssignStmt:
                AssignStmt ass = cast(AssignStmt) node;
                checkLValue(ass.left);
                ass.value = loweringExpr(ass.value);
                return node;

            case NodeKind.ReturnStmt:
                ReturnStmt ret = cast(ReturnStmt) node;
                if (ret.val !is null)
                    ret.val = loweringExpr(ret.val);
                return node;

            case NodeKind.CallExpr:
                CallExpr call = cast(CallExpr) node;
                call.args = loweringBody(call.args, true);
                return node;

            case NodeKind.IfStmt:
                IfStmt ifstmt = cast(IfStmt) node;
                
                if (ifstmt.expr !is null)
                    ifstmt.expr = loweringExpr(ifstmt.expr);

                ifstmt.body = loweringBody(ifstmt.body);

                if (ifstmt._else !is null)
                    ifstmt._else = cast(IfStmt) loweringStmt(cast(Node) ifstmt._else);

                return node;

            case NodeKind.BlockStmt:
                BlockStmt block = cast(BlockStmt) node;
                block.body = loweringBody(block.body);
                return node;

            case NodeKind.WhileStmt:
                WhileStmt wstmt = cast(WhileStmt) node;
                wstmt.expr = loweringExpr(wstmt.expr);
                wstmt.body = loweringBody(wstmt.body);
                return node;

            case NodeKind.MemberExpr:
                MemberExpr member = cast(MemberExpr) node;
                member.left = loweringExpr(member.left);
                member.right = loweringExpr(member.right);
                return node;

            case NodeKind.UnaryExpr:
                // x++
                // x = x + 1
                return loweringUnaryExpr(cast(UnaryExpr) node);

            default:
                err.error(node.pos, "Era esperado uma declaração com efeito.");
                return node;
        }
    }

    Node loweringExpr(Node node)
    {
        switch (node.kind)
        {
            case NodeKind.Identifier:
            case NodeKind.CallExpr:
            case NodeKind.ArrayLit:
            case NodeKind.IndexExpr:
                return node;

            case NodeKind.StringLit:
            case NodeKind.IntLit:
            case NodeKind.DoubleLit:
            case NodeKind.BoolLit:
            case NodeKind.BlockStmt:
                return node;

            case NodeKind.BinaryExpr:
                return loweringBinaryExpr(cast(BinaryExpr) node);

            case NodeKind.UnaryExpr:
                return loweringUnaryExpr(cast(UnaryExpr) node);

            default:
                err.error(node.pos, "Era esperado uma expressão válida.");
                return node;
        }
    }

    Node loweringUnaryExpr(UnaryExpr un)
    {
        // operadores que necessitam de atribuição
        TokenKind[TokenKind] ops = [
            TokenKind.PPlus: TokenKind.Plus,
            TokenKind.MMinus: TokenKind.Minus,
            TokenKind.Minus:  TokenKind.Minus,
        ];

        // operadores comuns
        TokenKind[TokenKind] unary = [
            TokenKind.BITNot: TokenKind.BITNot,
            TokenKind.Bang:   TokenKind.Bang,
        ];

        un.value = loweringExpr(un.value);

        if (un.op in unary)
        {
            const(dstring)* fn = un.op in opToFn;
            return createCallExpr(*fn, [un.value], un.pos);
        }

        checkLValue(un.value);

        TokenKind* mapped = un.op in ops;
        if (mapped is null)
        {
            err.error(un.pos, "Operador unário inválido.");
            return un;
        }

        static size_t tmpCount;
        dstring tmpName = formatD("__temp%d", tmpCount++);

        Node[] stmts;

        VarDecl tmp = new VarDecl(tmpName, un.value, false, null, un.pos);
        stmts ~= tmp;

        BinaryExpr bexpr = new BinaryExpr(un.value, new IntLit(1, un.pos), *mapped, un.pos);
        AssignStmt ass = new AssignStmt(un.value, bexpr, TokenKind.Equals, un.pos);
        ass.value = loweringExpr(ass.value);
        stmts ~= ass;

        Node result = un.post
            ? new Identifier(tmpName, un.pos) // i++ -> valor antigo (temp)
            : un.value;                       // ++i -> valor novo (o próprio i)

        stmts ~= result;

        BlockStmt block = new BlockStmt(stmts, un.pos);
        return block;
    }

    Node loweringBinaryExpr(BinaryExpr node)
    {
        Node left = loweringExpr(node.left);
        Node right = loweringExpr(node.right);

        const(dstring)* fn = node.op in opToFn;
        if (fn is null)
        {
            err.error(node.pos, "Operação binária inválida.");
            return node;
        }

        return createCallExpr(*fn, [left, right], node.pos);
    }

    pragma(inline, true)
    Node createCallExpr(dstring name, Node[] args, Position pos = Position.init)
    {
        return new CallExpr(new Identifier(name, pos), args, pos);
    }

    void checkLValue(Node node)
    {
        switch (node.kind)
        {
            case NodeKind.Identifier:
            case NodeKind.IndexExpr:
                return;
            
            default:
                err.error(node.pos, "Era esperado uma expressão válida para atribuição de valor.");
                return;
        }
    }

public:
    this(Diagnostics err)
    {
        this.err = err;
    }

    void lowering(Program program)
    {
        program.body = loweringBody(program.body);
    }
}
