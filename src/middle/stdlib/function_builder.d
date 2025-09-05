module middle.stdlib.function_builder;

import std.string;
import std.array;
import std.conv;
import std.algorithm;
import middle.stdlib.std_lib_module_builder;
import middle.type_checker;
import frontend.parser.ftype_info;

enum ExternStrategy
{
    WithLinkage, // extern(C++) int func(int param);
    WithAttributes, // @nogc @safe extern(C) int func(int param);
    WithPragma, // pragma(lib, "mylib"); extern(C) int func(int param);
    Complete // Documentação + pragma + atributos + extern
}

class FunctionBuilder
{
    public StdLibFunction func;
    private StdLibModuleBuilder moduleBuilder;
    private TypeChecker typeChecker;

    this(string name, StdLibModuleBuilder moduleBuilder)
    {
        this.func = StdLibFunction();
        this.func.name = name;
        this.func.isStdLib = true;
        this.func.isVariadic = false;
        this.func.opt = 0;
        this.func.params = [];

        this.moduleBuilder = moduleBuilder;
        this.typeChecker = getTypeChecker();
    }

    FunctionBuilder returns(FTypeInfo type)
    {
        this.func.returnType = type;
        // this.func.targetType = createTypeInfo(this.typeChecker.mapToDType(type.baseType));
        return this;
    }

    FunctionBuilder withParams(FTypeInfo[] params...)
    {
        this.func.params = params.dup;
        return this;
    }

    FunctionBuilder variadic()
    {
        this.func.isVariadic = true;
        return this;
    }

    FunctionBuilder opt(long n = 0)
    {
        this.func.opt = n;
        return this;
    }

    FunctionBuilder targetName(string name)
    {
        this.func.targetName = name;
        return this;
    }

    FunctionBuilder ir(string ir)
    {
        this.func.ir = ir;
        return this;
    }

    FunctionBuilder libraryName(string name)
    {
        this.func.libraryName = name;
        return this;
    }

    FunctionBuilder isNoGc()
    {
        this.func.isNoGC = true;
        return this;
    }

    FunctionBuilder isNoThrow()
    {
        this.func.isNoThrow = true;
        return this;
    }

    FunctionBuilder isSafe()
    {
        this.func.isSafe = true;
        return this;
    }

    FunctionBuilder isPure()
    {
        this.func.isPure = true;
        return this;
    }

    FunctionBuilder customTargetType(FTypeInfo targetType)
    {
        this.func.targetType = targetType;
        return this;
    }

    FunctionBuilder generateDExternWithPragma()
    {
        if (this.func.ir.length > 0)
            return this; // already exists

        string fnName = this.func.targetName.length > 0 ?
            this.func.targetName : this.func.name;

        string[] paramDecls;

        foreach (i, p; this.func.params)
        {
            string dType = this.typeChecker.mapToType(p.baseType);
            paramDecls ~= dType ~ " param" ~ to!string(i);
        }

        string returnType = this.typeChecker.mapToType(this.func.targetType.baseType);
        string paramList = paramDecls.join(", ");

        if (this.func.isVariadic)
        {
            paramList ~= paramList.length > 0 ? ", ..." : "...";
        }

        // Adicionar pragma lib se especificado
        string pragmaStr = "";
        if (this.func.libraryName.length > 0)
        {
            pragmaStr = "pragma(mangle, \"" ~ this.func.libraryName ~ "\")\n";
        }

        this.func.ir = pragmaStr ~ "extern(" ~ this.func.linkage ~ ") " ~
            returnType ~ " " ~ fnName ~ "(" ~ paramList ~ ");";

        return this;
    }

    // Funções auxiliares
    private bool isGenericType(string type)
    {
        return type.startsWith("T") || type == "auto" || type == "generic";
    }

    private bool isNumericType(string type)
    {
        return ["int", "float", "double", "long", "real"].canFind(type);
    }

    private bool needsSerializationMixin(string type)
    {
        return ["struct", "class", "object"].canFind(type);
    }

    private string generateBaseTemplate(string fnName)
    {
        return "T " ~ fnName ~ "(T)(T param) {\n    // Base implementation\n}";
    }

    private string[] generateSpecializations(string fnName)
    {
        return [
            "int " ~ fnName ~ "(int param) {\n    // Specialized for int\n}",
            "string " ~ fnName ~ "(string param) {\n    // Specialized for string\n}"
        ];
    }

    FunctionBuilder generate(ExternStrategy strategy = ExternStrategy.WithLinkage)
    {
        return generateDExternWithPragma();
    }

    StdLibModuleBuilder done()
    {
        if (this.func.returnType.baseType is null)
        {
            throw new Exception("Function " ~ this.func.name ~
                    " must have a return type");
        }

        if (this.func.targetName.length == 0)
        {
            this.func.targetName = this.func.name;
        }

        // Auto-generate if not provided
        // this.generate();

        this.moduleBuilder.addCompleteFunction(this.func);
        return this.moduleBuilder;
    }
}
