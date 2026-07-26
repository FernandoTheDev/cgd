module utils;

import std.stdio;
import std.exception;
import frontend.parser.ast : Node;

T as(T)(Node v)
{
    T r = cast(T) v;
    enforce(r !is null, "Erro ao converter tipo: Node para " ~ T.stringof);
    return r;
}

void cgd_erro(string message)
{
    writefln("Erro: %s", message);
    import core.stdc.stdlib:exit;
    exit(1);   
}

void cgd_validar(bool cond, string message)
{
    if (cond) return;
    cgd_erro(message);
}
