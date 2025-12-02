module frontend.types.builtins;

import frontend.types.type;
import std.stdio;

/// Inicializa todos os tipos built-in da linguagem
class BuiltinTypes
{
    static PrimitiveType _Int; // inteiro / i32
    static PrimitiveType _Long; // longo / i64
    static PrimitiveType _Float; // real / decimal / f32
    static PrimitiveType _Double; // duplo / f64
    static PrimitiveType _Bool; // logico / bool
    static PrimitiveType _String; // texto / string
    static PrimitiveType _Void; // vazio / void
    static PrimitiveType _Any; // qualquer / any

    static PrimitiveType _Null;
    static PrimitiveType _Never;
    static PrimitiveType[string] aliases;

    /// Inicializa todos os tipos built-in
    static void initialize()
    {
        // Cria os tipos primitivos
        _Int = new PrimitiveType(BaseType.Int);
        _Long = new PrimitiveType(BaseType.Long);
        _Float = new PrimitiveType(BaseType.Float);
        _Double = new PrimitiveType(BaseType.Double);
        _Bool = new PrimitiveType(BaseType.Bool);
        _String = new PrimitiveType(BaseType.String);
        _Void = new PrimitiveType(BaseType.Void);
        _Any = new PrimitiveType(BaseType.Any);

        _Null = new PrimitiveType(BaseType.Void); // ou criar BaseType.Null
        _Never = new PrimitiveType(BaseType.Void); // ou criar BaseType.Never

        registerAliases();
        // writeln("[BuiltinTypes] Tipos built-in inicializados");
    }

    private static void registerAliases()
    {
        aliases["inteiro"] = _Int;
        aliases["longo"] = _Long;
        aliases["decimal"] = _Float;
        aliases["real"] = _Float;
        aliases["duplo"] = _Double;
        aliases["logico"] = _Bool;
        aliases["texto"] = _String;
        aliases["vazio"] = _Void;
        aliases["qualquer"] = _Any;
        aliases["nulo"] = _Null;
        aliases["i32"] = _Int;
        aliases["i64"] = _Long;
        aliases["f32"] = _Float;
        aliases["f64"] = _Double;
        aliases["bool"] = _Bool;
        aliases["i1"] = _Bool;
        aliases["any"] = _Any;
    }

    static bool isPrimitiveTypeName(string name)
    {
        return (name in aliases) !is null;
    }

    static PrimitiveType getPrimitive(string name)
    {
        if (auto type = name in aliases)
            return *type;
        return null;
    }

    static string[] listPrimitives()
    {
        return aliases.keys;
    }
}

/// Funções built-in da linguagem
// class BuiltinFunctions
// {
//     struct FunctionSignature
//     {
//         string name;
//         Type returnType;
//         Type[] paramTypes;
//         string[] paramNames;
//         bool isVariadic;
//     }

//     static FunctionSignature[string] functions;

//     static void initialize()
//     {
//         // I/O básico
//         registerFunction("imprimir", BuiltinTypes.Void,
//             [BuiltinTypes.Any], ["valor"], true);
//         registerFunction("ler", BuiltinTypes.String, [], []);
//         registerFunction("lerInteiro", BuiltinTypes.Int, [], []);
//         registerFunction("lerDecimal", BuiltinTypes.Float, [], []);

//         // Conversões de tipo
//         registerFunction("paraInteiro", BuiltinTypes.Int,
//             [BuiltinTypes.Any], ["valor"]);
//         registerFunction("paraDecimal", BuiltinTypes.Float,
//             [BuiltinTypes.Any], ["valor"]);
//         registerFunction("paraTexto", BuiltinTypes.String,
//             [BuiltinTypes.Any], ["valor"]);
//         registerFunction("paraLogico", BuiltinTypes.Bool,
//             [BuiltinTypes.Any], ["valor"]);

//         // Funções matemáticas
//         registerFunction("abs", BuiltinTypes.Double,
//             [BuiltinTypes.Double], ["x"]);
//         registerFunction("potencia", BuiltinTypes.Double,
//             [BuiltinTypes.Double, BuiltinTypes.Double], ["base", "expoente"]);
//         registerFunction("raiz", BuiltinTypes.Double,
//             [BuiltinTypes.Double], ["x"]);
//         registerFunction("arredondar", BuiltinTypes.Int,
//             [BuiltinTypes.Double], ["x"]);

//         // String
//         registerFunction("tamanho", BuiltinTypes.Int,
//             [BuiltinTypes.String], ["texto"]);
//         registerFunction("maiuscula", BuiltinTypes.String,
//             [BuiltinTypes.String], ["texto"]);
//         registerFunction("minuscula", BuiltinTypes.String,
//             [BuiltinTypes.String], ["texto"]);
//         registerFunction("dividir", BuiltinTypes.Any, // deveria ser String[]
//             [BuiltinTypes.String, BuiltinTypes.String], ["texto", "separador"]);

//         // Array
//         registerFunction("tamanhoArray", BuiltinTypes.Int,
//             [BuiltinTypes.Any], ["array"]);
//         registerFunction("adicionar", BuiltinTypes.Void,
//             [BuiltinTypes.Any, BuiltinTypes.Any], ["array", "elemento"]);
//         registerFunction("remover", BuiltinTypes.Void,
//             [BuiltinTypes.Any, BuiltinTypes.Int], ["array", "indice"]);

//         writeln("[BuiltinFunctions] Funções built-in registradas: ", functions.length);
//     }

//     private static void registerFunction(
//         string name,
//         Type returnType,
//         Type[] paramTypes = [],
//         string[] paramNames = [],
//         bool isVariadic = false
//     )
//     {
//         functions[name] = FunctionSignature(
//             name, returnType, paramTypes, paramNames, isVariadic
//         );
//     }

//     static bool isBuiltinFunction(string name)
//     {
//         return (name in functions) !is null;
//     }

//     static FunctionSignature* getFunction(string name)
//     {
//         if (auto func = name in functions)
//             return func;
//         return null;
//     }
// }
