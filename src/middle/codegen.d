module middle.codegen;

import frontend.lexer.token : TokenKind;
import frontend.parser.ast;
import frontend.type_sema;
import std.conv : to;
import std.format;
import std.array;

class CodeGen
{
private:
    Program program;
    string[] lines;
    uint indent;

    bool[string] fnRuntime = [
        "escreva": true
    ];

    void emit(string s)
    {
        string pad;
        foreach (_; 0 .. indent)
            pad ~= "    ";
        lines ~= pad ~ s;
    }

    void emitRaw(string s)
    {
        lines ~= s;
    }

    string cType()
    {
        return "CGD_Value";
    }

    string name(dstring d)
    {
        return to!string(d);
    }

public:
    this(Program p)
    {
        program = p;
    }

    string generate()
    {
        enum RUNTIME = import("runtime.c");
        emitRaw(RUNTIME);

        // protótipos de funções declaradas
        foreach (node; program.body)
            if (auto fn = cast(FnDecl) node)
                emitRaw(emitProto(fn) ~ ";");
        
        // corpos das funções declaradas
        foreach (node; program.body)
            if (auto fn = cast(FnDecl) node)
                emitFunction(fn);

        // cgd_main: tudo que está no toplevel que não é FnDecl
        emitRaw("void cgd_main(void)");
        emitRaw("{");
        indent++;

        foreach (node; program.body)
            if (cast(FnDecl) node is null)
                emitStmt(node);

        emit("return;");
        emitRaw("}");

        return lines.join("\n");
    }

    string debug_comment(dstring s)
    {
        return debug_comment(name(s));
    }

    string debug_comment(string s)
    {
        return " /* " ~ s ~ " */ ";
    }

private:
    // protótipo: "CGD_Value foo(CGD_Value x, CGD_Value y)"
    string emitProto(FnDecl fn)
    {
        auto buf = appender!string();
        buf ~= cType() ~ debug_comment(fn.type_sema.toStr()) ~ " " ~ name(fn.fn) ~ "(";

        foreach (i, arg; fn.args)
        {
            if (i > 0)
                buf ~= ", ";
            buf ~= cType() ~ debug_comment(arg.type_sema.toStr()) ~ " " ~ name(arg.name);
        }

        buf ~= ")";
        return buf[];
    }

    void emitFunction(FnDecl fn)
    {
        emitRaw(emitProto(fn));
        emitRaw("{");
        indent++;

        foreach (stmt; fn.body)
            emitStmt(stmt);

        indent--;
        emitRaw("}");
        emitRaw("");
    }

    void emitStmt(Node node)
    {
        if (ReturnStmt r = cast(ReturnStmt) node)
        {
            emit("return " ~ emitExpr(r.val) ~ ";");
            return;
        }

        if (VarDecl v = cast(VarDecl) node)
        {
            string val = v.value !is null ? emitExpr(v.value) : "cgd_int(0)";
            emit(cType() ~ " " ~ name(v.name) ~ " = " ~ val ~ ";");
            return;
        }

        if (CallExpr call = cast(CallExpr) node)
        {
            emit(emitExpr(call) ~ ";");
            return;
        }

        if (IfStmt iff = cast(IfStmt) node)
        {
            emitIf(iff);
            return;
        }

        // fallback: tenta emitir como expressão-statement
        emit("/* stmt não implementado: " ~ node.kind.to!string ~ " */");
    }

    void emitIf(IfStmt node)
    {
        string header = node.expr !is null
            ? "if (__cgd_is_truthy(" ~ emitExpr(node.expr) ~ "))" : "else";

        emitRaw(" ".replicate(indent * 4) ~ header);
        emitRaw(" ".replicate(indent * 4) ~ "{");
        indent++;
        foreach (s; node.body)
            emitStmt(s);
        indent--;
        emitRaw(" ".replicate(indent * 4) ~ "}");

        if (node._else !is null)
        {
            if (node._else.expr !is null)
                // else if — prefixar com "else "
                // hack simples: emitir o próximo if e colar "else " na frente
                emitElseIf(node._else);
            else
                emitIf(node._else); // else puro
        }
    }

    void emitElseIf(IfStmt node)
    {
        string header = "else if (__cgd_is_truthy(" ~ emitExpr(node.expr) ~ "))";
        emitRaw(" ".replicate(indent * 4) ~ header);
        emitRaw(" ".replicate(indent * 4) ~ "{");
        indent++;
        foreach (s; node.body)
            emitStmt(s);
        indent--;
        emitRaw(" ".replicate(indent * 4) ~ "}");

        if (node._else !is null)
        {
            if (node._else.expr !is null)
                emitElseIf(node._else);
            else
                emitIf(node._else);
        }
    }

    // string emitTypeOf(TypeOfExpr node)
    // {
    //     return name(node.value.type_sema.toStr());
    // }

    string emitExpr(Node node)
    {
        if (IntLit lit = cast(IntLit) node)
            return format("cgd_int(%dL)", lit.value);

        if (DoubleLit lit = cast(DoubleLit) node)
            return format("cgd_double(%g.0)", lit.value);

        if (StringLit lit = cast(StringLit) node)
            return format(`cgd_str("%s")`, to!string(lit.value));

        if (Identifier id = cast(Identifier) node)
            return name(id.value);

        if (BinaryExpr bin = cast(BinaryExpr) node)
            return emitBinary(bin);

        if (CallExpr call = cast(CallExpr) node)
            return emitCall(call);

        if (UnaryExpr u = cast(UnaryExpr) node)
            return emitUnary(u);
        
        // if (TypeOfExpr toe = cast(TypeOfExpr) node)
        //     return emitTypeOf(toe);

        return "/* expr? */";
    }

    string emitBinary(BinaryExpr node)
    {
        string l = emitExpr(node.left);
        string r = emitExpr(node.right);

        switch (node.op)
        {
        case TokenKind.Plus:
            return format("__cgd_binary_op_add(%s, %s)", l, r);
        case TokenKind.Minus:
            return format("__cgd_binary_op_minus(%s, %s)", l, r);
        case TokenKind.Star:
            return format("__cgd_binary_op_mul(%s, %s)", l, r);
        case TokenKind.EEquals:
            return format("__cgd_binary_op_ee(%s, %s)", l, r);
        case TokenKind.LThan:
            return format("__cgd_binary_op_lt(%s, %s, %d)", l, r, 0);
        case TokenKind.GThan:
            return format("__cgd_binary_op_gt(%s, %s, %d)", l, r, 0);
        case TokenKind.LEquals:
            return format("__cgd_binary_op_lt(%s, %s, %d)", l, r, 1);
        case TokenKind.GEquals:
            return format("__cgd_binary_op_gt(%s, %s, %d)", l, r, 1);
        default:
            return format("/* op %s */(%s)", node.op.to!string, l);
        }
    }

    string emitUnary(UnaryExpr node)
    {
        string v = emitExpr(node.value);
        switch (node.op)
        {
        case TokenKind.Minus:
            return format("__cgd_binary_mul(%s, cgd_int(-1L))", v);
        default:
            return format("/* unary %s */(%s)", node.op.to!string, v);
        }
    }

    string emitCall(CallExpr node)
    {
        auto buf = appender!string();

        string fnName;
        if (Identifier id = cast(Identifier) node.fn)
        {
            fnName = name(id.value);
            if (fnName in fnRuntime)
                fnName = "cgd_" ~ fnName; // escreva -> cgd_escreva
        }
        else
            fnName = emitExpr(node.fn);

        buf ~= fnName ~ "(";
        foreach (i, arg; node.args)
        {
            if (i > 0)
                buf ~= ", ";
            buf ~= emitExpr(arg);
        }
        buf ~= ")";

        return buf[];
    }
}
