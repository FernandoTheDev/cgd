module frontend.parser.parse_type;
import std.variant;
import std.conv : to;
import std.algorithm;
import std.array;
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
* - Fixed-size arrays ([n x T])
* - Vectors (<n x T>)
* - Structures ({ T1, T2, ... })
* - Function types (T(T1, T2, ...))
*/
class ParseType
{
private:
    Token[] tokens;
    size_t current = 0;

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

    bool match(TokenType[] types...)
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
        while (this.match(TokenType.ASTERISK, TokenType.EXPONENTIATION))
        {
            if (this.previous().kind == TokenType.EXPONENTIATION)
                pointerLevel += 2;
            else
                pointerLevel++;
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
            // Integer types
        case "i1":
            return TypesNative.I1;
        case "i8":
            return TypesNative.I8;
        case "i16":
            return TypesNative.I16;
        case "i32":
            return TypesNative.I32;
        case "i64":
            return TypesNative.I64;

            // Floating-point types
        case "half":
        case "float":
            return TypesNative.F32;
        case "double":
            return TypesNative.F64;
        case "fp128":
            return TypesNative.FP128;
        case "x86_fp80":
            return TypesNative.X86_FP80;

            // Other types
        case "void":
            return TypesNative.NULO;
        case "bool":
            return TypesNative.I1;
        case "label":
            return TypesNative.LABEL;
        case "metadata":
            return TypesNative.METADATA;
        case "token":
            return TypesNative.TOKEN;

        default:
            return TypesNative.STRUCT; // fallback
            throw new Exception("Unknown native type: " ~ value);
        }
    }

    FTypeInfo parseBaseType()
    {
        if (this.match(TokenType.LBRACKET))
        {
            return this.parseFixedArrayType();
        }
        else if (this.match(TokenType.LESS_THAN))
        {
            return this.parseVectorType();
        }
        else if (this.match(TokenType.LBRACE))
        {
            return this.parseStructType();
        }
        else if (this.match(TokenType.LPAREN))
        {
            return this.parseFunctionType();
        }
        else
        {
            TypesNative baseType = this.tokenValueToTypesNative(this.advance());
            return createTypeInfo(baseType);
        }
    }

    FTypeInfo parseFixedArrayType()
    {
        // Format: [n x T]
        if (!this.match(TokenType.I32))
            throw new Exception("Expected array size in fixed array type");

        Token sizeToken = this.previous();
        ulong size = sizeToken.value
            .get!string
            .to!ulong;

        if (!this.match(TokenType.IDENTIFIER) || this.previous().value.get!string != "x")
            throw new Exception("Expected 'x' in fixed array type");

        FTypeInfo elementType = this.parseBaseType();

        if (!this.match(TokenType.RBRACKET))
            throw new Exception("Expected ']' in fixed array type");

        FTypeInfo arrayType = createTypeInfo(TypesNative.ARRAY);
        arrayType.fixedArraySize = size;
        *arrayType.elementType = elementType;
        return arrayType;
    }

    FTypeInfo parseVectorType()
    {
        // Format: <n x T>
        if (!this.match(TokenType.I32))
            throw new Exception("Expected vector size in vector type");

        Token sizeToken = this.previous();
        ulong size = sizeToken.value
            .get!string
            .to!ulong;

        if (!this.match(TokenType.IDENTIFIER) || this.previous().value.get!string != "x")
            throw new Exception("Expected 'x' in vector type");

        FTypeInfo elementType = this.parseBaseType();

        if (!this.match(TokenType.GREATER_THAN))
            throw new Exception("Expected '>' in vector type");

        FTypeInfo vectorType = createTypeInfo(TypesNative.VECTOR);
        vectorType.vectorSize = size;
        *vectorType.elementType = elementType;
        return vectorType;
    }

    FTypeInfo parseStructType()
    {
        // Format: { T1, T2, ... }
        FTypeInfo[] fieldTypes;

        if (!this.match(TokenType.RBRACE))
        {
            do
            {
                FTypeInfo fieldType = this.parseBaseType();
                fieldTypes ~= fieldType;
            }
            while (this.match(TokenType.COMMA));

            if (!this.match(TokenType.RBRACE))
                throw new Exception("Expected '}' in struct type");
        }

        FTypeInfo structType = createTypeInfo(TypesNative.STRUCT);
        structType.fieldTypes = toPtrArray(fieldTypes);
        return structType;
    }

    FTypeInfo parseFunctionType()
    {
        // Format: T(T1, T2, ...)
        FTypeInfo returnType = this.parseBaseType();

        if (!this.match(TokenType.LPAREN))
            throw new Exception("Expected '(' in function type");

        FTypeInfo[] paramTypes;

        if (!this.match(TokenType.RPAREN))
        {
            do
            {
                FTypeInfo paramType = this.parseBaseType();
                paramTypes ~= paramType;
            }
            while (this.match(TokenType.COMMA));

            if (!this.match(TokenType.RPAREN))
                throw new Exception("Expected ')' in function type");
        }

        FTypeInfo funcType = createTypeInfo(TypesNative.FUNCTION);
        *funcType.returnType = returnType;
        funcType.paramTypes = toPtrArray(paramTypes);
        return funcType;
    }

    ulong parseArrayDimensions()
    {
        ulong dimensions;
        while (this.match(TokenType.LBRACKET))
        {
            if (!this.match(TokenType.RBRACKET))
                throw new Exception("Expected ']' in array type");
            dimensions++;
        }
        return dimensions;
    }

public:
    this(Token[] tokens = [])
    {
        this.tokens = tokens;
    }

    FTypeInfo parse()
    {
        ulong pointerLevel = this.parsePointerPrefix();
        FTypeInfo baseType = this.parseBaseType();
        ulong dimensions = this.parseArrayDimensions();

        // Apply array dimensions if any
        if (dimensions > 0)
        {
            FTypeInfo arrayType = createArrayType(baseType.baseType, dimensions);
            *arrayType.elementType = baseType;
            baseType = arrayType;
        }

        // Apply pointer level if any
        if (pointerLevel > 0)
        {
            FTypeInfo pointerType = createPointerType(baseType.baseType, pointerLevel);
            pointerType.pointerLevel = pointerLevel;
            baseType = pointerType;
        }

        return baseType;
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

FTypeInfo*[] toPtrArray(ref FTypeInfo[] arr)
{
    auto _out = new FTypeInfo*[](arr.length);
    foreach (i; 0 .. arr.length)
        _out[i] = &arr[i]; // ponteiro pro elemento do array original
    return _out;
}
