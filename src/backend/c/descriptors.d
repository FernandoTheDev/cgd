module backend.c.descriptors;

import std.array : join;
import frontend.type_expr;
import backend.c.utils;

/// Gera o descritor estrutural C99 correspondente a um TypeExpr.
dstring typeDescriptor(TypeExpr type)
{
    if (TypeExprNamed named = cast(TypeExprNamed) type)
    {
        if (named.classLinkName.length)
            return formatD("delegua_descr_classe(%s)", cName(named.classLinkName));
        switch (named.name)
        {
            case "ci8":
            case "cu8":
            case "ci16":
            case "cu16":
            case "ci32":
            case "cu32":
            case "ci64":
            case "cu64":
            case "cshort":
            case "cushort":
            case "cint":
            case "cuint":
            case "clong":
            case "culong":
            case "csize":
            case "cponteiro":
                return "delegua_descr_nome(\"inteiro\")"d;
            case "cf32":
            case "cf64":
            case "cfloat":
            case "cdouble":
                return "delegua_descr_nome(\"real\")"d;
            case "cbool":
                return "delegua_descr_nome(\"logico\")"d;
            default:
                return formatD("delegua_descr_nome(%s)", cString(named.name));
        }
    }
    if (TypeExprPromise promise = cast(TypeExprPromise) type)
        return formatD("delegua_descr_promessa(%s)", typeDescriptor(promise.result));
    if (TypeExprTask task = cast(TypeExprTask) type)
        return formatD("delegua_descr_tarefa(%s)", typeDescriptor(task.result));
    if (TypeExprArray array = cast(TypeExprArray) type)
        return formatD("delegua_descr_array(%s)", typeDescriptor(array.base));
    if (TypeExprTuple tuple = cast(TypeExprTuple) type)
    {
        dstring[] children;
        foreach (TypeExpr t; tuple.types)
            children ~= typeDescriptor(t);
        return formatD("delegua_descr_tupla(%s,(delegua_tipo*[]){%s})", children.length, children.join(","));
    }
    return "delegua_descr_nome(\"qualquer\")";
}
