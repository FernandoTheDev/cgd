// tipo semantico
module frontend.type_sema;

enum TypeSemaBase : dstring
{
    Int = "numero",
    Float = "decimal",
    Double = "duplo",
    Logico = "logico",
    String = "texto",
    Void = "vazio",
    Any = "qualquer",
}

enum TypeSemaKind : ubyte
{
    Builtin,
    Array,
    Tuple,
    Class,
}

abstract class TypeSema
{
    TypeSemaKind kind;
    bool isBuiltin() => kind == TypeSemaKind.Builtin;
    bool isArray() => kind == TypeSemaKind.Array;
    bool isTuple() => kind == TypeSemaKind.Tuple;
    bool isClass() => kind == TypeSemaKind.Class;
    bool isNumeric();
    bool isComp(TypeSema type);
    dstring toStr();
}

class TypeSemaBuiltin : TypeSema
{
    TypeSemaBase base;

    this(TypeSemaBase base)
    {
        this.kind = TypeSemaKind.Builtin;
        this.base = base;
    }

    override bool isComp(TypeSema type)
    {   
        if (TypeSemaBuiltin t = cast(TypeSemaBuiltin) type)
        {
            // TODO: validar
            if (base == TypeSemaBase.Any || t.base == TypeSemaBase.Any)
                return true;
            return true;
        }
        return false;
    }

    override bool isNumeric()
    {
        return base == TypeSemaBase.Int
            || base == TypeSemaBase.Float
            || base == TypeSemaBase.Double;
    }

    override dstring toStr()
    {
        return base;
    }
}

class TypeSemaArray : TypeSema
{
    TypeSema base;

    this(TypeSema base)
    {
        this.kind = TypeSemaKind.Array;
        this.base = base;
    }

    override bool isComp(TypeSema type)
    {
        if (TypeSemaArray arr = cast(TypeSemaArray) type)
            return arr.base.isComp(base);
        return false;
    }

    override bool isNumeric()
    {
        return false;
    }

    override dstring toStr()
    {
        return base.toStr() ~ "[]";
    }
}
