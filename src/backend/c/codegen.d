module backend.c.codegen;

import std.algorithm;
import std.format;
import std.array;
import std.stdio;
import std.conv;

import frontend.lexer.token;
import frontend.type_sema;
import backend.c.lvalue;
import frontend.parser;
import backend.c.utils;

enum VALUE = "delegua_value";
enum ENTRY = "delegua_main";

struct BuiltinTypeFn
{
    BuiltinFn ptr;
    TypeSema[] args;
    TypeSema ret;
}

BuiltinTypeFn[dstring][TypeSemaKind] builtinTypeFn = [
    TypeSemaKind.Array: [
        "adicionar": BuiltinTypeFn(&compileVetorAdicionar, [
            new TypeSemaBuiltin(TypeSemaBase.Any)
        ], new TypeSemaArray(new TypeSemaBuiltin(TypeSemaBase.Any)))
    ]
];

class BackendC
{
private:
    size_t tmp;

    dstring[] includes = [
        `#include "vendor/delegua-runtime/src/delegua_rt.h"`
        // `#include "/home/fernandodev/.cgd/delegua_rt.h"`
    ];

    dstring[] prototypes = [
        "\n/* protótipos */",
    ];

    dstring[] code = [
        "\n\n/* código */"
    ];

    dstring[][] pendingStack;

    pragma(inline, true)
    void pushFrame()
    {
        pendingStack ~= (dstring[]).init;
    }

    pragma(inline, true)
    dstring[] popFrame()
    {
        dstring[] top = pendingStack[$ - 1];
        pendingStack.length -= 1;
        return top;
    }

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

    // emitLocal(): vai para o frame local do topo da pilha, se
    // houver um aberto; caso contrário cai no buffer global (isso
    // preserva o comportamento antigo fora de qualquer frame, ex.
    // no nível de compile()/compileFnDecl(), que já emitem direto).
    pragma(inline, true)
    void emitLocal(dstring line, uint indent = 0)
    {
        if (pendingStack.length > 0)
            pendingStack[$ - 1] ~= genIndent(indent) ~ line;
        else
            emit(line, indent);
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

    public dstring compileStmt(Node node)
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
                dstring value = compileExpr(assign.value);
                LValue lv = resolveLValue(assign.left);
                return formatD("%s;", lv.write(value));

            case NodeKind.BlockStmt:
                BlockStmt block = cast(BlockStmt) node;
                dstring[] body;

                foreach (Node child; block.body)
                    body ~= compileStmtOrdered(child);

                return body.join("\n");

            case NodeKind.WhileStmt:
                WhileStmt wstmt = cast(WhileStmt) node;
                emit(formatD("while (delegua_is_truthy(%s)) {", compileExpr(wstmt.expr)));

                dstring[] body;

                foreach (Node child; wstmt.body)
                    body ~= compileStmtOrdered(child);

                body ~= "}";

                return body.join("\n");

            case NodeKind.MemberExpr:
                MemberExpr member = cast(MemberExpr) node;
                CallExpr call = cast(CallExpr) member.right;
                dstring fname = (cast(Identifier) call.fn).value;

                BuiltinTypeFn[dstring]* inner = member.left.type_sema.kind in builtinTypeFn;
                BuiltinTypeFn* builtin = inner !is null ? (fname in *inner) : null;

                return builtin.ptr(this, node);

            default:
                return "/* statement desconhecido. */";
        }
    }

    // -------------------------------------------------------------
    // compileStmtOrdered: abre um frame local, roda compileStmt(),
    // e devolve TODOS os efeitos colaterais gerados durante essa
    // chamada seguidos da linha final do statement, na ordem
    // correta. É isso que garante que side effects de UM statement
    // nunca vazem para antes de statements anteriores do mesmo
    // bloco (o bug do `i++` saindo antes de `a_bits`/`b_bits`).
    // -------------------------------------------------------------
    dstring compileStmtOrdered(Node node)
    {
        pushFrame();
        dstring result = compileStmt(node);
        dstring[] sideEffects = popFrame();

        if (sideEffects.length == 0)
            return result;

        return (sideEffects ~ result).join("\n");
    }

    public dstring compileExpr(Node node)
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

            case NodeKind.ArrayLit:
                ArrayLit arr = cast(ArrayLit) node;

                dstring temp = formatD("t%d", tmp++);
                // cria uma variavel temporaria
                emitLocal(formatD("%s %s = create_vetor();", VALUE, temp));

                foreach (Node element; arr.elements)
                    emitLocal(formatD("delegua_vetor_adicionar(&%s, %s);", temp, compileExpr(element)));

                return temp;

            case NodeKind.IndexExpr:
                return compileIndexExpr(cast(IndexExpr) node);

            case NodeKind.BlockStmt:
                BlockStmt block = cast(BlockStmt) node;
                dstring[] body;

                foreach (Node child; block.body)
                    body ~= compileStmtOrdered(child);

                for (size_t i; i + 1 < body.length; i++)
                    emitLocal(body[i]);

                return compileExpr(block.body[$ - 1]);

            default:
                node.print();
                return "/* expressão desconhecida. */";
        }
    }

    LValue resolveLValue(Node node)
    {
        switch (node.kind)
        {
            case NodeKind.Identifier:
                return LValue(LValueKind.Var, (cast(Identifier) node).value);

            case NodeKind.IndexExpr:
                IndexExpr idx = cast(IndexExpr) node;
                return LValue(
                    LValueKind.Index,
                    null,
                    compileExpr(idx.value), // container
                    compileExpr(idx.idx)    // index
                );

            default:
                node.print();
                assert(0, "nó não é um lvalue válido");
        }
    }

    dstring compileIndexExpr(IndexExpr idxexpr)
    {
        // o vetor é passado por referencia
        dstring value = compileExpr(idxexpr.value); // vetor
        dstring idx = compileExpr(idxexpr.idx); // indice

        // cria uma variavel temporaria
        dstring var = formatD("tmp%d", tmp++);
        emitLocal(formatD("%s %s = delegua_vetor_obter(&%s, %s);", VALUE, var, value, idx));

        return var;
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
            emit(compileStmtOrdered(n), 4);

        emit("}");
    }

    dstring compileIfStmt(IfStmt ifstmt, bool fromIf = false)
    {
        dstring[] cd;

        if (ifstmt.expr is null) // else puro
        {
            cd ~= fromIf ? "else {" : "else {";

            foreach (Node n; ifstmt.body)
                cd ~= compileStmtOrdered(n);

            cd ~= "}";
            return cd.join("\n");
        }

        cd ~= formatD("%s (delegua_is_truthy(%s)) {",
            fromIf ? "else if" : "if", compileExpr(ifstmt.expr));

        foreach (Node n; ifstmt.body)
            cd ~= compileStmtOrdered(n);

        if (ifstmt._else is null)
            cd ~= "}";
        else
        {
            cd[$ - 1] ~= " } ";
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
                emit(compileStmtOrdered(node), 4);

        emit("}");

        dstring source = includes.join("\n");
        source ~= prototypes.join("\n");
        source ~= code.join("\n");
        return source;
    }
}
