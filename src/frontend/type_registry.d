module frontend.type_registry;

import frontend;

class TypeRegistry
{
private:
    TypeSema[dstring] types;

public:
    this()
    {
        // inicializa com os tipos builtin da linguagem
        types["dicionario"] = new TypeSemaBuiltin(TypeSemaBase.Map);
        types["dicionário"] = types["dicionario"];
        types["tupla"] = new TypeSemaBuiltin(TypeSemaBase.Tuple);
        types["funcao"] = new TypeSemaBuiltin(TypeSemaBase.Function);
        types["função"] = types["funcao"];
        types["Objeto"]=new TypeSemaBuiltin(TypeSemaBase.Any);
        types["Excecao"]=new TypeSemaBuiltin(TypeSemaBase.Any);
        types["decimal"]=new TypeSemaBuiltin(TypeSemaBase.Double);
        types["longo"]=new TypeSemaBuiltin(TypeSemaBase.Int);
        types["nulo"]=new TypeSemaBuiltin(TypeSemaBase.Any);
        types["binário"]=new TypeSemaBuiltin(TypeSemaBase.Bool);
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
