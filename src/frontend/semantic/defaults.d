module frontend.semantic.defaults;

import frontend;

/// Coleções novas por avaliação; classes não são instanciadas implicitamente.
Node defaultValue(TypeSema type, Position position)
{
    if (type is null)
        return null;
    if (type.isArray())
        return new ArrayLit([], position);
    if (TypeSemaBuiltin primitive = cast(TypeSemaBuiltin) type) switch (primitive.base)
    {
        case TypeSemaBase.Int:
            return new IntLit(0, position);
        case TypeSemaBase.Double:
            return new DoubleLit(0, position);
        case TypeSemaBase.Bool:
            return new BoolLit(false, position);
        case TypeSemaBase.String:
            return new StringLit("", position);
        case TypeSemaBase.Map:
            return new MapLit([], [], position);
        default:
            return null;
    }
    if (TypeSemaNative nat = cast(TypeSemaNative) type)
    {
        if (nat.isBool())
            return new BoolLit(false, position);
        if (nat.isFloat())
            return new DoubleLit(0.0, position);
        return new IntLit(0, position);
    }
    return null;
}
