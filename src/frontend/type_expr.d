// tipo sintatico
module frontend.type_expr;

import std.stdio;

import frontend.lexer : Position;

enum TypeExprKind : ubyte
{
    Promise,
    Task,
    Array,
    Tuple,
    Named,
    Generic
}

abstract class TypeExpr
{
    TypeExprKind kind;
    Position pos;
    dstring toStr();
}

class TypeExprNamed : TypeExpr
{
    dstring[] qualifier;
    dstring name;
    dstring classLinkName;

    this(dstring name, Position p, dstring[] qualifier = null)
    {
        this.kind = TypeExprKind.Named;
        this.qualifier = qualifier;
        this.name = name;
        this.pos = p;
    }

    override dstring toStr()
    {
        if (!qualifier.length)
            return name;
        import std.array : join;

        return qualifier.join("."d) ~ "."d ~ name;
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

class TypeExprPromise : TypeExpr
{
    TypeExpr result;
    this(TypeExpr result, Position pos)
    {
        this.kind = TypeExprKind.Promise;
        this.result = result;
        this.pos = pos;
    }

    override dstring toStr()
    {
        return "Promessa<" ~ result.toStr() ~ ">";
    }
}

class TypeExprTask : TypeExpr
{
    TypeExpr result;
    this(TypeExpr result, Position pos)
    {
        this.kind = TypeExprKind.Task;
        this.result = result;
        this.pos = pos;
    }

    override dstring toStr()
    {
        return "Tarefa<" ~ result.toStr() ~ ">";
    }
}

class TypeExprGeneric : TypeExpr
{
    dstring name;
    TypeExpr[] typeArgs;

    this(dstring name, TypeExpr[] typeArgs, Position pos)
    {
        this.kind = TypeExprKind.Generic;
        this.name = name;
        this.typeArgs = typeArgs;
        this.pos = pos;
    }

    override dstring toStr()
    {
        dstring res = name ~ "<"d;
        foreach (size_t i, TypeExpr arg; typeArgs)
        {
            if (i > 0)
                res ~= ", "d;
            res ~= arg.toStr();
        }
        return res ~ ">"d;
    }
}
