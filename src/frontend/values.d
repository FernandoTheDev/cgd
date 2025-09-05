module frontend.values;

enum TypesNative : string
{
    I1 = "bool", // 1-bit integer (maps to bool)
    I8P = "string", // string
    I8 = "byte", // 8-bit integer
    I16 = "short", // 16-bit integer
    I32 = "int", // 32-bit integer
    I64 = "long", // 64-bit integer
    I128 = "cent", // 128-bit integer (D's cent type)

    // LLVM Floating point types
    HALF = "float", // 16-bit float (maps to float for now)
    F32 = "float", // 32-bit float
    F64 = "double", // 64-bit double
    FP128 = "real", // 128-bit quad precision (maps to D's real)
    X86_FP80 = "real", // x86 80-bit extended precision
    PPC_FP128 = "real", // PowerPC 128-bit double-double

    // LLVM Special types
    LABEL = "void*", // label type (maps to void pointer)
    METADATA = "void*", // metadata type
    TOKEN = "void*", // token type

    // Composite type indicators
    POINTER = "ptr", // generic pointer
    ARRAY = "array", // array type
    VECTOR = "vector", // vector type
    STRUCT = "struct", // structure type
    FUNCTION = "function", // function type

    NULO = "null", // null
}

unittest
{
    import std.stdio;

    writeln("Testando TypesNative...");

    // LLVM Integer types
    assert(TypesNative.I1 == "bool");
    assert(TypesNative.I8 == "byte");
    assert(TypesNative.I16 == "short");
    assert(TypesNative.I32 == "int");
    assert(TypesNative.I64 == "long");
    assert(TypesNative.I128 == "cent");

    // LLVM Float types
    assert(TypesNative.HALF == "float");
    assert(TypesNative.F32 == "float");
    assert(TypesNative.F64 == "double");
    assert(TypesNative.FP128 == "real");
    assert(TypesNative.X86_FP80 == "real");
    assert(TypesNative.PPC_FP128 == "real");

    // Special types
    assert(TypesNative.LABEL == "void*");
    assert(TypesNative.METADATA == "void*");
    assert(TypesNative.TOKEN == "void*");

    // Composite types
    assert(TypesNative.POINTER == "ptr");
    assert(TypesNative.ARRAY == "array");
    assert(TypesNative.VECTOR == "vector");
    assert(TypesNative.STRUCT == "struct");
    assert(TypesNative.FUNCTION == "function");

    // Portuguese aliases
    assert(TypesNative.VAZIO == "void");
    assert(TypesNative.INTEIRO == "int");
    assert(TypesNative.FLUTUANTE == "double");
    assert(TypesNative.BOOLEANO == "bool");
    assert(TypesNative.NULO == "null");

    writeln("✓ Todos os testes de TypesNative passaram!");
}
