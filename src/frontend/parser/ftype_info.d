module frontend.parser.ftype_info;

import frontend.values;
import std.string : toLower;

struct FTypeInfo
{
    TypesNative baseType;
    bool isArray;
    ulong dimensions;
    bool isPointer;
    bool isStruct;
    ulong pointerLevel;
    bool isRef;
    string className;
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
    info.baseType = TypesNative.NULO;
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
