module frontend.values;

enum TypesNative : string
{
    STRING = "string",
    INT = "long",
    LONG = "long",
    FLOAT = "float",
    BOOL = "bool",
    VOID = "void",
    CHAR = "char",
    NULL = "null",
    ID = "auto", // Para identificadores (tipo ainda não conhecido)
    CLASS = "class" // Novo tipo para classes
}
