module middle.type_checker;

import std.string;
import std.conv;
import std.math : isNaN;
import std.exception;
import std.algorithm;
import frontend.lexer.token;
import frontend.parser.ast;
import frontend.values;
import middle.semantic;
import frontend.parser.ftype_info;
import std.variant;

class TypeChecker
{
    private string[string] typeMap;
    private int[string] typeHierarchy;
    private Semantic semanticAnalyzer;
    private ClassDeclaration[string] availableClasses;

    this(Semantic semanticAnalyzer = null)
    {
        this.semanticAnalyzer = semanticAnalyzer;

        // Updated hierarchy with all LLVM types
        typeHierarchy = [
            // Boolean/1-bit types
            "i1": 1,
            "bool": 1,
            "booleano": 1,

            // 8-bit types
            "i8": 2,
            "byte": 2,
            "char": 2,

            // 16-bit types
            "i16": 3,
            "short": 3,
            "half": 3, // 16-bit float

            // 32-bit types
            "i32": 4,
            "int": 4,
            "inteiro": 4,
            "binary": 4,
            "f32": 4,
            "float": 4,

            // 64-bit types
            "i64": 5,
            "long": 5,
            "f64": 5,
            "double": 5,
            "flutuante": 5,

            // 128-bit types
            "i128": 6,
            "cent": 6,
            "fp128": 6,
            "x86_fp80": 6,
            "ppc_fp128": 6,
            "real": 6
        ];

        initializeTypeMap();
    }

    private void initializeTypeMap()
    {
        // Original mappings
        typeMap["int"] = "long";
        typeMap["long"] = "long";
        typeMap["float"] = "double";
        typeMap["double"] = "double";
        typeMap["string"] = "string";
        typeMap["bool"] = "bool";
        typeMap["null"] = "null";
        typeMap["id"] = "auto";
        typeMap["void"] = "void";
        typeMap["void*"] = "void*";
        typeMap["class"] = "void*";

        // LLVM integer types
        typeMap["i1"] = "bool";
        typeMap["i8"] = "byte";
        typeMap["i16"] = "short";
        typeMap["i32"] = "int";
        typeMap["i64"] = "long";
        typeMap["i128"] = "cent";

        // LLVM floating point types
        typeMap["half"] = "float";
        typeMap["f32"] = "float";
        typeMap["f64"] = "double";
        typeMap["fp128"] = "real";
        typeMap["x86_fp80"] = "real";
        typeMap["ppc_fp128"] = "real";

        // LLVM special types
        typeMap["label"] = "void*";
        typeMap["metadata"] = "void*";
        typeMap["token"] = "void*";

        // Composite types
        typeMap["pointer"] = "ptr";
        typeMap["array"] = "array";
        typeMap["vector"] = "vector";
        typeMap["struct"] = "struct";
        typeMap["function"] = "function";

        // Portuguese types
        typeMap["vazio"] = "void";
        typeMap["inteiro"] = "int";
        typeMap["flutuante"] = "double";
        typeMap["booleano"] = "bool";
        typeMap["nulo"] = "null";

        // Additional D native types
        typeMap["byte"] = "byte";
        typeMap["short"] = "short";
        typeMap["cent"] = "cent";
        typeMap["real"] = "real";
    }

    public bool isValidType(string type)
    {
        return (type in typeMap) !is null;
    }

    public string mapToType(string sourceType)
    {
        if (sourceType in typeMap)
        {
            return typeMap[sourceType];
        }
        throw new Exception("Unsupported type mapping for " ~ sourceType);
    }

    public void registerClass(string className, ClassDeclaration classDecl)
    {
        availableClasses[className] = classDecl;
    }

    public bool isValidClass(string className)
    {
        return (className in availableClasses) !is null;
    }

    public bool isNumericType(string type)
    {
        string[] numericTypes = [
            // Original types
            "int", "i32", "i64", "long", "float", "double", "binary", "id", "auto",
            // LLVM integer types
            "i1", "i8", "i16", "i128", "byte", "short", "cent",
            // LLVM floating point types
            "half", "f32", "f64", "fp128", "x86_fp80", "ppc_fp128", "real",
            // Portuguese
            "inteiro", "flutuante"
        ];
        return numericTypes.canFind(type);
    }

    public bool isFloatType(string type)
    {
        string[] floatTypes = [
            "float", "double", "real", "half", "f32", "f64",
            "fp128", "x86_fp80", "ppc_fp128", "flutuante"
        ];
        return floatTypes.canFind(type);
    }

    public bool isIntegerType(string type)
    {
        string[] intTypes = [
            "int", "long", "byte", "short", "cent",
            "i1", "i8", "i16", "i32", "i64", "i128",
            "bool", "binary", "inteiro", "booleano"
        ];
        return intTypes.canFind(type);
    }

    public bool isFloat(string left, string right)
    {
        return isFloatType(left) || isFloatType(right);
    }

    // Gets the promoted type between two numeric types
    private FTypeInfo promoteTypes(TypesNative leftType, TypesNative rightType)
    {
        int leftRank = typeHierarchy.get(cast(string) leftType, 0);
        int rightRank = typeHierarchy.get(cast(string) rightType, 0);

        if (leftRank >= rightRank)
        {
            return createTypeInfo(cast(TypesNative) leftType);
        }
        return createTypeInfo(rightType);
    }

    public bool areTypesCompatible(string sourceType, string targetType)
    {
        if (sourceType == targetType)
            return true;

        if (isNumericType(sourceType) && isNumericType(targetType))
            return true;

        // Extended compatibility map with LLVM types
        string[][string] compatibilityMap = [
            // Original compatibility
            "int": [
                "float", "double", "i64", "long", "bool", "i128", "string", "i32",
                "i16", "i8"
            ],
            "i32": [
                "float", "double", "i64", "long", "bool", "int", "i16", "i8",
                "f32", "f64"
            ],
            "float": [
                "double", "int", "i32", "i64", "long", "bool", "string", "f64",
                "real"
            ],
            "double": [
                "int", "i32", "float", "i64", "long", "bool", "string", "f32",
                "f64"
            ],
            "binary": ["int", "i32", "i64", "long"],
            "i64": ["float", "double", "bool", "long", "i32", "i16", "i8"],
            "long": ["float", "double", "bool", "string", "i64", "i32"],
            "string": ["const char", "char", "long", "double"],
            "bool": [
                "int", "i32", "long", "float", "double", "string", "i64", "i1"
            ],

            // LLVM integer types
            "i1": ["bool", "i8", "i16", "i32", "i64", "i128"],
            "i8": ["i16", "i32", "i64", "i128", "float", "double", "byte"],
            "i16": ["i32", "i64", "i128", "float", "double", "short"],
            "i128": ["float", "double", "real", "cent"],

            // LLVM floating point types
            "half": ["float", "double", "real", "f32", "f64"],
            "f32": ["f64", "double", "real", "float"],
            "f64": ["real", "double", "fp128"],
            "fp128": ["real"],
            "x86_fp80": ["real", "double"],
            "ppc_fp128": ["real", "double"],

            // D native types
            "byte": [
                "short", "int", "long", "float", "double", "i8", "i16", "i32",
                "i64"
            ],
            "short": ["int", "long", "float", "double", "i16", "i32", "i64"],
            "cent": ["real", "double", "i128"],
            "real": ["double", "float"]
        ];

        if (sourceType in compatibilityMap &&
            compatibilityMap[sourceType].canFind(targetType))
            return true;

        if (sourceType.startsWith("class") && targetType.startsWith("class"))
            return false;

        return false;
    }

    public FTypeInfo checkBinaryExprTypes(Stmt left, Stmt right, string operator)
    {
        TypesNative leftType = left.type.baseType;
        TypesNative rightType = right.type.baseType;

        if (leftType != rightType && !areTypesCompatible(cast(string) leftType, cast(string) rightType))
        {
            throw new Exception(
                "Operator '" ~ operator ~ "' cannot be applied to types '" ~
                    leftType ~ "' and '" ~ rightType ~ "'"
            );
        }

        switch (operator)
        {
        case "+":
            if (leftType == TypesNative.I8P || rightType == TypesNative.I8P)
            {
                return createTypeInfo(TypesNative.I8P);
            }
            if (isNumericType(leftType) && isNumericType(rightType))
            {
                return promoteTypes(leftType, rightType);
            }
            throw new Exception(
                "Operator '+' cannot be applied to types '" ~
                    leftType ~ "' and '" ~ rightType ~ "'"
            );

        case "-":
        case "*":
        case "/":
            if (isNumericType(leftType) && isNumericType(rightType))
            {
                return promoteTypes(leftType, rightType);
            }
            if (right.value == 0 && operator == "/")
            {
                throw new Exception("Division by zero detected during type checking");
            }
            throw new Exception(
                "Operator '" ~ operator ~ "' cannot be applied to types '" ~
                    leftType ~ "' and '" ~ rightType ~ "'"
            );

        case "%":
            // Modulo only works with integer types
            if (isIntegerType(leftType) && isIntegerType(rightType))
            {
                return promoteTypes(leftType, rightType);
            }
            if (right.value == 0)
            {
                throw new Exception("Division by zero detected during type checking");
            }
            throw new Exception(
                "Operator '%' can only be applied to integer types, got '" ~
                    leftType ~ "' and '" ~ rightType ~ "'"
            );

        case "**":
            if (isNumericType(leftType) && isNumericType(rightType))
            {
                return promoteTypes(leftType, rightType);
            }
            throw new Exception(
                "Operator '**' cannot be applied to types '" ~
                    leftType ~ "' and '" ~ rightType ~ "'"
            );

        case "==":
        case "!=":
            if (areTypesCompatible(leftType, rightType))
            {
                return createTypeInfo(TypesNative.I1);
            }
            throw new Exception(
                "Operator '" ~ operator ~ "' cannot be applied to incompatible types '" ~
                    leftType ~ "' and '" ~ rightType ~ "'"
            );

        case "<":
        case "<=":
        case ">":
        case ">=":
            if ((isNumericType(leftType) && isNumericType(rightType)) || (leftType == TypesNative.I8P && rightType == TypesNative
                    .I8P))
            {
                return createTypeInfo(TypesNative.I1);
            }
            throw new Exception(
                "Operator '" ~ operator ~ "' cannot be applied to types '" ~
                    leftType ~ "' and '" ~ rightType ~ "'"
            );

        case "&&":
        case "||":
            if (leftType == TypesNative.I1 && rightType == TypesNative.I1)
            {
                return createTypeInfo(TypesNative.I1);
            }
            throw new Exception(
                "Operator '" ~ operator ~ "' cannot be applied to types '" ~
                    leftType ~ "' and '" ~ rightType ~ "'"
            );

        case "~":
            if (leftType == TypesNative.I8P || rightType == TypesNative.I8P)
            {
                return createTypeInfo(TypesNative.I8P);
            }
            throw new Exception(
                "Operator '" ~ operator ~ "' cannot be applied to types '" ~
                    leftType ~ "' and '" ~ rightType ~ "'"
            );

        case "&":
        case "|":
        case "^":
            if (isIntegerType(leftType) && isIntegerType(rightType))
            {
                return promoteTypes(leftType, rightType);
            }
            throw new Exception(
                "Operator '" ~ operator ~ "' can only be applied to integer types, got '" ~
                    leftType ~ "' and '" ~ rightType ~ "'"
            );

        case "<<":
        case ">>":
            if (isIntegerType(leftType) && isIntegerType(rightType))
            {
                return createTypeInfo(leftType);
            }
            throw new Exception(
                "Shift operators can only be applied to integer types, got '" ~
                    leftType ~ "' and '" ~ rightType ~ "'"
            );

        case "&=":
        case "|=":
        case "^=":
        case "<<=":
        case ">>=":
            if (isIntegerType(leftType) && isIntegerType(rightType))
            {
                return createTypeInfo(leftType);
            }
            throw new Exception(
                "Operator '" ~ operator ~ "' can only be applied to integer types, got '" ~
                    leftType ~ "' and '" ~ rightType ~ "'"
            );

        default:
            throw new Exception("Unknown operator: " ~ operator);
        }
    }

    public FTypeInfo checkUnaryExprType(Stmt operand, string operator, bool isPostfix = false)
    {
        string operandType = cast(string) operand.type.baseType;

        switch (operator)
        {
        case "++":
        case "--":
            if (!isNumericType(operandType))
            {
                throw new Exception(
                    "Operator '" ~ operator ~ "' can only be applied to numeric types, got '" ~
                        operandType ~ "'"
                );
            }
            return operand.type;

        case "+":
        case "-":
            if (!isNumericType(operandType))
            {
                throw new Exception(
                    "Unary operator '" ~ operator ~ "' can only be applied to numeric types, got '" ~
                        operandType ~ "'"
                );
            }
            return operand.type;

        case "!":
            return createTypeInfo(TypesNative.I1);

        case "~":
            if (!isIntegerType(operandType))
            {
                throw new Exception(
                    "Bitwise NOT operator '~' can only be applied to integer types, got '" ~
                        operandType ~ "'"
                );
            }
            return operand.type;

        case "*":
        case "&":
            return operand.type;

        default:
            throw new Exception("Unknown unary operator: " ~ operator);
        }
    }

    public void registerCustomType(string sourceType, string targetType)
    {
        typeMap[sourceType] = targetType;
    }

    private Loc makeLoc(Loc start, Loc end)
    {
        Loc result = start;
        result.end = end.end;
        return result;
    }

    public string formatLiteralForType(Variant value, string targetType)
    {
        try
        {
            if (!targetType.canFind("string"))
            {
                auto numValue = value.get!double();
                if (!isNaN(numValue))
                {
                    if (isFloatType(targetType))
                    {
                        string strValue = to!string(value);
                        if (to!long(numValue) == numValue && !strValue.canFind("."))
                        {
                            return value.get!string ~ ".0";
                        }
                        return value.get!string;
                    }
                    return to!string(cast(long) numValue);
                }
            }

            if (is(typeof(value) == string))
            {
                return value.get!string;
            }
        }
        catch (Exception e)
        {
            // Ignore conversion errors and fall through to default
        }
        return value.get!string;
    }

    public bool isPointerType(FTypeInfo type)
    {
        return type.isPointer;
    }

    // Helper method to get optimal numeric type for a value
    public string getOptimalNumericType(long value)
    {
        if (value >= -128 && value <= 127)
            return "i8";
        else if (value >= -32_768 && value <= 32_767)
            return "i16";
        else if (value >= -2_147_483_648L && value <= 2_147_483_647L)
            return "i32";
        else
            return "i64";
    }
}

// Singleton instance for global access
private __gshared TypeChecker typeCheckerInstance;

public TypeChecker getTypeChecker(Semantic semanticAnalyzer = null)
{
    if (typeCheckerInstance is null)
    {
        typeCheckerInstance = new TypeChecker(semanticAnalyzer);
    }
    return typeCheckerInstance;
}
