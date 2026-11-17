module frontend.type_resolver;

import frontend;
import errors;
import std.format;
import std.stdio;
import std.exception;

class TypeResolver
{
private:
    TypeRegistry registry;
    Diagnostics diagnostics;

public:
    this(TypeRegistry registry, Diagnostics diagnostics = null)
    {
        this.registry = registry;
        this.diagnostics = diagnostics;
    }

    TypeSema resolver(TypeExpr type)
    {
        if (type is null)
            return new TypeSemaBuiltin(TypeSemaBase.Any);

        switch (type.kind)
        {
            case TypeExprKind.Named:
                TypeExprNamed named = cast(TypeExprNamed) type;
                if (registry.isEnum(named.name))
                    named.name = "inteiro";
                TypeSema* tsema = registry.get(named.name);

                if (tsema is null)
                {
                    if (diagnostics !is null)
                        diagnostics.error(named.pos, format("O tipo '%s' não existe.", named.name));
                    return new TypeSemaBuiltin(TypeSemaBase.Any);
                }

                if (TypeSemaClass c = cast(TypeSemaClass)*tsema)
                    named.classLinkName = c.declaration.signature.linkName;
                return *tsema;

            case TypeExprKind.Tuple:
                return new TypeSemaBuiltin(TypeSemaBase.Tuple);
            case TypeExprKind.Array:
                TypeExprArray arr = cast(TypeExprArray) type;
                return new TypeSemaArray(resolver(arr.base));

            default:
                writeln("Falha ao resolver tipo.");
                return new TypeSemaBuiltin(TypeSemaBase.Any);
        }
    }
}
