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
    bool isVariable;
    bool isStruct;
    string structName;
    int fieldIndex = -1; // Para campos de struct
}

// Estrutura para manter informações de classe
struct ClassInfo
{
    string name;
    LLVMTypeRef structType;
    ClassProperty[] properties;
    ClassMethodDeclaration[] methods;
    ConstructorDeclaration constructor;
    DestructorDeclaration destructor;
    Symbol[string] fields; // Mapeamento nome -> Symbol do campo
}

// Estrutura para gerenciar contexto/escopo
struct Context
{
    Symbol[string] variables;
    Symbol[string] functions;
    ClassInfo* currentClass;
    LLVMValueRef currentThis;
    Context* parent;

    void enterScope()
    {
        Context* newContext = new Context();
        newContext.parent = &this;
        newContext.functions = this.functions; // Funções são globais
        newContext.currentClass = this.currentClass;
        newContext.currentThis = this.currentThis;
    }

    void exitScope()
    {
        if (parent !is null)
        {
            this.variables = parent.variables;
            this.currentClass = parent.currentClass;
            this.currentThis = parent.currentThis;
        }
    }

    Symbol* findVariable(string name)
    {
        Context* current = &this;
        while (current !is null)
        {
            if (name in current.variables)
                return &current.variables[name];
            current = current.parent;
        }
        return null;
    }

    Symbol* findFunction(string name)
    {
        return name in functions;
    }
}

class Builder
{
private:
    Context globalContext;
    Context* currentContext;
    ClassInfo[string] classes; // Registro global de classes

    LLVMValueRef alloca; // ponteiro para um alloca atual
    LLVMValueRef currentFunction; // ponteiro para um alloca atual
    LLVMTypeRef currentStructType;
    Program program;

    // Método para getType com FTypeInfo
    LLVMTypeRef getType(FTypeInfo type, uint len = 64)
    {
        // Handle pointer levels
        if (type.isPointer || type.pointerLevel > 0)
        {
            LLVMTypeRef baseType;
            if (type.isStruct)
            {
                if (type.className in classes)
                    baseType = classes[type.className].structType;
                else
                    baseType = currentStructType;
            }
            else
            {
                baseType = getTypeFromNative(type.baseType);
            }

            // Apply pointer levels
            for (ulong i = 0; i < type.pointerLevel; i++)
            {
                baseType = LLVMPointerType(baseType, 0);
            }
            return baseType;
        }

        // Handle struct types
        if (type.isStruct || type.baseType == TypesNative.STRUCT)
        {
            if (type.className in classes)
                return classes[type.className].structType;
            else
                return currentStructType;
        }

        // Handle base types
        return getTypeFromNative(type.baseType);
    }

    // Helper method to get native types
    LLVMTypeRef getTypeFromNative(TypesNative type)
    {
        switch (type)
        {
        case TypesNative.I8P:
            return LLVMPointerType(LLVMInt8TypeInContext(context), 0);
        case TypesNative.I8:
            return LLVMInt8TypeInContext(context);
        case TypesNative.NULO:
            return LLVMPointerType(LLVMInt32TypeInContext(context), 0);
        case TypesNative.I32:
            return LLVMInt32TypeInContext(context);
        case TypesNative.F32:
            return LLVMFloatTypeInContext(context);
        case TypesNative.STRUCT:
            return currentStructType;
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
        currentContext.functions["printf"] = Symbol(printfFunc, printfType, false);

        // Primeiro passo: registrar todas as classes
        foreach (Stmt n; node.body)
        {
            if (n.kind == NodeType.ClassDeclaration)
            {
                registerClass(cast(ClassDeclaration) n);
            }
        }

        // Segundo passo: gerar métodos das classes
        foreach (Stmt n; node.body)
        {
            if (n.kind == NodeType.ClassDeclaration)
            {
                genClassMethods(cast(ClassDeclaration) n);
            }
        }

        // gera a função main
        LLVMTypeRef int32Ty = getTypeFromNative(TypesNative.I32);
        LLVMTypeRef mainTy = LLVMFunctionType(int32Ty, null, 0, 0);
        LLVMValueRef main = LLVMAddFunction(mod, "main", mainTy);
        currentFunction = main;
        LLVMBasicBlockRef entry = LLVMAppendBasicBlockInContext(context, main, "entry");
        LLVMPositionBuilderAtEnd(builder, entry);

        // gera o corpo (exceto classes que já foram processadas)
        foreach (Stmt n; node.body)
        {
            if (n.kind != NodeType.ClassDeclaration)
            {
                genStmt(n);
                if (n.kind == NodeType.FunctionDeclaration)
                    LLVMPositionBuilderAtEnd(builder, entry);
            }
        }

        // retorno da main
        LLVMPositionBuilderAtEnd(builder, entry);
        LLVMBuildRet(builder, LLVMConstInt(int32Ty, 0, 0));

        return true;
    }

    void registerClass(ClassDeclaration classDecl)
    {
        string className = classDecl.id.value.get!string;
        const char* name = ("class." ~ className).toStringz();
        LLVMTypeRef structTy = LLVMStructCreateNamed(context, name);

        ClassInfo classInfo;
        classInfo.name = className;
        classInfo.structType = structTy;
        classInfo.properties = classDecl.properties;
        classInfo.methods = classDecl.methods;
        classInfo.constructor = classDecl.construct;
        classInfo.destructor = classDecl.destruct;

        // Definir campos da struct
        LLVMTypeRef[] fields;
        foreach (i, prop; classDecl.properties)
        {
            LLVMTypeRef fieldType = getType(prop.type);
            fields ~= fieldType;
            classInfo.fields[prop.name.value.get!string] = Symbol(
                null, fieldType, true, false, "", cast(int) i
            );
        }

        LLVMStructSetBody(structTy, fields.ptr, cast(uint) fields.length, 0);
        classes[className] = classInfo;
    }

    void genClassMethods(ClassDeclaration classDecl)
    {
        string className = classDecl.id.value.get!string;
        ClassInfo* classInfo = &classes[className];

        // Configurar contexto da classe
        ClassInfo* savedClass = currentContext.currentClass;
        currentContext.currentClass = classInfo;

        // Gerar métodos da classe
        foreach (method; classDecl.methods)
        {
            genClassMethod(method, className);
        }

        // Gerar construtor se existir
        if (classDecl.construct !is null)
        {
            genConstructor(classDecl.construct, className);
        }

        // Restaurar contexto
        currentContext.currentClass = savedClass;
    }

    void genConstructor(ConstructorDeclaration constructor, string className)
    {
        string methodName = className ~ "_constructor";
        ClassInfo* classInfo = &classes[className];

        // Construtor sempre retorna void e recebe 'this' como primeiro parâmetro
        LLVMTypeRef returnType = LLVMVoidTypeInContext(context);

        // Parâmetros: primeiro é sempre 'this'
        LLVMTypeRef[] paramTypes;
        paramTypes ~= LLVMPointerType(classInfo.structType, 0); // this

        // Adicionar parâmetros do construtor
        foreach (arg; constructor.args)
        {
            paramTypes ~= getType(arg.type);
        }

        LLVMTypeRef functionType = LLVMFunctionType(
            returnType,
            paramTypes.ptr,
            cast(uint) paramTypes.length,
            0
        );

        LLVMValueRef function_ = LLVMAddFunction(mod, methodName.toStringz(), functionType);

        auto curFn = currentFunction;
        currentFunction = function_;

        currentContext.functions["constructor"] = Symbol(function_, functionType, false);
        currentContext.functions[className ~ "_constructor"] = Symbol(function_, functionType, false);

        // Criar bloco de entrada
        LLVMBasicBlockRef entryBlock = LLVMAppendBasicBlockInContext(context, function_, "entry");
        LLVMPositionBuilderAtEnd(builder, entryBlock);

        // Salvar contexto
        Context savedContext = *currentContext;
        currentContext.enterScope();

        // Configurar 'this'
        LLVMValueRef thisParam = LLVMGetParam(function_, 0);
        currentContext.currentThis = thisParam;
        currentContext.currentClass = classInfo;

        // Configurar parâmetros do construtor
        for (uint i = 1; i < paramTypes.length; i++)
        {
            LLVMValueRef param = LLVMGetParam(function_, i);
            string paramName = constructor.args[i - 1].id.value.get!string;
            LLVMTypeRef paramType = getType(constructor.args[i - 1].type);
            LLVMValueRef paramAlloca = LLVMBuildAlloca(builder, paramType, paramName.toStringz());
            LLVMBuildStore(builder, param, paramAlloca);
            currentContext.variables[paramName] = Symbol(paramAlloca, paramType, true);
        }

        // Gerar corpo do construtor
        foreach (stmt; constructor.body)
        {
            genStmt(stmt);
        }

        // Construtor sempre retorna void
        LLVMBuildRetVoid(builder);

        // Restaurar contexto
        currentFunction = curFn;
        *currentContext = savedContext;
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

            return Symbol(strPtr, getType(node.type, cast(uint) str.length), false);

        case NodeType.IntLiteral:
            return Symbol(LLVMConstInt(getType(node.type), node.value.get!long, 0),
                getTypeFromNative(node.type.baseType), false);
        case NodeType.FloatLiteral:
            return Symbol(LLVMConstReal(getType(node.type), node.value.get!double),
                getTypeFromNative(node.type.baseType), false);
        case NodeType.Identifier:
            return genIdentifier(cast(Identifier) node);
        case NodeType.VariableDeclaration:
            return genVarDeclaration(cast(VariableDeclaration) node);
        case NodeType.FunctionDeclaration:
            return genFunctionDeclaration(cast(FunctionDeclaration) node);
        case NodeType.ClassDeclaration:
            // Classes já foram processadas na fase de registro
            return Symbol(LLVMConstInt(getTypeFromNative(TypesNative.I32), 0, 0),
                getTypeFromNative(TypesNative.I32), false);
        case NodeType.CallExpr:
            return genCallExpr(cast(CallExpr) node);
        case NodeType.ThisExpr:
            return genThisExpr(cast(ThisExpr) node);
        case NodeType.NewExpr:
            return genNewExpr(cast(NewExpr) node);
        case NodeType.MemberAssignment:
            return genMemberAssignment(cast(MemberAssignment) node);
        case NodeType.MemberCallExpr:
            return genMemberCallExpr(cast(MemberCallExpr) node);
        case NodeType.UnaryExpr:
            return genUnaryExpr(cast(UnaryExpr) node);
        case NodeType.ReturnStatement:
            ReturnStatement n = cast(ReturnStatement) node;
            Symbol value = this.genStmt(n.expr);

            LLVMTypeRef functionType = LLVMGlobalGetValueType(currentFunction);
            LLVMTypeRef currentFunctionReturnType = LLVMGetReturnType(functionType);

            if (LLVMGetTypeKind(currentFunctionReturnType) == LLVMTypeKind.LLVMStructTypeKind &&
                LLVMGetTypeKind(LLVMTypeOf(value.value)) == LLVMTypeKind.LLVMPointerTypeKind)
            {
                value.value = LLVMBuildLoad2(builder, currentFunctionReturnType, value.value, "loaded_return_value"
                        .toStringz());
            }

            return Symbol(LLVMBuildRet(builder, value.value), value.type, false);
        case NodeType.BinaryExpr:
            return genBinaryExpr(cast(BinaryExpr) node);
        default:
            throw new Exception(format("Node desconhecido '%s'.", to!string(node.kind)));
        }
    }

    Symbol genMemberAccess(LLVMValueRef objectPtr, string memberName, string className)
    {
        if (className !in classes)
        {
            throw new Exception(format("Classe '%s' não encontrada", className));
        }

        ClassInfo classInfo = classes[className];
        if (memberName !in classInfo.fields)
        {
            throw new Exception(format("Campo '%s' não encontrado na classe '%s'", memberName, className));
        }

        Symbol field = classInfo.fields[memberName];

        // Criar GEP para acessar o campo
        LLVMValueRef[2] indices;
        indices[0] = LLVMConstInt(LLVMInt32TypeInContext(context), 0, 0);
        indices[1] = LLVMConstInt(LLVMInt32TypeInContext(context), field.fieldIndex, 0);

        LLVMValueRef fieldPtr = LLVMBuildGEP2(
            builder,
            classInfo.structType,
            objectPtr,
            indices.ptr,
            2,
            (memberName ~ "_ptr").toStringz()
        );

        LLVMValueRef fieldValue = LLVMBuildLoad2(builder, field.type, fieldPtr, memberName.toStringz());
        return Symbol(fieldValue, field.type, true, true, className, field.fieldIndex);
    }

    Symbol genMemberAssignment(MemberAssignment node)
    {
        // obj.field = value
        Symbol objectSymbol = genStmt(node.left);
        string memberName = node.value.value.get!string;
        Symbol value = genStmt(node.value);

        if (!objectSymbol.isStruct)
        {
            throw new Exception("Tentativa de atribuir a membro de tipo não-struct");
        }

        string className = objectSymbol.structName;
        if (className !in classes)
        {
            throw new Exception(format("Classe '%s' não encontrada", className));
        }

        ClassInfo classInfo = classes[className];
        if (memberName !in classInfo.fields)
        {
            throw new Exception(format("Campo '%s' não encontrado na classe '%s'", memberName, className));
        }

        Symbol field = classInfo.fields[memberName];

        // Criar GEP para acessar o campo
        LLVMValueRef[2] indices;
        indices[0] = LLVMConstInt(LLVMInt32TypeInContext(context), 0, 0);
        indices[1] = LLVMConstInt(LLVMInt32TypeInContext(context), field.fieldIndex, 0);

        LLVMValueRef fieldPtr = LLVMBuildGEP2(
            builder,
            classInfo.structType,
            objectSymbol.value,
            indices.ptr,
            2,
            (memberName ~ "_assign_ptr").toStringz()
        );

        LLVMBuildStore(builder, value.value, fieldPtr);
        return value;
    }

    Symbol genThisExpr(ThisExpr node)
    {
        if (currentContext.currentThis is null || currentContext.currentClass is null)
        {
            throw new Exception("'this' usado fora de contexto de classe");
        }

        return Symbol(currentContext.currentThis,
            LLVMPointerType(currentContext.currentClass.structType, 0),
            true, true, currentContext.currentClass.name);
    }

    Symbol genNewExpr(NewExpr node)
    {
        string className = node.className.value.get!string;

        if (className !in classes)
        {
            throw new Exception(format("Classe '%s' não encontrada", className));
        }

        ClassInfo classInfo = classes[className];

        // Alocar memória para o objeto
        LLVMValueRef objectPtr;

        if (alloca !is null)
            objectPtr = alloca;
        else
            objectPtr = LLVMBuildAlloca(builder, classInfo.structType,
                (className ~ "_instance").toStringz());

        // Inicializar campos com valores padrão
        foreach (i, prop; classInfo.properties)
        {
            if (prop.defaultValue !is null)
            {
                Symbol defaultVal = genStmt(prop.defaultValue);

                LLVMValueRef[2] indices;
                indices[0] = LLVMConstInt(LLVMInt32TypeInContext(context), 0, 0);
                indices[1] = LLVMConstInt(LLVMInt32TypeInContext(context), i, 0);

                LLVMValueRef fieldPtr = LLVMBuildGEP2(
                    builder,
                    classInfo.structType,
                    objectPtr,
                    indices.ptr,
                    2,
                    (prop.name.value.get!string ~ "_init").toStringz()
                );

                LLVMBuildStore(builder, defaultVal.value, fieldPtr);
            }
        }

        // Chamar construtor se existir e foi solicitado
        if (classInfo.constructor !is null && node.args !is null && node.args.length > 0)
        {
        }

        string constructorName = className ~ "__";
        Symbol* constructor = currentContext.findFunction(constructorName);

        if (constructor !is null)
        {
            // Preparar argumentos: primeiro é sempre 'this'
            LLVMValueRef[] args;
            args ~= objectPtr; // 'this' pointer

            // Adicionar argumentos do construtor
            foreach (arg; node.args)
            {
                Symbol argSymbol = genStmt(arg);
                args ~= argSymbol.value;
            }

            // Chamar o construtor
            LLVMBuildCall2(
                builder,
                constructor.type,
                constructor.value,
                args.ptr,
                cast(uint) args.length,
                ""
            );
        }
        return Symbol(objectPtr, LLVMPointerType(classInfo.structType, 0), false, true, className);
    }

    Symbol genClassMethod(ClassMethodDeclaration method, string className)
    {
        string methodName = className ~ "_" ~ method.id.value.get!string;
        ClassInfo* classInfo = &classes[className];

        // Tipo de retorno
        LLVMTypeRef returnType = getType(method.type);
        bool isCons;

        // construtor
        if (method.id.value.get!string == "_")
        {
            returnType = LLVMVoidTypeInContext(context);
            isCons = true;
        }

        // Parâmetros: primeiro é sempre 'this'
        LLVMTypeRef[] paramTypes;

        paramTypes ~= LLVMPointerType(classInfo.structType, 0); // this

        foreach (arg; method.args)
        {
            paramTypes ~= getType(arg.type);
        }

        LLVMTypeRef functionType = LLVMFunctionType(
            returnType,
            paramTypes.ptr,
            cast(uint) paramTypes.length,
            0
        );

        LLVMValueRef function_ = LLVMAddFunction(mod, methodName.toStringz(), functionType);

        auto curFn = currentFunction;
        currentFunction = function_;

        currentContext.functions[method.id.value.get!string] = Symbol(function_, functionType, false);
        currentContext.functions[methodName] = Symbol(function_, functionType, false);

        // Criar bloco de entrada
        LLVMBasicBlockRef entryBlock = LLVMAppendBasicBlockInContext(context, function_, "entry");
        LLVMPositionBuilderAtEnd(builder, entryBlock);

        // Salvar contexto
        Context savedContext = *currentContext;
        currentContext.enterScope();

        // Configurar 'this'
        LLVMValueRef thisParam = LLVMGetParam(function_, 0);
        LLVMSetValueName(thisParam, "isto".toStringz());

        currentContext.variables["isto"] = Symbol(thisParam, paramTypes[0], true, true, className, 0);

        currentContext.currentThis = thisParam;
        currentContext.currentClass = classInfo;

        // Configurar parâmetros do método
        for (uint i = 1; i < paramTypes.length; i++)
        {
            LLVMValueRef param = LLVMGetParam(function_, i);
            string paramName = method.args[i - 1].id.value.get!string;
            LLVMTypeRef paramType = getType(method.args[i - 1].type);
            LLVMValueRef paramAlloca = LLVMBuildAlloca(builder, paramType, paramName.toStringz());
            LLVMBuildStore(builder, param, paramAlloca);
            currentContext.variables[paramName] = Symbol(paramAlloca, paramType, true);
        }

        // Gerar corpo do método
        foreach (stmt; method.body)
        {
            genStmt(stmt);
        }

        // Restaurar contexto
        currentFunction = curFn;
        *currentContext = savedContext;

        if (isCons)
            LLVMBuildRetVoid(builder);

        return Symbol(function_, functionType, false);
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
            if (node.type.baseType == TypesNative.I32 || node.type.baseType == TypesNative.I8)
            {
                LLVMValueRef zero = LLVMConstInt(operand.type, 0, 0);
                result = LLVMBuildICmp(builder, LLVMIntPredicate.LLVMIntEQ, operand.value, zero, "not");
                result = LLVMBuildZExt(builder, result, operand.type, "not_ext");
            }
            else if (node.type.baseType == TypesNative.F32)
            {
                LLVMValueRef zero = LLVMConstReal(operand.type, 0.0);
                result = LLVMBuildFCmp(builder, LLVMRealPredicate.LLVMRealOEQ, operand.value, zero, "fnot");
                result = LLVMBuildUIToFP(builder, result, operand.type, "fnot_conv");
            }
            else
            {
                throw new Exception(format("Operador '!' não suportado para tipo '%s'", to!string(
                        node.type.baseType)));
            }
            return Symbol(result, operand.type, false);

        case "&":
            // Address-of operator
            if (!operand.isVariable)
            {
                throw new Exception("Operador '&' só pode ser aplicado a variáveis (lvalues)");
            }
            LLVMTypeRef ptrType = LLVMPointerType(operand.type, 0);
            return Symbol(operand.value, ptrType, false);

        case "*":
            // Dereference operator
            if (node.operand.kind != NodeType.Identifier && node.operand.kind != NodeType
                .MemberCallExpr)
            {
                throw new Exception("Operador '*' requer um identificador de ponteiro");
            }

            string varName = node.operand.kind == NodeType.Identifier
                ? node.operand.value.get!string
                : (cast(MemberCallExpr) node.operand).object.value.get!string;

            Symbol* ptrVar = currentContext.findVariable(varName);
            if (ptrVar is null)
            {
                throw new Exception(format("Variável '%s' não encontrada", varName));
            }

            LLVMTypeRef varTy = ptrVar.type;
            auto kind = LLVMGetTypeKind(varTy);
            if (kind != LLVMTypeKind.LLVMPointerTypeKind)
            {
                throw new Exception("Operador '*' aplicado a um valor que não é ponteiro");
            }

            LLVMTypeRef pointedTy = LLVMGetElementType(varTy);

            if (LLVMGetTypeKind(pointedTy) == LLVMTypeKind.LLVMPointerTypeKind)
            {
                LLVMValueRef innerPtr = LLVMBuildLoad2(builder, pointedTy, ptrVar.value, "ptr_load");
                LLVMTypeRef elemTy = LLVMGetElementType(pointedTy);
                LLVMValueRef val = LLVMBuildLoad2(builder, elemTy, innerPtr, "deref");
                return Symbol(val, elemTy, false);
            }
            else
            {
                LLVMValueRef val = LLVMBuildLoad2(builder, pointedTy, ptrVar.value, "deref");
                return Symbol(val, pointedTy, false);
            }

        default:
            throw new Exception(format("Operador unário desconhecido '%s'", node.op));
        }
    }

    Symbol genCallExpr(CallExpr node)
    {
        string functionName = node.calle.value.get!string;
        Symbol* function_ = currentContext.findFunction(functionName);

        if (function_ is null)
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

        return Symbol(call, LLVMGetReturnType(function_.type), false);
    }

    Symbol genFunctionDeclaration(FunctionDeclaration node)
    {
        LLVMTypeRef returnType = getType(node.type);
        LLVMTypeRef[] paramTypes = node.args.map!(x => getType(x.type)).array;

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

        auto curFn = currentFunction;
        currentFunction = function_;

        currentContext.functions[node.id.value.get!string] = Symbol(function_, functionType, false);

        LLVMBasicBlockRef entryBlock = LLVMAppendBasicBlockInContext(
            context,
            function_,
            "entry"
        );

        LLVMPositionBuilderAtEnd(builder, entryBlock);

        // Salvar contexto atual
        Context savedContext = *currentContext;
        currentContext.enterScope();

        for (uint i = 0; i < node.args.length; i++)
        {
            LLVMValueRef param = LLVMGetParam(function_, i);
            string paramName = node.args[i].id.value.get!string;
            LLVMTypeRef paramType = getType(node.args[i].type);
            LLVMValueRef paramAlloca = LLVMBuildAlloca(builder, paramType, paramName.toStringz());
            LLVMBuildStore(builder, param, paramAlloca);
            currentContext.variables[paramName] = Symbol(paramAlloca, paramType, true);
        }

        foreach (Stmt stmt; node.body)
        {
            genStmt(stmt);
        }

        // Restaurar contexto
        currentFunction = curFn;
        *currentContext = savedContext;
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
        return Symbol(result, getType(node.type), false);
    }

    // Implementação corrigida do genMemberCallExpr
    Symbol genMemberCallExpr(MemberCallExpr node)
    {
        // Avaliar o objeto (lado esquerdo do ponto)
        Symbol objectSymbol = genStmt(node.object);
        string memberName = node.member.value.get!string;

        // Verificar se é um acesso a propriedade (não é chamada de método)
        if (!node.isMethodCall)
        {
            // Acesso a propriedade/campo
            if (objectSymbol.isStruct)
            {
                return genMemberAccess(objectSymbol.value, memberName, objectSymbol.structName);
            }
            else
            {
                throw new Exception(format("Tentativa de acessar propriedade '%s' em tipo não-struct", memberName));
            }
        }
        else
        {
            // Chamada de método
            if (objectSymbol.isStruct)
            {
                // Chamada de método em classe/struct
                string className = objectSymbol.structName;
                if (className !in classes)
                {
                    throw new Exception(format("Classe '%s' não encontrada", className));
                }

                // Nome do método mangled (className_methodName)
                string mangledMethodName = className ~ "_" ~ memberName;

                // Verificar se o método existe
                Symbol* method = currentContext.findFunction(mangledMethodName);
                if (method is null)
                {
                    throw new Exception(format("Método '%s' não encontrado na classe '%s'", memberName, className));
                }

                // Preparar argumentos: primeiro é sempre 'this'
                LLVMValueRef[] args;
                args ~= objectSymbol.value; // 'this' pointer

                // Adicionar outros argumentos
                if (node.args !is null)
                {
                    foreach (arg; node.args)
                    {
                        Symbol argSymbol = genStmt(arg);
                        args ~= argSymbol.value;
                    }
                }

                // Fazer a chamada
                LLVMValueRef call = LLVMBuildCall2(
                    builder,
                    method.type,
                    method.value,
                    args.ptr,
                    cast(uint) args.length,
                    (memberName ~ "_call").toStringz()
                );

                // Determinar o tipo de retorno correto
                LLVMTypeRef returnType = LLVMGetReturnType(method.type);

                return Symbol(call, returnType, false);
            }
            else
            {
                throw new Exception(format("Chamada de método '%s' em tipo primitivo não implementada", memberName));
            }
        }
    }

    // Correção no genVarDeclaration para lidar com FTypeInfo corretamente
    Symbol genVarDeclaration(VariableDeclaration node)
    {
        FTypeInfo type = node.value.get!Stmt.type;

        // Para strings
        if (type.baseType == TypesNative.I8P)
        {
            Symbol stringSymbol = genStmt(node.value.get!Stmt);
            currentContext.variables[node.id.value.get!string] = stringSymbol;
            return stringSymbol;
        }

        LLVMValueRef var = LLVMBuildAlloca(builder, getType(type),
            node.id.value.get!string.toStringz());

        LLVMValueRef current = alloca;
        alloca = var;
        Symbol valueSymbol = this.genStmt(node.value.get!Stmt);
        alloca = current;

        if (!valueSymbol.isStruct)
            LLVMBuildStore(builder, valueSymbol.value, var);

        Symbol symbol = Symbol(var, getType(type), true);

        // Se for struct, configurar informações adicionais
        if (type.isStruct || type.baseType == TypesNative.STRUCT)
        {
            symbol.isStruct = true;
            symbol.structName = type.className;
        }

        currentContext.variables[node.id.value.get!string] = symbol;
        return symbol;
    }

    // Correção no genIdentifier para propagar informações de struct
    Symbol genIdentifier(Identifier node)
    {
        string varName = node.value.get!string;

        // Tentar encontrar variável no contexto atual
        Symbol* variable = currentContext.findVariable(varName);
        if (variable !is null)
        {
            if (!variable.isVariable)
            {
                return *variable;
            }

            // Preservar informações de struct ao carregar
            if (variable.isStruct)
            {
                return Symbol(variable.value, variable.type, true, true, variable.structName, variable
                        .fieldIndex);
            }

            auto loadedValue = LLVMBuildLoad2(builder, variable.type, variable.value, "");
            return Symbol(loadedValue, variable.type, true);
        }

        // Se não encontrou, pode ser um campo da classe atual
        if (currentContext.currentClass !is null)
        {
            if (varName in currentContext.currentClass.fields)
            {
                return genMemberAccess(currentContext.currentThis, varName, currentContext
                        .currentClass.name);
            }
        }

        throw new Exception(format("Variável '%s' não encontrada.", varName));
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

        // Inicializar contexto global
        this.currentContext = &this.globalContext;

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
            return true;
        }
    }
}
