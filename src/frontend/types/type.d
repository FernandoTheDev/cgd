module frontend.types.type;

import std.format : format;
import std.algorithm : canFind;

enum BaseType : string
{
    String = "texto",
    Int = "inteiro",
    Bool = "logico",
    Void = "vazio",
    Any = "qualquer",
}

immutable int[string] TYPE_HIERARCHY = [
    "logico": 1,
    "inteiro": 2,
    "real": 3
];

abstract class Type
{
    abstract bool isCompatibleWith(Type other, bool strict = true);
    abstract string toStr();
    abstract Type clone();

    bool isNumeric()
    {
        return false;
    }

    bool isArray()
    {
        return false;
    }

    bool isStruct()
    {
        return false;
    }

    bool isEnum()
    {
        return false;
    }

    bool isPrimitive()
    {
        return false;
    }

    bool isVoid()
    {
        return false;
    }

    bool isQualified()
    {
        return false;
    }

    Type getPromotedType(Type other)
    {
        if (auto prim1 = cast(PrimitiveType) this)
            if (auto prim2 = cast(PrimitiveType) other)
                return PrimitiveType.promote(prim1, prim2);
        return this;
    }
}

class PrimitiveType : Type
{
    BaseType baseType;

    this(BaseType baseType)
    {
        this.baseType = baseType;
    }

    override bool isPrimitive()
    {
        return true;
    }

    override bool isNumeric()
    {
        return baseType == BaseType.Int;
    }

    override bool isCompatibleWith(Type other, bool strict = true)
    {
        // Any é compatível com tudo
        if (baseType == BaseType.Any)
            return true;

        if (auto otherPrim = cast(PrimitiveType) other)
        {
            if (otherPrim.baseType == BaseType.Any)
                return true;

            // Compatibilidade exata
            if (baseType == otherPrim.baseType)
                return true;

            // Compatibilidade por mapa
            auto compatMap = strict ? STRICT_COMPAT : LIBERAL_COMPAT;

            string baseStr = cast(string) baseType;
            string otherStr = cast(string) otherPrim.baseType;

            if (baseStr in compatMap)
                return compatMap[baseStr].canFind(otherStr);
        }

        return false;
    }

    override string toStr()
    {
        return cast(string) baseType;
    }

    override Type clone()
    {
        return new PrimitiveType(baseType);
    }

    // Type promotion
    static PrimitiveType promote(PrimitiveType left, PrimitiveType right)
    {
        int leftLevel = TYPE_HIERARCHY.get(cast(string) left.baseType, 0);
        int rightLevel = TYPE_HIERARCHY.get(cast(string) right.baseType, 0);

        return (leftLevel >= rightLevel) ? left : right;
    }

    // Mapas de compatibilidade
    private static immutable string[][string] STRICT_COMPAT = null;

    private static immutable string[][string] LIBERAL_COMPAT = null;
}

class VoidType : Type
{
    private static VoidType _instance;

    // Singleton
    static VoidType instance()
    {
        if (_instance is null)
            _instance = new VoidType();
        return _instance;
    }

    private this()
    {
    }

    override bool isVoid()
    {
        return true;
    }

    override bool isCompatibleWith(Type other, bool strict = true)
    {
        return cast(VoidType) other !is null;
    }

    override string toStr()
    {
        return "vazio";
    }

    override Type clone()
    {
        return instance();
    }
}
