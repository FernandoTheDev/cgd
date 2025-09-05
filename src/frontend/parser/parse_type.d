module frontend.parser.parse_type;

import std.variant;
import frontend.lexer.token : Token, TokenType;
import frontend.values : TypesNative;
import frontend.parser.ftype_info : createArrayType, createPointerType, createTypeInfo, FTypeInfo;

/**
* ParseType - Responsible for analyzing complex type declarations
* Supports:
* - Basic types (int, string, etc.)
* - Arrays (int[], string[], etc.)
* - Multidimensional arrays (int[][], int[][][], etc.)
* - Pointers (*int, **int, etc.)
* - Combinations (*int[], int*[], **int[][], etc.)
*/
class ParseType
{
private:
    Token[] tokens;

    bool isAtEnd()
    {
        return this.current >= this.tokens.length;
    }

    Token peek()
    {
        return this.tokens[this.current];
    }

    Token previous()
    {
        return this.tokens[this.current - 1];
    }

    Token advance()
    {
        if (!this.isAtEnd())
            this.current++;
        return this.previous();
    }

    bool check(TokenType type)
    {
        if (this.isAtEnd())
            return false;
        return this.peek().kind == type;
    }

    bool match(TokenType[] types)
    {
        foreach (type; types)
        {
            if (this.check(type))
            {
                this.advance();
                return true;
            }
        }
        return false;
    }

    ulong parsePointerPrefix()
    {
        ulong pointerLevel;

        while (this.check(TokenType.ASTERISK) || this.check(TokenType.EXPONENTIATION))
        {
            if (this.peek().kind == TokenType.EXPONENTIATION)
            {
                pointerLevel += 2;
            }
            else
            {
                pointerLevel++;
            }
            this.advance(); // '*' || '**'
        }
        return pointerLevel;
    }

    TypesNative tokenValueToTypesNative(Token token)
    {
        if (token.value.type != typeid(string))
        {
            throw new Exception(
                "Expected token with string value, but it came: " ~ token.value.type.toString());
        }

        string value = token.value.get!string;

        switch (value)
        {
        case "i8":
            return TypesNative.I8;
        case "i16":
            return TypesNative.I16;
        case "i32":
            return TypesNative.I32;
        case "i64":
            return TypesNative.I64;
        case "float":
            return TypesNative.F32;
        case "double":
            return TypesNative.F64;
        case "i8*":
            return TypesNative.I8P;
        case "void":
            // return TypesNative.NULO;
        case "null":
            return TypesNative.NULO;
        case "bool":
            return TypesNative.I1;
        default:
            throw new Exception("Unknown native type: " ~ value);
        }
    }

    TypesNative parseBaseType()
    {
        return this.tokenValueToTypesNative(this.advance());
    }

    ulong parseArrayDimensions()
    {
        ulong dimensions;
        while (this.match([TokenType.LBRACKET, TokenType.RBRACKET]))
        {
            dimensions++;
        }
        return dimensions;
    }

protected:
    ulong current = 0;
public:
    this(Token[] tokens = [])
    {
        this.tokens = tokens;
    }

    FTypeInfo parse()
    {
        ulong pointerLevel = this.parsePointerPrefix();
        TypesNative baseType = this.parseBaseType();
        ulong dimensions = this.parseArrayDimensions();
        FTypeInfo typeInfo;

        if (dimensions > 0)
        {
            typeInfo = createArrayType(baseType, dimensions);
        }
        else
        {
            typeInfo = createTypeInfo(baseType);
        }

        if (pointerLevel > 0)
        {
            typeInfo = createPointerType(typeInfo.baseType, pointerLevel);
        }

        return typeInfo;
    }
}

class ArrayBrackets
{
public:
    bool isValid;
    ulong dimensions;
    ulong endIndex;

    this(bool isValid, ulong dimensions, ulong endIndex)
    {
        this.isValid = isValid;
        this.dimensions = dimensions;
        this.endIndex = endIndex;
    }
}

ArrayBrackets parseArrayBrackets(
    ref Token[] tokens,
    ulong startIndex
)
{
    ulong current = startIndex;
    ulong dimensions = 0;

    while (current + 1 < tokens.length)
    {
        if (
            tokens[current].kind == TokenType.LBRACKET &&
            tokens[current + 1].kind == TokenType.RBRACKET
            )
        {
            dimensions++;
            current += 2;
        }
        else
        {
            break;
        }
    }

    return new ArrayBrackets(dimensions > 0, dimensions, current);
}

class TypeAnnotation
{
public:
    FTypeInfo typeInfo;
    ulong endIndex;

    this(FTypeInfo typeInfo, ulong endIndex)
    {
        this.typeInfo = typeInfo;
        this.endIndex = endIndex;
    }
}

TypeAnnotation parseTypeAnnotation(Token[] tokens, ulong startIndex)
{
    ParseType parser = new ParseType(tokens[startIndex .. $]);
    FTypeInfo typeInfo = parser.parse();
    auto tokensConsumed = parser.current;
    return new TypeAnnotation(typeInfo, startIndex + tokensConsumed);
}
