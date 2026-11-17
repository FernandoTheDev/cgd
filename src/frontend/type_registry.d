module frontend.type_registry;

import frontend;

class TypeRegistry
{
    bool[dstring] enums;
private:
    TypeSema[dstring] types;
    bool[dstring][] enumScopes;
    bool[dstring][][ClassDecl] classEnumScopes;

public:
    this()
    {
        // inicializa com os tipos builtin da linguagem
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
}
