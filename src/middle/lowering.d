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
        TokenKind.Plus: "delegua_op_add",
        TokenKind.Minus: "delegua_op_sub",
        TokenKind.Star: "delegua_op_mul",
        TokenKind.Slash: "delegua_op_div",
        TokenKind.Modulo: "delegua_op_mod",

        TokenKind.NEquals: "delegua_op_neq",
        TokenKind.Pow: "delegua_op_pow",
        TokenKind.IntDiv: "delegua_op_idiv",
        TokenKind.In: "delegua_op_in",
        TokenKind.EEquals: "delegua_op_eq",

        TokenKind.LEquals: "delegua_op_le",
        TokenKind.LThan: "delegua_op_lt",

        TokenKind.GEquals: "delegua_op_ge",
        TokenKind.GThan: "delegua_op_gt",

        TokenKind.BITOr: "delegua_op_bor",
        TokenKind.BITAnd: "delegua_op_bnd",
        TokenKind.BITNot: "delegua_op_bnt",
        TokenKind.BITXor: "delegua_op_bxr",
        TokenKind.BITSL: "delegua_op_shl",
        TokenKind.BITSR: "delegua_op_shr",

        TokenKind.Bang: "delegua_op_not",
    ];

    Diagnostics err;

    void lowerDecorators(ref Decorator[] decorators)
    {
        foreach (ref d; decorators)
            d.values = loweringBody(d.values, true);
    }

    Node[] loweringBody(Node[] body, bool isExpr = false)
    {
        Node[] nodes;
        foreach (Node child; body)
        {
            Node node = isExpr ? loweringExpr(child) : loweringStmt(child);
            if (node !is null)
                nodes ~= node;
        }
        return nodes;
    }

    Node loweringStmt(Node node)
    {
        switch (node.kind)
        {
        case NodeKind.SequenceStmt:
            auto sequence = cast(SequenceStmt) node;
            sequence.body = loweringBody(sequence.body);
            return node;
        case NodeKind.SwitchStmt:
            auto s = cast(SwitchStmt) node;
            s.value = loweringExpr(s.value);
            foreach (ref c; s.cases)
            {
                c.values = loweringBody(c.values, true);
                c.body = loweringBody(c.body);
            }
            s.fallback = loweringBody(s.fallback);
            return node;
        case NodeKind.NaN:
            return node;
        case NodeKind.EachStmt:
            auto loop = cast(EachStmt) node;
            loop.iterable = loweringExpr(loop.iterable);
            loop.body = loweringBody(loop.body);
            return node;
        case NodeKind.ForStmt:
            auto loop = cast(ForStmt) node;
            if (loop.init !is null)
                loop.init = loweringStmt(loop.init);
            if (loop.condition !is null)
                loop.condition = loweringExpr(loop.condition);
            if (loop.step !is null)
                loop.step = loweringStmt(loop.step);
            loop.body = loweringBody(loop.body);
            return node;
        case NodeKind.DoStmt:
            auto loop = cast(DoStmt) node;
            loop.condition = loweringExpr(loop.condition);
            loop.body = loweringBody(loop.body);
            return node;
        case NodeKind.BreakStmt:
        case NodeKind.ContinueStmt:
            return node;
        case NodeKind.ThrowStmt:
            auto t = cast(ThrowStmt) node;
            t.value = loweringExpr(t.value);
            return node;
        case NodeKind.TryStmt:
            auto t = cast(TryStmt) node;
            t.body = loweringBody(t.body);
            t.finalBody = loweringBody(t.finalBody);
            foreach (ref c; t.catches)
                c.body = loweringBody(c.body);
            return node;
        case NodeKind.ClassDecl:
            auto c = cast(ClassDecl) node;
            lowerDecorators(c.decorators);
            foreach (ref field; c.fields)
                lowerDecorators(field.decorators);
            foreach (ref method; c.methods)
                method = cast(FnDecl) loweringStmt(method);
            return node;
        case NodeKind.FnDecl:
            FnDecl fn = cast(FnDecl) node;
            lowerDecorators(fn.decorators);
            foreach (arg; fn.args)
                if (arg.value !is null)
                    arg.value = loweringExpr(arg.value);
            fn.body = loweringBody(fn.body);
            return node;

        case NodeKind.VarDecl:
            VarDecl var = cast(VarDecl) node;
            var.value = loweringExpr(var.value);
            return node;

        case NodeKind.AssignStmt:
            AssignStmt ass = cast(AssignStmt) node;
            checkLValue(ass.left);
            if (auto member = cast(MemberExpr) ass.left)
                member.left = loweringExpr(member.left);
            if (auto idx = cast(IndexExpr) ass.left)
            {
                idx.value = loweringExpr(idx.value);
                idx.idx = loweringExpr(idx.idx);
            }
            ass.value = loweringExpr(ass.value);
            return node;

        case NodeKind.ReturnStmt:
            ReturnStmt ret = cast(ReturnStmt) node;
            if (ret.val !is null)
                ret.val = loweringExpr(ret.val);
            return node;

        case NodeKind.CallExpr:
            CallExpr call = cast(CallExpr) node;
            if (!call.runtimeCall)
                call.fn = loweringExpr(call.fn);
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
            // A propriedade é um nome, não uma referência lexical.
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
        case NodeKind.AssignStmt:
            return loweringStmt(node);
        case NodeKind.ConditionalExpr:
            auto c = cast(ConditionalExpr) node;
            c.condition = loweringExpr(c.condition);
            c.yes = loweringExpr(c.yes);
            c.no = loweringExpr(c.no);
            return node;
        case NodeKind.SpreadExpr:
            auto s = cast(SpreadExpr) node;
            s.value = loweringExpr(s.value);
            return node;
        case NodeKind.SliceExpr:
            auto s = cast(SliceExpr) node;
            s.value = loweringExpr(s.value);
            if (s.start !is null)
                s.start = loweringExpr(s.start);
            if (s.end !is null)
                s.end = loweringExpr(s.end);
            if (s.step !is null)
                s.step = loweringExpr(s.step);
            return node;
        case NodeKind.Comprehension:
            auto c = cast(Comprehension) node;
            c.value = loweringExpr(c.value);
            c.iterable = loweringExpr(c.iterable);
            if (c.condition !is null)
                c.condition = loweringExpr(c.condition);
            return node;
        case NodeKind.LoopExpr:
            auto l = cast(LoopExpr) node;
            l.loop = loweringStmt(l.loop);
            return node;
        case NodeKind.ImportExpr:
            auto imported = cast(ImportExpr) node;
            if (imported.target !is null && !imported.target.lowered)
            {
                imported.target.lowered = true;
                imported.target.program.body = loweringBody(imported.target.program.body);
            }
            return node;
        case NodeKind.FunctionExpr:
            auto fn = cast(FunctionExpr) node;
            fn.declaration = cast(FnDecl) loweringStmt(fn.declaration);
            return node;
        case NodeKind.MapLit:
            auto map = cast(MapLit) node;
            foreach (ref key; map.keys)
                if (key !is null)
                    key = loweringExpr(key);
            map.values = loweringBody(map.values, true);
            return node;
        case NodeKind.TypeOfExpr:
            auto type = cast(TypeOfExpr) node;
            return createCallExpr("delegua_tipo_objeto", [
                    loweringExpr(type.value)
                ], type.pos);
        case NodeKind.Identifier:
        case NodeKind.SuperExpr:
            return node;
        case NodeKind.CallExpr:
            auto call = cast(CallExpr) node;
            if (!call.runtimeCall)
                call.fn = loweringExpr(call.fn);
            call.args = loweringBody(call.args, true);
            return node;
        case NodeKind.TupleLit:
        case NodeKind.ArrayLit:
            auto arr = cast(ArrayLit) node;
            arr.elements = loweringBody(arr.elements, true);
            return node;
        case NodeKind.IndexExpr:
            auto idx = cast(IndexExpr) node;
            idx.value = loweringExpr(idx.value);
            idx.idx = loweringExpr(idx.idx);
            return node;
        case NodeKind.MemberExpr:
            auto member = cast(MemberExpr) node;
            member.left = loweringExpr(member.left);
            member.right = loweringExpr(member.right);
            return node;
        case NodeKind.NullLit:
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
        un.value = loweringExpr(un.value);
        switch (un.op)
        {
        case TokenKind.BITNot:
            return createCallExpr("delegua_op_bnt", [un.value], un.pos);
        case TokenKind.Bang:
            return createCallExpr("delegua_op_not", [un.value], un.pos);
        case TokenKind.Minus:
            return createCallExpr("delegua_op_sub", [
                    new IntLit(0, un.pos), un.value
                ], un.pos);
        case TokenKind.Plus:
            return un.value;
        case TokenKind.PPlus:
        case TokenKind.MMinus:
            checkLValue(un.value);
            return un;
        default:
            err.error(un.pos, "Operador unário inválido.");
            return un;
        }
    }

    Node loweringBinaryExpr(BinaryExpr node)
    {
        Node left = loweringExpr(node.left);
        Node right = loweringExpr(node.right);

        if (node.op == TokenKind.And || node.op == TokenKind.Or || node.op == TokenKind.Coalesce)
        {
            node.left = left;
            node.right = right;
            return node;
        }
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
        auto call = new CallExpr(new Identifier(name, pos), args, pos);
        call.runtimeCall = true;
        return call;
    }

    void checkLValue(Node node)
    {
        switch (node.kind)
        {
        case NodeKind.Identifier:
        case NodeKind.MemberExpr:
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
