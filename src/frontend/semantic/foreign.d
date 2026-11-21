module frontend.semantic.foreign;

import frontend;

private dstring metadata(Decorator[] decorators, dstring key)
{
    foreach (Decorator decorator; decorators)
        if (decorator.name == "definicao" || decorator.name == "definição")
            foreach (size_t index, dstring name; decorator.keys)
                if (name == key)
                    if (StringLit literal = cast(StringLit) decorator.values[index])
                        return literal.value;
    return "";
}

private bool boolMetadata(Decorator[] decorators, dstring key)
{
    foreach (Decorator decorator; decorators)
        if (decorator.name == "definicao" || decorator.name == "definição")
            foreach (size_t index, dstring name; decorator.keys)
                if (name == key)
                    if (BoolLit literal = cast(BoolLit) decorator.values[index])
                        return literal.value;
    return false;
}

private bool identifier(dstring name)
{
    if (!name.length)
        return false;
    foreach (size_t index, dchar letter; name)
        if (!(letter == '_' || letter >= 'a' && letter <= 'z' || letter >= 'A' && letter <= 'Z' || index
                && letter >= '0' && letter <= '9'))
            return false;
    return true;
}

void resolveForeignClass(ClassDecl declaration, Diagnostics diagnostics)
{
    declaration.foreignLibrary = metadata(declaration.decorators, "biblioteca");
    if (!declaration.foreignLibrary.length)
        diagnostics.error(declaration.pos, "FFI C exige @definicao(biblioteca=...).");
    foreach (dchar letter; declaration.foreignLibrary)
        if (!(letter >= 'a' && letter <= 'z' || letter >= 'A' && letter <= 'Z' || letter >= '0'
                && letter <= '9' || letter == '_' || letter == '.' || letter == '+' || letter == '-'))
            diagnostics.error(declaration.pos, "Nome de biblioteca C inválido.");
    bool instanceField;
    foreach (ClassField field; declaration.fields)
        instanceField = instanceField || !field.isEnum;
    if (instanceField || declaration.superName.length || declaration.isInterface || declaration.isAbstract)
        diagnostics.error(declaration.pos, "Classe estrangeira C contém apenas assinaturas de métodos estáticos.");
    dstring abi = metadata(declaration.decorators, "abi");
    if (abi.length && abi != "c" && abi != "delegua")
        diagnostics.error(declaration.pos, "ABI FFI desconhecida.");
    dstring prefix = metadata(declaration.decorators, "prefixo");
    bool supported(TypeExpr type, bool result)
    {
        dstring name = type is null ? "" : type.toStr();
        return name == "numero" || name == "número" || name == "real" || name == "inteiro"
            || name == "longo" || name == "texto" || name == "logico" || name == "lógico" || result && name == "vazio";
    }

    foreach (FnDecl method; declaration.methods)
    {
        method.foreignManaged = abi == "delegua";
        method.foreignSymbol = prefix ~ metadata(method.decorators, "simbolo");
        method.foreignParallelSafe = declaration.foreignLibrary == "cgd-runtime"
            && method.foreignManaged && boolMetadata(method.decorators, "paralelo");
        if (!identifier(method.foreignSymbol))
            diagnostics.error(method.pos, "FFI exige @definicao(simbolo=...) com identificador C válido.");
        if (!method.foreignManaged && !supported(method.type_expr, true))
            diagnostics.error(method.pos, "Retorno não representável na ABI C escalar.");
        foreach (FnArg argument; method.args)
            if ((!method.foreignManaged && !supported(argument.type_expr, false))
                    || argument.rest || argument.value !is null)
                diagnostics.error(argument.pos,
                        "FFI exige parâmetros escalares explícitos, sem defaults ou variádicos.");
    }
}
