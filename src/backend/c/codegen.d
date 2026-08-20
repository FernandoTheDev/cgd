module backend.c.codegen;

import std.algorithm;
import std.format;
import std.array;
import std.stdio;
import std.conv;

import frontend.lexer.token;
import frontend.type_sema;
import frontend.parser;
import backend.c.utils;

enum VALUE = "delegua_value";
enum ENTRY = "delegua_main";

class BackendC
{
private:
    dstring[] includes = [
        `#include "vendor/delegua-runtime/src/delegua_rt.h"`
    ];

    dstring[] prototypes = [
        "\n/* protótipos */",
    ];

    dstring[] code = [
        "\n\n/* código */"
    ];

    const string[TokenKind] opToFn = [
        TokenKind.Plus:    "delegua_op_add",
        TokenKind.Minus:   "delegua_op_sub",
        TokenKind.Star:    "delegua_op_mul",
        TokenKind.Slash:   "delegua_op_div",
        TokenKind.EEquals: "delegua_op_eq",
        TokenKind.LEquals: "delegua_op_le",
        TokenKind.LThan:   "delegua_op_lt",
    ];

    const BuiltinFn[dstring] builtinFn = [
        "escreva": &compileEscreva
    ];

    pragma(inline, true)
    dstring genIndent(uint indent = 0)
    {
        dstring buffer;
        while (indent --> 0) 
            buffer ~= " ";
        return buffer;
    }

    pragma(inline, true)
    void emit(dstring line, uint indent = 0)
    {
        code ~= genIndent(indent) ~ line;
    }

    pragma(inline, true)
    void emitProto(dstring line, uint indent = 0)
    {
        prototypes ~= genIndent(indent) ~ line;
    }

    void compileDecl(Node node)
    {
        if (node is null || node.kind == NodeKind.NaN) return;
        switch (node.kind) 
        {
            case NodeKind.FnDecl:
                return compileFnDecl(cast(FnDecl) node);

            default:
                writeln("...");
                return;
        }
    }

    dstring compileStmt(Node node)
    {
        if (node is null) return "/* Nó nulo recebido no codegen */";
        if (node.kind == NodeKind.NaN) return "/* NaN */";
        switch (node.kind) 
        {
            case NodeKind.VarDecl:
                VarDecl var = cast(VarDecl) node;
                return formatD("%s %s = %s;", VALUE, var.name, compileExpr(var.value));

            case NodeKind.ReturnStmt:
                ReturnStmt ret = cast(ReturnStmt) node;
                return formatD("return %s;", ret.val !is null ? compileExpr(ret.val) : "");

            case NodeKind.CallExpr:
                return compileExpr(node) ~ ";";

            case NodeKind.IfStmt:
                return compileIfStmt(to!IfStmt(node));

            case NodeKind.AssignStmt:
                AssignStmt assign = cast(AssignStmt) node;
                return formatD("%s = %s;", compileExpr(assign.left), compileExpr(assign.value));

            default:
                return "/* statement desconhecido. */";
        }
    }

    dstring compileExpr(Node node)
    {
        if (node is null) return "/* Nó nulo recebido no codegen */";
        if (node.kind == NodeKind.NaN) return "/* NaN */";

        switch (node.kind) 
        {
            case NodeKind.Identifier:
                return (cast(Identifier) node).value;

            case NodeKind.StringLit:
                return formatD(`create_text("%s")`, (cast(StringLit) node).value);

            case NodeKind.IntLit:
                return formatD("create_num(%d)", (cast(IntLit) node).value);

            case NodeKind.DoubleLit:
                return formatD("create_real(%f)", (cast(DoubleLit) node).value);

            case NodeKind.BoolLit:
                return formatD("create_bool(%d)", (cast(BoolLit) node).value);

            case NodeKind.CallExpr:
                CallExpr call = cast(CallExpr) node;
                dstring callee = compileExpr(call.fn);

                if (const(BuiltinFn)* fn = callee in builtinFn)
                    return (*fn)(this, node);

                return formatD("%s(%s)", callee, nodesToStr(call.args));

            case NodeKind.BinaryExpr:
                BinaryExpr bexpr = cast(BinaryExpr) node;
                
                dstring left = compileExpr(bexpr.left);
                dstring right = compileExpr(bexpr.right);

                if (const(string)* fn = bexpr.op in opToFn)
                    return formatD("%s(%s, %s)", *fn, left, right);
                
                return formatD("%s %s %s", left, getOp(bexpr.op), right);
            default:
                return "/* expressão desconhecida. */";
        }
    }

    void compileFnDecl(FnDecl node) 
    {
        dstring args;
        size_t len = node.args.length;

        for (size_t i; i < len; i++)
        {
            args ~= formatD("%s %s", VALUE, node.args[i].name);
            if (i + 1 < len) args ~= ", ";
        }

        dstring proto = formatD("%s %s(%s)", VALUE, node.fn, args);
        emitProto(proto ~ ";");

        emit(formatD("%s {", proto));

        foreach (Node n; node.body)
            emit(compileStmt(n), 4);
        
        emit("}");
    }

    dstring compileIfStmt(IfStmt ifstmt, bool fromIf = false)
    {
        dstring[] cd;

        if (ifstmt.expr is null) // else puro
        {
            cd ~= fromIf ? "else {" : "else {";
    
            foreach (Node n; ifstmt.body)
                cd ~= compileStmt(n);
    
            cd ~= "}";
            return cd.join("\n");
        }

        cd ~= formatD("%s (delegua_is_truthy(%s)) {",
            fromIf ? "else if" : "if", compileExpr(ifstmt.expr));

        foreach (Node n; ifstmt.body)
            cd ~= compileStmt(n);

        if (ifstmt._else is null)
            cd ~= "}";
        else
        {
            cd[$-1] ~= " } ";
            cd ~= compileIfStmt(ifstmt._else, true);
        }

        return cd.join("\n");
    }

    pragma(inline, true)
    bool isDecl(NodeKind kind) => kind == NodeKind.FnDecl;

    pragma(inline, true)
    public dstring nodesToStr(Node[] nodes) => (nodes.map!(n => compileExpr(n)).array).join(", ");

public:
    dstring compile(Program prog)
    {
        foreach (Node node; prog.body)
            if (isDecl(node.kind))
                compileDecl(node);

        emit(formatD("void %s(void) {", ENTRY));
        
        foreach (Node node; prog.body)
            if (!isDecl(node.kind))
                emit(compileStmt(node), 4);

        emit("}");

        dstring source = includes.join("\n");
        source ~= prototypes.join("\n");
        source ~= code.join("\n");
        return source;
    }
}
