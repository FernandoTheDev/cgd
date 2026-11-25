module frontend.type_registry;

import frontend;

class TypeRegistry
{
    bool[dstring] enums;
private:
    TypeSema[dstring] types;
    bool[dstring][] enumScopes;
    bool[dstring][][ClassDecl] classEnumScopes;
    ModuleUnit[dstring] moduleAliases;
    ModuleUnit[dstring] qualifiedModules;
    bool[dstring] namespacePrefixes;

public:
    this()
    {
        // inicializa com os tipos builtin da linguagem
        types["Promessa"] = new TypeSemaPromise(new TypeSemaBuiltin(TypeSemaBase.Any));
        types["Tarefa"] = new TypeSemaTask(new TypeSemaBuiltin(TypeSemaBase.Any));
        types["dicionario"] = new TypeSemaBuiltin(TypeSemaBase.Map);
        types["dicionário"] = types["dicionario"];
        types["tupla"] = new TypeSemaBuiltin(TypeSemaBase.Tuple);
        types["funcao"] = new TypeSemaBuiltin(TypeSemaBase.Function);
        types["função"] = types["funcao"];
        types["Objeto"] = new TypeSemaBuiltin(TypeSemaBase.Any);
        types["Excecao"] = new TypeSemaBuiltin(TypeSemaBase.Any);
        types["decimal"] = new TypeSemaBuiltin(TypeSemaBase.Double);
        types["longo"] = new TypeSemaBuiltin(TypeSemaBase.Int);
        types["nulo"] = new TypeSemaBuiltin(TypeSemaBase.Any);
        types["binário"] = new TypeSemaBuiltin(TypeSemaBase.Bool);
        types["vazio"] = new TypeSemaBuiltin(TypeSemaBase.Void);
        types["número"] = new TypeSemaBuiltin(TypeSemaBase.Int);
        types["lógico"] = new TypeSemaBuiltin(TypeSemaBase.Bool);
        types["texto"] = new TypeSemaBuiltin(TypeSemaBase.String);

        types["inteiro"] = new TypeSemaBuiltin(TypeSemaBase.Int);
        types["numero"] = types["inteiro"];

        types["real"] = new TypeSemaBuiltin(TypeSemaBase.Double);

        types["logico"] = new TypeSemaBuiltin(TypeSemaBase.Bool);
        types["booleano"] = types["logico"];
        types["binario"] = types["logico"];

        types["qualquer"] = new TypeSemaBuiltin(TypeSemaBase.Any);

        // Tipos C nativos de largura fixa e dependentes de ABI
        types["ci8"] = new TypeSemaNative(NativeScalarKind.I8, "ci8"d);
        types["cu8"] = new TypeSemaNative(NativeScalarKind.U8, "cu8"d);
        types["ci16"] = new TypeSemaNative(NativeScalarKind.I16, "ci16"d);
        types["cu16"] = new TypeSemaNative(NativeScalarKind.U16, "cu16"d);
        types["ci32"] = new TypeSemaNative(NativeScalarKind.I32, "ci32"d);
        types["cu32"] = new TypeSemaNative(NativeScalarKind.U32, "cu32"d);
        types["ci64"] = new TypeSemaNative(NativeScalarKind.I64, "ci64"d);
        types["cu64"] = new TypeSemaNative(NativeScalarKind.U64, "cu64"d);
        types["cchar"] = new TypeSemaNative(NativeScalarKind.CChar, "cchar"d);
        types["cschar"] = new TypeSemaNative(NativeScalarKind.CSChar, "cschar"d);
        types["cuchar"] = new TypeSemaNative(NativeScalarKind.CUChar, "cuchar"d);
        types["cshort"] = new TypeSemaNative(NativeScalarKind.CShort, "cshort"d);
        types["cushort"] = new TypeSemaNative(NativeScalarKind.CUShort, "cushort"d);
        types["cint"] = new TypeSemaNative(NativeScalarKind.CInt, "cint"d);
        types["cuint"] = new TypeSemaNative(NativeScalarKind.CUInt, "cuint"d);
        types["clong"] = new TypeSemaNative(NativeScalarKind.CLong, "clong"d);
        types["culong"] = new TypeSemaNative(NativeScalarKind.CULong, "culong"d);
        types["csize"] = new TypeSemaNative(NativeScalarKind.CSize, "csize"d);
        types["cf32"] = new TypeSemaNative(NativeScalarKind.F32, "cf32"d);
        types["cf64"] = new TypeSemaNative(NativeScalarKind.F64, "cf64"d);
        types["cfloat"] = new TypeSemaNative(NativeScalarKind.CFloat, "cfloat"d);
        types["cdouble"] = new TypeSemaNative(NativeScalarKind.CDouble, "cdouble"d);
        types["cbool"] = new TypeSemaNative(NativeScalarKind.CBool, "cbool"d);
        types["cponteiro"] = new TypeSemaNative(NativeScalarKind.U64, "cponteiro"d);

        // Containers nativos não-genéricos
        types["StringNativa"] = new TypeSemaNativeContainer(NativeContainerKind.StringNativa);
        types["VisaoTexto"] = new TypeSemaNativeContainer(NativeContainerKind.VisaoTexto);
    }

    /// Aliases locais não escapam de blocos, funções ou corpos de classe.
    void pushEnumScope()
    {
        enumScopes ~= cast(bool[dstring]) null;
    }

    void popEnumScope()
    {
        enumScopes.length--;
    }

    void rememberClass(ClassDecl declaration)
    {
        classEnumScopes[declaration] = enumScopes.dup;
    }

    bool[dstring][] enterClassScope(ClassDecl declaration)
    {
        bool[dstring][] previous = enumScopes;
        if (bool[dstring][]* lexical = declaration in classEnumScopes)
            enumScopes = (*lexical).dup;
        pushEnumScope();
        return previous;
    }

    void leaveClassScope(bool[dstring][] previous)
    {
        enumScopes = previous;
    }

    bool isEnum(dstring name)
    {
        foreach_reverse (bool[dstring] scopeEntry; enumScopes)
            if (name in scopeEntry)
                return true;
        return (name in enums) !is null;
    }

    bool declareEnum(dstring name)
    {
        if (exists(name) && !isEnum(name))
            return false;
        if (enumScopes.length)
        {
            if (name in enumScopes[$ - 1])
                return false;
            enumScopes[$ - 1][name] = true;
            return true;
        }
        if (!set(name, new TypeSemaBuiltin(TypeSemaBase.Int)))
            return false;
        enums[name] = true;
        return true;
    }

    TypeSema* get(dstring name)
    {
        return name in types;
    }

    bool exists(dstring name)
    {
        return get(name) !is null;
    }

    bool set(dstring name, TypeSema type)
    {
        if (name in types)
            return false;
        types[name] = type;
        return true;
    }

    void registerModuleAlias(dstring aliasName, ModuleUnit unit)
    {
        if (aliasName.length && unit !is null)
            moduleAliases[aliasName] = unit;
    }

    void registerQualifiedModule(dstring[] path, ModuleUnit unit)
    {
        if (!path.length || unit is null)
            return;
        import std.array : join;

        dstring full = path.join("."d);
        qualifiedModules[full] = unit;
        dstring prefix;
        foreach (size_t i, dstring seg; path)
        {
            prefix = i == 0 ? seg : (prefix ~ "."d ~ seg);
            namespacePrefixes[prefix] = true;
        }
        if (path.length == 1)
            moduleAliases[path[0]] = unit;
    }

    bool hasNamespacePrefix(dstring[] prefix)
    {
        if (!prefix.length)
            return false;
        import std.array : join;

        return (prefix.join("."d) in namespacePrefixes) !is null;
    }

    ModuleUnit resolveModule(dstring[] qualifier)
    {
        if (!qualifier.length)
            return null;
        if (qualifier.length == 1)
        {
            if (ModuleUnit* found = qualifier[0] in moduleAliases)
                return *found;
        }
        import std.array : join;

        dstring key = qualifier.join("."d);
        if (ModuleUnit* found = key in qualifiedModules)
            return *found;
        return null;
    }
}
