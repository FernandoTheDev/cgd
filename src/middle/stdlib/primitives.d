module middle.stdlib.primitives;

import std.stdio;
import std.format;
import frontend.values;
import frontend.parser.ftype_info;

// "String".tamanho -> string_tamanho("String")

// Primitive
// string
// métodos|propriedades

struct PrimitiveProperty
{
    string name; // tamanho, substr, ...
    FTypeInfo type; // string
    string mangle; // string_tamanho, ...
    FTypeInfo[] args; // types -> [int, string, ...]
    long ignore; // numero de argumentos a serem ignorados. 1 by default

    string generateD()
    {
        string code = format("pragma(mangle, \"%s\")\n", mangle);
        string args_;
        for (long i; i < args.length; i++)
        {
            if (args[i].isRef)
                args_ ~= "ref ";
            if (args[i].isArray)
                args_ ~= cast(string) args[i].baseType ~ "[]";
            else
                args_ ~= cast(string) args[i].baseType;
            if (i + 1 < args.length)
                args_ ~= ", ";
        }
        code ~= format("extern(D) %s %s(%s);", type.isArray ? cast(string) type.baseType ~ "[]" : cast(
                string) type.baseType, mangle, args_);
        return code;
    }
}

struct Primitive
{
    string name; // string, ...
    PrimitiveProperty[] properties; // OverloadedPrimitive[...]
}

class StdPrimitive
{
private:
    Primitive[string] primitives; // baseado no tipo atual
public:
    this()
    {
        // String
        // PrimitiveProperty[] str_properties;
        // str_properties ~= PrimitiveProperty("tamanho", createTypeInfo("long"), "string_tamanho", [
        //         createTypeInfo("string")
        //     ], 1);
        // str_properties ~= PrimitiveProperty("substituir", createTypeInfo("string"), "string_substituir", [
        //         createTypeInfo("string"), createTypeInfo("string"),
        //         createTypeInfo("string")
        //     ], 1);
        // str_properties ~= PrimitiveProperty("dividir", createArrayType(TypesNative.STRING), "string_dividir",
        //     [
        //         createTypeInfo("string"), createTypeInfo("string")
        //     ], 1);

        // Primitive str = Primitive("string", str_properties);
        // primitives["string"] = str;

        // // Long
        // PrimitiveProperty[] long_properties;
        // long_properties ~= PrimitiveProperty("tamanho", createTypeInfo("long"), "long_tamanho", [
        //         createTypeInfo("long")
        //     ], 1);
        // Primitive lng = Primitive("long", long_properties);
        // primitives["long"] = lng;

        // // Vetores
        // PrimitiveProperty[] arr_properties;
        // arr_properties ~= PrimitiveProperty("tamanho", createTypeInfo("long"), "array_tamanho", [
        //         createArrayType(TypesNative.STRING)
        //     ]);
        // arr_properties ~= PrimitiveProperty("adicionar", createTypeInfo("void"), "array_string_adicionar",
        //     [
        //         createArrayTypeRef(TypesNative.T),
        //         createTypeInfo("string"),
        //     ], 1);
        // arr_properties ~= PrimitiveProperty("adicionar", createTypeInfo("void"), "array_long_adicionar", [
        //         createArrayTypeRef(TypesNative.T),
        //         createTypeInfo("long"),
        //     ], 1);
        // arr_properties ~= PrimitiveProperty("adicionar", createTypeInfo("void"), "array_double_adicionar", [
        //         createArrayTypeRef(TypesNative.T),
        //         createTypeInfo("double"),
        //     ], 1);
        // Primitive arr = Primitive("array", arr_properties);
        // primitives["array"] = arr;
    }

    bool exists(string type, FTypeInfo[] args)
    {
        if (type !in primitives)
            return false;
        foreach (PrimitiveProperty prop; primitives[type].properties)
        {
            if (prop.args[prop.ignore .. $] == args)
                return true;
        }
        return false;
    }

    bool exists(string type)
    {
        return type !in primitives;
    }

    PrimitiveProperty get(string type, FTypeInfo[] args)
    {
        PrimitiveProperty fallback;
        if (!exists(type, args))
            return fallback;
        foreach (PrimitiveProperty prop; primitives[type].properties)
        {
            if (prop.args[prop.ignore .. $] == args)
                return prop;
            fallback = prop;
        }
        return fallback;
    }

    Primitive[string] get()
    {
        return primitives;
    }
}
