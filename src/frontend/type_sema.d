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
    Function = "funcao",
    Map = "dicionario",
    Tuple = "tupla",
}

enum TypeSemaKind : ubyte
{
    Promise,
    Task,
    Builtin,
    Array,
    Tuple,
    Class,
    Native,
    NativeContainer,
}

enum NativeScalarKind : ubyte
{
    I8,
    U8,
    I16,
    U16,
    I32,
    U32,
    I64,
    U64,
    CChar,
    CSChar,
    CUChar,
    CShort,
    CUShort,
    CInt,
    CUInt,
    CLong,
    CULong,
    CSize,
    F32,
    F64,
    CFloat,
    CDouble,
    CBool,
}

enum NativeContainerKind : ubyte
{
    VetorNativo,
    MapaNativo,
    FatiaNativa,
    StringNativa,
    VisaoTexto,
    ResultadoNativo,
    OpcionalNativo,
    MatrizNativa,
}

abstract class TypeSema
{
    TypeSemaKind kind;
    bool isBuiltin() => kind == TypeSemaKind.Builtin;
    bool isArray() => kind == TypeSemaKind.Array;
    bool isTuple() => kind == TypeSemaKind.Tuple;
    bool isClass() => kind == TypeSemaKind.Class;
    bool isNativeScalar() => kind == TypeSemaKind.Native;
    bool isNativeContainer() => kind == TypeSemaKind.NativeContainer;

    bool isNumeric();
    bool isBool();
    bool isAny() => false;

    bool isComp(TypeSema type);
    TypeSema promote(TypeSema other);

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

        if (TypeSemaNative nat = cast(TypeSemaNative) other)
        {
            if (isNumeric() && nat.isNumeric())
                return true;
            if (isBool() && nat.isBool())
                return true;
            if ((isNumeric() && nat.isBool()) || (isBool() && nat.isNumeric()))
                return true;
            return false;
        }

        TypeSemaBuiltin t = cast(TypeSemaBuiltin) other;
        if (t is null)
            return false;

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
        if (TypeSemaNative nat = cast(TypeSemaNative) other)
            return nat.promote(this);
        TypeSemaBuiltin t = cast(TypeSemaBuiltin) other;
        if (t is null)
            return this; // tipos incompatíveis, sem promoção

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
        return base == TypeSemaBase.Int || base == TypeSemaBase.Double;
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
        if (arr is null)
            return this;
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

class TypeSemaClass : TypeSema
{
    import frontend.parser.ast : ClassDecl;

    ClassDecl declaration;
    this(ClassDecl declaration)
    {
        kind = TypeSemaKind.Class;
        this.declaration = declaration;
    }

    override bool isNumeric()
    {
        return false;
    }

    override bool isBool()
    {
        return false;
    }

    override bool isComp(TypeSema other)
    {
        if (other.isAny())
            return true;
        if (TypeSemaClass c = cast(TypeSemaClass) other)
            for (ClassDecl node = c.declaration; node !is null; node = node.superClass)
            {
                if (node is declaration)
                    return true;
                foreach (ClassDecl contract; node.interfaces)
                    if (contract is declaration)
                        return true;
            }
        return false;
    }

    override TypeSema promote(TypeSema other)
    {
        return this;
    }

    override dstring toStr()
    {
        return declaration.name;
    }
}

class TypeSemaPromise : TypeSema
{
    TypeSema result;
    this(TypeSema result)
    {
        kind = TypeSemaKind.Promise;
        this.result = result is null ? new TypeSemaBuiltin(TypeSemaBase.Any) : result;
    }

    override bool isNumeric()
    {
        return false;
    }

    override bool isBool()
    {
        return false;
    }

    private bool dynamicResult(TypeSema type)
    {
        TypeSemaBuiltin primitive = cast(TypeSemaBuiltin) type;
        return primitive !is null && primitive.base == TypeSemaBase.Any;
    }

    private bool sameResult(TypeSema left, TypeSema right)
    {
        if (dynamicResult(left) || dynamicResult(right))
            return true;
        if (left.kind != right.kind)
            return false;
        if (TypeSemaArray array = cast(TypeSemaArray) left)
            return sameResult(array.base, (cast(TypeSemaArray) right).base);
        if (TypeSemaPromise promise = cast(TypeSemaPromise) left)
            return sameResult(promise.result, (cast(TypeSemaPromise) right).result);
        if (TypeSemaTask task = cast(TypeSemaTask) left)
            return sameResult(task.result, (cast(TypeSemaTask) right).result);
        if (TypeSemaClass klass = cast(TypeSemaClass) left)
            return klass.declaration is(cast(TypeSemaClass) right).declaration;
        return left.toStr() == right.toStr();
    }

    override bool isComp(TypeSema other)
    {
        if (dynamicResult(other))
            return true;
        TypeSemaPromise promise = cast(TypeSemaPromise) other;
        return promise !is null && sameResult(result, promise.result);
    }

    override TypeSema promote(TypeSema other)
    {
        return this;
    }

    override dstring toStr()
    {
        return "Promessa<" ~ result.toStr() ~ ">";
    }
}

class TypeSemaTask : TypeSema
{
    TypeSema result;
    this(TypeSema result)
    {
        kind = TypeSemaKind.Task;
        this.result = result is null ? new TypeSemaBuiltin(TypeSemaBase.Any) : result;
    }

    override bool isNumeric()
    {
        return false;
    }

    override bool isBool()
    {
        return false;
    }

    private bool dynamicResult(TypeSema type)
    {
        TypeSemaBuiltin primitive = cast(TypeSemaBuiltin) type;
        return primitive !is null && primitive.base == TypeSemaBase.Any;
    }

    private bool sameResult(TypeSema left, TypeSema right)
    {
        if (dynamicResult(left) || dynamicResult(right))
            return true;
        if (left.kind != right.kind)
            return false;
        if (TypeSemaArray array = cast(TypeSemaArray) left)
            return sameResult(array.base, (cast(TypeSemaArray) right).base);
        if (TypeSemaPromise promise = cast(TypeSemaPromise) left)
            return sameResult(promise.result, (cast(TypeSemaPromise) right).result);
        if (TypeSemaTask task = cast(TypeSemaTask) left)
            return sameResult(task.result, (cast(TypeSemaTask) right).result);
        if (TypeSemaClass klass = cast(TypeSemaClass) left)
            return klass.declaration is(cast(TypeSemaClass) right).declaration;
        return left.toStr() == right.toStr();
    }

    override bool isComp(TypeSema other)
    {
        if (dynamicResult(other))
            return true;
        TypeSemaTask task = cast(TypeSemaTask) other;
        return task !is null && sameResult(result, task.result);
    }

    override TypeSema promote(TypeSema other)
    {
        return this;
    }

    override dstring toStr()
    {
        return "Tarefa<" ~ result.toStr() ~ ">";
    }
}

class TypeSemaNative : TypeSema
{
    NativeScalarKind scalar;
    dstring name;

    this(NativeScalarKind scalar, dstring name)
    {
        this.kind = TypeSemaKind.Native;
        this.scalar = scalar;
        this.name = name;
    }

    string cTypeName() const
    {
        final switch (scalar)
        {
            case NativeScalarKind.I8:
                return "int8_t";
            case NativeScalarKind.U8:
                return "uint8_t";
            case NativeScalarKind.I16:
                return "int16_t";
            case NativeScalarKind.U16:
                return "uint16_t";
            case NativeScalarKind.I32:
                return "int32_t";
            case NativeScalarKind.U32:
                return "uint32_t";
            case NativeScalarKind.I64:
                return "int64_t";
            case NativeScalarKind.U64:
                return "uint64_t";
            case NativeScalarKind.CChar:
                return "char";
            case NativeScalarKind.CSChar:
                return "signed char";
            case NativeScalarKind.CUChar:
                return "unsigned char";
            case NativeScalarKind.CShort:
                return "short";
            case NativeScalarKind.CUShort:
                return "unsigned short";
            case NativeScalarKind.CInt:
                return "int";
            case NativeScalarKind.CUInt:
                return "unsigned int";
            case NativeScalarKind.CLong:
                return "long";
            case NativeScalarKind.CULong:
                return "unsigned long";
            case NativeScalarKind.CSize:
                return "size_t";
            case NativeScalarKind.F32:
            case NativeScalarKind.CFloat:
                return "float";
            case NativeScalarKind.F64:
            case NativeScalarKind.CDouble:
                return "double";
            case NativeScalarKind.CBool:
                return "bool";
        }
    }

    bool isFloat() const
    {
        return scalar == NativeScalarKind.F32 || scalar == NativeScalarKind.F64
            || scalar == NativeScalarKind.CFloat || scalar == NativeScalarKind.CDouble;
    }

    bool isUnsigned() const
    {
        return scalar == NativeScalarKind.U8 || scalar == NativeScalarKind.U16
            || scalar == NativeScalarKind.U32 || scalar == NativeScalarKind.U64
            || scalar == NativeScalarKind.CUChar || scalar == NativeScalarKind.CUShort
            || scalar == NativeScalarKind.CUInt || scalar == NativeScalarKind.CULong
            || scalar == NativeScalarKind.CSize;
    }

    bool isInteger() const
    {
        return !isFloat() && scalar != NativeScalarKind.CBool;
    }

    int bitWidth() const
    {
        final switch (scalar)
        {
            case NativeScalarKind.CBool:
            case NativeScalarKind.I8:
            case NativeScalarKind.U8:
            case NativeScalarKind.CChar:
            case NativeScalarKind.CSChar:
            case NativeScalarKind.CUChar:
                return 8;
            case NativeScalarKind.I16:
            case NativeScalarKind.U16:
            case NativeScalarKind.CShort:
            case NativeScalarKind.CUShort:
                return 16;
            case NativeScalarKind.I32:
            case NativeScalarKind.U32:
            case NativeScalarKind.CInt:
            case NativeScalarKind.CUInt:
            case NativeScalarKind.F32:
            case NativeScalarKind.CFloat:
                return 32;
            case NativeScalarKind.I64:
            case NativeScalarKind.U64:
            case NativeScalarKind.CLong:
            case NativeScalarKind.CULong:
            case NativeScalarKind.CSize:
            case NativeScalarKind.F64:
            case NativeScalarKind.CDouble:
                return 64;
        }
    }

    override bool isNumeric()
    {
        return scalar != NativeScalarKind.CBool;
    }

    override bool isBool()
    {
        return scalar == NativeScalarKind.CBool;
    }

    override bool isComp(TypeSema other)
    {
        if (other.isAny())
            return true;
        if (TypeSemaNative nat = cast(TypeSemaNative) other)
        {
            if (isBool() && nat.isBool())
                return true;
            if (isNumeric() && nat.isNumeric())
                return true;
            return false;
        }
        if (TypeSemaBuiltin b = cast(TypeSemaBuiltin) other)
        {
            if (isBool() && b.isBool())
                return true;
            if (isNumeric() && b.isNumeric())
                return true;
            return false;
        }
        return false;
    }

    override TypeSema promote(TypeSema other)
    {
        if (TypeSemaNative nat = cast(TypeSemaNative) other)
        {
            if (scalar == nat.scalar)
                return this;
            if (isFloat() || nat.isFloat())
            {
                if (bitWidth() >= 64 || nat.bitWidth() >= 64)
                    return new TypeSemaNative(NativeScalarKind.F64, "cf64"d);
                return new TypeSemaNative(NativeScalarKind.F32, "cf32"d);
            }
            if (bitWidth() >= nat.bitWidth())
                return this;
            return nat;
        }
        if (TypeSemaBuiltin b = cast(TypeSemaBuiltin) other)
        {
            if (b.base == TypeSemaBase.Double && !isFloat())
                return new TypeSemaNative(NativeScalarKind.F64, "cf64"d);
            if (b.base == TypeSemaBase.Int && isNumeric())
                return this;
            if (b.base == TypeSemaBase.Double && isFloat())
                return this;
        }
        return this;
    }

    override dstring toStr()
    {
        return name;
    }
}

class TypeSemaNativeContainer : TypeSema
{
    NativeContainerKind containerKind;
    TypeSema[] typeArgs;

    this(NativeContainerKind containerKind, TypeSema[] typeArgs = null)
    {
        this.kind = TypeSemaKind.NativeContainer;
        this.containerKind = containerKind;
        this.typeArgs = typeArgs;
    }

    bool isOwnedResource() const
    {
        return containerKind == NativeContainerKind.VetorNativo
            || containerKind == NativeContainerKind.MapaNativo
            || containerKind == NativeContainerKind.StringNativa
            || containerKind == NativeContainerKind.MatrizNativa;
    }

    bool isBorrowedView() const
    {
        return containerKind == NativeContainerKind.FatiaNativa
            || containerKind == NativeContainerKind.VisaoTexto;
    }

    override bool isNumeric()
    {
        return false;
    }

    override bool isBool()
    {
        return false;
    }

    override bool isComp(TypeSema other)
    {
        if (other.isAny())
            return true;
        TypeSemaNativeContainer o = cast(TypeSemaNativeContainer) other;
        if (o is null || o.containerKind != containerKind || o.typeArgs.length != typeArgs.length)
            return false;
        foreach (size_t i, TypeSema ta; typeArgs)
            if (ta.toStr() != o.typeArgs[i].toStr())
                return false;
        return true;
    }

    override TypeSema promote(TypeSema other)
    {
        return this;
    }

    override dstring toStr()
    {
        dstring base;
        final switch (containerKind)
        {
            case NativeContainerKind.VetorNativo:
                base = "VetorNativo"d;
                break;
            case NativeContainerKind.MapaNativo:
                base = "MapaNativo"d;
                break;
            case NativeContainerKind.FatiaNativa:
                base = "FatiaNativa"d;
                break;
            case NativeContainerKind.StringNativa:
                return "StringNativa"d;
            case NativeContainerKind.VisaoTexto:
                return "VisaoTexto"d;
            case NativeContainerKind.ResultadoNativo:
                base = "ResultadoNativo"d;
                break;
            case NativeContainerKind.OpcionalNativo:
                base = "OpcionalNativo"d;
                break;
            case NativeContainerKind.MatrizNativa:
                base = "MatrizNativa"d;
                break;
        }
        if (!typeArgs.length)
            return base;
        dstring res = base ~ "<"d;
        foreach (size_t i, TypeSema ta; typeArgs)
        {
            if (i > 0)
                res ~= ", "d;
            res ~= ta.toStr();
        }
        return res ~ ">"d;
    }
}
