module backend.builder;

import core.stdc.stdio;
import std.format : format;
import std.conv : to;
import std.stdio : write, writefln, writeln;
import std.algorithm;
import std.array;
import std.string;
import frontend.parser.ftype_info;
import frontend.parser.ast;
import frontend.values;
import middle.stdlib.std_lib_module_builder : StdLibFunction;
import backend.codegen.llvm;
import middle.semantic;
import middle.stdlib.primitives;

struct Symbol
{
    LLVMValueRef value;
    LLVMTypeRef type;
    bool isVariable; // Novo campo para distinguir variável de valor
}

class Builder
{
private:
    Symbol[string] variables;
    Symbol[string] functions;
    Program program;

    LLVMTypeRef getType(TypesNative type, uint len = 0)
    {
        switch (type)
        {
        case TypesNative.I8P:
            return LLVMPointerType(LLVMInt8TypeInContext(context), len);
        case TypesNative.I8:
            return LLVMInt8TypeInContext(context);
        case TypesNative.I32:
            return LLVMInt32TypeInContext(context);
        case TypesNative.F32:
            return LLVMFloatTypeInContext(context);
        default:
            throw new Exception(format("Tipo desconhecido '%s'.", cast(string) type));
        }
    }

    bool genProgram(Program node)
    {
        // gera o printf
        auto i8ptr = LLVMPointerType(LLVMInt8TypeInContext(context), 0);
        auto printfType = LLVMFunctionType(LLVMInt32TypeInContext(context), &i8ptr, 1, 1);
        auto printfFunc = LLVMAddFunction(mod, "printf", printfType);
        functions["printf"] = Symbol(printfFunc, printfType, false);

        // gera a função main
        LLVMTypeRef int32Ty = getType(TypesNative.I32);
        LLVMTypeRef mainTy = LLVMFunctionType(int32Ty, null, 0, 0);
        LLVMValueRef main = LLVMAddFunction(mod, "main", mainTy);
        LLVMBasicBlockRef entry = LLVMAppendBasicBlockInContext(context, main, "entry");
        LLVMPositionBuilderAtEnd(builder, entry);

        // gera o corpo
        foreach (Stmt n; node.body)
        {
            genStmt(n);
            if (n.kind == NodeType.FunctionDeclaration)
                LLVMPositionBuilderAtEnd(builder, entry);
        }

        // retorno da main
        LLVMPositionBuilderAtEnd(builder, entry);
        LLVMBuildRet(builder, LLVMConstInt(int32Ty, 0, 0));

        return true;
    }

    Symbol genStmt(Stmt node)
    {
        switch (node.kind)
        {
        case NodeType.StringLiteral:
            string str = (cast(StringLiteral) node).value.get!string;
            auto strConst = LLVMConstStringInContext(context, str.toStringz(), cast(uint) str.length + 1, true);

            auto globalStr = LLVMAddGlobal(mod, LLVMTypeOf(strConst), ".str");
            LLVMSetInitializer(globalStr, strConst);
            LLVMSetGlobalConstant(globalStr, true);
            LLVMSetLinkage(globalStr, LLVMLinkage.LLVMPrivateLinkage);

            LLVMValueRef[2] indices;
            indices[0] = LLVMConstInt(LLVMInt32TypeInContext(context), 0, 0);
            indices[1] = LLVMConstInt(LLVMInt32TypeInContext(context), 0, 0);

            auto strPtr = LLVMConstGEP2(
                LLVMTypeOf(strConst),
                globalStr,
                indices.ptr,
                2
            );

            return Symbol(strPtr, getType(TypesNative.I8P, cast(uint) str.length), false);

        case NodeType.IntLiteral:
            return Symbol(LLVMConstInt(getType(node.type.baseType), node.value.get!long, 0),
                getType(node.type.baseType), false);
        case NodeType.FloatLiteral:
            return Symbol(LLVMConstReal(getType(node.type.baseType), node.value.get!double),
                getType(node.type.baseType), false);
        case NodeType.Identifier:
            auto variable = this.variables[node.value.get!string];
            if (!variable.isVariable)
            {
                return variable;
            }
            auto loadedValue = LLVMBuildLoad2(builder, variable.type, variable.value, "");
            return Symbol(loadedValue, variable.type, true);
        case NodeType.VariableDeclaration:
            return genVarDeclaration(cast(VariableDeclaration) node);
        case NodeType.FunctionDeclaration:
            return genFunctionDeclaration(cast(FunctionDeclaration) node);
        case NodeType.CallExpr:
            return genCallExpr(cast(CallExpr) node);
        case NodeType.UnaryExpr:
            return genUnaryExpr(cast(UnaryExpr) node);
        case NodeType.ReturnStatement:
            Symbol value = this.genStmt((cast(ReturnStatement) node).expr);
            return Symbol(LLVMBuildRet(builder, value.value), value.type, false);
        case NodeType.BinaryExpr:
            return genBinaryExpr(cast(BinaryExpr) node);
        default:
            throw new Exception(format("Node desconhecido '%s'.", to!string(node.kind)));
        }
    }

    Symbol genUnaryExpr(UnaryExpr node)
    {
        Symbol operand = genStmt(node.operand);
        LLVMValueRef result;

        switch (node.op)
        {
        case "-":
            // Negação aritmética
            if (node.type.baseType == TypesNative.I32 || node.type.baseType == TypesNative.I8)
            {
                result = LLVMBuildNeg(builder, operand.value, "neg");
            }
            else if (node.type.baseType == TypesNative.F32)
            {
                result = LLVMBuildFNeg(builder, operand.value, "fneg");
            }
            else
            {
                throw new Exception(format("Operador '-' não suportado para tipo '%s'", to!string(
                        node.type.baseType)));
            }
            return Symbol(result, operand.type, false);

        case "!":
            // Negação lógica (NOT)
            // Converte para booleano (0 ou 1) e inverte
            if (node.type.baseType == TypesNative.I32 || node.type.baseType == TypesNative.I8)
            {
                // Compara com zero: operand == 0 ? 1 : 0
                LLVMValueRef zero = LLVMConstInt(operand.type, 0, 0);
                result = LLVMBuildICmp(builder, LLVMIntPredicate.LLVMIntEQ, operand.value, zero, "not");
                // Converte o resultado i1 para o tipo original
                result = LLVMBuildZExt(builder, result, operand.type, "not_ext");
            }
            else if (node.type.baseType == TypesNative.F32)
            {
                // Para float: operand == 0.0 ? 1 : 0
                LLVMValueRef zero = LLVMConstReal(operand.type, 0.0);
                result = LLVMBuildFCmp(builder, LLVMRealPredicate.LLVMRealOEQ, operand.value, zero, "fnot");
                // Converte para inteiro e depois para float se necessário
                result = LLVMBuildUIToFP(builder, result, operand.type, "fnot_conv");
            }
            else
            {
                throw new Exception(format("Operador '!' não suportado para tipo '%s'", to!string(
                        node.type.baseType)));
            }
            return Symbol(result, operand.type, false);

        case "&":
            // Address-of operator (pegar endereço)
            writeln(node.operand);
            if (!operand.isVariable)
            {
                throw new Exception("Operador '&' só pode ser aplicado a variáveis (lvalues)");
            }

            // O operand.value já é um ponteiro para a variável (resultado do alloca)
            // Então simplesmente retornamos esse ponteiro
            LLVMTypeRef ptrType = LLVMPointerType(operand.type, 0);
            return Symbol(operand.value, ptrType, false);

        case "*":
            // Dereference operator (desreferenciar ponteiro)
            if (node.operand.kind != NodeType.Identifier)
            {
                throw new Exception("Operador '*' requer um identificador de ponteiro");
            }

            // Verifica se é um ponteiro
            string varName = node.operand.value.get!string;
            if (varName !in variables)
            {
                throw new Exception(format("Variável '%s' não encontrada", varName));
            }

            Symbol ptrVar = variables[varName];
            // Primeiro carrega o ponteiro da variável
            LLVMValueRef ptr = LLVMBuildLoad2(builder, ptrVar.type, ptrVar.value, "ptr_load");
            // Depois carrega o valor apontado pelo ponteiro
            result = LLVMBuildLoad2(builder, getType(node.operand.type.baseType), ptrVar.value, "deref");
            return Symbol(result, getType(node.operand.type.baseType), false);

        default:
            throw new Exception(format("Operador unário desconhecido '%s'", node.op));
        }
    }

    Symbol genCallExpr(CallExpr node)
    {
        string functionName = node.calle.value.get!string;
        Symbol function_ = functions[functionName];

        if (function_.value is null)
        {
            throw new Exception("Função '" ~ functionName ~ "' não encontrada.");
        }

        LLVMValueRef[] args;
        if (node.args !is null)
        {
            foreach (arg; node.args)
            {
                Symbol argSymbol = genStmt(arg);
                args ~= argSymbol.value;
            }
        }

        LLVMValueRef call = LLVMBuildCall2(
            builder,
            function_.type,
            function_.value,
            args.length > 0 ? args.ptr : null,
            cast(uint) args.length,
            ""
        );

        return Symbol(call, function_.type, false);
    }

    Symbol genFunctionDeclaration(FunctionDeclaration node)
    {
        LLVMTypeRef returnType = getType(node.type.baseType);
        LLVMTypeRef[] paramTypes = node.args.map!(x => getType(x.type.baseType)).array;

        LLVMTypeRef functionType = LLVMFunctionType(
            returnType,
            paramTypes.length > 0 ? paramTypes.ptr : null,
            cast(uint) paramTypes.length,
            0
        );

        LLVMValueRef function_ = LLVMAddFunction(
            mod,
            node.id.value.get!string.toStringz(),
            functionType
        );

        functions[node.id.value.get!string] = Symbol(function_, functionType, false);

        LLVMBasicBlockRef entryBlock = LLVMAppendBasicBlockInContext(
            context,
            function_,
            "entry"
        );

        LLVMPositionBuilderAtEnd(builder, entryBlock);

        Symbol[string] previousVars = variables; // Backup das variáveis do escopo anterior

        for (uint i = 0; i < node.args.length; i++)
        {
            LLVMValueRef param = LLVMGetParam(function_, i);
            string paramName = node.args[i].id.value.get!string;
            LLVMTypeRef paramType = getType(node.args[i].type.baseType);
            LLVMValueRef paramAlloca = LLVMBuildAlloca(builder, paramType, paramName.toStringz());
            LLVMBuildStore(builder, param, paramAlloca);
            variables[paramName] = Symbol(paramAlloca, paramType, true);
        }

        foreach (Stmt stmt; node.body)
        {
            genStmt(stmt);
        }

        variables = previousVars;
        return Symbol(function_, functionType, false);
    }

    Symbol genBinaryExpr(BinaryExpr node)
    {
        auto left = this.genStmt(node.left);
        auto right = this.genStmt(node.right);
        LLVMValueRef result;
        switch (node.op)
        {
        case "+":
            result = LLVMBuildAdd(builder, left.value, right.value, "");
            break;
        case "-":
            result = LLVMBuildSub(builder, left.value, right.value, "");
            break;
        case "*":
            result = LLVMBuildMul(builder, left.value, right.value, "");
            break;
        default:
            throw new Exception(format("Operador desconhecido '%s'.", node.op));
        }
        return Symbol(result, getType(node.type.baseType), false);
    }

    Symbol genVarDeclaration(VariableDeclaration node)
    {
        FTypeInfo type = node.value.get!Stmt.type;
        if (type.baseType == TypesNative.I8P)
        {
            Symbol stringSymbol = genStmt(node.value.get!Stmt);
            this.variables[node.id.value.get!string] = stringSymbol;
            return stringSymbol;
        }

        LLVMValueRef var = LLVMBuildAlloca(builder, getType(type.baseType),
            node.id.value.get!string.toStringz());
        LLVMBuildStore(builder, this.genStmt(node.value.get!Stmt).value, var);
        Symbol symbol = Symbol(var, getType(type.baseType), true);
        this.variables[node.id.value.get!string] = symbol;
        return symbol;
    }

    void cleanup()
    {
        if (this.builder !is null)
        {
            LLVMDisposeBuilder(this.builder);
            this.builder = null;
        }

        if (this.mod !is null)
        {
            LLVMDisposeModule(this.mod);
            this.mod = null;
        }

        if (this.context !is null)
        {
            LLVMContextDispose(this.context);
            this.context = null;
        }
    }

public:
    Semantic semantic;
    LLVMModuleRef mod;
    LLVMContextRef context;
    LLVMBuilderRef builder;

    this(Program program, Semantic semantic)
    {
        this.semantic = semantic;
        this.program = program;

        this.context = LLVMContextCreate();
        this.mod = LLVMModuleCreateWithNameInContext("main", this.context);
        this.builder = LLVMCreateBuilderInContext(this.context);

        if (this.context is null || this.mod is null || this.builder is null)
        {
            printf("ERRO: Falha ao inicializar componentes LLVM\n");
            this.cleanup();
            return;
        }
    }

    ~this()
    {
        this.cleanup();
    }

    bool build()
    {
        if (this.context is null || this.mod is null || this.builder is null)
        {
            printf("ERRO: Builder não foi inicializado corretamente\n");
            return false;
        }

        bool success = this.genProgram(this.program);

        if (!success)
        {
            printf("ERRO: Falha ao gerar programa\n");
            this.cleanup();
            return false;
        }

        return true;
    }

    bool saveModule(const(char)* filename)
    {
        const(char)* errorMessage = null;
        if (LLVMPrintModuleToFile(this.mod, filename, &errorMessage))
        {
            printf("ERRO ao salvar módulo: %s\n", errorMessage);
            return false;
        }
        else
        {
            printf("Módulo salvo em: %s\n", filename);
            return true;
        }
    }
}
