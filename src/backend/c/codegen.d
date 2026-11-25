module backend.c.codegen;

import std.algorithm;
import std.format;
import std.array;
import std.stdio;
import std.conv;
import std.math : isFinite;

import frontend.lexer.token;
import frontend.semantic.members;
import frontend.flow : terminates;
import middle.async_ir;
import frontend.type_sema;
import frontend.type_expr;
import backend.c.async_codegen;
import backend.c.descriptors;
import backend.c.lvalue;
import backend.c.foreign;
import backend.c.native_codegen;
import middle.memory_model;
import middle.ans;
import frontend.semantic.native_validation : isNativeCastName;
import frontend.semantic.ownership : OwnershipInfo;
import frontend.parser;
import backend.c.utils;

enum string VALUE = "delegua_value";
enum string ENTRY = "delegua_main";

class BackendC
{
private:
    size_t tmp;
    size_t icCount;
    dstring nextIcSlot()
    {
        return formatD("&cgd_ic[%s]", icCount++);
    }
    dstring[] sourceSites;
    size_t[string] sourceSiteIds;
    dstring[] sourceFileDecls;
    size_t[string] sourceFileIds;
    bool currentFnHasTry = true;
    dstring currentDeclaringVar;
    bool inDefaultArg = false;
    bool reachabilityComputed = false;
    bool[Node] reachableNodes;
    bool[VarDecl] mutatedVars;
    bool[ClassDecl] classesWithSubclasses;
    bool[dstring] referencedNames;
    bool dynamicMethodDispatch = false;
    public bool emitDebugLines = false;
    public string[string] debugFunctionNames;
    public OwnershipInfo ownershipInfo;
    public MemoryPlan memoryPlan;
    private NativeCodegen nativeCg;
    private AnsCodegen ansCg;
    private dstring[][] detFreeScopes;
    private size_t[] loopDetScopeDepth;
    private size_t[] breakDetScopeDepth;
    package ClassDecl currentClass;

    private bool isSubclassOrSame(ClassDecl sub, ClassDecl base)
    {
        if (sub is null || base is null)
            return false;
        ClassDecl cur = sub;
        size_t guard = 0;
        while (cur !is null && guard < 64)
        {
            if (cur is base)
                return true;
            cur = cur.superClass;
            guard++;
        }
        return false;
    }

    private void pushDetScope()
    {
        detFreeScopes ~= (dstring[]).init;
    }

    private dstring popDetScopeCode()
    {
        if (detFreeScopes.length == 0)
            return ""d;
        dstring[] vars = detFreeScopes[$ - 1];
        detFreeScopes.length--;
        if (vars.length == 0)
            return ""d;
        dstring[] lines;
        foreach_reverse (dstring v; vars)
            lines ~= formatD("cgd_gc_free_det_value(%s);", v);
        return lines.join("\n");
    }

    private dstring detFreeCode(size_t limit)
    {
        dstring[] lines;
        for (size_t i = detFreeScopes.length; i > limit; --i)
        {
            dstring[] vars = detFreeScopes[i - 1];
            foreach_reverse (dstring v; vars)
                lines ~= formatD("cgd_gc_free_det_value(%s);", v);
        }
        return lines.join("\n");
    }

    private bool hasDetFreeVars(size_t limit = 0)
    {
        for (size_t i = detFreeScopes.length; i > limit; --i)
            if (detFreeScopes[i - 1].length > 0)
                return true;
        return false;
    }

    private bool isValueTypeExpr(Node n)
    {
        if (n is null || n.type_sema is null)
            return false;
        if (TypeSemaClass cls = cast(TypeSemaClass) n.type_sema)
            return cls.declaration !is null && cls.declaration.isValueType;
        return false;
    }

    private dstring emitManagedMathCall(dstring fnName, Node[] args)
    {
        dstring numArg(Node a)
        {
            return formatD("(delegua_op_cast(%s, DELEGUA_T_REAL).value.real)", materialize(a, true));
        }

        switch (fnName)
        {
            case "raiz":
            case "raizQuadrada":
                return formatD("create_real(sqrt(%s))", numArg(args[0]));
            case "seno":
                return formatD("create_real(sin(%s))", numArg(args[0]));
            case "cosseno":
                return formatD("create_real(cos(%s))", numArg(args[0]));
            case "tangente":
                return formatD("create_real(tan(%s))", numArg(args[0]));
            case "absoluto":
                return formatD("create_real(fabs(%s))", numArg(args[0]));
            case "piso":
                return formatD("create_real(floor(%s))", numArg(args[0]));
            case "teto":
                return formatD("create_real(ceil(%s))", numArg(args[0]));
            case "arredondar":
                return formatD("create_real(round(%s))", numArg(args[0]));
            case "logaritmo":
                return formatD("create_real(log(%s))", numArg(args[0]));
            case "exponencial":
                return formatD("create_real(exp(%s))", numArg(args[0]));
            case "arcoSeno":
                return formatD("create_real(asin(%s))", numArg(args[0]));
            case "arcoCosseno":
                return formatD("create_real(acos(%s))", numArg(args[0]));
            case "arcoTangente":
                return formatD("create_real(atan(%s))", numArg(args[0]));
            case "potencia":
            case "potência":
                return formatD("create_real(pow(%s, %s))", numArg(args[0]), numArg(args[1]));
            case "minimo":
            case "mínimo":
                return formatD("create_real(fmin(%s, %s))", numArg(args[0]), numArg(args[1]));
            case "maximo":
            case "máximo":
                return formatD("create_real(fmax(%s, %s))", numArg(args[0]), numArg(args[1]));
            case "arcoTangente2":
                return formatD("create_real(atan2(%s, %s))", numArg(args[0]), numArg(args[1]));
            default:
                return "create_real(0.0)"d;
        }
    }

    private dstring emitManagedCCast(dstring ctype, dstring argExpr)
    {
        switch (ctype)
        {
            case "ci8":
                return formatD("create_num((int64_t)(int8_t)(delegua_op_cast(%s, DELEGUA_T_NUM).value.num))", argExpr);
            case "cu8":
                return formatD("create_num((int64_t)(uint8_t)(delegua_op_cast(%s, DELEGUA_T_NUM).value.num))", argExpr);
            case "cchar":
                return formatD("create_num((int64_t)(char)(delegua_op_cast(%s, DELEGUA_T_NUM).value.num))", argExpr);
            case "cschar":
                return formatD("create_num((int64_t)(signed char)(delegua_op_cast(%s, DELEGUA_T_NUM).value.num))", argExpr);
            case "cuchar":
                return formatD("create_num((int64_t)(unsigned char)(delegua_op_cast(%s, DELEGUA_T_NUM).value.num))", argExpr);
            case "ci16":
                return formatD("create_num((int64_t)(int16_t)(delegua_op_cast(%s, DELEGUA_T_NUM).value.num))", argExpr);
            case "cu16":
                return formatD("create_num((int64_t)(uint16_t)(delegua_op_cast(%s, DELEGUA_T_NUM).value.num))", argExpr);
            case "ci32":
                return formatD("create_num((int64_t)(int32_t)(delegua_op_cast(%s, DELEGUA_T_NUM).value.num))", argExpr);
            case "cu32":
                return formatD("create_num((int64_t)(uint32_t)(delegua_op_cast(%s, DELEGUA_T_NUM).value.num))", argExpr);
            case "ci64":
            case "clong":
                return formatD("create_num((int64_t)(delegua_op_cast(%s, DELEGUA_T_NUM).value.num))", argExpr);
            case "cu64":
            case "culong":
            case "csize":
                return formatD("create_num((int64_t)(size_t)(delegua_op_cast(%s, DELEGUA_T_NUM).value.num))", argExpr);
            case "cshort":
                return formatD("create_num((int64_t)(short)(delegua_op_cast(%s, DELEGUA_T_NUM).value.num))", argExpr);
            case "cushort":
                return formatD("create_num((int64_t)(unsigned short)(delegua_op_cast(%s, DELEGUA_T_NUM).value.num))", argExpr);
            case "cint":
                return formatD("create_num((int64_t)(int)(delegua_op_cast(%s, DELEGUA_T_NUM).value.num))", argExpr);
            case "cuint":
                return formatD("create_num((int64_t)(unsigned int)(delegua_op_cast(%s, DELEGUA_T_NUM).value.num))", argExpr);
            case "cf32":
            case "cfloat":
                return formatD("create_real((double)(float)(delegua_op_cast(%s, DELEGUA_T_REAL).value.real))", argExpr);
            case "cf64":
            case "cdouble":
                return formatD("create_real((double)(delegua_op_cast(%s, DELEGUA_T_REAL).value.real))", argExpr);
            case "cbool":
                return formatD("create_bool(delegua_is_truthy(%s))", argExpr);
            default:
                return argExpr;
        }
    }
    TypeExpr functionReturn;
    package dstring asyncSelf;
    package dstring descriptor(TypeExpr type)
    {
        return typeDescriptor(type);
    }

    private bool typeNamesMatchExact(dstring actualName, dstring expectedName)
    {
        switch (expectedName)
        {
            case "inteiro":
            case "longo":
                return actualName == "inteiro" || actualName == "longo";
            case "real":
            case "decimal":
            case "numero":
            case "número":
                return actualName == "inteiro" || actualName == "longo" || actualName == "real"
                    || actualName == "decimal" || actualName == "numero" || actualName == "número";
            case "texto":
                return actualName == "texto";
            case "logico":
            case "lógico":
            case "booleano":
            case "binario":
            case "binário":
                return actualName == "logico" || actualName == "lógico" || actualName == "booleano"
                    || actualName == "binario" || actualName == "binário";
            case "dicionario":
            case "dicionário":
                return actualName == "dicionario" || actualName == "dicionário";
            case "funcao":
            case "função":
                return actualName == "funcao" || actualName == "função";
            case "vazio":
            case "nulo":
                return actualName == "vazio" || actualName == "nulo";
            default:
                return false;
        }
    }

    private TypeExpr effectiveTypeExpr(Node expr)
    {
        if (expr is null)
            return null;
        if (Identifier id = cast(Identifier) expr)
        {
            if (id.value != currentDeclaringVar)
            {
                if (id.variableRef !is null && !id.variableRef.uninitialized)
                    return id.variableRef.type_expr;
                if (!inDefaultArg && id.parameterRef !is null)
                    return id.parameterRef.rest ? new TypeExprArray(id.parameterRef.type_expr,
                            id.pos) : id.parameterRef.type_expr;
            }
        }
        else if (MemberExpr member = cast(MemberExpr) expr)
        {
            if (member.enumValue !is null)
                return new TypeExprNamed("inteiro"d, member.pos);
            if (member.type_expr !is null && cast(TypeSemaClass) member.left.type_sema !is null)
            {
                TypeSemaClass leftCls = cast(TypeSemaClass) member.left.type_sema;
                if (reachabilityComputed && leftCls.declaration !is null && leftCls
                        .declaration !in classesWithSubclasses)
                    return member.type_expr;
            }
        }
        return null;
    }

    private bool hasEnvelope(FnDecl fn)
    {
        if (fn is null)
            return false;
        foreach (Decorator d; fn.decorators)
            if (d.envelope !is null)
                return true;
        return false;
    }

    private bool arityMatches(FnDecl fn, Node[] args)
    {
        if (fn is null)
            return false;
        size_t minimum = 0;
        foreach (FnArg arg; fn.args)
            if (arg.value is null && !arg.rest)
                minimum++;
        bool variadic = fn.args.length > 0 && fn.args[$ - 1].rest;
        return args.length >= minimum && (variadic || args.length <= fn.args.length);
    }

    private ModuleUnit staticModuleOf(Node expr, int depth = 0)
    {
        if (expr is null || depth > 8)
            return null;
        if (ImportExpr imp = cast(ImportExpr) expr)
            return imp.target;
        if (MemberExpr member = cast(MemberExpr) expr)
        {
            if (member.resolvedModule !is null)
                return member.resolvedModule;
        }
        if (Identifier id = cast(Identifier) expr)
        {
            if (id.moduleRef !is null)
                return id.moduleRef;
            if (id.variableRef !is null && id.variableRef.isConst && !id.variableRef.uninitialized
                    && id.variableRef.value !is null)
                return staticModuleOf(id.variableRef.value, depth + 1);
        }
        return null;
    }

    private Node findModuleExport(ModuleUnit mod, dstring name)
    {
        if (mod is null || mod.program is null || !name.length || name[0] == '#')
            return null;
        Node found = null;
        void scan(Node[] list)
        {
            foreach (Node item; list)
            {
                if (SequenceStmt seq = cast(SequenceStmt) item)
                    scan(seq.body);
                else if (VarDecl v = cast(VarDecl) item)
                {
                    if (v.name == name)
                        found = v;
                }
                else if (FnDecl fn = cast(FnDecl) item)
                {
                    if (fn.fn == name)
                        found = fn;
                }
                else if (ClassDecl c = cast(ClassDecl) item)
                {
                    if (c.name == name)
                        found = c;
                }
            }
        }

        scan(mod.program.body);
        return found;
    }

    private ClassDecl staticClassOf(Node expr, out bool needsModuleInit, out dstring modLinkName, int depth = 0)
    {
        needsModuleInit = false;
        modLinkName = ""d;
        if (expr is null || depth > 8)
            return null;
        if (Identifier id = cast(Identifier) expr)
        {
            if (id.classRef !is null)
                return id.classRef;
            if (id.variableRef !is null && id.variableRef.isConst && !id.variableRef.uninitialized
                    && id.variableRef.value !is null)
                return staticClassOf(id.variableRef.value, needsModuleInit, modLinkName, depth + 1);
            return null;
        }
        if (MemberExpr member = cast(MemberExpr) expr)
        {
            if (member.enumValue !is null)
                return null;
            Identifier rightId = cast(Identifier) member.right;
            if (rightId is null)
                return null;
            if (ModuleUnit mod = staticModuleOf(member.left))
            {
                if (ClassDecl cls = cast(ClassDecl) findModuleExport(mod, rightId.value))
                {
                    needsModuleInit = true;
                    modLinkName = mod.linkName;
                    return cls;
                }
            }
        }
        return null;
    }

    private FnDecl resolveDirectCallee(CallExpr call, out bool needsModuleInit, out dstring modLinkName)
    {
        needsModuleInit = false;
        modLinkName = ""d;
        if (call is null || call.runtimeCall || call.args.any!((Node a) => a.kind == NodeKind.SpreadExpr))
            return null;
        if (Identifier fnId = cast(Identifier) call.fn)
        {
            if (fnId.classRef !is null)
                return null;
            FnDecl target = fnId.functionRef;
            if (target is null && fnId.variableRef !is null && fnId.variableRef.isConst
                    && !fnId.variableRef.uninitialized)
            {
                if (Identifier aliasId = cast(Identifier) fnId.variableRef.value)
                    if (aliasId.classRef is null)
                        target = aliasId.functionRef;
            }
            if (target !is null && !target.builtinName.length && target.classFactory is null
                    && !target.isAbstract && (!target.isMethod || target.isStatic)
                    && !hasEnvelope(target) && arityMatches(target, call.args))
                return target;
            return null;
        }
        if (MemberExpr member = cast(MemberExpr) call.fn)
        {
            if (member.enumValue !is null)
                return null;
            Identifier rightId = cast(Identifier) member.right;
            if (rightId is null)
                return null;
            if (ClassDecl cls = staticClassOf(member.left, needsModuleInit, modLinkName))
            {
                FnDecl target = rightId.functionRef;
                bool visible = target !is null;
                if (target is null)
                {
                    ClassMember cm = resolveClassMember(cls, rightId.value);
                    if (cm.field is null && cm.method !is null)
                    {
                        target = cm.method;
                        visible = cm.method.access == 0 || cm.owner == currentClass;
                    }
                }
                if (visible && target !is null && target.isStatic && !target.isAbstract
                        && target.classFactory is null && !hasEnvelope(target) && arityMatches(target, call.args))
                    return target;
                needsModuleInit = false;
                modLinkName = ""d;
                return null;
            }
            if (ModuleUnit mod = staticModuleOf(member.left))
            {
                FnDecl target = cast(FnDecl) findModuleExport(mod, rightId.value);
                if (target !is null && !target.builtinName.length && target.classFactory is null
                        && !target.isAbstract && (!target.isMethod || target.isStatic)
                        && !hasEnvelope(target) && arityMatches(target, call.args))
                {
                    needsModuleInit = true;
                    modLinkName = mod.linkName;
                    return target;
                }
            }
        }
        return null;
    }

    private ClassDecl resolveDirectConstructor(CallExpr call, out bool needsModuleInit, out dstring modLinkName)
    {
        needsModuleInit = false;
        modLinkName = ""d;
        if (call is null || call.runtimeCall || call.args.any!((Node a) => a.kind == NodeKind.SpreadExpr))
            return null;
        ClassDecl cls = staticClassOf(call.fn, needsModuleInit, modLinkName);
        if (cls !is null && !cls.signature.builtinName.length)
            return cls;
        needsModuleInit = false;
        modLinkName = ""d;
        return null;
    }

    private bool nodeMatchesExactType(Node valueNode, TypeExprNamed named)
    {
        if (valueNode is null || named is null)
            return false;
        if (TypeExpr knownExpr = effectiveTypeExpr(valueNode))
        {
            if (TypeExprNamed kn = cast(TypeExprNamed) knownExpr)
            {
                if (named.classLinkName.length)
                {
                    if (kn.classLinkName == named.classLinkName)
                        return true;
                }
                else if (!kn.classLinkName.length && typeNamesMatchExact(kn.name, named.name))
                    return true;
            }
        }
        if (IndexExpr idxExpr = cast(IndexExpr) valueNode)
        {
            if (TypeExprArray arrExpr = cast(TypeExprArray) effectiveTypeExpr(idxExpr.value))
                if (TypeExprNamed baseNamed = cast(TypeExprNamed) arrExpr.base)
                {
                    if (named.classLinkName.length)
                    {
                        if (baseNamed.classLinkName == named.classLinkName)
                            return true;
                    }
                    else if (!baseNamed.classLinkName.length && typeNamesMatchExact(baseNamed.name, named.name))
                        return true;
                }
            if (!named.classLinkName.length)
            {
                if (TypeSemaBuiltin textSema = cast(TypeSemaBuiltin) idxExpr.value.type_sema)
                    if (textSema.base == TypeSemaBase.String && typeNamesMatchExact("texto"d, named.name))
                        return true;
            }
        }
        if (CallExpr call = cast(CallExpr) valueNode)
        {
            bool unusedInit;
            dstring unusedMod;
            if (named.classLinkName.length)
            {
                if (ClassDecl cls = resolveDirectConstructor(call, unusedInit, unusedMod))
                    if (cls.signature.linkName == named.classLinkName)
                        return true;
                if (FnDecl target = resolveDirectCallee(call, unusedInit, unusedMod))
                    if (TypeExprNamed retNamed = cast(TypeExprNamed) target.type_expr)
                        if (retNamed.classLinkName == named.classLinkName)
                            return true;
                if (MemberExpr member = cast(MemberExpr) call.fn)
                    if (Identifier rightId = cast(Identifier) member.right)
                        if (reachabilityComputed && rightId.functionRef !is null
                                && rightId.functionRef.ownerClass !is null
                                && rightId.functionRef.ownerClass !in classesWithSubclasses
                                && cast(TypeSemaClass) member.left.type_sema !is null)
                            if (TypeExprNamed retNamed = cast(TypeExprNamed) rightId.functionRef.type_expr)
                                if (retNamed.classLinkName == named.classLinkName)
                                    return true;
                return false;
            }
            if (call.runtimeCall)
            {
                dstring opName = (cast(Identifier) call.fn).value;
                if (opName == "delegua_op_bor" || opName == "delegua_op_bnd"
                        || opName == "delegua_op_bxr" || opName == "delegua_op_shl"
                        || opName == "delegua_op_shr" || opName == "delegua_op_bnt"
                        || opName == "delegua_op_idiv" || opName == "delegua_op_mod")
                    return typeNamesMatchExact("inteiro"d, named.name);
                if (opName == "delegua_op_eq" || opName == "delegua_op_neq"
                        || opName == "delegua_op_lt" || opName == "delegua_op_le"
                        || opName == "delegua_op_gt"
                        || opName == "delegua_op_ge" || opName == "delegua_op_not" || opName == "delegua_op_in")
                    return typeNamesMatchExact("logico"d, named.name);
                if (opName == "delegua_para_texto")
                    return typeNamesMatchExact("texto"d, named.name);
            }
            else if (Identifier fnId = cast(Identifier) call.fn)
            {
                if (fnId.functionRef !is null && fnId.functionRef.builtinName.length
                        && call.args.length == 1 && call.args[0].kind != NodeKind.SpreadExpr)
                {
                    dstring b = fnId.functionRef.builtinName;
                    if (b == "texto" || b == "leia")
                        return typeNamesMatchExact("texto"d, named.name);
                    if (b == "tamanho" || b == "inteiro")
                        return typeNamesMatchExact("inteiro"d, named.name);
                    if (b == "real" || b == "numero" || b == "número")
                        return typeNamesMatchExact("real"d, named.name);
                }
            }
            if (FnDecl target = resolveDirectCallee(call, unusedInit, unusedMod))
                if (TypeExprNamed retNamed = cast(TypeExprNamed) target.type_expr)
                    if (!retNamed.classLinkName.length && typeNamesMatchExact(retNamed.name, named.name))
                        return true;
            if (MemberExpr member = cast(MemberExpr) call.fn)
                if (Identifier rightId = cast(Identifier) member.right)
                    if (rightId.functionRef !is null && !rightId.functionRef.isAbstract)
                    {
                        bool safeNative = member.left.type_sema !is null && !member.left.type_sema.isAny()
                            && member.left.type_sema.toStr() != TypeSemaBase.Map
                            && rightId.functionRef.ownerClass is null
                            && rightId.functionRef.builtinName.length == 0 && rightId.functionRef.linkName.length == 0;
                        bool safeConcreteClass = rightId.functionRef.ownerClass !is null
                            && rightId.functionRef.ownerClass !in classesWithSubclasses
                            && cast(TypeSemaClass) member.left.type_sema !is null;
                        if (safeNative || safeConcreteClass)
                            if (TypeExprNamed retNamed = cast(TypeExprNamed) rightId.functionRef.type_expr)
                                if (!retNamed.classLinkName.length && typeNamesMatchExact(retNamed.name, named.name))
                                    return true;
                    }
        }
        if (named.classLinkName.length)
            return false;
        switch (named.name)
        {
            case "inteiro":
            case "longo":
                return cast(IntLit) valueNode !is null;
            case "real":
            case "decimal":
                return cast(DoubleLit) valueNode !is null;
            case "numero":
            case "número":
                return cast(IntLit) valueNode !is null || cast(DoubleLit) valueNode !is null;
            case "texto":
                return cast(StringLit) valueNode !is null;
            case "logico":
            case "lógico":
            case "booleano":
            case "binario":
            case "binário":
                return cast(BoolLit) valueNode !is null;
            case "dicionario":
            case "dicionário":
                return cast(MapLit) valueNode !is null;
            case "funcao":
            case "função":
                return cast(FunctionExpr) valueNode !is null;
            case "vazio":
            case "nulo":
                return cast(NullLit) valueNode !is null;
            default:
                return false;
        }
    }

    private bool isGuaranteedBoolNode(Node node)
    {
        if (node is null)
            return false;
        if (cast(BoolLit) node)
            return true;
        if (TypeExpr knownExpr = effectiveTypeExpr(node))
            if (TypeExprNamed kn = cast(TypeExprNamed) knownExpr)
                if (!kn.classLinkName.length && typeNamesMatchExact(kn.name, "logico"d))
                    return true;
        if (CallExpr call = cast(CallExpr) node)
        {
            if (call.runtimeCall)
            {
                dstring opName = (cast(Identifier) call.fn).value;
                return opName == "delegua_op_eq" || opName == "delegua_op_neq"
                    || opName == "delegua_op_lt" || opName == "delegua_op_le"
                    || opName == "delegua_op_gt"
                    || opName == "delegua_op_ge" || opName == "delegua_op_not" || opName == "delegua_op_in";
            }
            bool unusedInit;
            dstring unusedMod;
            if (FnDecl target = resolveDirectCallee(call, unusedInit, unusedMod))
                if (TypeExprNamed retNamed = cast(TypeExprNamed) target.type_expr)
                    if (!retNamed.classLinkName.length && typeNamesMatchExact(retNamed.name, "logico"d))
                        return true;
            if (MemberExpr member = cast(MemberExpr) call.fn)
                if (Identifier rightId = cast(Identifier) member.right)
                    if (rightId.functionRef !is null && member.left.type_sema !is null
                            && !member.left.type_sema.isAny() && member.left.type_sema.toStr() != TypeSemaBase.Map
                            && ((rightId.functionRef.ownerClass is null && rightId.functionRef.linkName.length == 0)
                                || (reachabilityComputed && rightId.functionRef.ownerClass !is null
                                && rightId.functionRef.ownerClass !in classesWithSubclasses
                                && cast(TypeSemaClass) member.left.type_sema !is null)))
                        if (TypeExprNamed retNamed = cast(TypeExprNamed) rightId.functionRef.type_expr)
                            if (!retNamed.classLinkName.length && typeNamesMatchExact(retNamed.name, "logico"d))
                                return true;
        }
        if (BinaryExpr bin = cast(BinaryExpr) node)
        {
            if (bin.op == TokenKind.And || bin.op == TokenKind.Or)
                return isGuaranteedBoolNode(bin.left) && isGuaranteedBoolNode(bin.right);
        }
        return false;
    }

    private dstring truthyExpr(Node node, dstring compiledExpr)
    {
        if (isGuaranteedBoolNode(node))
            return "(" ~ compiledExpr ~ ").value.b1";
        return formatD("delegua_is_truthy(%s)", compiledExpr);
    }

    private dstring compileCondition(Node cond, out dstring setup)
    {
        bool negated = false;
        while (CallExpr c = cast(CallExpr) cond)
        {
            if (c.runtimeCall && c.args.length == 1 && (cast(Identifier) c.fn).value == "delegua_op_not")
            {
                negated = !negated;
                cond = c.args[0];
            }
            else
                break;
        }
        dstring expr;
        setup = captureExpr(cond, expr);
        dstring test = truthyExpr(cond, expr);
        return negated ? ("!"d ~ test) : test;
    }

    package dstring checked(dstring value, TypeExpr type, Position pos = null, Node valueNode = null)
    {
        if (type is null || type.toStr() == "qualquer")
            return value;
        TypeExprNamed named = cast(TypeExprNamed) type;
        if (named !is null && nodeMatchesExactType(valueNode, named))
            return value;
        dstring sp = sitePtr(pos is null ? type.pos : pos);
        if (named !is null && !named.classLinkName.length)
        {
            switch (named.name)
            {
                case "inteiro":
                case "longo":
                    return formatD("delegua_assegurar_inteiro_em(%s,%s)", value, sp);
                case "numero":
                case "número":
                    return formatD("delegua_assegurar_numero_em(%s,%s)", value, sp);
                case "real":
                case "decimal":
                    return formatD("delegua_assegurar_real_em(%s,%s)", value, sp);
                case "texto":
                    return formatD("delegua_assegurar_texto_em(%s,%s)", value, sp);
                case "logico":
                case "lógico":
                case "booleano":
                case "binario":
                case "binário":
                    return formatD("delegua_assegurar_logico_em(%s,%s)", value, sp);
                case "dicionario":
                case "dicionário":
                    return formatD("delegua_assegurar_dicionario_em(%s,%s)", value, sp);
                case "funcao":
                case "função":
                    return formatD("delegua_assegurar_funcao_em(%s,%s)", value, sp);
                case "vazio":
                case "nulo":
                    return formatD("delegua_assegurar_vazio_em(%s,%s)", value, sp);
                default:
                    break;
            }
        }
        return formatD("delegua_assegurar_descr_em(%s,%s,%s)", value, descriptor(type), sp);
    }

    dstring lexicalClass()
    {
        return currentClass is null ? "create_nulo()"d : cName(currentClass.signature.linkName);
    }

    dstring[] continueLabels, breakLabels;
    bool[dstring] referencedLabels;
    dstring labelDeclaration(dstring label)
    {
        return label in referencedLabels ? label ~ ":;" : "";
    }

    // Referenciar o endereço marca uso em C99 sem ler um vínculo volatile.
    package dstring acknowledgeBinding(dstring name)
    {
        return formatD("(void)&%s;", name);
    }

    private dstring localValueDecl()
    {
        return currentFnHasTry ? ("volatile "d ~ VALUE) : VALUE;
    }

    private dstring acknowledgeLocal(dstring name)
    {
        return currentFnHasTry ? acknowledgeBinding(name) : formatD("(void)%s;", name);
    }

    private bool containsTryStmt(Node node)
    {
        if (node is null)
            return false;
        if (cast(TryStmt) node)
            return true;
        if (cast(FnDecl) node || cast(ClassDecl) node || cast(ModuleUnit) node)
            return false;
        foreach (Node child; childNodes(node))
            if (containsTryStmt(child))
                return true;
        return false;
    }

    size_t[] breakTryDepth;
    struct Collector
    {
        dstring output, label;
        size_t depth;
        size_t detDepth;
    }

    Collector[] collectors;
    dstring pendingCollector;
    void enterLoop(dstring label)
    {
        continueLabels ~= label;
        loopTryDepth ~= cleanups.length;
        loopDetScopeDepth ~= detFreeScopes.length;
        breakLabels ~= label ~ "_break";
        breakTryDepth ~= cleanups.length;
        breakDetScopeDepth ~= detFreeScopes.length;
        if (pendingCollector.length)
        {
            collectors ~= Collector(pendingCollector, label, cleanups.length, detFreeScopes.length);
            pendingCollector = "";
        }
    }

    void leaveLoop(dstring label)
    {
        continueLabels.length--;
        loopTryDepth.length--;
        loopDetScopeDepth.length--;
        breakLabels.length--;
        breakTryDepth.length--;
        breakDetScopeDepth.length--;
        if (collectors.length && collectors[$ - 1].label == label)
            collectors.length--;
    }

    dstring compileAssignment(AssignStmt assign, bool resultNeeded = true)
    {
        LValue lv = resolveLValue(assign.left, assign.value);
        dstring value;
        if (assign.op == TokenKind.Equals)
        {
            value = (!resultNeeded && lv.kind == LValueKind.Var) ? compileExpr(assign.value) : materialize(assign.value,
                    true);
            if (isValueTypeExpr(assign.value))
                value = formatD("delegua_clonar(%s)", value);
        }
        else
        {
            dstring old = lv.kind == LValueKind.Var && !canMutateVar(assign.value,
                    (cast(Identifier) assign.left).value) ? lv.read() : formatD("cgd_tmp_%s", tmp++);
            if (old != lv.read())
                emitLocal(formatD("delegua_value %s=%s;", old, atSite(lv.read(), assign.pos)));
            dstring op;
            switch (assign.op)
            {
                case TokenKind.PlusAssign:
                    op = "add";
                    break;
                case TokenKind.MinusAssign:
                    op = "sub";
                    break;
                case TokenKind.MulAssign:
                    op = "mul";
                    break;
                case TokenKind.DivAssign:
                    op = "div";
                    break;
                case TokenKind.ModAssign:
                    op = "mod";
                    break;
                default:
                    throw new Exception("Atribuição inválida no backend.");
            }
            dstring rhs = materialize(assign.value, true);
            value = atSite(formatD("delegua_op_%s(%s,%s)", op, old, rhs), assign.pos);
        }
        Node checkNode = assign.op == TokenKind.Equals ? assign.value : null;
        if (!resultNeeded)
        {
            dstring writeExpr = lv.write(checked(value, assign.left.type_expr, assign.pos, checkNode));
            return (lv.kind == LValueKind.Var ? writeExpr : atSite(writeExpr, assign.pos)) ~ ";";
        }
        dstring result = formatD("cgd_tmp_%s", tmp++);
        emitLocal(formatD("delegua_value %s=%s;", result, checked(value, assign.left.type_expr,
                assign.pos, checkNode)));
        dstring writeResult = lv.write(result);
        emitLocal((lv.kind == LValueKind.Var ? writeResult : atSite(writeResult, assign.pos)) ~ ";");
        return result;
    }

    dstring compileSwitch(SwitchStmt node)
    {
        dstring value = materialize(node.value), label = formatD("cgd_switch_%s", tmp++),
            done = formatD("cgd_done_%s", tmp++);
        breakLabels ~= label;
        breakTryDepth ~= cleanups.length;
        breakDetScopeDepth ~= detFreeScopes.length;
        dstring[] result = [formatD("{bool %s=false;", done)];
        foreach (SwitchCase c; node.cases)
        {
            dstring matched = formatD("cgd_match_%s", tmp++);
            result ~= formatD("if(!%s){bool %s=false;", done, matched);
            foreach (Node v; c.values)
            {
                dstring expression;
                dstring setup = captureExpr(v, expression);
                result ~= formatD("if(!%s){%s\n%s=delegua_op_eq(%s,%s).value.b1;}", matched, setup,
                        matched, value, expression);
            }
            result ~= formatD("if(%s){%s=true;", matched, done);
            foreach (Node child; c.body)
                result ~= compileStmtOrdered(child);
            result ~= "}}";
        }
        result ~= formatD("if(!%s){", done);
        foreach (Node child; node.fallback)
            result ~= compileStmtOrdered(child);
        result ~= "}";
        result ~= labelDeclaration(label) ~ " }";
        breakLabels.length--;
        breakTryDepth.length--;
        breakDetScopeDepth.length--;
        return result.join("\n");
    }

    size_t[] loopTryDepth;
    struct Cleanup
    {
        dstring frame;
        Node[] finalBody;
    }

    Cleanup[] cleanups;
    dstring classValue(const(ClassDecl) c)
    {
        return c.signature.builtinName.length ? formatD("delegua_builtin(%s)",
                cString(c.signature.builtinName)) : cName(c.signature.linkName);
    }

    dstring cleanupCode(size_t limit)
    {
        Cleanup[] original = cleanups.dup;
        dstring[] result;
        while (cleanups.length > limit)
        {
            Cleanup current = cleanups[$ - 1];
            cleanups.length--;
            result ~= formatD("delegua_sair_tente(%s);", current.frame);
            foreach (Node child; current.finalBody)
                result ~= compileStmtOrdered(child);
        }
        cleanups = original;
        return result.join("\n");
    }

    dstring compileTry(TryStmt node)
    {
        dstring outer = formatD("cgd_try_%s", tmp++), inner = formatD("cgd_try_%s", tmp++);
        dstring[] result = [
            "{", formatD("delegua_try_frame *const %s=delegua_tentar();", outer),
            formatD("if(setjmp(%s->env)==0) {", outer)
        ];
        cleanups ~= Cleanup(outer, node.finalBody);
        result ~= formatD("delegua_try_frame *const %s=delegua_tentar();", inner);
        result ~= formatD("if(setjmp(%s->env)==0) {", inner);
        cleanups ~= Cleanup(inner, []);
        foreach (Node child; node.body)
            result ~= compileStmtOrdered(child);
        result ~= formatD("delegua_sair_tente(%s); } else {", inner);
        cleanups.length--;
        result ~= formatD("delegua_sair_tente(%s);", inner);
        foreach (size_t i, CatchClause c; node.catches)
        {
            dstring condition = c.type is null ? "true"d : formatD("delegua_tipo_compativel(%s->error,%s)",
                    inner, cString(c.type.toStr()));
            result ~= formatD("%sif(%s) {", i ? "else "d : ""d, condition);
            if (c.name.length)
                result ~= formatD("volatile delegua_value %s=%s->error;", cName(c.name), inner) ~ acknowledgeBinding(
                        cName(c.name));
            foreach (Node child; c.body)
                result ~= compileStmtOrdered(child);
            result ~= "}";
        }
        result ~= (node.catches.length ? "else "d : ""d) ~ formatD("{delegua_falhar(%s->error);}", inner);
        result ~= "}";
        result ~= formatD("delegua_sair_tente(%s);", outer);
        cleanups.length--;
        foreach (Node child; node.finalBody)
            result ~= compileStmtOrdered(child);
        result ~= formatD("} else { delegua_sair_tente(%s);", outer);
        foreach (Node child; node.finalBody)
            result ~= compileStmtOrdered(child);
        result ~= formatD("delegua_falhar(%s->error); } }", outer);
        return location(node) ~ ";\n" ~ result.join("\n");
    }

    private bool isAlreadyMaterializedNode(Node node)
    {
        if (node is null)
            return false;
        switch (node.kind)
        {
            case NodeKind.IntLit:
            case NodeKind.DoubleLit:
            case NodeKind.BoolLit:
            case NodeKind.NullLit:
            case NodeKind.StringLit:
            case NodeKind.FunctionExpr:
            case NodeKind.ConditionalExpr:
            case NodeKind.LoopExpr:
            case NodeKind.Comprehension:
            case NodeKind.MapLit:
            case NodeKind.ArrayLit:
            case NodeKind.BinaryExpr:
            case NodeKind.AssignStmt:
                return true;
            default:
                return false;
        }
    }

    private bool isImmutableIdentifier(Identifier id)
    {
        if (id is null)
            return false;
        if (id.value == "isto" || id.classRef !is null || id.functionRef !is null)
            return true;
        if (id.variableRef !is null && id.variableRef.isConst)
            return true;
        return false;
    }

    private bool isPureConstantNode(Node node)
    {
        if (node is null)
            return true;
        switch (node.kind)
        {
            case NodeKind.IntLit:
            case NodeKind.DoubleLit:
            case NodeKind.BoolLit:
            case NodeKind.NullLit:
            case NodeKind.StringLit:
                return true;
            case NodeKind.MemberExpr:
                return (cast(MemberExpr) node).enumValue !is null;
            default:
                return false;
        }
    }

    private bool isSafeDirectMapKey(Node key)
    {
        if (key is null)
            return false;
        switch (key.kind)
        {
            case NodeKind.StringLit:
            case NodeKind.IntLit:
            case NodeKind.DoubleLit:
            case NodeKind.BoolLit:
                return true;
            case NodeKind.MemberExpr:
                return (cast(MemberExpr) key).enumValue !is null;
            default:
                return false;
        }
    }

    private bool canChangeLocalSite(Node node)
    {
        if (node is null)
            return false;
        switch (node.kind)
        {
            case NodeKind.IntLit:
            case NodeKind.DoubleLit:
            case NodeKind.BoolLit:
            case NodeKind.NullLit:
            case NodeKind.StringLit:
            case NodeKind.FunctionExpr:
            case NodeKind.Identifier:
            case NodeKind.BinaryExpr:
            case NodeKind.ConditionalExpr:
            case NodeKind.LoopExpr:
            case NodeKind.Comprehension:
            case NodeKind.MapLit:
            case NodeKind.ArrayLit:
            case NodeKind.AssignStmt:
            case NodeKind.UnaryExpr:
                return false;
            case NodeKind.MemberExpr:
                return (cast(MemberExpr) node).enumValue is null;
            case NodeKind.BlockStmt:
                BlockStmt blk = cast(BlockStmt) node;
                return blk.body.length > 0 && canChangeLocalSite(blk.body[$ - 1]);
            case NodeKind.CallExpr:
                CallExpr call = cast(CallExpr) node;
                if (!canFail(call))
                    return call.args.any!((Node a) => canChangeLocalSite(a));
                return true;
            default:
                return canFail(node);
        }
    }

    private bool canMutateVar(Node subtree, dstring varName)
    {
        if (subtree is null)
            return false;
        if (cast(ImportExpr) subtree || cast(ModuleUnit) subtree || cast(FnDecl) subtree
                || cast(ClassDecl) subtree || cast(FunctionExpr) subtree)
            return false;
        if (AssignStmt assign = cast(AssignStmt) subtree)
        {
            if (Identifier id = cast(Identifier) assign.left)
                if (id.value == varName)
                    return true;
        }
        else if (UnaryExpr unary = cast(UnaryExpr) subtree)
        {
            if (unary.op == TokenKind.PPlus || unary.op == TokenKind.MMinus)
                if (Identifier id = cast(Identifier) unary.value)
                    if (id.value == varName)
                        return true;
        }
        else if (CallExpr call = cast(CallExpr) subtree)
        {
            if (!call.runtimeCall)
                return true;
        }
        else if (cast(RoutineExpr) subtree || cast(AwaitExpr) subtree)
        {
            return true;
        }
        foreach (Node child; childNodes(subtree))
            if (canMutateVar(child, varName))
                return true;
        return false;
    }

    private bool siblingsCanMutateVar(Node[] siblings, dstring varName)
    {
        foreach (Node s; siblings)
            if (canMutateVar(s, varName))
                return true;
        return false;
    }

    private bool exprReferencesVar(Node subtree, dstring varName)
    {
        if (subtree is null)
            return false;
        if (cast(ImportExpr) subtree || cast(ModuleUnit) subtree || cast(FnDecl) subtree
                || cast(ClassDecl) subtree || cast(FunctionExpr) subtree)
            return false;
        if (Identifier id = cast(Identifier) subtree)
            if (id.value == varName)
                return true;
        foreach (Node child; childNodes(subtree))
            if (exprReferencesVar(child, varName))
                return true;
        return false;
    }

    public dstring materialize(Node node, bool allowMutableVar = false)
    {
        dstring expr = compileExpr(node);
        // Construtores escalares, textos literais, temporários recém-gerados e
        // identificadores imutáveis não exigem cópia extra em cgd_tmp.
        if (isAlreadyMaterializedNode(node))
            return expr;
        if (Identifier id = cast(Identifier) node)
        {
            if (id.value != currentDeclaringVar && (isImmutableIdentifier(id) || allowMutableVar))
                return expr;
        }
        dstring name = formatD("cgd_tmp_%d", tmp++);
        emitLocal(formatD("%s %s = %s;", VALUE, name, expr));
        return name;
    }

    package dstring captureExpr(Node node, out dstring expression)
    {
        pushFrame();
        expression = compileExpr(node);
        return popFrame().join("\n");
    }

    dstring loopCode(Node condition, Node[] body, Node step = null, bool post = false)
    {
        dstring label = formatD("cgd_continue_%d", tmp++);
        bool emitSp = memoryPlan is null || memoryPlan.config.enableSafepoints;
        dstring spCounter = emitSp ? formatD("cgd_sp_%d", tmp++) : ""d;
        enterLoop(label);
        pushDetScope();
        dstring setup;
        dstring testExpr = condition is null ? ""d : compileCondition(condition, setup);
        dstring check = ""d;
        if (condition !is null)
            check = setup.length ? setup ~ formatD("\nif (!(%s)) break;",
                    testExpr) : formatD("if (!(%s)) break;", testExpr);
        dstring[] result;
        if (emitSp)
            result ~= formatD("{ u32 %s = 0; while (1) {", spCounter);
        else
            result ~= "while (1) {"d;
        if (emitSp)
            result ~= formatD("if (DELEGUA_UNLIKELY((++%s & 1023U) == 0U)) cgd_gc_safepoint();", spCounter);
        if (!post && check.length)
            result ~= check;
        foreach (Node child; body)
            result ~= compileStmtOrdered(child);
        dstring detBodyFree = popDetScopeCode();
        if (detBodyFree.length)
            result ~= detBodyFree;
        dstring contLabel = labelDeclaration(label);
        if (contLabel.length)
            result ~= contLabel;
        if (step !is null)
            result ~= compileStmtOrdered(step);
        if (post && check.length)
            result ~= check;
        result ~= "}";
        dstring brkLabel = labelDeclaration(label ~ "_break");
        if (brkLabel.length)
            result ~= brkLabel;
        if (emitSp)
            result ~= "}";
        leaveLoop(label);
        return result.join("\n");
    }

    dstring[] includes = [
        `#include <math.h>`,
        `#include "vendor/delegua-runtime/src/delegua_rt.h"`,
        `#include "vendor/delegua-runtime/src/assincrono.h"`
    ];

    dstring[] prototypes = ["\n/* protótipos */",];

    dstring[] code = ["\n\n/* código */"];

    dstring[][] pendingStack;

    pragma(inline, true) void pushFrame()
    {
        pendingStack ~= (dstring[]).init;
    }

    pragma(inline, true) dstring[] popFrame()
    {
        dstring[] top = pendingStack[$ - 1];
        pendingStack.length -= 1;
        return top;
    }

    pragma(inline, true) dstring genIndent(uint indent = 0)
    {
        dstring buffer;
        while (indent-- > 0)
            buffer ~= " ";
        return buffer;
    }

    package pragma(inline, true) void emit(dstring line, uint indent = 0)
    {
        code ~= genIndent(indent) ~ line;
    }

    // emitLocal(): vai para o frame local do topo da pilha, se
    // houver um aberto; caso contrário cai no buffer global (isso
    // preserva o comportamento antigo fora de qualquer frame, ex.
    // no nível de compile()/compileFnDecl(), que já emitem direto).
    pragma(inline, true) void emitLocal(dstring line, uint indent = 0)
    {
        if (pendingStack.length > 0)
            pendingStack[$ - 1] ~= genIndent(indent) ~ line;
        else
            emit(line, indent);
    }

    package pragma(inline, true) void emitProto(dstring line, uint indent = 0)
    {
        prototypes ~= genIndent(indent) ~ line;
    }

    public dstring compileStmt(Node node)
    {
        if (node is null)
            return "/* Nó nulo recebido no codegen */";
        if (node.kind == NodeKind.NaN)
            return "/* NaN */";
        switch (node.kind)
        {
            case NodeKind.SequenceStmt:
                dstring[] statements;
                foreach (Node child; (cast(SequenceStmt) node).body)
                    statements ~= compileStmtOrdered(child);
                return statements.join("\n");
            case NodeKind.EachStmt:
                EachStmt loop = cast(EachStmt) node;
                dstring iterable = materialize(loop.iterable, false);
                dstring idx = formatD("cgd_idx_%d", tmp++);
                dstring label = formatD("cgd_continue_%d", tmp++);
                bool emitSp = memoryPlan is null || memoryPlan.config.enableSafepoints;
                enterLoop(label);
                pushDetScope();
                dstring[] body;
                if (emitSp)
                    body ~= formatD("if (DELEGUA_UNLIKELY((%s & 1023U) == 0U)) cgd_gc_safepoint();", idx);
                if (loop.bindingType !is null && loop.bindingType.toStr() != "qualquer")
                    body ~= atSite(formatD("%s=%s", cName(loop.name), checked(cName(loop.name),
                            loop.bindingType)), loop.pos) ~ ";";
                foreach (size_t i, dstring name; loop.destructured)
                {
                    dstring element = formatD("delegua_obter(%s,create_num(%s))", cName(loop.name), i);
                    TypeExpr type = i < loop.destructuredTypes.length ? loop.destructuredTypes[i] : null;
                    body ~= formatD("%s %s=%s;", localValueDecl(), cName(name),
                            atSite(checked(element, type), loop.pos)) ~ acknowledgeLocal(cName(name));
                }
                foreach (Node child; loop.body)
                    body ~= compileStmtOrdered(child);
                dstring detEachFree = popDetScopeCode();
                if (detEachFree.length)
                    body ~= detEachFree;
                leaveLoop(label);
                return formatD("for (sz %s = 0; %s < delegua_tamanho(%s); ++%s) {\n%s %s = delegua_iterar(%s, %s);\n%s\n%s\n%s\n}\n%s",
                        idx, idx, iterable, idx, localValueDecl(), cName(loop.name), iterable,
                        idx, acknowledgeLocal(cName(loop.name)), body.join("\n"),
                        labelDeclaration(label), labelDeclaration(label ~ "_break"));
            case NodeKind.TryStmt:
                return compileTry(cast(TryStmt) node);
            case NodeKind.ThrowStmt:
                dstring thrown = materialize((cast(ThrowStmt) node).value, true);
                return location(node) ~ ";" ~ formatD("delegua_falhar(%s);", thrown);
            case NodeKind.ForStmt:
                ForStmt loop = cast(ForStmt) node;
                dstring init = loop.init is null ? ""d : compileStmtOrdered(loop.init);
                return init.length ? "{\n" ~ init ~ "\n" ~ loopCode(loop.condition, loop.body,
                        loop.step) ~ "\n}" : "{\n" ~ loopCode(loop.condition, loop.body, loop.step) ~ "\n}";
            case NodeKind.DoStmt:
                DoStmt loop = cast(DoStmt) node;
                return loopCode(loop.condition, loop.body, null, true);
            case NodeKind.BreakStmt:
                referencedLabels[breakLabels[$ - 1]] = true;
                dstring bDet = detFreeCode(breakDetScopeDepth[$ - 1]);
                dstring bClean = cleanupCode(breakTryDepth[$ - 1]);
                dstring bPrefix = bDet.length ? (bClean.length ? bDet ~ "\n" ~ bClean : bDet) : bClean;
                return bPrefix.length ? bPrefix ~ "\ngoto " ~ breakLabels[$ - 1] ~ ";" : "goto " ~ breakLabels[$ - 1]
                    ~ ";";
            case NodeKind.ContinueStmt:
                referencedLabels[continueLabels[$ - 1]] = true;
                dstring cDet = detFreeCode(loopDetScopeDepth[$ - 1]);
                dstring cClean = cleanupCode(loopTryDepth[$ - 1]);
                dstring cPrefix = cDet.length ? (cClean.length ? cDet ~ "\n" ~ cClean : cDet) : cClean;
                return cPrefix.length ? cPrefix ~ "\ngoto " ~ continueLabels[$ - 1] ~ ";" : "goto "
                    ~ continueLabels[$ - 1] ~ ";";
            case NodeKind.VarDecl:
                VarDecl var = cast(VarDecl) node;
                const(LocalAllocPlan)* lp = memoryPlan !is null ? memoryPlan.localPlanOf(var) : null;
                if (lp !is null && lp.domain == StorageDomain.StackLocal && lp.stackClass !is null)
                {
                    if (CallExpr ctorCall = cast(CallExpr) var.value)
                    {
                        dstring prevDeclaringS = currentDeclaringVar;
                        currentDeclaringVar = var.name;
                        dstring stkBuf = formatD("cgd_stk_%s", tmp++);
                        dstring cargs = nodesToStr(ctorCall.args);
                        currentDeclaringVar = prevDeclaringS;
                        size_t bufSlots = lp.stackSlots + 1;
                        emitLocal(formatD("union { long double _a; delegua_value _v; unsigned char _b[128 + %s * sizeof(delegua_value)]; } %s;",
                                bufSlots, stkBuf));
                        dstring initCall = formatD("delegua_init_stack_objeto(%s._b, sizeof(%s._b), %s, %s, %s)",
                                stkBuf, stkBuf, classValue(lp.stackClass), ctorCall.args.length,
                                ctorCall.args.length ? "(delegua_value[]){" ~ cargs ~ "}" : "NULL");
                        dstring siteInit = atSite(initCall, ctorCall.pos);
                        return formatD("%s %s = %s;", localValueDecl(), cName(var.name), checked(siteInit,
                                var.uninitialized ? null : var.type_expr, var.pos, var.value)) ~ acknowledgeLocal(
                                cName(var.name));
                    }
                }
                dstring prevDeclaring = currentDeclaringVar;
                currentDeclaringVar = var.name;
                bool selfRef = exprReferencesVar(var.value, var.name);
                dstring initial = selfRef ? materialize(var.value, false) : compileExpr(var.value);
                currentDeclaringVar = prevDeclaring;
                if (!var.uninitialized && isValueTypeExpr(var.value))
                    initial = formatD("delegua_clonar(%s)", initial);
                if (lp !is null && lp.domain == StorageDomain.DeterministicHeap && lp.freeAtScopeExit
                        && detFreeScopes.length > 0)
                    detFreeScopes[$ - 1] ~= cName(var.name);
                return formatD("%s %s = %s;", localValueDecl(), cName(var.name), checked(initial,
                        var.uninitialized ? null : var.type_expr, var.pos, var.value)) ~ acknowledgeLocal(
                        cName(var.name));

            case NodeKind.ReturnStmt:
                ReturnStmt ret = cast(ReturnStmt) node;
                bool anyDetFree = hasDetFreeVars(ret.collectionReturn ? collectors[$ - 1].detDepth : 0);
                bool needsSnapshot = cleanups.length > 0 || anyDetFree || ret.collectionReturn || emitDebugLines;
                dstring value = ret.val is null ? "create_nulo()"d : (needsSnapshot
                        ? materialize(ret.val, !emitDebugLines && cleanups.length == 0 && !anyDetFree)
                        : compileExpr(ret.val));
                if (ret.collectionReturn)
                {
                    Collector collector = collectors[$ - 1];
                    referencedLabels[collector.label] = true;
                    dstring rDet = detFreeCode(collector.detDepth);
                    dstring rClean = cleanupCode(collector.depth);
                    dstring rPrefix = rDet.length ? (rClean.length ? rDet ~ "\n" ~ rClean : rDet) : rClean;
                    dstring stmt = formatD("delegua_vetor_adicionar(&%s,%s); goto %s;",
                            collector.output, value, collector.label);
                    return rPrefix.length ? rPrefix ~ "\n" ~ stmt : stmt;
                }
                dstring rDetAll = detFreeCode(0);
                dstring clean = cleanupCode(0);
                dstring prefix = rDetAll.length ? (clean.length ? rDetAll ~ "\n" ~ clean : rDetAll) : clean;
                dstring retStmt = formatD("return %s;", checked(value, functionReturn, ret.pos, ret.val));
                return prefix.length ? prefix ~ "\n" ~ retStmt : retStmt;

            case NodeKind.UnaryExpr:
                UnaryExpr unary = cast(UnaryExpr) node;
                if (unary.op == TokenKind.PPlus || unary.op == TokenKind.MMinus)
                {
                    LValue target = resolveLValue(unary.value);
                    dstring updated = atSite(formatD("delegua_op_%s(%s,create_num(1))",
                            unary.op == TokenKind.PPlus ? "add" : "sub", target.read()), unary.pos);
                    return atSite(target.write(checked(updated, unary.value.type_expr, unary.pos)), unary.pos) ~ ";";
                }
                return "(void)(" ~ compileExpr(node) ~ ");";
            case NodeKind.RoutineExpr:
            case NodeKind.CallExpr:
                return "(void)(" ~ compileExpr(node) ~ ");";

            case NodeKind.IfStmt:
                return compileIfStmt(to!IfStmt(node));

            case NodeKind.AssignStmt:
                return compileAssignment(cast(AssignStmt) node, false);
            case NodeKind.SwitchStmt:
                return compileSwitch(cast(SwitchStmt) node);
            case NodeKind.NaN:
                return ";";
            case NodeKind.BlockStmt:
                BlockStmt block = cast(BlockStmt) node;
                pushDetScope();
                dstring[] body;

                foreach (Node child; block.body)
                    body ~= compileStmtOrdered(child);
                dstring detBlkFree = popDetScopeCode();
                if (detBlkFree.length)
                    body ~= detBlkFree;

                return "{\n" ~ body.join("\n") ~ "\n}";

            case NodeKind.WhileStmt:
                WhileStmt wstmt = cast(WhileStmt) node;
                return loopCode(wstmt.expr, wstmt.body);

            case NodeKind.ClassDecl:
            case NodeKind.FnDecl:
                return ";";
            case NodeKind.MemberExpr:
                return "(void)(" ~ compileExpr(node) ~ ");";

            case NodeKind.ArrayLit:
            case NodeKind.TupleLit:
            case NodeKind.MapLit:
            case NodeKind.IndexExpr:
            case NodeKind.BinaryExpr:
            case NodeKind.ConditionalExpr:
            case NodeKind.SliceExpr:
            case NodeKind.LoopExpr:
            case NodeKind.Comprehension:
            case NodeKind.FunctionExpr:
            case NodeKind.ImportExpr:
            case NodeKind.Identifier:
            case NodeKind.StringLit:
            case NodeKind.IntLit:
            case NodeKind.DoubleLit:
            case NodeKind.BoolLit:
            case NodeKind.NullLit:
            case NodeKind.TypeOfExpr:
            case NodeKind.SuperExpr:
                return "(void)(" ~ compileExpr(node) ~ ");";
            default:
                throw new Exception("Comando não suportado no backend C.");
        }
    }

    // -------------------------------------------------------------
    // compileStmtOrdered: abre um frame local, roda compileStmt(),
    // e devolve TODOS os efeitos colaterais gerados durante essa
    // chamada seguidos da linha final do statement, na ordem
    // correta. É isso que garante que side effects de UM statement
    // nunca vazem para antes de statements anteriores do mesmo
    // bloco (o bug do `i++` saindo antes de `a_bits`/`b_bits`).
    // -------------------------------------------------------------
    private dstring debugLineDirective(Node node)
    {
        if (!emitDebugLines || node is null || node.pos is null || !node.pos.filename.length || node.pos.start.line == 0)
            return ""d;
        import std.path : absolutePath, asNormalizedPath;

        string absFile = absolutePath(node.pos.filename).asNormalizedPath.to!string;
        dstring escaped;
        foreach (char ch; absFile)
        {
            if (ch == '\\' || ch == '"')
                escaped ~= '\\';
            escaped ~= ch;
        }
        return formatD("\n#line %s \"%s\"\n", node.pos.start.line, escaped);
    }

    dstring compileStmtOrdered(Node node)
    {
        pushFrame();
        dstring result = compileStmt(node);
        dstring[] sideEffects = popFrame();

        dstring lineDir = debugLineDirective(node);
        if (!lineDir.length)
        {
            if (sideEffects.length == 0)
                return result;
            return (sideEffects ~ result).join("\n");
        }
        dstring combined = sideEffects.length == 0 ? result : (sideEffects ~ result).join("\n");
        // Em modo de depuração, prefixa cada linha física gerada para este statement com o mesmo #line
        // para que declarações multi-linha (ex: vetores/mapas) não desloquem o número da linha no DWARF.
        if (cast(IfStmt) node || cast(WhileStmt) node || cast(ForStmt) node || cast(DoStmt) node
                || cast(EachStmt) node || cast(TryStmt) node || cast(SwitchStmt) node
                || cast(BlockStmt) node || cast(SequenceStmt) node)
            return lineDir ~ combined;
        import std.string : splitLines;

        dstring[] physLines = combined.splitLines();
        dstring[] tagged;
        foreach (dstring l; physLines)
            if (l.length)
                tagged ~= lineDir ~ l;
        return tagged.join("\n");
    }

    private ptrdiff_t siteIndex(Position pos)
    {
        if (pos is null)
            return -1;
        string key = format("%s:%s:%s", pos.filename, pos.start.line, pos.start.offset);
        if (size_t* cached = key in sourceSiteIds)
            return cast(ptrdiff_t)(*cached);
        size_t fileIdx;
        if (size_t* cachedFile = pos.filename in sourceFileIds)
            fileIdx = *cachedFile;
        else
        {
            fileIdx = sourceFileDecls.length;
            sourceFileIds[pos.filename] = fileIdx;
            sourceFileDecls ~= formatD("static const char cgd_file_%s[]=%s;", fileIdx,
                    cString(pos.filename.to!dstring));
        }
        size_t index = sourceSites.length;
        sourceSiteIds[key] = index;
        sourceSites ~= formatD("{cgd_file_%s,%s,%s}", fileIdx, pos.start.line, pos.start.offset);
        return cast(ptrdiff_t) index;
    }

    package dstring location(Position pos)
    {
        ptrdiff_t index = siteIndex(pos);
        return index < 0 ? ""d : formatD("delegua_local_atual=&cgd_source_sites[%s]", index);
    }

    private dstring sitePtr(Position pos)
    {
        ptrdiff_t index = siteIndex(pos);
        return index < 0 ? "NULL"d : formatD("&cgd_source_sites[%s]", index);
    }

    package dstring location(Node node)
    {
        return node is null ? ""d : location(node.pos);
    }

    dstring atSite(dstring expression, Position pos)
    {
        dstring site = location(pos);
        return site.length ? "(" ~ site ~ ", " ~ expression ~ ")" : expression;
    }

    bool canFail(Node node)
    {
        if (node is null)
            return false;
        switch (node.kind)
        {
            case NodeKind.CallExpr:
                CallExpr call = cast(CallExpr) node;
                if (call.runtimeCall)
                {
                    dstring opName = (cast(Identifier) call.fn).value;
                    if (opName == "delegua_op_eq" || opName == "delegua_op_neq" || opName == "delegua_op_not")
                        return false;
                }
                return true;
            case NodeKind.RoutineExpr:
            case NodeKind.IndexExpr:
            case NodeKind.MemberExpr:
            case NodeKind.SliceExpr:
            case NodeKind.ImportExpr:
                return true;
            default:
                return false;
        }
    }

    public dstring compileExpr(Node node)
    {
        if (node !is null && (cast(ArrayLit) node || cast(MapLit) node || cast(Comprehension) node))
        {
            dstring site = location(node);
            if (site.length)
                emitLocal(site ~ ";");
        }
        dstring expression = compileExprIntern(node);
        dstring site = canFail(node) ? location(node) : ""d;
        return site.length ? "(" ~ site ~ ", " ~ expression ~ ")" : expression;
    }

    private dstring compileExprIntern(Node node)
    {
        if (node is null)
            return "/* Nó nulo recebido no codegen */";
        if (node.kind == NodeKind.NaN)
            return "/* NaN */";

        switch (node.kind)
        {
            case NodeKind.AssignStmt:
                return compileAssignment(cast(AssignStmt) node);
            case NodeKind.SpreadExpr:
                throw new Exception("Espalhamento fora de chamada/coleção.");
            case NodeKind.ConditionalExpr:
                ConditionalExpr c = cast(ConditionalExpr) node;
                dstring condSetup;
                dstring condExpr = compileCondition(c.condition, condSetup);
                dstring resultName = formatD("cgd_cond_%s", tmp++);
                emitLocal(formatD("delegua_value %s;", resultName));
                if (condSetup.length)
                    emitLocal(condSetup);
                dstring yes, no;
                dstring yesSetup = captureExpr(c.yes, yes), noSetup = captureExpr(c.no, no);
                dstring yesBranch = yesSetup.length ? formatD("%s\n%s=%s;", yesSetup, resultName,
                        yes) : formatD("%s=%s;", resultName, yes);
                dstring noBranch = noSetup.length ? formatD("%s\n%s=%s;", noSetup, resultName,
                        no) : formatD("%s=%s;", resultName, no);
                emitLocal(formatD("if(%s){%s}else{%s}", condExpr, yesBranch, noBranch));
                return resultName;
            case NodeKind.SliceExpr:
                SliceExpr s = cast(SliceExpr) node;
                Node[3] tailNodes = [s.start, s.end, s.step];
                bool allowVal = true;
                if (Identifier idVal = cast(Identifier) s.value)
                    allowVal = !siblingsCanMutateVar(tailNodes[], idVal.value);
                dstring value = materialize(s.value, allowVal);
                Node[2] afterStart = [s.end, s.step];
                bool allowStart = true;
                if (Identifier idStart = cast(Identifier) s.start)
                    allowStart = !siblingsCanMutateVar(afterStart[], idStart.value);
                dstring start = s.start is null ? "create_nulo()"d : materialize(s.start, allowStart);
                bool allowEnd = true;
                if (Identifier idEnd = cast(Identifier) s.end)
                    allowEnd = !canMutateVar(s.step, idEnd.value);
                dstring end = s.end is null ? "create_nulo()"d : materialize(s.end, allowEnd);
                dstring step = s.step is null ? "create_nulo()"d : materialize(s.step, true);
                return formatD("delegua_intervalo(%s,%s,%s,%s)", value, start, end, step);
            case NodeKind.LoopExpr:
                LoopExpr l = cast(LoopExpr) node;
                dstring resultName = formatD("cgd_loop_%s", tmp++);
                emitLocal(formatD("delegua_value %s=create_vetor();", resultName));
                dstring oldPending = pendingCollector;
                pendingCollector = resultName;
                emitLocal(compileStmtOrdered(l.loop));
                pendingCollector = oldPending;
                return resultName;
            case NodeKind.Comprehension:
                Comprehension c = cast(Comprehension) node;
                dstring source = materialize(c.iterable, false);
                dstring resultName = formatD("cgd_comp_%s", tmp++), idx = formatD("cgd_comp_i_%s", tmp++);
                emitLocal(formatD("delegua_value %s=create_vetor();", resultName));
                dstring value, condition;
                dstring valueSetup = captureExpr(c.value, value);
                dstring condSetup = c.condition is null ? ""d : captureExpr(c.condition, condition);
                dstring body = formatD("%s\ndelegua_vetor_adicionar(&%s,%s);", valueSetup, resultName, value);
                if (c.condition !is null)
                    body = formatD("%s\nif(%s){%s}", condSetup, truthyExpr(c.condition, condition), body);
                emitLocal(formatD("for(sz %s=0;%s<delegua_tamanho(%s);++%s){%s %s=%s;%s}", idx, idx, source, idx,
                        localValueDecl(), cName(c.name), checked(formatD("delegua_iterar(%s,%s)",
                        source, idx), c.bindingType, c.pos), acknowledgeLocal(cName(c.name)) ~ body));
                return resultName;
            case NodeKind.Identifier:
                Identifier id = cast(Identifier) node;
                if (id.moduleRef !is null)
                {
                    dstring modName = cName(id.moduleRef.linkName);
                    return formatD("(%s_init(), %s)", modName, modName);
                }
                if (id.classRef !is null)
                    return classValue(id.classRef);
                return id.functionRef is null ? cName(id.value) : functionValue(id.functionRef);

            case NodeKind.UnaryExpr:
                UnaryExpr unary = cast(UnaryExpr) node;
                LValue lv = resolveLValue(unary.value);
                dstring previous = formatD("cgd_tmp_%d", tmp++);
                dstring updated = formatD("cgd_tmp_%d", tmp++);
                dstring site = location(node);
                if (site.length)
                    emitLocal(site ~ ";");
                emitLocal(formatD("%s %s = %s;", VALUE, previous, lv.read()));
                emitLocal(formatD("%s %s = %s;", VALUE, updated, atSite(formatD("delegua_op_%s(%s,create_num(1))",
                        unary.op == TokenKind.PPlus ? "add" : "sub", previous), node.pos)));
                emitLocal(atSite(lv.write(updated), node.pos) ~ ";");
                return unary.post ? previous : updated;
            case NodeKind.MapLit:
                MapLit map = cast(MapLit) node;
                dstring name = formatD("cgd_map_%d", tmp++);
                emitLocal(formatD("%s %s = create_map();", VALUE, name));
                foreach (size_t i, Node key; map.keys)
                {
                    if (key is null)
                    {
                        SpreadExpr spread = cast(SpreadExpr) map.values[i];
                        emitLocal(formatD("delegua_map_expandir(%s,%s);", name, materialize(spread.value, true)));
                        continue;
                    }
                    if (isSafeDirectMapKey(key))
                    {
                        dstring k = compileExpr(key);
                        dstring v = compileExpr(map.values[i]);
                        emitLocal(formatD("delegua_map_setar(%s, %s, %s);", name, k, v));
                        continue;
                    }
                    bool allowKey = true;
                    if (Identifier idKey = cast(Identifier) key)
                        allowKey = !canMutateVar(map.values[i], idKey.value);
                    dstring k = materialize(key, allowKey);
                    dstring v = materialize(map.values[i], true);
                    emitLocal(formatD("delegua_map_setar(%s, %s, %s);", name, k, v));
                }
                if (map.readonly)
                    emitLocal(formatD("delegua_map_congelar(%s);", name));
                return name;
            case NodeKind.NullLit:
                return "create_nulo()";
            case NodeKind.BinaryExpr:
                BinaryExpr binary = cast(BinaryExpr) node;
                dstring left = materialize(binary.left, true);
                dstring result = formatD("cgd_tmp_%d", tmp++);
                emitLocal(formatD("%s %s = %s;", VALUE, result, left));
                dstring condition = binary.op == TokenKind.And ? truthyExpr(binary.left,
                        left) : binary.op == TokenKind.Or ? ("!"d ~ truthyExpr(binary.left,
                        left)) : formatD("%s.type == DELEGUA_T_NULO", left);
                dstring right;
                dstring setup = captureExpr(binary.right, right);
                emitLocal(formatD("if (%s) {\n%s\n%s = %s;\n}", condition, setup, result, right));
                return result;
            case NodeKind.ImportExpr:
                ImportExpr imported = cast(ImportExpr) node;
                dstring name = cName(imported.target.linkName);
                return formatD("(%s_init(), %s)", name, name);
            case NodeKind.SuperExpr:
                SuperExpr superExpr = cast(SuperExpr) node;
                return formatD("delegua_super_metodo(%s, %s, %s)", lexicalClass(),
                        asyncSelf.length ? asyncSelf : cName("isto"), cString(superExpr.name));
            case NodeKind.FunctionExpr:
                return functionValue((cast(FunctionExpr) node).declaration);
            case NodeKind.MemberExpr:
                MemberExpr member = cast(MemberExpr) node;
                if (member.enumValue !is null)
                    return compileExpr(member.enumValue);
                if (member.resolvedModule !is null)
                {
                    dstring modName = cName(member.resolvedModule.linkName);
                    return formatD("(%s_init(), %s)", modName, modName);
                }
                dstring receiver = materialize(member.left, true);
                return formatD("delegua_prop_ic(%s, %s, %s, %s)", receiver,
                        cString((cast(Identifier) member.right).value), lexicalClass(), nextIcSlot());
            case NodeKind.StringLit:
                dstring text = (cast(StringLit) node).value;
                return formatD("create_text_lit(%s, %s)", cString(text), text.to!string.length);

            case NodeKind.IntLit:
                long integer = (cast(IntLit) node).value;
                return integer == long.min ? "create_num(INT64_MIN)" : formatD("create_num(%d)", integer);

            case NodeKind.DoubleLit:
                double realValue = (cast(DoubleLit) node).value;
                if (!isFinite(realValue))
                    throw new Exception("Literal real não finito no backend C.");
                dstring realLiteral = formatD("%.17g", realValue);
                if (!realLiteral.canFind('.') && !realLiteral.canFind('e') && !realLiteral.canFind('E'))
                    realLiteral ~= ".0";
                return "create_real(" ~ realLiteral ~ ")";

            case NodeKind.BoolLit:
                return formatD("create_bool(%d)", (cast(BoolLit) node).value);

            case NodeKind.RoutineExpr:
                RoutineExpr routine = cast(RoutineExpr) node;
                if (!cast(Identifier) routine.call.fn)
                    cast(void) materialize(routine.call.fn);
                dstring rargs = nodesToStr(routine.call.args);
                return formatD("delegua_rotina_iniciar(%s, %s, %s, %s)", cName(routine.target.linkName),
                        routine.call.args.length, routine.call.args.length
                        ? "(delegua_value[]){" ~ rargs ~ "}" : "NULL", descriptor(routine.resultType));
            case NodeKind.CallExpr:
                CallExpr call = cast(CallExpr) node;
                if (call.runtimeCall)
                    return formatD("%s(%s)", (cast(Identifier) call.fn).value, nodesToStr(call.args, !canFail(call)));
                if (!call.args.any!((Node a) => a.kind == NodeKind.SpreadExpr))
                {
                    if (Identifier fnId = cast(Identifier) call.fn)
                    {
                        if (fnId.classRef is null && fnId.functionRef !is null
                                && fnId.functionRef.builtinName.length && call.args.length == 1)
                        {
                            dstring b = fnId.functionRef.builtinName;
                            if (b == "texto")
                                return formatD("delegua_para_texto(%s)", nodesToStr(call.args));
                            if (b == "tamanho")
                                return formatD("delegua_tamanho_val(%s)", nodesToStr(call.args));
                            if (b == "inteiro")
                                return formatD("delegua_conv_inteiro(%s)", nodesToStr(call.args));
                            if (b == "real")
                                return formatD("delegua_conv_real(%s)", nodesToStr(call.args));
                            if (b == "clonar")
                                return formatD("delegua_clonar(%s)", nodesToStr(call.args));
                            if (b == "destruir")
                                return formatD("delegua_destruir(%s)", nodesToStr(call.args));
                            if (b == "tupla")
                            {
                                if (memoryPlan is null || memoryPlan.config.enableCollectionFusion)
                                {
                                    if (ArrayLit al = cast(ArrayLit) call.args[0])
                                    {
                                        if (al.elements.length >= 2 && al.elements.length <= 10
                                                && !al.elements.any!((Node e) => e.kind == NodeKind.SpreadExpr))
                                        {
                                            if (memoryPlan !is null)
                                                memoryPlan.fusedTuplesCount++;
                                            return formatD("create_tupla(%s, (delegua_value[]){%s})",
                                                    al.elements.length, nodesToStr(al.elements));
                                        }
                                    }
                                }
                                return formatD("delegua_para_tupla(%s)", nodesToStr(call.args));
                            }
                            if (b == "leia")
                                return formatD("delegua_leia(%s)", nodesToStr(call.args));
                            if (isNativeCastName(b))
                                return emitManagedCCast(b, nodesToStr(call.args));
                        }
                        if (fnId.functionRef is null && fnId.classRef is null)
                        {
                            if (TypeSemaNativeContainer nc = cast(TypeSemaNativeContainer) call.type_sema)
                            {
                                if (nc.containerKind == NativeContainerKind.VetorNativo)
                                    return "create_vetor()"d;
                                if (nc.containerKind == NativeContainerKind.MapaNativo)
                                    return "create_map()"d;
                                if (nc.containerKind == NativeContainerKind.StringNativa)
                                    return `create_text("")`d;
                            }
                        }
                    }
                    bool needsModInit;
                    dstring modLinkName;
                    if (ClassDecl cls = resolveDirectConstructor(call, needsModInit, modLinkName))
                    {
                        dstring cargs = nodesToStr(call.args);
                        dstring inst = formatD("delegua_instanciar(%s, %s, %s)", classValue(cls),
                                call.args.length, call.args.length ? "(delegua_value[]){" ~ cargs ~ "}" : "NULL");
                        return needsModInit ? formatD("(%s_init(), %s)", cName(modLinkName), inst) : inst;
                    }
                    if (FnDecl target = resolveDirectCallee(call, needsModInit, modLinkName))
                    {
                        if (target.ownerClass !is null && target.ownerClass.signature.builtinName == "Matematica"d)
                            return emitManagedMathCall(target.fn, call.args);
                        if (ansCg !is null && ansCg.canSpecialize(target) && call.args.length == target.args.length)
                        {
                            dstring[] cargs;
                            cargs.reserve(call.args.length);
                            foreach (size_t ai, Node argNode; call.args)
                            {
                                if (isPureConstantNode(argNode))
                                    cargs ~= compileExpr(argNode);
                                else if (Identifier aid = cast(Identifier) argNode)
                                    cargs ~= materialize(argNode, !siblingsCanMutateVar(call.args[ai + 1 .. $], aid.value));
                                else
                                    cargs ~= materialize(argNode, true);
                            }
                            dstring ansCall = ansCg.emitDirectCallFromManaged(target, cargs);
                            return needsModInit ? formatD("(%s_init(), %s)", cName(modLinkName), ansCall) : ansCall;
                        }
                        dstring dargs = nodesToStr(call.args);
                        dstring directCall = formatD("delegua_chamar_direto(%s, %s, %s)", cName(target.linkName),
                                call.args.length, call.args.length ? "(delegua_value[]){" ~ dargs ~ "}" : "NULL");
                        return needsModInit ? formatD("(%s_init(), %s)", cName(modLinkName), directCall) : directCall;
                    }
                    if (MemberExpr member = cast(MemberExpr) call.fn)
                    {
                        if (member.enumValue is null)
                        {
                            Identifier rightId = cast(Identifier) member.right;
                            if (Identifier leftId = cast(Identifier) member.left)
                            {
                                if (rightId !is null && leftId.value == "StringNativa"d)
                                {
                                    if (rightId.value == "vazia"d)
                                        return `create_text("")`d;
                                    if (rightId.value == "criar"d && call.args.length == 1)
                                        return formatD("delegua_op_cast(%s, DELEGUA_T_TEXT)", nodesToStr(call.args));
                                }
                            }
                            if (rightId !is null && cast(TypeSemaNativeContainer) member.left.type_sema !is null)
                            {
                                TypeSemaNativeContainer mnc = cast(TypeSemaNativeContainer) member.left.type_sema;
                                dstring mrecv = materialize(member.left, true);
                                if (rightId.value == "paraVetor"d || rightId.value == "paraTexto"d
                                        || rightId.value == "paraDicionario"d)
                                    return formatD("delegua_clonar(%s)", mrecv);
                                if (rightId.value == "clonar"d)
                                    return formatD("delegua_clonar(%s)", mrecv);
                                if (rightId.value == "tamanho"d)
                                    return formatD("delegua_tamanho_val(%s)", mrecv);
                                if (rightId.value == "vazio"d || rightId.value == "vazia"d)
                                    return formatD("create_bool(delegua_tamanho(%s) == 0)", mrecv);
                                if (rightId.value == "liberar"d || rightId.value == "reservar"d)
                                    return "create_null()"d;
                                if (mnc.containerKind == NativeContainerKind.MapaNativo)
                                {
                                    if (rightId.value == "definir"d && call.args.length == 2)
                                        return formatD("delegua_map_setar(%s, %s, %s)", mrecv,
                                                materialize(call.args[0], true), materialize(call.args[1], true));
                                    if (rightId.value == "obter"d && call.args.length == 1)
                                        return formatD("delegua_map_obter(%s, %s)", mrecv,
                                                materialize(call.args[0], true));
                                }
                                if (mnc.containerKind == NativeContainerKind.StringNativa
                                        && rightId.value == "anexar"d && call.args.length == 1)
                                {
                                    if (Identifier sid = cast(Identifier) member.left)
                                        return formatD("(%s = delegua_op_add(%s, %s))", cName(sid.value),
                                                cName(sid.value), materialize(call.args[0], true));
                                    return formatD("delegua_op_add(%s, %s)", mrecv, materialize(call.args[0], true));
                                }
                            }
                            bool allowRecv = true;
                            if (Identifier recvId = cast(Identifier) member.left)
                                allowRecv = !siblingsCanMutateVar(call.args, recvId.value);
                            dstring receiver = materialize(member.left, allowRecv);
                            dstring margs = nodesToStr(call.args);
                            if ((memoryPlan is null || memoryPlan.config.enableDevirt)
                                    && reachabilityComputed && rightId !is null)
                            {
                                if (TypeSemaClass leftCls = cast(TypeSemaClass) member.left.type_sema)
                                {
                                    ClassDecl cls = leftCls.declaration;
                                    if (cls !is null && !cls.isAbstract && !cls.isInterface && !cls.isValueType
                                            && !cls.isForeign && cls !in classesWithSubclasses
                                            && !cls.signature.builtinName.length)
                                    {
                                        ClassMember cm = resolveClassMember(cls, rightId.value);
                                        if (cm.method !is null && !cm.method.isStatic && !cm.method.isAbstract
                                                && !cm.method.accessor && !hasEnvelope(cm.method)
                                                && !cm.method.builtinName.length && cm.method.linkName.length
                                                && isReachable(cm.method) && arityMatches(cm.method, call.args))
                                        {
                                            bool accessOk = cm.method.access == 0
                                                || (cm.method.access == 1 && currentClass is cm.method.ownerClass)
                                                || (cm.method.access == 2 && currentClass !is null
                                                    && isSubclassOrSame(currentClass, cm.method.ownerClass));
                                            if (accessOk)
                                            {
                                                size_t minA = 0;
                                                foreach (FnArg fa; cm.method.args)
                                                    if (fa.value is null && !fa.rest)
                                                        minA++;
                                                dstring maxA = cm.method.args.length && cm.method.args[$ - 1].rest
                                                    ? "((sz)-1)"d : cm.method.args.length.to!dstring;
                                                if (memoryPlan !is null)
                                                    memoryPlan.devirtCallSitesCount++;
                                                return formatD("delegua_chamar_metodo_fn(&%s, %s, %s, %s, %s, %s)",
                                                        cName(cm.method.linkName), minA, maxA, receiver,
                                                        call.args.length,
                                                        call.args.length ? "(delegua_value[]){" ~ margs ~ "}" : "NULL");
                                            }
                                        }
                                    }
                                }
                            }
                            return formatD("delegua_chamar_ic(%s, %s, %s, %s, %s, %s)", receiver,
                                    cString(rightId.value),
                                    lexicalClass(), call.args.length, call.args.length
                                    ? "(delegua_value[]){" ~ margs ~ "}" : "NULL", nextIcSlot());
                        }
                    }
                }
                dstring callee = materialize(call.fn, call.args.length == 0);
                if (call.args.any!((Node a) => a.kind == NodeKind.SpreadExpr))
                {
                    dstring vector = formatD("cgd_args_%s", tmp++);
                    emitLocal(formatD("delegua_value %s=create_vetor();", vector));
                    foreach (Node arg; call.args)
                    {
                        if (SpreadExpr spread = cast(SpreadExpr) arg)
                            emitLocal(formatD("delegua_expandir(&%s,%s);", vector, materialize(spread.value, true)));
                        else
                            emitLocal(formatD("delegua_vetor_adicionar(&%s,%s);", vector, materialize(arg, true)));
                    }
                    return formatD("delegua_chamar_vetor(%s,%s)", callee, vector);
                }
                dstring args = nodesToStr(call.args);
                return formatD("delegua_chamar(%s, %s, %s)", callee, call.args.length,
                        call.args.length ? "(delegua_value[]){" ~ args ~ "}" : "NULL");

            case NodeKind.TupleLit:
            case NodeKind.ArrayLit:
                ArrayLit arr = cast(ArrayLit) node;
                bool hasSpread = arr.elements.any!((Node e) => e.kind == NodeKind.SpreadExpr);
                bool allowFusion = memoryPlan is null || memoryPlan.config.enableCollectionFusion;
                if (node.kind == NodeKind.TupleLit && allowFusion && !hasSpread
                        && arr.elements.length >= 2 && arr.elements.length <= 10)
                {
                    if (memoryPlan !is null)
                        memoryPlan.fusedTuplesCount++;
                    return formatD("create_tupla(%s, (delegua_value[]){%s})",
                            arr.elements.length, nodesToStr(arr.elements));
                }

                dstring temp = formatD("t%d", tmp++);
                // cria uma variavel temporaria
                if (node.kind == NodeKind.ArrayLit && allowFusion && !hasSpread && arr.elements.length > 4)
                {
                    if (memoryPlan !is null)
                        memoryPlan.preSizedArraysCount++;
                    emitLocal(formatD("%s %s = create_vetor_cap(%s);", VALUE, temp, arr.elements.length));
                }
                else
                {
                    emitLocal(formatD("%s %s = create_vetor();", VALUE, temp));
                }

                foreach (Node element; arr.elements)
                    if (SpreadExpr spread = cast(SpreadExpr) element)
                        emitLocal(formatD("delegua_expandir(&%s,%s);", temp, materialize(spread.value)));
                    else
                        emitLocal(formatD("delegua_vetor_adicionar(&%s, %s);", temp, compileExpr(element)));

                return node.kind == NodeKind.TupleLit ? formatD("delegua_para_tupla(%s)", temp) : temp;

            case NodeKind.IndexExpr:
                return compileIndexExpr(cast(IndexExpr) node);

            case NodeKind.BlockStmt:
                BlockStmt block = cast(BlockStmt) node;
                pushDetScope();
                dstring[] body;

                foreach (Node child; block.body)
                    body ~= compileStmtOrdered(child);

                for (size_t i; i + 1 < block.body.length; i++)
                    emitLocal(body[i]);

                dstring lastVal = compileExpr(block.body[$ - 1]);
                dstring detExprFree = popDetScopeCode();
                if (detExprFree.length)
                {
                    dstring tmpRes = formatD("cgd_blk_%s", tmp++);
                    emitLocal(formatD("%s %s = %s;", VALUE, tmpRes, lastVal));
                    emitLocal(detExprFree);
                    return tmpRes;
                }
                return lastVal;

            default:
                node.print();
                return "/* expressão desconhecida. */";
        }
    }

    LValue resolveLValue(Node node, Node rhs = null)
    {
        switch (node.kind)
        {
            case NodeKind.MemberExpr:
                MemberExpr member = cast(MemberExpr) node;
                bool allowLeft = true;
                if (rhs !is null)
                    if (Identifier idLeft = cast(Identifier) member.left)
                        allowLeft = !canMutateVar(rhs, idLeft.value);
                return LValue(LValueKind.Member, null, materialize(member.left, allowLeft),
                        cString((cast(Identifier) member.right).value), lexicalClass(), nextIcSlot());
            case NodeKind.Identifier:
                return LValue(LValueKind.Var, cName((cast(Identifier) node).value));

            case NodeKind.IndexExpr:
                IndexExpr idx = cast(IndexExpr) node;
                bool allowVal = true;
                if (Identifier idVal = cast(Identifier) idx.value)
                    allowVal = !canMutateVar(idx.idx, idVal.value) && (rhs is null || !canMutateVar(rhs, idVal.value));
                bool allowIdx = true;
                if (rhs !is null)
                    if (Identifier idIdx = cast(Identifier) idx.idx)
                        allowIdx = !canMutateVar(rhs, idIdx.value);
                return LValue(LValueKind.Index, null, materialize(idx.value, allowVal),
                        materialize(idx.idx, allowIdx));

            default:
                node.print();
                assert(0, "nó não é um lvalue válido");
        }
    }

    dstring compileIndexExpr(IndexExpr idxexpr)
    {
        bool allowVal = true;
        if (Identifier idVal = cast(Identifier) idxexpr.value)
            allowVal = !canMutateVar(idxexpr.idx, idVal.value);
        dstring value = materialize(idxexpr.value, allowVal);
        dstring idx = materialize(idxexpr.idx, true);

        return formatD("delegua_obter(%s, %s)", value, idx);
    }

    bool[FnDecl] functionSlots;
    dstring functionValue(FnDecl node)
    {
        if (node.builtinName.length)
            return formatD("delegua_builtin(%s)", cString(node.builtinName));
        size_t minimum;
        foreach (FnArg arg; node.args)
            if (arg.value is null && !arg.rest)
                minimum++;
        dstring maximum = node.args.length && node.args[$ - 1].rest ? "((sz)-1)"d : node.args.length.to!dstring;
        if (node.anonymous)
            return formatD("create_funcao_intervalo(&%s,%s,%s)", cName(node.linkName), minimum, maximum);
        if (node !in functionSlots)
        {
            emitProto(formatD("static delegua_value %s_slot;", cName(node.linkName)));
            functionSlots[node] = true;
        }
        return formatD("delegua_funcao_cache(&%s_slot,&%s,%s,%s)", cName(node.linkName),
                cName(node.linkName), minimum, maximum);
    }

    void compileFnDecl(FnDecl node)
    {
        dstring proto = formatD("delegua_value %s(sz argc, delegua_value *argv)", cName(node.linkName));
        emitProto(proto ~ ";");
        if (node.isAsync && !node.isAbstract)
        {
            compileAsyncFn(node, proto);
            return;
        }
        if (node.foreignSymbol.length)
        {
            dstring[] parameterContracts;
            foreach (FnArg argument; node.args)
                parameterContracts ~= descriptor(argument.type_expr);
            emit(foreignWrapper(node, proto, descriptor(node.type_expr), parameterContracts));
            return;
        }
        if (node.isAbstract)
        {
            emit(proto ~ " { (void)argc; (void)argv; delegua_panic(\"Método abstrato.\"); return create_nulo(); }");
            return;
        }
        if (node.ownerClass !is null && node.ownerClass.isValueType && !node.accessor)
        {
            if (node.fn == "construtor"d)
                emit(nativeCg.emitManagedValueConstructor(node.ownerClass, proto));
            else
                emit(nativeCg.emitManagedThunk(node, proto));
            return;
        }
        if (node.isNative)
        {
            if (emitDebugLines)
                emit("#line 1 \"<cgd-runtime-init>\"");
            emit(nativeCg.emitManagedThunk(node, proto));
            return;
        }
        if (ansCg !is null && ansCg.canSpecialize(node))
        {
            if (emitDebugLines)
                emit("#line 1 \"<cgd-runtime-init>\"");
            emit(ansCg.emitManagedWrapper(node, proto));
            return;
        }
        ClassDecl previousClass = currentClass;
        currentClass = node.ownerClass;
        TypeExpr previousReturn = functionReturn;
        functionReturn = node.type_expr;
        bool previousHasTry = currentFnHasTry;
        currentFnHasTry = node.body.any!((Node n) => containsTryStmt(n));
        dstring[][] savedDetScopes = detFreeScopes;
        detFreeScopes = null;
        pushDetScope();
        emit(proto ~ " {\n(void)argc; (void)argv;");
        if (node.isMethod && !node.isStatic)
            emit(formatD("%s %s=argv[0];", localValueDecl(), cName("isto")) ~ acknowledgeLocal(cName("isto")));
        foreach (size_t i, FnArg arg; node.args)
        {
            dstring binding = formatD("%s %s;", localValueDecl(), cName(arg.name));
            emit(binding);
            if (arg.rest)
                emit(formatD("%s=delegua_rest(argc,argv,%s);", cName(arg.name), i + (node.isMethod
                        && !node.isStatic ? 1 : 0)));
            else if (arg.value is null)
                emit(formatD("%s = argv[%s];", cName(arg.name), i + (node.isMethod && !node.isStatic ? 1 : 0)));
            else
            {
                bool prevInDefault = inDefaultArg;
                inDefaultArg = true;
                dstring value;
                dstring setup = captureExpr(arg.value, value);
                inDefaultArg = prevInDefault;
                emit(formatD("if (argc > %s) %s = argv[%s]; else {", i + (node.isMethod
                        && !node.isStatic ? 1 : 0), cName(arg.name), i + (node.isMethod && !node.isStatic ? 1 : 0)));
                if (setup.length)
                    emit(setup);
                emit(formatD("%s = %s;\n}", cName(arg.name), value));
            }
        }
        foreach (FnArg arg; node.args)
            emit(acknowledgeLocal(cName(arg.name)));
        foreach (FnArg arg; node.args)
        {
            if (arg.type_expr !is null && arg.type_expr.toStr() != "qualquer")
                emit(formatD("%s=%s;", cName(arg.name), checked(cName(arg.name), arg.rest
                        ? new TypeExprArray(arg.type_expr, arg.pos) : arg.type_expr)));
            if (TypeSemaClass argCls = cast(TypeSemaClass) arg.type_sema)
                if (argCls.declaration !is null && argCls.declaration.isValueType)
                    emit(formatD("%s=delegua_clonar(%s);", cName(arg.name), cName(arg.name)));
        }
        foreach (Node n; node.body)
            emit(compileStmtOrdered(n), 4);
        dstring detFnFree = popDetScopeCode();
        bool endsInDirectReturn = false;
        if (node.body.length > 0 && cleanups.length == 0)
            if (ReturnStmt lastRet = cast(ReturnStmt) node.body[$ - 1])
                endsInDirectReturn = !lastRet.collectionReturn;
        if (!endsInDirectReturn)
        {
            if (detFnFree.length)
                emit(detFnFree, 4);
            emit("return " ~ checked("create_nulo()", functionReturn, null, new NullLit(node.pos)) ~ ";\n}");
        }
        else
            emit("}");
        detFreeScopes = savedDetScopes;
        currentClass = previousClass;
        functionReturn = previousReturn;
        currentFnHasTry = previousHasTry;
    }

    void compileAsyncFn(FnDecl node, dstring prototype)
    {
        emitAsyncFunction(this, node, prototype);
    }

    FnDecl[] functions;
    bool[FnDecl] functionsInitialized, functionsInitializing;
    dstring metadata(Decorator[] decorators)
    {
        dstring list = formatD("cgd_attrs_%s", tmp++);
        emitLocal(formatD("delegua_value %s=create_vetor();", list));
        foreach (Decorator d; decorators)
        {
            dstring attr = formatD("cgd_attr_%s", tmp++), args = formatD("cgd_attr_args_%s", tmp++);
            emitLocal(formatD("delegua_value %s=create_map(),%s=create_map();", attr, args));
            foreach (size_t i, Node value; d.values)
                emitLocal(formatD("delegua_map_setar(%s,create_text(%s),%s);", args,
                        cString(d.keys[i]), materialize(value)));
            emitLocal(formatD("delegua_map_setar(%s,create_text(\"nome\"),create_text(%s));", attr, cString(d.name)));
            emitLocal(formatD("delegua_map_setar(%s,create_text(\"argumentos\"),%s);delegua_vetor_adicionar(&%s,%s);",
                    attr, args, list, attr));
        }
        return list;
    }

    void initializeFunction(FnDecl fn)
    {
        if (fn in functionsInitialized)
            return;
        if (fn in functionsInitializing)
            throw new Exception("Ciclo entre envelopes de decoradores.");
        functionsInitializing[fn] = true;
        foreach (Decorator d; fn.decorators)
            if (d.envelope !is null)
                initializeFunction(d.envelope);
        if (fn.decorators.length)
        {
            dstring original = functionValue(fn);
            dstring name = cName(fn.linkName) ~ "_slot";
            emit(formatD("%s=%s;", name, original));
            foreach_reverse (Decorator d; fn.decorators)
                if (d.envelope !is null)
                {
                    if (fn.isMethod && !fn.isStatic)
                        emit(formatD("%s=delegua_ajustar_metodo_envelope(%s,delegua_assegurar_tipo(delegua_chamar(%s,1,&%s),\"funcao\"));",
                                name, name, functionValue(d.envelope), name));
                    else
                        emit(formatD("%s=delegua_assegurar_tipo(delegua_chamar(%s,1,&%s),\"funcao\");",
                                name, functionValue(d.envelope), name));
                }
            dstring attrs = metadata(fn.decorators);
            emit(formatD("delegua_definir_decoradores(%s,%s);", name, attrs));
        }
        functionsInitializing.remove(fn);
        functionsInitialized[fn] = true;
    }

    ModuleUnit[] modules;
    bool[Node] collected;
    ClassDecl[] classes;
    bool[ClassDecl] initializedClasses;
    bool[ClassDecl] classShells;
    void createClassShell(ClassDecl c)
    {
        if (c.signature.builtinName.length || c in classShells)
            return;
        classShells[c] = true;
        if (c.superClass !is null)
            createClassShell(c.superClass);
        dstring name = cName(c.signature.linkName);
        emit(formatD("%s=create_classe(%s,%s);", name, cString(c.name), c.superClass is null
                ? "delegua_classe_objeto()"d : classValue(c.superClass)));
        emit(formatD("delegua_classe_fechada(%s);", name));
        if (c.isAbstract)
            emit(formatD("delegua_classe_abstrata(%s);", name));
    }

    void initializeClass(ClassDecl c)
    {
        if (c.signature.builtinName.length || c in initializedClasses)
            return;
        initializedClasses[c] = true;
        if (c.superClass !is null)
            initializeClass(c.superClass);
        foreach (ClassDecl mixinClass; c.mixins)
            initializeClass(mixinClass);
        dstring name = cName(c.signature.linkName);
        foreach (ClassDecl mixinClass; c.mixins)
            emit(formatD("delegua_classe_mescla(%s,%s);", name, classValue(mixinClass)));
        if (c.decorators.length)
            emit(formatD("delegua_definir_decoradores(%s,%s);", name, metadata(c.decorators)));
        foreach (ClassField field; c.fields)
            if (field.decorators.length)
                emit(formatD("delegua_classe_decoradores_campo(%s,%s,%s);", name,
                        cString(field.name), metadata(field.decorators)));
        foreach (ClassField field; c.fields)
            if (field.isEnum)
                emit(formatD("delegua_classe_enum(%s,%s,%s,%s);", name, cString(field.name),
                        materialize(field.value), field.access));
            else if (field.isStatic)
                emit(formatD("delegua_classe_campo_estatico(%s,%s,%s,%s,%s);", name,
                        cString(field.name), descriptor(field.type), materialize(field.value), field.access));
            else
                emit(formatD("delegua_classe_campo_tipo(%s,%s,%s,%s);", name, cString(field.name),
                        descriptor(field.type), field.access));
        foreach (ClassField field; c.fields)
            if (field.initializer !is null)
                emit(formatD("delegua_classe_inicializador(%s,%s,%s);", name, cString(field.name),
                        functionValue(field.initializer)));
        foreach (ClassField field; c.fields)
            if (field.customAccess)
                emit(formatD("delegua_classe_acessor(%s,%s,%s,%s,%s,%s);", name, cString(field.name),
                        field.getter is null ? "create_nulo()"d : functionValue(field.getter),
                        field.setter is null ? "create_nulo()"d : functionValue(field.setter),
                        field.readable ? 1 : 0, field.writable ? 1 : 0));
        foreach (ClassDecl contract; c.interfaces)
        {
            createClassShell(contract);
            emit(formatD("delegua_classe_interface(%s,%s);", name, classValue(contract)));
        }
        bool hasExplicitCtor = false;
        foreach (FnDecl method; c.methods)
            if (!method.accessor && (!reachabilityComputed || method in reachableNodes))
            {
                if (method.fn == "construtor"d)
                    hasExplicitCtor = true;
                if (method.decorators.length)
                    initializeFunction(method);
                emit(formatD(method.isStatic
                        ? "delegua_classe_metodo_estatico(%s,%s,%s,%s);" : "delegua_classe_metodo_acesso(%s,%s,%s,%s);",
                        name, cString(method.fn), functionValue(method), method.access));
            }
        if (c.isValueType && !hasExplicitCtor)
        {
            dstring autoCtorSym = name ~ "_auto_ctor"d;
            dstring autoProto = formatD("static delegua_value %s(sz argc, delegua_value *argv)", autoCtorSym);
            emitProto(autoProto ~ ";");
            nativeCg.addExtraDef(nativeCg.emitManagedValueConstructor(c, autoProto));
            size_t fieldCount = 0;
            foreach (ClassField field; c.fields)
                if (!field.isEnum && !field.isStatic)
                    fieldCount++;
            emit(formatD("delegua_classe_metodo_acesso(%s,\"construtor\",create_funcao_intervalo(&%s,0,%s),0);",
                    name, autoCtorSym, fieldCount + 1));
        }
    }

    void compileModule(ModuleUnit m)
    {
        dstring name = cName(m.linkName), frame = name ~ "_frame";
        emit(formatD("static void %s_init(void) { if(DELEGUA_ATOMIC_LOAD_INT(&%s_state)==2) return; delegua_mod_lock(); if(DELEGUA_ATOMIC_LOAD_INT(&%s_state)==2) { delegua_mod_unlock(); return; } if(%s_state==1) { delegua_mod_unlock(); delegua_panic(\"Ciclo de inicialização de módulos.\"); } %s_state=1;",
                name, name, name, name, name));
        emit(formatD("delegua_try_frame *const %s=delegua_tentar(); if(setjmp(%s->env)!=0) { delegua_sair_tente(%s); %s_state=0; delegua_mod_unlock(); delegua_falhar(%s->error); }",
                frame, frame, frame, name, frame));
        foreach (Node node; m.program.body)
            if (!isDecl(node.kind))
                emit(compileStmtOrdered(node));
        emit(formatD("delegua_value %s_exports=create_map();", name));
        Node[] exports;
        foreach (Node node; m.program.body)
        {
            if (SequenceStmt sequence = cast(SequenceStmt) node)
                exports ~= sequence.body;
            else
                exports ~= node;
        }
        foreach (Node node; exports)
        {
            dstring key, value;
            if (VarDecl v = cast(VarDecl) node)
            {
                key = v.name;
                value = cName(v.name);
            }
            if (FnDecl fn = cast(FnDecl) node)
            {
                if (reachabilityComputed && fn !in reachableNodes)
                    continue;
                key = fn.fn;
                value = functionValue(fn);
            }
            if (ClassDecl c = cast(ClassDecl) node)
            {
                if (reachabilityComputed && c !in reachableNodes)
                    continue;
                key = c.name;
                value = classValue(c);
            }
            if (key.length && key[0] != '#')
                emit(formatD("delegua_map_setar(%s_exports,%s,%s);", name, cString(key).length
                        ? formatD("create_text(%s)", cString(key)) : "create_nulo()"d, value));
        }
        emit(formatD("%s=create_modulo(%s_exports); DELEGUA_ATOMIC_STORE_INT(&%s_state,2); delegua_sair_tente(%s); delegua_mod_unlock(); }",
                name, name, name, frame));
    }

    void collectFunctions(Node node)
    {
        if (node is null || node in collected)
            return;
        if (reachabilityComputed)
        {
            if (ModuleUnit m = cast(ModuleUnit) node)
                if (m !in reachableNodes)
                    return;
            if (ClassDecl c = cast(ClassDecl) node)
                if (c !in reachableNodes)
                    return;
            if (FnDecl fn = cast(FnDecl) node)
                if (fn !in reachableNodes)
                    return;
        }
        collected[node] = true;
        if (ModuleUnit m = cast(ModuleUnit) node)
        {
            modules ~= m;
            emitProto(formatD("static delegua_value %s; static int %s_state; static void %s_init(void);",
                    cName(m.linkName), cName(m.linkName), cName(m.linkName)));
        }
        if (ClassDecl c = cast(ClassDecl) node)
        {
            classes ~= c;
            emitProto(formatD("static delegua_value %s;", cName(c.signature.linkName)));
        }
        foreach (Node child; childNodes(node))
            collectFunctions(child);
        if (FnDecl fn = cast(FnDecl) node)
        {
            if (emitDebugLines)
            {
                string cSym = cName(fn.linkName).to!string;
                string displayName = fn.ownerClass !is null
                    ? (fn.ownerClass.name.to!string ~ "." ~ fn.fn.to!string)
                    : fn.fn.to!string;
                if (fn.operatorSymbol.length)
                    displayName ~= " [@operador(\"" ~ fn.operatorSymbol.to!string ~ "\")]";
                debugFunctionNames[cSym] = displayName;
                if (fn.isNative || (fn.ownerClass !is null && fn.ownerClass.isValueType))
                    debugFunctionNames["cgd_nat_" ~ cSym] = displayName ~ " [@nativo]";
            }
            functions ~= fn;
            compileFnDecl(fn);
        }
    }

    dstring compileIfStmt(IfStmt node, bool fromIf = false)
    {
        pushDetScope();
        dstring[] body;
        foreach (Node child; node.body)
            body ~= compileStmtOrdered(child);
        dstring detIfFree = popDetScopeCode();
        if (detIfFree.length)
            body ~= detIfFree;
        if (node.expr is null)
            return "{\n" ~ body.join("\n") ~ "\n}";
        dstring setup;
        dstring cond = compileCondition(node.expr, setup);
        dstring result = (setup.length ? setup ~ "\n"d : ""d) ~ formatD("if (%s) {\n%s\n}", cond, body.join("\n"));
        if (node._else !is null)
            result ~= " else {\n" ~ compileIfStmt(node._else) ~ "\n}";
        return result;
    }

    pragma(inline, true) bool isDecl(NodeKind kind) => kind == NodeKind.FnDecl || kind == NodeKind.ClassDecl;

    public dstring nodesToStr(Node[] nodes, bool allowInliningLastNonTrivial = false)
    {
        dstring[] parts;
        parts.reserve(nodes.length);
        foreach (size_t i, Node n; nodes)
        {
            if (isPureConstantNode(n))
            {
                parts ~= compileExpr(n);
                continue;
            }
            if (isAlreadyMaterializedNode(n))
            {
                parts ~= materialize(n, true);
                continue;
            }
            if (Identifier id = cast(Identifier) n)
            {
                bool allowVar = !siblingsCanMutateVar(nodes[i + 1 .. $], id.value);
                parts ~= materialize(n, allowVar);
                continue;
            }
            bool tailIsPure = nodes[i + 1 .. $].all!((Node s) => isPureConstantNode(s));
            if (tailIsPure && (allowInliningLastNonTrivial || !canChangeLocalSite(n)))
                parts ~= compileExpr(n);
            else
                parts ~= materialize(n, true);
        }
        return parts.join(", ");
    }

    private void indexClassesAndHierarchy(Node node, ref ClassDecl[dstring] classesByLink, ref bool[Node] visited)
    {
        if (node is null || node in visited)
            return;
        visited[node] = true;
        if (ClassDecl c = cast(ClassDecl) node)
        {
            if (c.signature !is null && c.signature.linkName.length)
                classesByLink[c.signature.linkName] = c;
            if (c.superClass !is null)
                classesWithSubclasses[c.superClass] = true;
            foreach (ClassDecl mix; c.mixins)
                classesWithSubclasses[mix] = true;
            foreach (ClassDecl iface; c.interfaces)
                classesWithSubclasses[iface] = true;
        }
        foreach (Node child; childNodes(node))
            indexClassesAndHierarchy(child, classesByLink, visited);
    }

    private void computeReachability(Program prog)
    {
        reachableNodes = null;
        mutatedVars = null;
        classesWithSubclasses = null;
        referencedNames = null;
        dynamicMethodDispatch = false;
        reachabilityComputed = true;

        ClassDecl[dstring] classesByLink;
        bool[Node] indexed;
        indexClassesAndHierarchy(prog, classesByLink, indexed);

        Node[] queue;
        ClassDecl[] reachedClasses;
        ModuleUnit[] reachedModules;

        void enqueue(Node n)
        {
            if (n is null || n in reachableNodes)
                return;
            reachableNodes[n] = true;
            queue ~= n;
        }

        void markTypeExpr(TypeExpr type)
        {
            if (type is null)
                return;
            if (TypeExprNamed named = cast(TypeExprNamed) type)
            {
                if (named.classLinkName.length)
                    if (ClassDecl* targetCls = named.classLinkName in classesByLink)
                        enqueue(*targetCls);
                return;
            }
            if (TypeExprArray arr = cast(TypeExprArray) type)
            {
                markTypeExpr(arr.base);
                return;
            }
            if (TypeExprPromise prom = cast(TypeExprPromise) type)
            {
                markTypeExpr(prom.result);
                return;
            }
            if (TypeExprTask task = cast(TypeExprTask) type)
            {
                markTypeExpr(task.result);
                return;
            }
            if (TypeExprTuple tup = cast(TypeExprTuple) type)
            {
                foreach (TypeExpr child; tup.types)
                    markTypeExpr(child);
                return;
            }
            if (TypeExprGeneric gen = cast(TypeExprGeneric) type)
            {
                foreach (TypeExpr child; gen.typeArgs)
                    markTypeExpr(child);
            }
        }

        void markNameMatchesForClass(ClassDecl c, dstring name)
        {
            foreach (FnDecl m; c.methods)
                if (!m.accessor && m.fn == name)
                    enqueue(m);
        }

        void markNameMatchesForModule(ModuleUnit mod, dstring name)
        {
            if (mod.program is null)
                return;
            void scan(Node[] list)
            {
                foreach (Node item; list)
                {
                    if (SequenceStmt seq = cast(SequenceStmt) item)
                        scan(seq.body);
                    else if (FnDecl fn = cast(FnDecl) item)
                    {
                        if (fn.fn == name)
                            enqueue(fn);
                    }
                    else if (ClassDecl cls = cast(ClassDecl) item)
                    {
                        if (cls.name == name)
                            enqueue(cls);
                    }
                }
            }

            scan(mod.program.body);
        }

        void addReferencedName(dstring name)
        {
            if (!name.length || name in referencedNames)
                return;
            referencedNames[name] = true;
            foreach (ClassDecl c; reachedClasses)
                markNameMatchesForClass(c, name);
            foreach (ModuleUnit m; reachedModules)
                markNameMatchesForModule(m, name);
        }

        void enableDynamicDispatch()
        {
            if (dynamicMethodDispatch)
                return;
            dynamicMethodDispatch = true;
            foreach (ClassDecl c; reachedClasses)
                foreach (FnDecl m; c.methods)
                    if (!m.accessor)
                        enqueue(m);
            foreach (ModuleUnit mod; reachedModules)
            {
                if (mod.program is null)
                    continue;
                void scanAll(Node[] list)
                {
                    foreach (Node item; list)
                    {
                        if (SequenceStmt seq = cast(SequenceStmt) item)
                            scanAll(seq.body);
                        else if (FnDecl fn = cast(FnDecl) item)
                            enqueue(fn);
                        else if (ClassDecl cls = cast(ClassDecl) item)
                            enqueue(cls);
                    }
                }

                scanAll(mod.program.body);
            }
        }

        void scanExprOrStmt(Node n)
        {
            if (n is null)
                return;
            if (cast(FnDecl) n || cast(ClassDecl) n)
                return;
            if (ModuleUnit mod = cast(ModuleUnit) n)
            {
                enqueue(mod);
                return;
            }
            markTypeExpr(n.type_expr);
            if (AssignStmt assign = cast(AssignStmt) n)
            {
                if (Identifier id = cast(Identifier) assign.left)
                    if (id.variableRef !is null)
                        mutatedVars[id.variableRef] = true;
            }
            else if (UnaryExpr unary = cast(UnaryExpr) n)
            {
                if (unary.op == TokenKind.PPlus || unary.op == TokenKind.MMinus)
                    if (Identifier id = cast(Identifier) unary.value)
                        if (id.variableRef !is null)
                            mutatedVars[id.variableRef] = true;
            }
            else if (TryStmt tryStmt = cast(TryStmt) n)
            {
                foreach (CatchClause cc; tryStmt.catches)
                    markTypeExpr(cc.type);
            }
            else if (EachStmt eachStmt = cast(EachStmt) n)
            {
                markTypeExpr(eachStmt.bindingType);
                foreach (TypeExpr dt; eachStmt.destructuredTypes)
                    markTypeExpr(dt);
            }
            else if (Comprehension comp = cast(Comprehension) n)
            {
                markTypeExpr(comp.bindingType);
            }
            else if (ImportExpr imp = cast(ImportExpr) n)
            {
                enqueue(imp.target);
            }
            else if (Identifier id = cast(Identifier) n)
            {
                enqueue(id.classRef);
                enqueue(id.functionRef);
                enqueue(id.moduleRef);
            }
            else if (FunctionExpr fnExpr = cast(FunctionExpr) n)
            {
                enqueue(fnExpr.declaration);
            }
            else if (RoutineExpr routine = cast(RoutineExpr) n)
            {
                enqueue(routine.target);
                markTypeExpr(routine.resultType);
            }
            else if (SuperExpr sup = cast(SuperExpr) n)
            {
                addReferencedName(sup.name);
            }
            else if (BinaryExpr bin = cast(BinaryExpr) n)
            {
                enqueue(bin.resolvedOperator);
            }
            else if (UnaryExpr un = cast(UnaryExpr) n)
            {
                enqueue(un.resolvedOperator);
            }
            else if (IndexExpr idx = cast(IndexExpr) n)
            {
                enqueue(idx.resolvedOperator);
            }
            else if (AssignStmt ass = cast(AssignStmt) n)
            {
                enqueue(ass.resolvedIndexSetOperator);
            }
            else if (MemberExpr member = cast(MemberExpr) n)
            {
                enqueue(member.resolvedModule);
                if (Identifier rightId = cast(Identifier) member.right)
                    addReferencedName(rightId.value);
            }
            else if (CallExpr call = cast(CallExpr) n)
            {
                if (Identifier fnId = cast(Identifier) call.fn)
                {
                    if ((fnId.functionRef !is null && fnId.functionRef.builtinName == "respondeA")
                            || fnId.value == "respondeA")
                    {
                        if (call.args.length >= 2)
                        {
                            if (StringLit lit = cast(StringLit) call.args[1])
                                addReferencedName(lit.value);
                            else
                                enableDynamicDispatch();
                        }
                    }
                }
                bool unusedInit;
                dstring unusedMod;
                if (FnDecl directFn = resolveDirectCallee(call, unusedInit, unusedMod))
                    enqueue(directFn);
                if (ClassDecl directCls = resolveDirectConstructor(call, unusedInit, unusedMod))
                    enqueue(directCls);
            }
            foreach (Node child; childNodes(n))
                scanExprOrStmt(child);
        }

        addReferencedName("construtor"d);
        addReferencedName("destrutor"d);
        addReferencedName("paraTexto"d);

        foreach (Node node; prog.body)
            if (!isDecl(node.kind))
                scanExprOrStmt(node);

        size_t cursor = 0;
        while (cursor < queue.length)
        {
            Node current = queue[cursor++];
            if (ModuleUnit mod = cast(ModuleUnit) current)
            {
                reachedModules ~= mod;
                if (mod.program !is null)
                {
                    foreach (Node item; mod.program.body)
                        if (!isDecl(item.kind))
                            scanExprOrStmt(item);
                    if (dynamicMethodDispatch)
                    {
                        void scanAll(Node[] list)
                        {
                            foreach (Node item; list)
                            {
                                if (SequenceStmt seq = cast(SequenceStmt) item)
                                    scanAll(seq.body);
                                else if (FnDecl fn = cast(FnDecl) item)
                                    enqueue(fn);
                                else if (ClassDecl cls = cast(ClassDecl) item)
                                    enqueue(cls);
                            }
                        }

                        scanAll(mod.program.body);
                    }
                    else
                    {
                        foreach (dstring name; referencedNames.byKey())
                            markNameMatchesForModule(mod, name);
                    }
                }
            }
            else if (ClassDecl c = cast(ClassDecl) current)
            {
                reachedClasses ~= c;
                enqueue(c.superClass);
                foreach (ClassDecl mix; c.mixins)
                    enqueue(mix);
                foreach (ClassDecl iface; c.interfaces)
                    enqueue(iface);
                foreach (Decorator d; c.decorators)
                {
                    enqueue(d.envelope);
                    foreach (Node dv; d.values)
                        scanExprOrStmt(dv);
                }
                foreach (ClassField field; c.fields)
                {
                    markTypeExpr(field.type);
                    if (field.value !is null)
                        scanExprOrStmt(field.value);
                    enqueue(field.initializer);
                    enqueue(field.getter);
                    enqueue(field.setter);
                    foreach (Decorator d; field.decorators)
                    {
                        enqueue(d.envelope);
                        foreach (Node dv; d.values)
                            scanExprOrStmt(dv);
                    }
                }
                if (c.isInterface)
                {
                    foreach (FnDecl m; c.methods)
                        if (!m.accessor)
                            addReferencedName(m.fn);
                }
                foreach (FnDecl m; c.methods)
                {
                    if (!m.accessor && (dynamicMethodDispatch || c.isInterface || c.isValueType
                            || m.operatorSymbol.length || m.fn in referencedNames))
                        enqueue(m);
                }
            }
            else if (FnDecl fn = cast(FnDecl) current)
            {
                markTypeExpr(fn.type_expr);
                foreach (FnArg arg; fn.args)
                {
                    markTypeExpr(arg.type_expr);
                    if (arg.value !is null)
                        scanExprOrStmt(arg.value);
                }
                foreach (Decorator d; fn.decorators)
                {
                    enqueue(d.envelope);
                    foreach (Node dv; d.values)
                        scanExprOrStmt(dv);
                }
                foreach (Node stmt; fn.body)
                    scanExprOrStmt(stmt);
            }
        }
    }

    public bool isReachable(Node node)
    {
        return !reachabilityComputed || (node !is null && (node in reachableNodes) !is null);
    }

public:
    dstring compile(Program prog)
    {
        nativeCg = new NativeCodegen(ownershipInfo);
        nativeCg.emitDebugLines = emitDebugLines;
        if (memoryPlan !is null && memoryPlan.config.enableAns)
            ansCg = new AnsCodegen(memoryPlan);
        else
            ansCg = null;
        emitProto("static void cgd_gc_scan_generated_roots(cgd_gc_visit_fn visit_ptr, void (*visit_val)(const void *, void *), void *gc_ctx);"d);
        computeReachability(prog);
        collectFunctions(prog);
        foreach (ClassDecl c; classes)
            if (c.isValueType)
                nativeCg.emitValueClassBodies(c);
        foreach (ModuleUnit m; modules)
        {
            currentFnHasTry = true;
            compileModule(m);
        }

        currentFnHasTry = prog.body.any!((Node n) => containsTryStmt(n));
        if (emitDebugLines)
            emit("#line 1 \"<cgd-runtime-init>\"");
        emit(formatD("void %s(void) {", ENTRY));
        emit("cgd_gc_register_root_scanner(cgd_gc_scan_generated_roots);"d, 4);
        foreach (ClassDecl c; classes)
            createClassShell(c);
        foreach (ClassDecl c; classes)
            initializeClass(c);
        foreach (FnDecl fn; functions)
            initializeFunction(fn);

        detFreeScopes = null;
        pushDetScope();
        foreach (Node node; prog.body)
            if (!isDecl(node.kind))
                emit(compileStmtOrdered(node), 4);
        dstring detMainFree = popDetScopeCode();
        if (detMainFree.length)
            emit(detMainFree, 4);

        emit("}");

        dstring[] rootScanLines;
        rootScanLines ~= "static void cgd_gc_scan_generated_roots(cgd_gc_visit_fn visit_ptr, void (*visit_val)(const void *, void *), void *gc_ctx) {"d;
        rootScanLines ~= "    (void)visit_ptr; (void)visit_val; (void)gc_ctx;"d;
        size_t totalGlobalRoots = 0;
        if (classes.length || modules.length || functionSlots.length)
        {
            rootScanLines ~= "    if (visit_val) {"d;
            foreach (ClassDecl c; classes)
            {
                rootScanLines ~= formatD("        visit_val(&%s, gc_ctx);", cName(c.signature.linkName));
                totalGlobalRoots++;
            }
            foreach (ModuleUnit m; modules)
            {
                rootScanLines ~= formatD("        visit_val(&%s, gc_ctx);", cName(m.linkName));
                totalGlobalRoots++;
            }
            foreach (FnDecl fn; functionSlots.byKey())
            {
                rootScanLines ~= formatD("        visit_val(&%s_slot, gc_ctx);", cName(fn.linkName));
                totalGlobalRoots++;
            }
            rootScanLines ~= "    }"d;
        }
        if (icCount > 0)
        {
            rootScanLines ~= formatD("    if (visit_ptr) { for (sz i = 0; i < %s; ++i) { if (cgd_ic[i]) visit_ptr(cgd_ic[i], gc_ctx); } }",
                    icCount);
            totalGlobalRoots += icCount;
        }
        rootScanLines ~= "}"d;
        if (memoryPlan !is null)
            memoryPlan.globalRootsRegistered = totalGlobalRoots;
        emit(rootScanLines.join("\n"));

        dstring source = includes.join("\n");
        source ~= "\n" ~ nativeCg.emitTypePreamble();
        if (sourceFileDecls.length)
            source ~= "\n" ~ sourceFileDecls.join("\n");
        if (sourceSites.length)
            source ~= "\nstatic const delegua_local cgd_source_sites[]={" ~ sourceSites.join(",") ~ "};\n";
        if (icCount > 0)
            source ~= formatD("static const void *cgd_ic[%s];\n", icCount);
        source ~= prototypes.join("\n");
        source ~= "\n" ~ nativeCg.emitPrototypes();
        if (ansCg !is null)
            source ~= ansCg.emitPrototypes();
        source ~= nativeCg.emitDefinitions();
        if (ansCg !is null)
            source ~= ansCg.emitDefinitions();
        source ~= code.join("\n");
        return source;
    }
}
