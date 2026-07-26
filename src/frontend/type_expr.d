// tipo sintatico
module frontend.type_expr;

import std.stdio;
import frontend.lexer : Position;

enum TypeExprKind : ubyte
{
    Array,
    Tuple,
    Named
}

abstract class TypeExpr
{
    TypeExprKind kind;
    Position pos;
    dstring toStr();
}

class TypeExprNamed : TypeExpr
{
    dstring name;

    this(dstring name, Position p)
    {
        this.kind = TypeExprKind.Named;
        this.name = name;
        this.pos = p;
    }

    override dstring toStr()
    {
        return name;
    }
}

class TypeExprTuple : TypeExpr
{
    TypeExpr[] types;

    this(TypeExpr[] types, Position p)
    {
        this.kind = TypeExprKind.Tuple;
        this.types = types;
        this.pos = p;
    }

    override dstring toStr()
    {
        dstring type = "(";
        for (uint i; i < types.length; i++)
        {
            type ~= types[i].toStr();
            if ((i + 1) < types.length)
                type ~= ", ";
        }
        type ~= ")";
        return type;
    }
}

class TypeExprArray : TypeExpr
{
    TypeExpr base;

    this(TypeExpr base, Position p)
    {
        this.kind = TypeExprKind.Array;
        this.base = base;
        this.pos = p;
    }

    override dstring toStr()
    {
        return base.toStr() ~ "[]";
    }
}
