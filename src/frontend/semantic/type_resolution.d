module frontend.semantic.type_resolution;

import std.algorithm;
import frontend;
import common.reporter;

class TypeResolver
{
    Context ctx;
    DiagnosticError error;
    TypeRegistry registry;

    this(Context ctx, DiagnosticError error)
    {
        this.ctx = ctx;
        this.error = error;
        registry = new TypeRegistry();
    }

    Type resolve(TypeExpr typeExpr)
    {
        if (typeExpr is null)
            return null;

        return this.resolveInternal(typeExpr);
    }

    private Type resolveInternal(TypeExpr typeExpr)
    {
        if (auto named = cast(NamedTypeExpr) typeExpr)
            return resolveNamed(named);

        if (auto arr = cast(ArrayTypeExpr) typeExpr)
            return resolveArray(arr);

        if (auto ptr = cast(PointerTypeExpr) typeExpr)
            return resolvePointer(ptr);

        if (auto uniont = cast(UnionTypeExpr) typeExpr)
            return resolveUnion(uniont);

        if (auto fn = cast(FunctionTypeExpr) typeExpr)
            return resolveFuncType(fn);

        error.addError(Diagnostic(
                "Tipo desconhecido na resolução",
                typeExpr.loc
        ));
        return new PrimitiveType(BaseType.Any);
    }

    Type resolveFuncType(FunctionTypeExpr fn)
    {
        Type[] types = fn.paramTypes.map!(t => resolve(t)).array;
        return new FunctionType(types, resolve(fn.returnType));
    }

    private Type resolveNamed(NamedTypeExpr named)
    {
        string name = named.name;
        if (!registry.typeExists(name))
        {
            error.addError(Diagnostic(
                    format("O tipo não existe '%s'.", name),
                    named.loc
            ));
            return new PrimitiveType(BaseType.Any);
        }
        return registry.lookupType(name);
    }

    private Type resolveArray(ArrayTypeExpr arr)
    {
        Type elemType = resolve(arr.elementType);

        if (elemType is null)
        {
            error.addError(Diagnostic(
                    "Tipo do elemento do array não pode ser resolvido",
                    arr.loc
            ));
            return new PrimitiveType(BaseType.Any);
        }

        return new ArrayType(elemType);
    }

    private Type resolvePointer(PointerTypeExpr ptr)
    {
        Type pointeeType = resolve(ptr.pointeeType);

        if (pointeeType is null)
        {
            error.addError(Diagnostic(
                    "Tipo apontado não pode ser resolvido",
                    ptr.loc
            ));
            return new PrimitiveType(BaseType.Any);
        }

        return new PointerType(pointeeType);
    }

    private Type resolveUnion(UnionTypeExpr uniont)
    {

        Type[] types = uniont.types.map!(t => resolve(t)).array;
        return new UnionType(types);
    }
}
