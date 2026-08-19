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
