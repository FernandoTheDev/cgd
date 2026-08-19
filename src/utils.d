module utils;

import std.exception;
import std.format;
import std.stdio;

import frontend.parser.ast : Node;
import frontend.semantic.symbol;
import frontend.type_resolver;
import frontend.lexer;
import errors;

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

pragma(inline, true)
dstring ternary(bool cond, dstring s1, dstring s2) => cond ? s1 : s2;

pragma(inline, true)
void alreadyDeclaredHere(dstring name, Position pos, Diagnostics err)
{
    err.hint(pos, format("O simbolo '%s' foi declarado aqui.", name));
}

pragma(inline, true)
void updateType(Node node, TypeResolver resolver)
{
    if (node.type_sema is null)
        node.type_sema = resolver.resolver(node.type_expr);
}

Position getPosFromSymbol(Symbol* sym)
{
    final switch (sym.kind) with (SymbolKind)
    {
        case Var:
            return (cast(SymbolVar*)sym).node.pos;
        case Param:
            return (cast(SymbolParam*)sym).node.pos;
        case Fn:
            return (cast(SymbolFn*)sym).node.pos;
    }
}
