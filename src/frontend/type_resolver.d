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
                if (named.qualifier.length > 0)
                {
                    ModuleUnit mod = registry.resolveModule(named.qualifier);
                    if (mod is null || mod.program is null)
                    {
                        import std.array : join;

                        if (diagnostics !is null)
                            diagnostics.error(named.pos, format("O módulo '%s' não foi importado para o tipo '%s'.",
                                    named.qualifier.join("."d), named.toStr()));
                        return new TypeSemaBuiltin(TypeSemaBase.Any);
                    }
                    foreach (Node exported; mod.program.body)
                    {
                        if (ClassDecl cls = cast(ClassDecl) exported)
                        {
                            if (cls.name == named.name)
                            {
                                named.classLinkName = cls.signature.linkName;
                                return new TypeSemaClass(cls);
                            }
                        }
                        if (VarDecl varDecl = cast(VarDecl) exported)
                        {
                            if (varDecl.isEnum && varDecl.name == named.name)
                            {
                                named.qualifier = null;
                                named.name = "inteiro";
                                return new TypeSemaBuiltin(TypeSemaBase.Int);
                            }
                        }
                    }
                    if (diagnostics !is null)
                        diagnostics.error(named.pos, format("O tipo '%s' não existe no módulo '%s'.",
                                named.name, named.toStr()));
                    return new TypeSemaBuiltin(TypeSemaBase.Any);
                }
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

            case TypeExprKind.Promise:
                return new TypeSemaPromise(resolver((cast(TypeExprPromise) type).result));
            case TypeExprKind.Task:
                return new TypeSemaTask(resolver((cast(TypeExprTask) type).result));
            case TypeExprKind.Tuple:
                return new TypeSemaBuiltin(TypeSemaBase.Tuple);
            case TypeExprKind.Array:
                TypeExprArray arr = cast(TypeExprArray) type;
                return new TypeSemaArray(resolver(arr.base));

            case TypeExprKind.Generic:
                TypeExprGeneric gen = cast(TypeExprGeneric) type;
                TypeSema[] resolvedArgs;
                foreach (TypeExpr ta; gen.typeArgs)
                    resolvedArgs ~= resolver(ta);
                if (gen.name == "VetorNativo"d)
                    return new TypeSemaNativeContainer(NativeContainerKind.VetorNativo, resolvedArgs);
                if (gen.name == "MapaNativo"d)
                    return new TypeSemaNativeContainer(NativeContainerKind.MapaNativo, resolvedArgs);
                if (gen.name == "FatiaNativa"d)
                    return new TypeSemaNativeContainer(NativeContainerKind.FatiaNativa, resolvedArgs);
                if (gen.name == "ResultadoNativo"d)
                    return new TypeSemaNativeContainer(NativeContainerKind.ResultadoNativo, resolvedArgs);
                if (gen.name == "OpcionalNativo"d)
                    return new TypeSemaNativeContainer(NativeContainerKind.OpcionalNativo, resolvedArgs);
                if (gen.name == "MatrizNativa"d)
                    return new TypeSemaNativeContainer(NativeContainerKind.MatrizNativa, resolvedArgs);
                if (diagnostics !is null)
                    diagnostics.error(gen.pos, format("Tipo genérico desconhecido: '%s'.", gen.name));
                return new TypeSemaBuiltin(TypeSemaBase.Any);

            default:
                writeln("Falha ao resolver tipo.");
                return new TypeSemaBuiltin(TypeSemaBase.Any);
        }
    }
}
