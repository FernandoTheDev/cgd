module frontend.types.registry;

import frontend.types.type;
import frontend.types.builtins;
import std.stdio;

/// Registry centralizado para gerenciar todos os tipos da linguagem
class TypeRegistry
{
    private static TypeRegistry _instance;

    // Tipos definidos pelo usuário
    private Type[string] userTypes;

    // Cache de tipos compostos (arrays, ponteiros, etc)
    private Type[string] compositeCache;

    // Tipos atualmente em processo de definição (detecta ciclos)
    private bool[string] inProgress;

    private this()
    {
        BuiltinTypes.initialize();
        // BuiltinFunctions.initialize();
    }

    /// Singleton instance
    static TypeRegistry instance()
    {
        if (_instance is null)
            _instance = new TypeRegistry();
        return _instance;
    }

    /// Registra um tipo definido pelo usuário
    bool registerType(string name, Type type)
    {
        if (name in userTypes)
        {
            stderr.writeln("Erro: tipo '", name, "' já foi definido");
            return false;
        }

        if (BuiltinTypes.isPrimitiveTypeName(name))
        {
            stderr.writeln("Erro: '", name, "' é um tipo primitivo e não pode ser redefinido");
            return false;
        }

        userTypes[name] = type;
        writeln("[TypeRegistry] Tipo registrado: ", name);
        return true;
    }

    /// Busca um tipo pelo nome (primitivo ou definido pelo usuário)
    Type lookupType(string name)
    {
        // Primeiro tenta tipos primitivos
        if (auto prim = BuiltinTypes.getPrimitive(name))
            return prim;

        // Depois tipos do usuário
        if (auto userType = name in userTypes)
            return *userType;

        return null;
    }

    /// Verifica se um tipo existe
    bool typeExists(string name)
    {
        return lookupType(name) !is null;
    }

    /// Cria ou obtém um tipo array do cache
    Type getArrayType(Type elementType)
    {
        string key = elementType.toStr() ~ "[]";

        if (auto cached = key in compositeCache)
            return *cached;

        // Cria novo ArrayType
        auto arrayType = new ArrayType(elementType);
        compositeCache[key] = arrayType;
        return arrayType;
    }

    /// Marca tipo como em progresso (para detectar ciclos)
    bool beginTypeDefinition(string name)
    {
        if (name in inProgress)
        {
            stderr.writeln("Erro: definição circular detectada para tipo '", name, "'");
            return false;
        }

        inProgress[name] = true;
        return true;
    }

    /// Marca tipo como completo
    void endTypeDefinition(string name)
    {
        inProgress.remove(name);
    }

    /// Remove um tipo (útil para hot reload)
    bool unregisterType(string name)
    {
        if (BuiltinTypes.isPrimitiveTypeName(name))
        {
            stderr.writeln("Erro: não é possível remover tipo primitivo '", name, "'");
            return false;
        }

        return userTypes.remove(name);
    }

    /// Lista todos os tipos registrados
    string[] listAllTypes()
    {
        import std.array : array;
        import std.algorithm : sort;

        string[] types;

        // Tipos primitivos
        types ~= BuiltinTypes.listPrimitives();

        // Tipos do usuário
        types ~= userTypes.keys;

        return types.sort.array;
    }

    /// Debug: imprime todos os tipos
    void dump()
    {
        writeln("\n=== Type Registry Dump ===");
        writeln("Tipos Primitivos: ", BuiltinTypes.aliases.length);
        foreach (name, type; BuiltinTypes.aliases)
            writeln("  - ", name, " -> ", type.toStr());

        writeln("\nTipos do Usuário: ", userTypes.length);
        foreach (name, type; userTypes)
            writeln("  - ", name, " : ", type.toStr());

        writeln("\nCache de Compostos: ", compositeCache.length);
        foreach (key, type; compositeCache)
            writeln("  - ", key, " : ", type.toStr());

        writeln("========================\n");
    }

    /// Reset completo (útil para testes)
    void reset()
    {
        userTypes.clear();
        compositeCache.clear();
        inProgress.clear();
        BuiltinTypes.initialize();
        // BuiltinFunctions.initialize();
    }
}
