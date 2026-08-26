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

    // -------------------------------------------------------------
    // Pilha de buffers locais para efeitos colaterais (temp vars,
    // incrementos, materializações de vetor, etc). Cada statement
    // de nível "linha" empurra um frame novo, roda sua compilação,
    // e resgata as linhas que a compilação gerou de forma LOCAL —
    // preservando a ordem relativa dentro do próprio statement, em
    // vez de vazar para o buffer global fora de ordem.
    // -------------------------------------------------------------
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

    const string[TokenKind] opToFn = [
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

    // emit(): vai para o buffer GLOBAL. Use apenas para linhas de
    // estrutura de verdade (assinaturas de função, "while (...) {",
    // "}", etc) — nunca para efeitos colaterais de sub-expressões.
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

    // -------------------------------------------------------------
    // compileStmt: versão "crua". Pode disparar emitLocal() para o
    // frame que estiver aberto no momento em que for chamada — por
    // isso, quem quiser um bloco de linhas AUTOCONTIDO e em ordem
    // (ex. o corpo de um while/if/bloco) deve chamar
    // compileStmtOrdered() em vez desta diretamente.
    // -------------------------------------------------------------
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
                dstring value = compileExpr(assign.value, true);
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

            case NodeKind.UnaryExpr:
                UnaryExpr un = cast(UnaryExpr) node;
                AssignStmt ass = new AssignStmt(un.value, un, TokenKind.Equals, node.pos);
                return compileStmt(ass);

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

    public dstring compileExpr(Node node, bool isStmt = false)
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

            case NodeKind.UnaryExpr:
                return compileUnaryExpr(cast(UnaryExpr) node, isStmt);

            default:
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

    dstring compileUnaryExpr(UnaryExpr unary, bool isStmt = false)
    {
        TokenKind[TokenKind] ops = [
            TokenKind.PPlus: TokenKind.Plus,
            TokenKind.MMinus: TokenKind.Minus,
            TokenKind.BITNot: TokenKind.BITNot,
            TokenKind.Bang: TokenKind.Bang,
            TokenKind.Minus:  TokenKind.Minus,
        ];

        TokenKind[TokenKind] un = [
            TokenKind.BITNot: TokenKind.BITNot,
            TokenKind.Bang:   TokenKind.Bang,
        ];

        TokenKind[TokenKind] notMath = [
            TokenKind.Bang: TokenKind.Bang,
        ];

        const(string)* fn = ops[unary.op] in opToFn;
        dstring sum = "create_num(1)"; // valor pra soma/subtração de 1

        // monta a chamada, exemplo:
        // delegua_op_add(t0, create_num(1))
        dstring cur = formatD("t%d", tmp++);
        emitLocal(formatD("%s %s = {0};", VALUE, cur));

        dstring call = unary.op in un
            ? 
                unary.op in notMath
                    ? formatD("%s(%s)", *fn, compileExpr(unary.value))
                    : formatD("%s(%s)", *fn, cur)
            : formatD("%s(%s, %s)", *fn, cur, sum);

        if (unary.op in notMath)
            return call;

        LValue lv = resolveLValue(unary.value);
        emitLocal(formatD("%s = %s;", cur, lv.read()));

        // valor "antigo", devolvido no caso pós-fixado (i++)
        dstring old = cur;
        if (unary.post)
        {
            old = formatD("t%d", tmp++);
            emitLocal(formatD("%s %s = %s;", VALUE, old, cur));
        }

        if (!isStmt)
            emitLocal(lv.write(call) ~ ";");

        return unary.post ? old : formatD("(%s)", call);
    }

    dstring compileIndexExpr(IndexExpr idxexpr, bool isAssign = false, dstring left = "")
    {
        // o vetor é passado por referencia
        dstring value = compileExpr(idxexpr.value); // vetor
        dstring idx = compileExpr(idxexpr.idx); // indice

        if (isAssign)
            return formatD("delegua_vetor_setar(&%s, %s, %s)", value, idx, left);

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
