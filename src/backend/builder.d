module backend.builder;

import core.stdc.stdio;
import std.format : format;
import std.string : toStringz, fromStringz;
import std.conv : to;
import std.stdio : write, writefln, writeln, FILE, File;
import std.algorithm;
import std.array;
import frontend.parser.ftype_info;
import frontend.parser.ast;
import frontend.values;
import middle.stdlib.std_lib_module_builder : StdLibFunction;
import backend.codegen.llvm;
import middle.semantic;
import middle.type_checker;
import middle.stdlib.primitives;
import target;

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
    LLVMTargetDataRef targetData;
    LLVMBasicBlockRef currentBreakBlock = null; // Bloco para break
    LLVMBasicBlockRef currentContinueBlock = null; // Bloco para continue

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
        case TypesNative.I64:
            return LLVMInt64TypeInContext(context);
        case TypesNative.F32:
            return LLVMFloatTypeInContext(context);
        case TypesNative.F64:
            return LLVMDoubleTypeInContext(context);
        case TypesNative.I1:
            return LLVMInt1TypeInContext(context);
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

        auto doubleType = LLVMDoubleTypeInContext(context);
        auto sqrtType = LLVMFunctionType(doubleType, &doubleType, 1, 0);
        auto sqrtFunc = LLVMAddFunction(mod, "llvm.sqrt.f64", sqrtType);
        currentContext.functions["raiz"] = Symbol(sqrtFunc, sqrtType, false);

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
        // LLVMPositionBuilderAtEnd(builder, entry);
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
                null, getType(prop.type), true, prop.type.isStruct, "", cast(int) i
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
        string methodName = className ~ "__";
        ClassInfo* classInfo = &classes[className];

        // Construtor sempre retorna void e recebe 'this' como primeiro parâmetro
        LLVMTypeRef returnType = LLVMVoidTypeInContext(context);

        // Parâmetros: primeiro é sempre 'this'
        LLVMTypeRef[] paramTypes;
        paramTypes ~= LLVMPointerType(classInfo.structType, 0); // this

        // Adicionar parâmetros do construtor
        foreach (arg; constructor.args)
        {
            LLVMTypeRef argType = getType(arg.type);
            if (arg.type.isStruct || arg.type.baseType == TypesNative.STRUCT)
            {
                argType = LLVMPointerType(argType, 0);
            }
            paramTypes ~= argType;
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
        case NodeType.BoolLiteral:
            return Symbol(
                LLVMConstInt(getType(node.type), node.value.get!bool ? 1 : 0, 0),
                getTypeFromNative(node.type.baseType),
                false
            );

        case NodeType.Identifier:
            return genIdentifier(cast(Identifier) node);
        case NodeType.VariableDeclaration:
            return genVarDeclaration(cast(VariableDeclaration) node);
        case NodeType.FunctionDeclaration:
            return genFunctionDeclaration(cast(FunctionDeclaration) node);
        case NodeType.ClassDeclaration:
            // Classes já foram processadas na fase de registro
            return Symbol(LLVMConstInt(getTypeFromNative(TypesNative.I64), 0, 0),
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
        case NodeType.IfStatement:
            return genIfStatement(cast(IfStatement) node);
        case NodeType.ForStatement:
            return genForStatement(cast(ForStatement) node);
        case NodeType.AssignmentDeclaration:
            return genAssignmentDeclaration(cast(AssignmentDeclaration) node);
        default:
            throw new Exception(format("Node desconhecido '%s'.", to!string(node.kind)));
        }
    }

    Symbol genAssignmentDeclaration(AssignmentDeclaration node)
    {
        string varName = node.id.value.get!string;

        // Procurar a variável existente
        Symbol* variable = currentContext.findVariable(varName);
        if (variable is null)
        {
            throw new Exception(format("Variável '%s' não foi declarada antes da atribuição", varName));
        }

        // Verificar se é uma variável (lvalue) e não uma constante
        if (!variable.isVariable)
        {
            throw new Exception(format("Não é possível atribuir valor a '%s' - não é uma variável", varName));
        }

        // Gerar o valor a ser atribuído
        Symbol valueSymbol = genStmt(node.value.get!Stmt);

        // Converter o tipo se necessário
        LLVMValueRef convertedValue = convertIfNeeded(
            valueSymbol.value,
            LLVMTypeOf(valueSymbol.value),
            variable.type
        );

        // Realizar a atribuição
        LLVMBuildStore(builder, convertedValue, variable.value);

        // Atualizar informações da variável se for struct
        if (valueSymbol.isStruct)
        {
            variable.isStruct = true;
            variable.structName = valueSymbol.structName;
        }

        // Retornar o valor atribuído
        return Symbol(convertedValue, variable.type, false, variable.isStruct, variable.structName);
    }

    // Symbol genForStatement(ForStatement node)
    // {
    //     LLVMBasicBlockRef initBlock = LLVMAppendBasicBlock(currentFunction, "for_init");
    // LLVMBasicBlockRef condBlock = LLVMAppendBasicBlock(currentFunction, "for_cond");
    // LLVMBasicBlockRef bodyBlock = LLVMAppendBasicBlock(currentFunction, "for_body");
    // LLVMBasicBlockRef incrBlock = LLVMAppendBasicBlock(currentFunction, "for_incr");
    // LLVMBasicBlockRef afterBlock = LLVMAppendBasicBlock(currentFunction, "for_after");
    // }

    Symbol genForStatement(ForStatement node)
    {
        // Criar blocos básicos para o loop
        LLVMBasicBlockRef initBlock = LLVMAppendBasicBlock(currentFunction, "for_init");
        LLVMBasicBlockRef condBlock = LLVMAppendBasicBlock(currentFunction, "for_cond");
        LLVMBasicBlockRef bodyBlock = LLVMAppendBasicBlock(currentFunction, "for_body");
        LLVMBasicBlockRef incrBlock = LLVMAppendBasicBlock(currentFunction, "for_incr");
        LLVMBasicBlockRef afterBlock = LLVMAppendBasicBlock(currentFunction, "for_after");

        // Salvar blocos atuais para break/continue
        LLVMBasicBlockRef savedBreakBlock = currentBreakBlock;
        LLVMBasicBlockRef savedContinueBlock = currentContinueBlock;
        currentBreakBlock = afterBlock;
        currentContinueBlock = incrBlock;

        // Branch para o bloco de inicialização
        LLVMBuildBr(builder, initBlock);

        // Bloco de inicialização
        LLVMPositionBuilderAtEnd(builder, initBlock);

        // Salvar contexto atual e criar novo escopo
        Context savedContext = *currentContext;
        currentContext.enterScope();

        // Executar inicialização se existir
        if (node._init !is null)
        {
            genStmt(node._init);
        }

        // Branch para condição
        LLVMBuildBr(builder, condBlock);

        // Bloco de condição
        LLVMPositionBuilderAtEnd(builder, condBlock);

        LLVMValueRef condValue;
        if (node.cond !is null)
        {
            Symbol condition = genStmt(node.cond);
            condValue = condition.value;

            // Se a condição não for booleana, converter para booleana
            if (LLVMGetTypeKind(LLVMTypeOf(condValue)) != LLVMTypeKind.LLVMIntegerTypeKind ||
                LLVMGetIntTypeWidth(LLVMTypeOf(condValue)) != 1)
            {
                LLVMValueRef zero;
                if (isFloatingPointType(LLVMTypeOf(condValue)))
                {
                    zero = LLVMConstReal(LLVMTypeOf(condValue), 0.0);
                    condValue = LLVMBuildFCmp(builder, LLVMRealPredicate.LLVMRealONE,
                        condValue, zero, "for_cond_bool");
                }
                else
                {
                    zero = LLVMConstInt(LLVMTypeOf(condValue), 0, 0);
                    condValue = LLVMBuildICmp(builder, LLVMIntPredicate.LLVMIntNE,
                        condValue, zero, "for_cond_bool");
                }
            }
        }
        else
        {
            // Se não há condição, loop infinito (true)
            condValue = LLVMConstInt(LLVMInt1TypeInContext(context), 1, 0);
        }

        // Branch condicional
        LLVMBuildCondBr(builder, condValue, bodyBlock, afterBlock);

        // Bloco do corpo
        LLVMPositionBuilderAtEnd(builder, bodyBlock);

        // Gerar corpo do loop
        foreach (stmt; node.body)
        {
            genStmt(stmt);

            // Verificar se houve return ou break
            LLVMBasicBlockRef currentBlock = LLVMGetInsertBlock(builder);
            if (currentBlock !is null)
            {
                LLVMValueRef lastInstr = LLVMGetLastInstruction(currentBlock);
                if (lastInstr !is null)
                {
                    LLVMOpcode opcode = LLVMGetInstructionOpcode(lastInstr);
                    if (opcode == LLVMOpcode.LLVMRet || opcode == LLVMOpcode.LLVMBr)
                    {
                        // Se já houve branch/return, não adicionar mais instruções
                        break;
                    }
                }
            }
        }

        // Se ainda estamos no bloco do corpo (não houve break/return), branch para incremento
        LLVMBasicBlockRef bodyEndBlock = LLVMGetInsertBlock(builder);
        if (bodyEndBlock !is null)
        {
            LLVMValueRef lastInstr = LLVMGetLastInstruction(bodyEndBlock);
            if (lastInstr is null ||
                (LLVMGetInstructionOpcode(lastInstr) != LLVMOpcode.LLVMBr &&
                    LLVMGetInstructionOpcode(lastInstr) != LLVMOpcode.LLVMRet))
            {
                LLVMBuildBr(builder, incrBlock);
            }
        }

        // Bloco de incremento
        LLVMPositionBuilderAtEnd(builder, incrBlock);

        // Executar expressão de incremento se existir
        if (node.expr !is null)
        {
            genStmt(node.expr);
        }

        // Branch de volta para condição
        LLVMBuildBr(builder, condBlock);

        // Bloco após o loop
        LLVMPositionBuilderAtEnd(builder, afterBlock);

        // Restaurar contexto
        *currentContext = savedContext;

        // Restaurar blocos break/continue
        currentBreakBlock = savedBreakBlock;
        currentContinueBlock = savedContinueBlock;

        return Symbol(null, LLVMVoidTypeInContext(context), false);
    }

    Symbol genIfStatement(IfStatement node)
    {
        Symbol condition = genStmt(node.condition);
        LLVMValueRef condValue = condition.value;
        LLVMBasicBlockRef thenBlock = LLVMAppendBasicBlock(currentFunction, "then");
        LLVMBasicBlockRef elseBlock = LLVMAppendBasicBlock(currentFunction, "else");
        LLVMBasicBlockRef mergeBlock = LLVMAppendBasicBlock(currentFunction, "ifcont");

        LLVMBuildCondBr(builder, condValue, thenBlock, elseBlock);

        // Bloco THEN
        LLVMPositionBuilderAtEnd(builder, thenBlock);
        Symbol thenValue;
        bool thenHasReturn = false;
        foreach (stmt; node.primary)
        {
            thenValue = genStmt(stmt);
            // Verificar se a última instrução foi um return
            if (LLVMGetInstructionOpcode(
                    LLVMGetLastInstruction(
                    LLVMGetInsertBlock(builder))) == LLVMOpcode.LLVMRet)
            {
                thenHasReturn = true;
                break; // Não processar mais statements após return
            }
        }

        // Só fazer branch se não houve return
        if (!thenHasReturn)
        {
            LLVMBuildBr(builder, mergeBlock);
        }
        LLVMBasicBlockRef thenEndBlock = LLVMGetInsertBlock(builder);

        // Bloco ELSE
        LLVMPositionBuilderAtEnd(builder, elseBlock);
        Symbol elseValue;
        if (node.secondary.get() !is null)
        {
            foreach (stmt; node.secondary)
            {
                elseValue = genStmt(stmt);
            }
        }
        else
        {
            // Se não há else, criar um valor padrão se necessário
            if (node.type.baseType != TypesNative.NULO)
            {
                // Criar valor padrão baseado no tipo
                if (thenValue.type !is null)
                {
                    elseValue = Symbol(LLVMGetUndef(thenValue.type), thenValue.type, false);
                }
            }
        }
        LLVMBuildBr(builder, mergeBlock);
        // Salvar o bloco atual após processamento
        LLVMBasicBlockRef elseEndBlock = LLVMGetInsertBlock(builder);

        LLVMPositionBuilderAtEnd(builder, mergeBlock);

        if (node.type.baseType != TypesNative.NULO && thenValue.value !is null)
        {
            LLVMValueRef phi = LLVMBuildPhi(builder, thenValue.type, "iftmp");

            // Arrays para valores e blocos
            LLVMValueRef[2] values = [thenValue.value, elseValue.value];
            LLVMBasicBlockRef[2] blocks = [thenEndBlock, elseEndBlock];

            LLVMAddIncoming(phi, values.ptr, blocks.ptr, 2);

            return Symbol(phi, thenValue.type, false);
        }

        return Symbol(null, LLVMVoidTypeInContext(context), false);
    }

    Symbol genMemberAssignment(MemberAssignment node)
    {
        // obj.field = value
        Symbol objectSymbol = genStmt(node.left);
        string memberName = node.member.value.get!string;
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

        LLVMValueRef objectPtr = LLVMBuildAlloca(builder, classInfo.structType,
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
            LLVMTypeRef argType = getType(arg.type);

            if (arg.type.isStruct || arg.type.baseType == TypesNative.STRUCT)
                argType = LLVMPointerType(argType, 0);

            paramTypes ~= argType;
        }

        LLVMTypeRef functionType = LLVMFunctionType(
            returnType,
            paramTypes.ptr,
            cast(uint) paramTypes.length,
            0
        );

        const char* methodNameCStr = methodName.toStringz();
        LLVMValueRef function_ = LLVMAddFunction(mod, methodNameCStr, functionType);

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
            if (node.type.baseType == TypesNative.I64 || node.type.baseType == TypesNative.I8)
            {
                result = LLVMBuildNeg(builder, operand.value, "neg");
            }
            else if (node.type.baseType == TypesNative.F32 || node.type.baseType == TypesNative.F64)
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
            if (!operand.isVariable)
            {
                throw new Exception("Operador '&' só pode ser aplicado a variáveis (lvalues)");
            }
            LLVMTypeRef ptrType = LLVMPointerType(operand.type, 0);
            return Symbol(operand.value, ptrType, false);

        case "*":
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

        case "++":
            return genIncrementDecrement(node, true, node.postFix);

        case "--":
            return genIncrementDecrement(node, false, node.postFix);

        default:
            throw new Exception(format("Operador unário desconhecido '%s'", node.op));
        }
    }

    Symbol genIncrementDecrement(UnaryExpr node, bool isIncrement, bool isPostfix)
    {
        // Verificar se o operando é uma variável (lvalue)
        if (node.operand.kind != NodeType.Identifier)
        {
            throw new Exception(format("Operador '%s' só pode ser aplicado a variáveis", node.op));
        }

        string varName = node.operand.value.get!string;
        Symbol* variable = currentContext.findVariable(varName);

        if (variable is null)
        {
            throw new Exception(format("Variável '%s' não encontrada", varName));
        }

        if (!variable.isVariable)
        {
            throw new Exception(format("Operador '%s' não pode ser aplicado a constante", node.op));
        }

        LLVMValueRef currentValue = LLVMBuildLoad2(builder, variable.type, variable.value, "current");
        LLVMValueRef newValue;

        LLVMValueRef one;
        if (isFloatingPointType(variable.type))
        {
            one = LLVMConstReal(variable.type, 1.0);
            if (isIncrement)
            {
                newValue = LLVMBuildFAdd(builder, currentValue, one, "inc_f");
            }
            else
            {
                newValue = LLVMBuildFSub(builder, currentValue, one, "dec_f");
            }
        }
        else if (isIntegerType(variable.type))
        {
            one = LLVMConstInt(variable.type, 1, 0);
            if (isIncrement)
            {
                newValue = LLVMBuildAdd(builder, currentValue, one, "inc_i");
            }
            else
            {
                newValue = LLVMBuildSub(builder, currentValue, one, "dec_i");
            }
        }
        else
        {
            throw new Exception(format("Operador '%s' não suportado para este tipo", node.op));
        }

        LLVMBuildStore(builder, newValue, variable.value);

        if (isPostfix)
            return Symbol(currentValue, variable.type, false);
        else
            return Symbol(newValue, variable.type, false);
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
            auto funcType = function_.type;
            auto paramCount = LLVMCountParamTypes(funcType);
            LLVMTypeRef[] expectedTypes = new LLVMTypeRef[paramCount];
            LLVMGetParamTypes(funcType, expectedTypes.ptr);

            foreach (i, arg; node.args)
            {
                Symbol argSymbol = genStmt(arg);
                LLVMValueRef argValue = argSymbol.value;

                if (i < paramCount)
                {
                    auto expectedType = expectedTypes[i];
                    auto actualType = LLVMTypeOf(argValue);

                    if (actualType != expectedType)
                        argValue = convertIfNeeded(argValue, actualType, expectedType);
                }

                args ~= argValue;
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

    bool isFloatingPointType(LLVMTypeRef type)
    {
        auto kind = LLVMGetTypeKind(type);
        return kind == LLVMTypeKind.LLVMFloatTypeKind ||
            kind == LLVMTypeKind.LLVMDoubleTypeKind;
    }

    bool isIntegerType(LLVMTypeRef type)
    {
        return LLVMGetTypeKind(type) == LLVMTypeKind.LLVMIntegerTypeKind;
    }

    LLVMValueRef convertIfNeeded(LLVMValueRef value, LLVMTypeRef fromType, LLVMTypeRef toType)
    {
        if (LLVMTypeOf(value) == toType)
            return value; // Não precisa converter

        if (LLVMGetTypeKind(toType) == LLVMTypeKind.LLVMIntegerTypeKind &&
            LLVMGetIntTypeWidth(toType) == 1) // Se estamos tentando converter para i1, é provavelmente uma comparação
            // Retorne o valor original e deixe a comparação lidar com isso
            return value;

        bool fromFloat = isFloatingPointType(fromType);
        bool toFloat = isFloatingPointType(toType);

        if (fromFloat && !toFloat)
        {
            // Float para inteiro
            return LLVMBuildFPToSI(builder, value, toType, "f2i_conv");
        }
        else if (!fromFloat && toFloat)
        {
            // Inteiro para float
            return LLVMBuildSIToFP(builder, value, toType, "i2f_conv");
        }
        else if (fromFloat && toFloat)
        {
            // Float para float (mudança de precisão)
            auto fromSize = LLVMSizeOfTypeInBits(targetData, fromType);
            auto toSize = LLVMSizeOfTypeInBits(targetData, toType);

            if (fromSize < toSize)
            {
                return LLVMBuildFPExt(builder, value, toType, "f_ext");
            }
            else if (fromSize > toSize)
            {
                return LLVMBuildFPTrunc(builder, value, toType, "f_trunc");
            }
        }
        else
        {
            // Inteiro para inteiro (mudança de tamanho)
            auto fromSize = LLVMSizeOfTypeInBits(targetData, fromType);
            auto toSize = LLVMSizeOfTypeInBits(targetData, toType);

            if (fromSize < toSize)
            {
                return LLVMBuildSExt(builder, value, toType, "i_ext");
            }
            else if (fromSize > toSize)
            {
                return LLVMBuildTrunc(builder, value, toType, "i_trunc");
            }
        }

        return value;
    }

    LLVMValueRef genIntegerOperation(string op, LLVMValueRef left, LLVMValueRef right)
    {
        switch (op)
        {
        case "+":
            return LLVMBuildAdd(builder, left, right, "add_i");
        case "-":
            return LLVMBuildSub(builder, left, right, "sub_i");
        case "*":
            return LLVMBuildMul(builder, left, right, "mul_i");
        case "/":
            return LLVMBuildSDiv(builder, left, right, "div_i");
        case "%":
            return LLVMBuildSRem(builder, left, right, "mod_i");
        default:
            throw new Exception(format("Operador inteiro desconhecido '%s'.", op));
        }
    }

    LLVMValueRef genFloatOperation(string op, LLVMValueRef left, LLVMValueRef right)
    {
        switch (op)
        {
        case "+":
            return LLVMBuildFAdd(builder, left, right, "add_f");
        case "-":
            return LLVMBuildFSub(builder, left, right, "sub_f");
        case "*":
            return LLVMBuildFMul(builder, left, right, "mul_f");
        case "/":
            return LLVMBuildFDiv(builder, left, right, "div_f");
        case "%":
            return LLVMBuildFRem(builder, left, right, "mod_f");
        case "==":
            return LLVMBuildFCmp(builder, LLVMRealPredicate.LLVMRealOEQ, left, right, "oeq_f");
        case "!=":
            return LLVMBuildFCmp(builder, LLVMRealPredicate.LLVMRealONE, left, right, "one_f");
        case ">=":
            return LLVMBuildFCmp(builder, LLVMRealPredicate.LLVMRealOGE, left, right, "oge_f");
        case "<=":
            return LLVMBuildFCmp(builder, LLVMRealPredicate.LLVMRealOLE, left, right, "ole_f");
        case ">":
            return LLVMBuildFCmp(builder, LLVMRealPredicate.LLVMRealOGT, left, right, "ogt_f");
        case "<":
            return LLVMBuildFCmp(builder, LLVMRealPredicate.LLVMRealOLT, left, right, "olt_f");
        default:
            throw new Exception(format("Operador flutuante desconhecido '%s'.", op));
        }
    }

    LLVMValueRef genBoolOperation(string op, LLVMValueRef left, LLVMValueRef right)
    {
        switch (op)
        {
        case "==":
            return LLVMBuildICmp(builder, LLVMIntPredicate.LLVMIntEQ, left, right, "eq");
        case "!=":
            return LLVMBuildICmp(builder, LLVMIntPredicate.LLVMIntNE, left, right, "ne");
        case ">=":
            return LLVMBuildICmp(builder, LLVMIntPredicate.LLVMIntSGE, left, right, "gte");
        case "<=":
            return LLVMBuildICmp(builder, LLVMIntPredicate.LLVMIntSLE, left, right, "lte");
        case ">":
            return LLVMBuildICmp(builder, LLVMIntPredicate.LLVMIntSGT, left, right, "gt");
        case "<":
            return LLVMBuildICmp(builder, LLVMIntPredicate.LLVMIntSLT, left, right, "lt");
        case "&&":
            return LLVMBuildAnd(builder, left, right, "and");
        case "||":
            return LLVMBuildOr(builder, left, right, "or");
        default:
            throw new Exception(format("Operador booleano desconhecido '%s'.", op));
        }
    }

    LLVMTypeRef getCommonType(LLVMTypeRef leftType, LLVMTypeRef rightType)
    {
        if (leftType == rightType)
            return leftType;

        bool leftIsFloat = isFloatingPointType(leftType);
        bool rightIsFloat = isFloatingPointType(rightType);
        bool leftIsInt = isIntegerType(leftType);
        bool rightIsInt = isIntegerType(rightType);

        // Se um é float e outro é int, promove para float
        if (leftIsFloat && rightIsInt)
            return leftType;
        if (rightIsFloat && leftIsInt)
            return rightType;

        // Se ambos são floats, pega o de maior precisão
        if (leftIsFloat && rightIsFloat)
        {
            auto leftBits = LLVMSizeOfTypeInBits(targetData, leftType);
            auto rightBits = LLVMSizeOfTypeInBits(targetData, rightType);
            return leftBits >= rightBits ? leftType : rightType;
        }

        // Se ambos são inteiros, pega o de maior largura
        if (leftIsInt && rightIsInt)
        {
            auto leftBits = LLVMGetIntTypeWidth(leftType);
            auto rightBits = LLVMGetIntTypeWidth(rightType);

            // Tratamento especial para i1 (bool) - sempre promove para o outro tipo se não for i1
            if (leftBits == 1 && rightBits > 1)
                return rightType;
            if (rightBits == 1 && leftBits > 1)
                return leftType;

            return leftBits >= rightBits ? leftType : rightType;
        }

        // Para tipos pointer, usar o tipo comum mais geral
        auto leftKind = LLVMGetTypeKind(leftType);
        auto rightKind = LLVMGetTypeKind(rightType);

        if (leftKind == LLVMTypeKind.LLVMPointerTypeKind && rightKind == LLVMTypeKind
            .LLVMPointerTypeKind)
        {
            // Para ponteiros, usar i8* como tipo comum se forem ponteiros diferentes
            return LLVMPointerType(LLVMInt8TypeInContext(context), 0);
        }

        // Caso padrão: tentar promover para i32 se possível
        if ((leftIsInt || leftIsFloat) && (rightIsInt || rightIsFloat))
        {
            return LLVMInt32TypeInContext(context);
        }

        // Se nenhuma das regras se aplica, retorna o tipo da esquerda
        return leftType;
    }

    Symbol genBinaryExpr(BinaryExpr node)
    {
        auto left = this.genStmt(node.left);
        auto right = this.genStmt(node.right);
        auto resultType = getType(node.type);
        auto leftType = LLVMTypeOf(left.value);
        auto rightType = LLVMTypeOf(right.value);
        auto commonType = getCommonType(leftType, rightType);
        auto leftConverted = convertIfNeeded(left.value, leftType, commonType);
        auto rightConverted = convertIfNeeded(right.value, rightType, commonType);

        LLVMValueRef result;

        if (isFloatingPointType(commonType))
            result = genFloatOperation(node.op, leftConverted, rightConverted);
        else if (node.type.baseType == TypesNative.I1)
            result = genBoolOperation(node.op, leftConverted, rightConverted);
        else if (isIntegerType(commonType))
            result = genIntegerOperation(node.op, leftConverted, rightConverted);

        // Se o tipo do resultado for diferente do tipo comum, converte o resultado
        if (!LLVMTypeEquals(resultType, commonType))
            result = convertIfNeeded(result, commonType, resultType);

        return Symbol(result, resultType, false);
    }

    Symbol genMemberCallExpr(MemberCallExpr node)
    {
        // Avaliar o objeto (lado esquerdo do ponto)
        Symbol objectSymbol = genStmt(node.object);
        string memberName = node.member.value.get!string;

        // Verificar se é um acesso a propriedade (não é chamada de método)
        if (!node.isMethodCall)
        {
            // Acesso a propriedade/campo
            if (!objectSymbol.isStruct)
            {
                throw new Exception(format("Tentativa de acessar propriedade '%s' em tipo não-struct", memberName));
            }

            return genMemberAccess(objectSymbol.value, memberName, objectSymbol.structName);
        }
        else
        {
            // Chamada de método
            if (objectSymbol.isStruct)
            {
                return genClassMethodCall(objectSymbol, memberName, node.args);
            }
            else
            {
                return genPrimitiveMethodCall(objectSymbol, memberName, node.args);
            }
        }
    }

    Symbol genClassMethodCall(Symbol objectSymbol, string methodName, Stmt[] args)
    {
        string className = objectSymbol.structName;

        if (className !in classes)
        {
            throw new Exception(format("Classe '%s' não encontrada", className));
        }

        string mangledMethodName = className ~ "_" ~ methodName;

        Symbol* method = currentContext.findFunction(mangledMethodName);
        if (method is null)
        {
            throw new Exception(format("Método '%s' não encontrado na classe '%s'", methodName, className));
        }

        LLVMValueRef[] llvmArgs;
        llvmArgs ~= objectSymbol.value; // 'this' pointer

        // Adicionar outros argumentos
        if (args !is null)
        {
            foreach (arg; args)
            {
                Symbol argSymbol = genStmt(arg);
                llvmArgs ~= argSymbol.value;
            }
        }

        // Fazer a chamada
        LLVMValueRef call = LLVMBuildCall2(
            builder,
            method.type,
            method.value,
            llvmArgs.ptr,
            cast(uint) llvmArgs.length,
            (methodName ~ "_call").toStringz()
        );

        // Determinar o tipo de retorno correto
        LLVMTypeRef returnType = LLVMGetReturnType(method.type);

        // Para métodos que retornam struct por valor, pode precisar de tratamento especial
        bool isStructReturn = (LLVMGetTypeKind(returnType) == LLVMTypeKind.LLVMStructTypeKind);
        string returnClassName = "";

        if (isStructReturn)
        {
            // Determinar o nome da classe de retorno baseado no método
            ClassInfo classInfo = classes[className];
            foreach (methodDecl; classInfo.methods)
            {
                if (methodDecl.id.value.get!string == methodName)
                {
                    if (methodDecl.type.isStruct)
                    {
                        returnClassName = methodDecl.type.className;
                    }
                    break;
                }
            }
        }

        return Symbol(call, returnType, false, isStructReturn, returnClassName);
    }

    Symbol genPrimitiveMethodCall(Symbol objectSymbol, string methodName, Stmt[] args)
    {
        // Implementação para métodos de tipos primitivos
        // Por exemplo: string.length(), array.size(), etc.

        throw new Exception(format("Chamada de método '%s' em tipo primitivo não implementada ainda", methodName));
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

        // Carregar o valor do campo
        LLVMValueRef fieldValue = LLVMBuildLoad2(builder, field.type, fieldPtr, memberName.toStringz());

        // Determinar se o campo é struct
        bool isFieldStruct = (LLVMGetTypeKind(field.type) == LLVMTypeKind.LLVMStructTypeKind);
        string fieldClassName = "";

        if (isFieldStruct)
        {
            // Buscar informações da propriedade para obter o nome da classe
            foreach (prop; classInfo.properties)
            {
                if (prop.name.value.get!string == memberName && prop.type.isStruct)
                {
                    fieldClassName = prop.type.className;
                    break;
                }
            }
        }

        return Symbol(fieldValue, field.type, true, isFieldStruct, fieldClassName, field.fieldIndex);
    }

    // Correção no genVarDeclaration para lidar com FTypeInfo corretamente
    Symbol genVarDeclaration(VariableDeclaration node)
    {
        FTypeInfo type = node.value.get!Stmt.type;

        if (type.baseType == TypesNative.I8P)
        {
            Symbol stringSymbol = genStmt(node.value.get!Stmt);

            // Criar variável local que aponta para a string
            LLVMValueRef var = LLVMBuildAlloca(builder, stringSymbol.type,
                node.id.value.get!string.toStringz());
            LLVMBuildStore(builder, stringSymbol.value, var);

            Symbol symbol = Symbol(var, stringSymbol.type, true);
            currentContext.variables[node.id.value.get!string] = symbol;
            return symbol;
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

        if (valueSymbol.isStruct)
        {
            LLVMValueRef loadedValue = LLVMBuildLoad2(builder,
                getType(type), valueSymbol.value, "loaded_value");
            LLVMBuildStore(builder, loadedValue, var);
        }

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

        Symbol* variable = currentContext.findVariable(varName);
        if (variable !is null)
        {
            if (!variable.isVariable)
            {
                return *variable;
            }

            if (variable.isStruct || node.type.isStruct || node.type.baseType == TypesNative.STRUCT)
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

    void initializeTargetForPlatform(string[] targetTypes)
    {
        foreach (targetType; targetTypes)
        {
            switch (targetType)
            {
            case "X86":
                LLVMInitializeX86Target();
                LLVMInitializeX86TargetInfo();
                LLVMInitializeX86TargetMC();
                LLVMInitializeX86AsmPrinter();
                LLVMInitializeX86AsmParser();
                break;
            case "AArch64":
                LLVMInitializeAArch64Target();
                LLVMInitializeAArch64TargetInfo();
                LLVMInitializeAArch64TargetMC();
                LLVMInitializeAArch64AsmPrinter();
                LLVMInitializeAArch64AsmParser();
                break;
            case "ARM":
                LLVMInitializeARMTarget();
                LLVMInitializeARMTargetInfo();
                LLVMInitializeARMTargetMC();
                LLVMInitializeARMAsmPrinter();
                LLVMInitializeARMAsmParser();
                break;
            default:
                throw new Exception(format("Arquitetura de target desconhecida: %s", targetType));
            }
        }
    }

    void initializeTargetData(TargetInfo _target)
    {
        initializeTargetForPlatform(_target.initFunctions);
        const char* targetTriple = _target.triple.ptr;

        LLVMTargetRef target;
        const(char)* errorMessage;
        if (LLVMGetTargetFromTriple(targetTriple, &target, &errorMessage))
        {
            writeln("Erro: ", errorMessage.to!string);
            LLVMDisposeMessage(cast(char*) errorMessage);
        }

        auto targetMachine = LLVMCreateTargetMachine(
            target,
            targetTriple,
            "", // CPU
            "", // Features
            LLVMCodeGenOptLevel.LLVMCodeGenLevelDefault,
            LLVMRelocMode.LLVMRelocDefault,
            LLVMCodeModel.LLVMCodeModelDefault
        );

        auto dataLayout = LLVMCreateTargetDataLayout(targetMachine);
        auto dataLayoutStr = LLVMCopyStringRepOfTargetData(dataLayout);

        LLVMSetDataLayout(mod, dataLayoutStr);
        LLVMSetTarget(mod, targetTriple);

        targetData = LLVMCreateTargetData(dataLayoutStr);

        LLVMDisposeMessage(cast(char*) dataLayoutStr);
        LLVMDisposeTargetData(dataLayout);
        LLVMDisposeTargetMachine(targetMachine);
    }

public:
    Semantic semantic;
    LLVMModuleRef mod;
    LLVMContextRef context;
    LLVMBuilderRef builder;

    this(Program program, Semantic semantic, TargetInfo _target)
    {
        this.semantic = semantic;
        this.program = program;

        this.currentContext = &this.globalContext;

        this.context = LLVMContextCreate();
        this.mod = LLVMModuleCreateWithNameInContext("main", this.context);
        this.builder = LLVMCreateBuilderInContext(this.context);

        initializeTargetData(_target);

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

    bool saveModule(string filename)
    {
        File file = File(filename, "w");
        try
        {
            char* llvmIR = LLVMPrintModuleToString(this.mod);
            if (llvmIR is null)
            {
                printf("ERRO: Falha ao gerar IR do módulo\n");
                return false;
            }
            string irContent = fromStringz(llvmIR).idup;
            LLVMDisposeMessage(llvmIR);
            file.rawWrite(irContent);
            printf("Módulo LLVM IR salvo com sucesso em: %s\n", filename.toStringz());
            return true;
        }
        catch (Exception e)
        {
            printf("ERRO ao salvar módulo: %s\n", e.msg.toStringz());
            return false;
        }
        finally
        {
            file.close();
        }
    }
}
