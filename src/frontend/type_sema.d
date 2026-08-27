// tipo semantico
module frontend.type_sema;

enum TypeSemaBase : dstring
{
    Int = "numero",
    Double = "real",
    Bool = "logico",
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
    bool isBool();
    bool isAny() => false;
    
    bool isComp(TypeSema type);
    TypeSema promote(TypeSema other );

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

    override bool isAny() => base == TypeSemaBase.Any;

    override bool isComp(TypeSema other)
    {
        if (isAny() || other.isAny())
            return true;

        TypeSemaBuiltin t = cast(TypeSemaBuiltin) other;
        if (t is null) return false;

        // Any é compatível com tudo
        if (base == TypeSemaBase.Any || t.base == TypeSemaBase.Any)
            return true;

        // tipos iguais são compatíveis
        if (base == t.base)
            return true;

        // promoção numérica: Int <-> Double
        // Int <-> Bool
        if (isNumeric() && t.isNumeric())
            return true;

        if ((isNumeric() && t.isBool()) || (isBool() && t.isNumeric()))
            return true;

        return false;
    }

    override TypeSema promote(TypeSema other)
    {
        TypeSemaBuiltin t = cast(TypeSemaBuiltin) other;
        if (t is null) return this; // tipos incompatíveis, sem promoção
        
        // Double domina Int
        if (base == TypeSemaBase.Double || t.base == TypeSemaBase.Double)
            return new TypeSemaBuiltin(TypeSemaBase.Double);

        if (base == TypeSemaBase.String || t.base == TypeSemaBase.String)
            return new TypeSemaBuiltin(TypeSemaBase.String);
        
        // Any domina tudo
        if (base == TypeSemaBase.Any || t.base == TypeSemaBase.Any)
            return new TypeSemaBuiltin(TypeSemaBase.Any);
        
        // mesmo tipo, sem promoção necessária
        return this;
    }

    override bool isNumeric()
    {
        return base == TypeSemaBase.Int
            || base == TypeSemaBase.Double;
    }

    override bool isBool()
    {
        return base == TypeSemaBase.Bool;
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

    override bool isAny() => base.isAny();

    override bool isComp(TypeSema type)
    {
        if (isAny() || type.isAny())
            return true;
        if (TypeSemaArray arr = cast(TypeSemaArray) type)
            return base.isComp(arr.base);
        return false;
    }

    override TypeSema promote(TypeSema other)
    {
        TypeSemaArray arr = cast(TypeSemaArray) other;
        if (arr is null) return this;
        return new TypeSemaArray(base.promote(arr.base));
    }

    override bool isNumeric()
    {
        return false;
    }

    override bool isBool()
    {
        return false;
    }

    override dstring toStr()
    {
        return base.toStr() ~ "[]";
    }
}
