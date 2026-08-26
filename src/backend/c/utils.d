module backend.c.utils;

import std.algorithm;
import std.format;
import std.stdio;
import std.array;
import std.conv;

import backend.c.codegen;
import frontend.parser;
import frontend.lexer;

string getOp(TokenKind k)
{
    switch (k)
    {
        case TokenKind.Equals:
            return "=";
        default:
            return "/* operador desconhecido */";
    }
}

dstring strToDstr(string str) => to!dstring(str);

dstring formatD(Args...)(string fmt, Args args)
{
    auto app = appender!dstring();
    formattedWrite(app, fmt, args);
    return app.data;
}

// builtins
alias BuiltinFn = dstring function(BackendC, Node);

dstring compileEscreva(BackendC ctx, Node node)
{
    CallExpr call = cast(CallExpr) node;
    return formatD("delegua_escreva(%d, %s)", call.args.length, ctx.nodesToStr(call.args));
}

dstring compileVetorAdicionar(BackendC ctx, Node node)
{
    MemberExpr member = cast(MemberExpr) node;
    dstring vetor = ctx.compileExpr(member.left);
    CallExpr call = cast(CallExpr) member.right;
    dstring[] args = call.args.map!(arg => ctx.compileExpr(arg)).array;
    return formatD("delegua_vetor_adicionar(&%s, %s);", vetor, args.join(", "));
}
