module frontend.type_resolver;

import frontend;
import std.stdio;
import std.exception;

class TypeResolver
{
private:
    TypeRegistry registry;

public:
    this(TypeRegistry registry)
    {
        this.registry = registry;
    }

    TypeSema resolver(TypeExpr type)
    {
        switch (type.kind)
        {
        case TypeExprKind.Named:
            TypeExprNamed named = cast(TypeExprNamed) type;
            TypeSema* tsema = registry.get(named.name);
            if (tsema is null)
                enforce(false, "O tipo não existe.");
            return *tsema;
        
        default:
            writeln("Falha ao resolver tipo.");
            return new TypeSemaBuiltin(TypeSemaBase.Any);
        }
    }
}
