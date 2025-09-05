module frontend.parser.ast_utils;

import frontend.parser.ftype_info;
import frontend.parser.ast : Stmt;
import frontend.values;

string strRepeat(string s, ulong times)
{
    string result;
    foreach (_; 0 .. times)
        result ~= s;
    return result;
}

FTypeInfo inferUnaryType(string operator, Stmt operand)
{
    switch (operator)
    {
    case "-":
        return operand.type;
    case "!":
        return createTypeInfo(TypesNative.I1);
    default:
        return createTypeInfo(TypesNative.NULO);
    }
}
