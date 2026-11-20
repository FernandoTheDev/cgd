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
