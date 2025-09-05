module frontend.parser.ftype_info;

import frontend.values;
import std.string : toLower;

struct FTypeInfo
{
    // Tipo base (para tipos primitivos)
    TypesNative baseType;

    // Informações sobre arrays
    bool isArray = false; // true para arrays (dinâmicos ou de tamanho fixo)
    ulong dimensions = 0; // número de dimensões (para arrays dinâmicos)
    ulong fixedArraySize = 0; // tamanho do array (0 = dinâmico, >0 = fixo)

    // Informações sobre ponteiros
    bool isPointer = false; // true para ponteiros
    ulong pointerLevel = 0; // nível de indireção (1 para *, 2 para **, etc.)

    // Informações sobre estruturas
    bool isStruct = false; // true para estruturas/classes
    FTypeInfo*[] fieldTypes; // tipos dos campos da estrutura (agora ponteiros)
    string className; // nome da estrutura/classe

    // Informações sobre vetores (SIMD)
    bool isVector = false; // true para vetores
    ulong vectorSize = 0; // número de elementos no vetor

    // Informações sobre funções
    bool isFunction = false; // true para tipos de função
    FTypeInfo* returnType; // tipo de retorno (agora ponteiro)
    FTypeInfo*[] paramTypes; // tipos dos parâmetros (agora ponteiros)

    // Tipo do elemento (usado para arrays, ponteiros e vetores)
    FTypeInfo* elementType; // agora ponteiro

    // Informações específicas da linguagem (não do LLVM)
    bool isRef = false; // true para referências
}

FTypeInfo createTypeInfo(TypesNative baseType, bool s = false)
{
    return FTypeInfo(
        baseType,
        false,
        0,
        false,
        s,
        0,
        false
    );
}

FTypeInfo createClassType(string className)
{
    FTypeInfo info;
    info.baseType = TypesNative.STRUCT;
    info.className = className;
    return info;
}

FTypeInfo createArrayTypeRef(TypesNative baseType, ulong dimensions = 1, bool s = false)
{
    return FTypeInfo(
        baseType,
        true,
        dimensions,
        false,
        s,
        0,
        true
    );
}

FTypeInfo createArrayType(TypesNative baseType, ulong dimensions = 1, bool s = false)
{
    return FTypeInfo(
        baseType,
        true,
        dimensions,
        false,
        s,
        0,
        false
    );
}

FTypeInfo createPointerType(TypesNative baseType, ulong pointerLevel, bool s = false)
{
    return FTypeInfo(
        baseType,
        false,
        0,
        true,
        s,
        pointerLevel,
        false
    );
}
