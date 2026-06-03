module utils;

import std.exception;
import frontend.parser.ast : Node;

T as(T)(Node v)
{
    T r = cast(T) v;
    enforce(r !is null, "Erro ao converter tipo: Node para " ~ T.stringof);
    return r;
}
