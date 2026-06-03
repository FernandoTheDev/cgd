module middle.codegen;

import frontend.parser.ast;
import frontend.type_sema;
import std.format;
import std.array;
import std.conv : to;

class CodeGen
{
private:
    Program program;
    string[] lines; // linhas do arquivo final
    uint indent; // indentação atual (dentro de funções)

    bool[string] fnRuntime = [
        "escreva": true
    ];

    // ----------------------------------------------------
    // helpers de indentação
    // ----------------------------------------------------
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

    // ----------------------------------------------------
    // tipos
    // ----------------------------------------------------
    // por enquanto tudo é CGD_Value — sem distinção no C gerado
    string cType()
    {
        return "CGD_Value";
    }

    // converte nome dstring -> string
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
        {
            if (auto fn = cast(FnDecl) node)
                emitRaw(emitProto(fn) ~ ";");
        }

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

private:
    // ----------------------------------------------------
    // protótipo: "CGD_Value foo(CGD_Value x, CGD_Value y)"
    // ----------------------------------------------------
    string emitProto(FnDecl fn)
    {
        auto buf = appender!string();
        buf ~= cType() ~ " " ~ name(fn.fn) ~ "(";

        foreach (i, arg; fn.args)
        {
            if (i > 0)
                buf ~= ", ";
            buf ~= cType() ~ " " ~ name(arg.name);
        }

        buf ~= ")";
        return buf[];
    }

    // ----------------------------------------------------
    // corpo completo da função
    // ----------------------------------------------------
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

    // ----------------------------------------------------
    // statements
    // ----------------------------------------------------
    void emitStmt(Node node)
    {
        if (auto r = cast(ReturnStmt) node)
        {
            emit("return " ~ emitExpr(r.val) ~ ";");
            return;
        }

        if (auto v = cast(VarDecl) node)
        {
            string val = v.value !is null ? emitExpr(v.value) : "cgd_int(0)";
            emit(cType() ~ " " ~ name(v.name) ~ " = " ~ val ~ ";");
            return;
        }

        if (auto call = cast(CallExpr) node)
        {
            emit(emitExpr(call) ~ ";");
            return;
        }

        if (auto iff = cast(IfStmt) node)
        {
            emitIf(iff);
            return;
        }

        // fallback: tenta emitir como expressão-statement
        emit("/* stmt não implementado: " ~ node.kind.to!string ~ " */");
    }

    // ----------------------------------------------------
    // if / else if / else
    // ----------------------------------------------------
    void emitIf(IfStmt node)
    {
        // else puro: expr é nulo
        string header = node.expr !is null
            ? "if (__cgd_is_truthy(" ~ emitExpr(node.expr) ~ "))" : "else";

        if (node.expr !is null && node._else !is null && node._else.expr !is null)
        {
            // vai virar "} else if" — emitido junto
        }
     
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
            {
                // else if — prefixar com "else "
                // hack simples: emitir o próximo if e colar "else " na frente
                emitElseIf(node._else);
            }
            else
                emitIf(node._else); // else puro
        }
    }

    void emitElseIf(IfStmt node)
    {
        string header = "else if (" ~ emitExpr(node.expr) ~ ".i.val)";
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

    // ----------------------------------------------------
    // expressões -> string C
    // ----------------------------------------------------
    string emitExpr(Node node)
    {
        if (auto lit = cast(IntLit) node)
            return format("cgd_int(%dL)", lit.value);

        if (auto lit = cast(FloatLit) node)
            return format("cgd_float(%gf)", lit.value);

        if (auto lit = cast(DoubleLit) node)
            return format("cgd_double(%g)", lit.value);

        if (auto lit = cast(StringLit) node)
            return format(`cgd_str("%s")`, to!string(lit.value));

        if (auto id = cast(Identifier) node)
            return name(id.value);

        if (auto bin = cast(BinaryExpr) node)
            return emitBinary(bin);

        if (auto call = cast(CallExpr) node)
            return emitCall(call);

        if (auto u = cast(UnaryExpr) node)
            return emitUnary(u);

        return "/* expr? */";
    }

    // ----------------------------------------------------
    // operações binárias
    // ----------------------------------------------------
    string emitBinary(BinaryExpr node)
    {
        import frontend.lexer.token : TokenKind;

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

    // ----------------------------------------------------
    // unário
    // ----------------------------------------------------
    string emitUnary(UnaryExpr node)
    {
        import frontend.lexer.token : TokenKind;

        string v = emitExpr(node.value);
        switch (node.op)
        {
        case TokenKind.Minus:
            return format("cgd_int(-%s.i.val)", v);
        default:
            return format("/* unary %s */(%s)", node.op.to!string, v);
        }
    }

    // ----------------------------------------------------
    // chamadas de função
    // ----------------------------------------------------
    string emitCall(CallExpr node)
    {
        auto buf = appender!string();

        // resolve o nome da função
        string fnName;
        if (auto id = cast(Identifier) node.fn)
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
