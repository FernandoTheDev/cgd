module frontend.types.type;

import frontend;

enum BaseType : string
{
    String = "texto",
    Int = "inteiro",
    Long = "longo",
    Float = "real",
    Double = "duplo",
    Bool = "logico",
    Void = "vazio",
    Any = "qualquer",
}

const int[string] TYPE_HIERARCHY = [
    BaseType.Bool: 1,
    BaseType.Int: 2,
    BaseType.Long: 3,
    BaseType.Float: 4,
    BaseType.Double: 5,
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

    bool isClass()
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

    bool isUnion()
    {
        return false;
    }

    bool isPointer()
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

    private static immutable string[][string] STRICT_COMPAT;
    private static immutable string[][string] LIBERAL_COMPAT;

    shared static this()
    {
        STRICT_COMPAT = [
            BaseType.Int: [
                BaseType.Long, BaseType.Float, BaseType.Double
            ],
            BaseType.Long: [BaseType.Double],
            BaseType.Float: [BaseType.Double],
            BaseType.Double: [],
            BaseType.Bool: [
                BaseType.Int, BaseType.Long, BaseType.Float, BaseType.Double
            ],
            BaseType.String: [
                BaseType.Int, BaseType.Long, BaseType.Float, BaseType.Double,
                BaseType.Bool
            ]
        ];

        LIBERAL_COMPAT = [
            BaseType.Int: [
                BaseType.Long, BaseType.Float, BaseType.Double,
                BaseType.Bool
            ],
            BaseType.Long: [
                BaseType.Int, BaseType.Float, BaseType.Double,
                BaseType.Bool
            ],
            BaseType.Float: [
                BaseType.Int, BaseType.Long, BaseType.Double,
                BaseType.Bool
            ],
            BaseType.Double: [
                BaseType.Int, BaseType.Long, BaseType.Float,
                BaseType.Bool
            ],
            BaseType.Bool: [
                BaseType.Int, BaseType.Long, BaseType.Float,
                BaseType.Double
            ],
            BaseType.String: [
                BaseType.Int, BaseType.Long, BaseType.Float,
                BaseType.Double, BaseType.Bool
            ]
        ];
    }

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
        return baseType == BaseType.Int || baseType == BaseType.Long
            || baseType == BaseType.Float || baseType == BaseType.Double;
    }

    override bool isCompatibleWith(Type other, bool strict = true)
    {
        if (baseType == BaseType.Any)
            return true;

        if (auto otherPrim = cast(PrimitiveType) other)
        {
            if (otherPrim.baseType == BaseType.Any)
                return true;

            if (baseType == otherPrim.baseType)
                return true;

            string thisStr = baseType;
            string otherStr = otherPrim.baseType;

            if (thisStr in STRICT_COMPAT && STRICT_COMPAT[thisStr].canFind(otherStr))
                return true;

            if (!strict)
            {
                if (thisStr in LIBERAL_COMPAT && LIBERAL_COMPAT[thisStr].canFind(otherStr))
                    return true;
            }
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

    static PrimitiveType promote(PrimitiveType left, PrimitiveType right)
    {
        int leftLevel = TYPE_HIERARCHY.get(cast(string) left.baseType, 0);
        int rightLevel = TYPE_HIERARCHY.get(cast(string) right.baseType, 0);

        return (leftLevel >= rightLevel) ? left : right;
    }
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

    this()
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

class ArrayType : Type
{
    Type elementType;
    int dimensions;

    this(Type elementType, int dimensions = 1)
    {
        this.elementType = elementType;
        this.dimensions = dimensions;
    }

    override bool isArray()
    {
        return true;
    }

    override bool isCompatibleWith(Type other, bool strict = true)
    {
        if (auto otherArray = cast(ArrayType) other)
        {
            // Arrays devem ter o mesmo número de dimensões
            if (dimensions != otherArray.dimensions)
                return false;

            // O tipo dos elementos deve ser compatível
            return elementType.isCompatibleWith(otherArray.elementType, strict);
        }

        return false;
    }

    override string toStr()
    {
        string result = elementType.toStr();
        for (int i = 0; i < dimensions; i++)
            result ~= "[]";
        return result;
    }

    override Type clone()
    {
        return new ArrayType(elementType.clone(), dimensions);
    }

    // Retorna o tipo base (sem as dimensões de array)
    Type getBaseType()
    {
        return elementType;
    }
}

class UnionType : Type
{
    Type[] types;

    this(Type[] types)
    {
        this.types = types;
    }

    override bool isCompatibleWith(Type other, bool strict = true)
    {
        // se other for um UnionType, verifica se todos os tipos de other
        // são compatíveis com pelo menos um tipo deste union
        if (auto otherUnion = cast(UnionType) other)
        {
            foreach (otherType; otherUnion.types)
            {
                foreach (thisType; types)
                    if (thisType.isCompatibleWith(otherType, strict))
                        return true;
            }
            return false;
        }

        // Se other for um tipo simples, verifica se é compatível
        // com pelo menos um dos tipos do union
        foreach (type; types)
            if (type.isCompatibleWith(other, strict))
                return true;

        return false;
    }

    override string toStr()
    {
        import std.algorithm : map;
        import std.array : join;

        return types.map!(t => t.toStr()).join(" | ");
    }

    override Type clone()
    {
        import std.algorithm : map;
        import std.array : array;

        return new UnionType(types.map!(t => t.clone()).array);
    }

    override bool isNumeric()
    {
        // Um union é numérico se todos os seus tipos forem numéricos
        foreach (type; types)
        {
            if (!type.isNumeric())
                return false;
        }
        return types.length > 0;
    }

    override bool isUnion()
    {
        return true;
    }

    // Verifica se o union contém um tipo específico
    bool containsType(Type type)
    {
        foreach (t; types)
        {
            if (t.isCompatibleWith(type, true))
                return true;
        }
        return false;
    }

    // Adiciona um novo tipo ao union (evita duplicatas)
    void addType(Type type)
    {
        if (!containsType(type))
            types ~= type;
    }
}

class PointerType : Type
{
    Type pointeeType;

    this(Type pointeeType)
    {
        this.pointeeType = pointeeType;
    }

    override bool isCompatibleWith(Type other, bool strict = true)
    {
        if (auto otherPtr = cast(PointerType) other)
            return pointeeType.isCompatibleWith(otherPtr.pointeeType, strict);
        return false;
    }

    override bool isPointer()
    {
        return true;
    }

    override string toStr()
    {
        return format("*%s", pointeeType.toStr());
    }

    override Type clone()
    {
        return new PointerType(pointeeType.clone());
    }
}

class ClassType : Type
{
    string name;
    ClassType superClass; // Suporte a herança

    this(string name, ClassType superClass = null)
    {
        this.name = name;
        this.superClass = superClass;
    }

    override bool isClass()
    {
        return true;
    }

    // se não for strict, permite que Subclasse seja compatível com Superclasse
    // ex.: Classe Filha pode ser passada onde se espera Classe Pai
    override bool isCompatibleWith(Type other, bool strict = true)
    {
        if (auto otherClass = cast(ClassType) other) // compatibilidade nominal exata
        {
            if (name == otherClass.name)
                return true;
            else if (!strict && superClass !is null)
                return superClass.isCompatibleWith(other, strict);
        }
        return false;
    }

    override string toStr()
    {
        return name;
    }

    override Type clone()
    {
        return new ClassType(name, superClass);
    }
}

/// Tipo função: (inteiro, texto): logico
class FunctionType : Type
{
    Type[] paramTypes;
    Type returnType;

    this(Type[] paramTypes, Type returnType)
    {
        this.paramTypes = paramTypes;
        this.returnType = returnType;
    }

    override bool isCompatibleWith(Type other, bool strict = true)
    {
        // Compatibilidade com outra função
        if (auto otherFunc = cast(FunctionType) other)
        {
            // Número de parâmetros deve ser igual
            if (paramTypes.length != otherFunc.paramTypes.length)
                return false;

            // Tipo de retorno deve ser compatível
            if (!returnType.isCompatibleWith(otherFunc.returnType, strict))
                return false;

            // Todos os parâmetros devem ser compatíveis
            foreach (i, thisParamType; paramTypes)
            {
                Type otherParamType = otherFunc.paramTypes[i];
                if (!thisParamType.isCompatibleWith(otherParamType, strict))
                    return false;
            }

            return true;
        }

        // Compatibilidade com union type
        if (auto unionType = cast(UnionType) other)
            return unionType.isCompatibleWith(returnType, strict);

        return false;
    }

    override string toStr()
    {
        string params = paramTypes.map!(t => t.toStr()).join(", ");
        return "(" ~ params ~ ") -> " ~ returnType.toStr();
    }

    override Type clone()
    {
        Type[] clonedParams = paramTypes.map!(t => t.clone()).array;
        return new FunctionType(clonedParams, returnType.clone());
    }
}
