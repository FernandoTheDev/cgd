module frontend.semantic.interprocedural;

import frontend.lexer.token : TokenKind;
import frontend.parser.ast;
import frontend.semantic.members : ClassMember, resolveClassMember;
import frontend.type_expr;
import frontend.type_sema;
import middle.memory_model;
import std.algorithm : canFind;
import std.conv : to;

/// Mapeia uma anotação TypeExpr exata para um tipo escalar ANS.
/// Conservador: `numero`/`número` aceita inteiro OU real em tempo de execução, portanto retorna `None`.
AnsScalarType classifyAnsType(TypeExpr texpr, bool allowVoid = false)
{
    TypeExprNamed named = cast(TypeExprNamed) texpr;
    if (named is null || named.classLinkName.length)
        return AnsScalarType.None;
    switch (named.name)
    {
        case "inteiro":
        case "longo":
            return AnsScalarType.Int64;
        case "real":
        case "decimal":
            return AnsScalarType.Float64;
        case "logico":
        case "lógico":
        case "booleano":
        case "binario":
        case "binário":
            return AnsScalarType.Bool;
        case "vazio":
        case "nulo":
            return allowVoid ? AnsScalarType.Void : AnsScalarType.None;
        default:
            return AnsScalarType.None;
    }
}

/// Analisador interprocedimental (Grafo de Chamadas + Tarjan SCC + Ponto Fixo + Escape/Lifetime + ANS).
final class InterproceduralMemoryAnalyzer
{
private:
    MemoryPlan plan;
    FnDecl[] allFns;
    bool[FnDecl] fnSeen;
    ClassDecl[] allClasses;
    bool[ClassDecl] classSeen;
    FnDecl[][FnDecl] callGraph;

    void collectProgramDecls(Node node, ref bool[Node] visited)
    {
        if (node is null || node in visited)
            return;
        visited[node] = true;
        if (ClassDecl cls = cast(ClassDecl) node)
        {
            if (cls !in classSeen)
            {
                classSeen[cls] = true;
                allClasses ~= cls;
                if (cls.superClass !is null)
                    plan.classesWithSubclasses[cls.superClass] = true;
                foreach (ClassDecl mix; cls.mixins)
                    plan.classesWithSubclasses[mix] = true;
                foreach (ClassDecl iface; cls.interfaces)
                    plan.classesWithSubclasses[iface] = true;
            }
        }
        else if (FnDecl fn = cast(FnDecl) node)
        {
            if (fn !in fnSeen)
            {
                fnSeen[fn] = true;
                allFns ~= fn;
            }
        }
        foreach (Node ch; childNodes(node))
            collectProgramDecls(ch, visited);
    }

    FnDecl resolveStaticCallee(CallExpr call)
    {
        if (call is null || call.runtimeCall || call.args.anySpread())
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
                    && !target.isAbstract && !hasDecoratorEnvelope(target))
                return target;
            return null;
        }
        if (MemberExpr mem = cast(MemberExpr) call.fn)
        {
            Identifier rightId = cast(Identifier) mem.right;
            if (rightId is null)
                return null;
            if (rightId.functionRef !is null && !rightId.functionRef.isAbstract
                    && !hasDecoratorEnvelope(rightId.functionRef))
            {
                if (rightId.functionRef.ownerClass is null)
                    return rightId.functionRef;
                if (rightId.functionRef.isStatic)
                    return rightId.functionRef;
                if (rightId.functionRef.ownerClass !in plan.classesWithSubclasses
                        && cast(TypeSemaClass) mem.left.type_sema !is null)
                    return rightId.functionRef;
            }
        }
        return null;
    }

    static bool hasDecoratorEnvelope(FnDecl fn)
    {
        if (fn is null)
            return false;
        foreach (Decorator d; fn.decorators)
            if (d.envelope !is null)
                return true;
        return false;
    }

    void buildCallGraph()
    {
        foreach (FnDecl fn; allFns)
        {
            FnDecl[] edges;
            bool[FnDecl] edgeSeen;
            bool[Node] seenNodes;

            void scan(Node n)
            {
                if (n is null || n in seenNodes)
                    return;
                seenNodes[n] = true;
                if (n !is fn && (cast(FnDecl) n !is null || cast(ClassDecl) n !is null))
                    return;
                if (CallExpr call = cast(CallExpr) n)
                {
                    FnDecl target = resolveStaticCallee(call);
                    if (target !is null && target !in edgeSeen)
                    {
                        edgeSeen[target] = true;
                        edges ~= target;
                    }
                }
                foreach (Node ch; childNodes(n))
                    scan(ch);
            }

            foreach (Node st; fn.body)
                scan(st);
            callGraph[fn] = edges;
        }
    }

    /// Algoritmo de Tarjan para identificar SCCs e funções recursivas (diretas ou mútuas).
    FnDecl[][] computeTarjanSCCs()
    {
        size_t nextIndex = 0;
        size_t[FnDecl] indexMap;
        size_t[FnDecl] lowlink;
        bool[FnDecl] onStack;
        FnDecl[] stack;
        FnDecl[][] sccs;

        void strongConnect(FnDecl v)
        {
            indexMap[v] = nextIndex;
            lowlink[v] = nextIndex;
            nextIndex++;
            stack ~= v;
            onStack[v] = true;

            FnDecl[]* nbrs = v in callGraph;
            if (nbrs !is null)
            {
                foreach (FnDecl w; *nbrs)
                {
                    if (w !in indexMap)
                    {
                        strongConnect(w);
                        if (lowlink[w] < lowlink[v])
                            lowlink[v] = lowlink[w];
                    }
                    else if (w in onStack && onStack[w])
                    {
                        if (indexMap[w] < lowlink[v])
                            lowlink[v] = indexMap[w];
                    }
                }
            }

            if (lowlink[v] == indexMap[v])
            {
                FnDecl[] comp;
                while (stack.length > 0)
                {
                    FnDecl w = stack[$ - 1];
                    stack.length--;
                    onStack[w] = false;
                    comp ~= w;
                    if (w is v)
                        break;
                }
                sccs ~= comp;
            }
        }

        foreach (FnDecl fn; allFns)
            if (fn !in indexMap)
                strongConnect(fn);

        return sccs;
    }

    void initializeSummaries(FnDecl[][] sccs)
    {
        foreach (FnDecl fn; allFns)
        {
            FunctionMemorySummary sum;
            sum.fn = fn;
            sum.maySuspend = fn.isAsync;
            sum.paramEscapes = new bool[fn.args.length];
            sum.paramMutated = new bool[fn.args.length];
            // Conservador para funções externas/abstratas/decoradas/async
            if (fn.foreignSymbol.length || fn.isAbstract || fn.isAsync || hasDecoratorEnvelope(fn))
            {
                sum.mayThrow = true;
                sum.allocatesManaged = true;
                foreach (size_t i; 0 .. fn.args.length)
                {
                    sum.paramEscapes[i] = true;
                    sum.paramMutated[i] = true;
                }
            }
            plan.fnSummaries[fn] = sum;
        }

        foreach (FnDecl[] comp; sccs)
        {
            if (comp.length > 1)
            {
                foreach (FnDecl fn; comp)
                    plan.fnSummaries[fn].isRecursive = true;
            }
            else if (comp.length == 1)
            {
                FnDecl fn = comp[0];
                FnDecl[]* nbrs = fn in callGraph;
                if (nbrs !is null && (*nbrs).canFind(fn))
                    plan.fnSummaries[fn].isRecursive = true;
            }
        }
    }

    bool computeSingleSummaryStep(FnDecl fn)
    {
        FunctionMemorySummary* sum = fn in plan.fnSummaries;
        if (sum is null || fn.foreignSymbol.length || fn.isAbstract || fn.isAsync || hasDecoratorEnvelope(fn))
            return false;

        bool changed = false;
        size_t[FnArg] paramIndex;
        foreach (size_t i, FnArg arg; fn.args)
            paramIndex[arg] = i;

        void markParamEscape(Node expr)
        {
            if (expr is null)
                return;
            if (Identifier id = cast(Identifier) expr)
            {
                if (id.parameterRef !is null)
                {
                    if (size_t* idx = id.parameterRef in paramIndex)
                    {
                        if (!sum.paramEscapes[*idx])
                        {
                            sum.paramEscapes[*idx] = true;
                            changed = true;
                        }
                    }
                }
                return;
            }
            if (ConditionalExpr cond = cast(ConditionalExpr) expr)
            {
                markParamEscape(cond.yes);
                markParamEscape(cond.no);
            }
            else if (BinaryExpr bin = cast(BinaryExpr) expr)
            {
                markParamEscape(bin.left);
                markParamEscape(bin.right);
            }
        }

        void markParamMutate(Node expr)
        {
            if (expr is null)
                return;
            if (Identifier id = cast(Identifier) expr)
            {
                if (id.parameterRef !is null)
                {
                    if (size_t* idx = id.parameterRef in paramIndex)
                    {
                        if (!sum.paramMutated[*idx])
                        {
                            sum.paramMutated[*idx] = true;
                            changed = true;
                        }
                    }
                }
            }
            else if (MemberExpr m = cast(MemberExpr) expr)
                markParamMutate(m.left);
            else if (IndexExpr ix = cast(IndexExpr) expr)
                markParamMutate(ix.value);
        }

        bool[Node] seen;
        void scan(Node n)
        {
            if (n is null || n in seen)
                return;
            seen[n] = true;
            if (n !is fn && (cast(FnDecl) n !is null || cast(ClassDecl) n !is null))
                return;

            if (ThrowStmt th = cast(ThrowStmt) n)
            {
                if (!sum.mayThrow)
                {
                    sum.mayThrow = true;
                    changed = true;
                }
                markParamEscape(th.value);
            }
            else if (ReturnStmt ret = cast(ReturnStmt) n)
            {
                markParamEscape(ret.val);
            }
            else if (VarDecl vd = cast(VarDecl) n)
            {
                // Qualquer alias de parâmetro para variável local trata-se conservadoramente como possível escape.
                markParamEscape(vd.value);
            }
            else if (AssignStmt ass = cast(AssignStmt) n)
            {
                markParamEscape(ass.value);
                markParamMutate(ass.left);
            }
            else if (ArrayLit arr = cast(ArrayLit) n)
            {
                if (!sum.allocatesManaged)
                {
                    sum.allocatesManaged = true;
                    changed = true;
                }
                foreach (Node el; arr.elements)
                    markParamEscape(el);
            }
            else if (MapLit mp = cast(MapLit) n)
            {
                if (!sum.allocatesManaged)
                {
                    sum.allocatesManaged = true;
                    changed = true;
                }
                foreach (Node k; mp.keys)
                    markParamEscape(k);
                foreach (Node v; mp.values)
                    markParamEscape(v);
            }
            else if (cast(Comprehension) n !is null || cast(LoopExpr) n !is null || cast(FunctionExpr) n !is null)
            {
                if (!sum.allocatesManaged)
                {
                    sum.allocatesManaged = true;
                    changed = true;
                }
            }
            else if (CallExpr call = cast(CallExpr) n)
            {
                if (call.runtimeCall)
                {
                    dstring opName = (cast(Identifier) call.fn).value;
                    if (opName != "delegua_op_eq" && opName != "delegua_op_neq" && opName != "delegua_op_not")
                    {
                        if (!sum.mayThrow)
                        {
                            sum.mayThrow = true;
                            changed = true;
                        }
                    }
                    if (opName == "delegua_op_add")
                    {
                        // Pode concatenar textos se não for numérico
                        if (call.type_sema is null || call.type_sema.toStr() == TypeSemaBase.String
                                || call.type_sema.isAny())
                        {
                            if (!sum.allocatesManaged)
                            {
                                sum.allocatesManaged = true;
                                changed = true;
                            }
                        }
                    }
                }
                else
                {
                    FnDecl target = resolveStaticCallee(call);
                    if (target !is null)
                    {
                        FunctionMemorySummary* tsum = target in plan.fnSummaries;
                        if (tsum !is null)
                        {
                            if (tsum.mayThrow && !sum.mayThrow)
                            {
                                sum.mayThrow = true;
                                changed = true;
                            }
                            if (tsum.allocatesManaged && !sum.allocatesManaged)
                            {
                                sum.allocatesManaged = true;
                                changed = true;
                            }
                            foreach (size_t i, Node arg; call.args)
                            {
                                if (i >= tsum.paramEscapes.length || tsum.paramEscapes[i])
                                    markParamEscape(arg);
                                if (i >= tsum.paramMutated.length || tsum.paramMutated[i])
                                    markParamMutate(arg);
                            }
                        }
                        else
                        {
                            foreach (Node arg; call.args)
                                markParamEscape(arg);
                        }
                    }
                    else
                    {
                        if (!sum.mayThrow)
                        {
                            sum.mayThrow = true;
                            changed = true;
                        }
                        if (!sum.allocatesManaged)
                        {
                            sum.allocatesManaged = true;
                            changed = true;
                        }
                        foreach (Node arg; call.args)
                            markParamEscape(arg);
                    }
                }
            }

            foreach (Node ch; childNodes(n))
                scan(ch);
        }

        foreach (Node st; fn.body)
            scan(st);
        return changed;
    }

    void runFixedPointSummaries(FnDecl[][] sccs)
    {
        // Tarjan emite SCCs em ordem topológica reversa (folhas primeiro).
        foreach (FnDecl[] comp; sccs)
        {
            bool changed = true;
            size_t guard = 0;
            while (changed && guard < 32)
            {
                changed = false;
                guard++;
                foreach (FnDecl fn; comp)
                    if (computeSingleSummaryStep(fn))
                        changed = true;
            }
        }
    }

    /// Determina elegibilidade exata para Especialização Nativa Automática (ANS) em ponto fixo.
    void analyzeAnsEligibility()
    {
        if (!plan.config.enableAns)
            return;

        // Passo 1: elegibilidade de assinatura + estrutura local
        foreach (FnDecl fn; allFns)
        {
            FunctionMemorySummary* sum = fn in plan.fnSummaries;
            if (sum is null)
                continue;
            if (fn.isNative || fn.isAsync || fn.isAbstract || fn.accessor || fn.anonymous
                    || fn.foreignSymbol.length || fn.builtinName.length || fn.classFactory !is null
                    || fn.decorators.length > 0 || (fn.isMethod && !fn.isStatic))
            {
                sum.ansRejectReason = "forma-nao-elegivel";
                continue;
            }
            if (fn.ownerClass !is null && fn.ownerClass.isValueType)
            {
                sum.ansRejectReason = "ja-nativo-valor";
                continue;
            }
            if (fn.body.length == 0)
            {
                sum.ansRejectReason = "corpo-vazio";
                continue;
            }

            AnsScalarType retT = classifyAnsType(fn.type_expr, true);
            if (retT == AnsScalarType.None)
            {
                sum.ansRejectReason = "retorno-nao-escalar";
                continue;
            }
            AnsScalarType[] pTypes = new AnsScalarType[fn.args.length];
            bool paramsOk = true;
            foreach (size_t i, FnArg arg; fn.args)
            {
                if (arg.rest || arg.value !is null)
                {
                    paramsOk = false;
                    break;
                }
                AnsScalarType pt = classifyAnsType(arg.type_expr, false);
                if (pt == AnsScalarType.None)
                {
                    paramsOk = false;
                    break;
                }
                pTypes[i] = pt;
            }
            if (!paramsOk)
            {
                sum.ansRejectReason = "parametro-nao-escalar";
                continue;
            }

            sum.ansReturnType = retT;
            sum.ansParamTypes = pTypes;
            sum.ansEligible = true;
        }

        // Passo 2: validação de corpo em ponto fixo (uma função ANS só pode chamar outras funções ANS)
        bool changed = true;
        while (changed)
        {
            changed = false;
            foreach (FnDecl fn; allFns)
            {
                FunctionMemorySummary* sum = fn in plan.fnSummaries;
                if (sum is null || !sum.ansEligible)
                    continue;
                string rejectReason;
                if (!verifyAnsBody(fn, sum, rejectReason))
                {
                    sum.ansEligible = false;
                    sum.ansRejectReason = rejectReason;
                    changed = true;
                }
            }
        }

        foreach (FnDecl fn; allFns)
        {
            FunctionMemorySummary* sum = fn in plan.fnSummaries;
            if (sum !is null && sum.ansEligible)
            {
                plan.ansFunctionsCount++;
                plan.ansFunctionNames ~= fn.fn.to!string;
            }
        }
    }

    AnsScalarType inferAnsExprType(Node expr, ref AnsScalarType[VarDecl] localTypes,
            ref AnsScalarType[FnArg] paramTypes, ref string rejectReason)
    {
        if (expr is null)
            return AnsScalarType.Void;
        if (cast(IntLit) expr !is null)
            return AnsScalarType.Int64;
        if (cast(DoubleLit) expr !is null)
            return AnsScalarType.Float64;
        if (cast(BoolLit) expr !is null)
            return AnsScalarType.Bool;
        if (cast(NullLit) expr !is null)
            return AnsScalarType.Void;
        if (Identifier id = cast(Identifier) expr)
        {
            if (id.parameterRef !is null)
            {
                if (AnsScalarType* pt = id.parameterRef in paramTypes)
                    return *pt;
            }
            if (id.variableRef !is null)
            {
                if (AnsScalarType* vt = id.variableRef in localTypes)
                    return *vt;
            }
            rejectReason = "identificador-nao-local";
            return AnsScalarType.None;
        }
        if (MemberExpr mem = cast(MemberExpr) expr)
        {
            if (mem.enumValue !is null)
                return AnsScalarType.Int64;
            rejectReason = "acesso-membro";
            return AnsScalarType.None;
        }
        if (UnaryExpr un = cast(UnaryExpr) expr)
        {
            if (un.op == TokenKind.PPlus || un.op == TokenKind.MMinus)
            {
                Identifier targetId = cast(Identifier) un.value;
                if (targetId is null)
                {
                    rejectReason = "inc-nao-identificador";
                    return AnsScalarType.None;
                }
                AnsScalarType t = inferAnsExprType(targetId, localTypes, paramTypes, rejectReason);
                if (t == AnsScalarType.Int64 || t == AnsScalarType.Float64)
                    return t;
                rejectReason = "inc-tipo-invalido";
                return AnsScalarType.None;
            }
            rejectReason = "unario-nao-suportado";
            return AnsScalarType.None;
        }
        if (BinaryExpr bin = cast(BinaryExpr) expr)
        {
            if (bin.op == TokenKind.And || bin.op == TokenKind.Or)
            {
                AnsScalarType lt = inferAnsExprType(bin.left, localTypes, paramTypes, rejectReason);
                AnsScalarType rt = inferAnsExprType(bin.right, localTypes, paramTypes, rejectReason);
                if (lt == AnsScalarType.Bool && rt == AnsScalarType.Bool)
                    return AnsScalarType.Bool;
                rejectReason = "logico-nao-booleano";
                return AnsScalarType.None;
            }
            rejectReason = "binario-nao-suportado";
            return AnsScalarType.None;
        }
        if (ConditionalExpr cond = cast(ConditionalExpr) expr)
        {
            AnsScalarType ct = inferAnsExprType(cond.condition, localTypes, paramTypes, rejectReason);
            AnsScalarType yt = inferAnsExprType(cond.yes, localTypes, paramTypes, rejectReason);
            AnsScalarType nt = inferAnsExprType(cond.no, localTypes, paramTypes, rejectReason);
            if (ct == AnsScalarType.Bool && yt != AnsScalarType.None && yt == nt && yt != AnsScalarType.Void)
                return yt;
            rejectReason = "ternario-heterogeneo";
            return AnsScalarType.None;
        }
        if (CallExpr call = cast(CallExpr) expr)
        {
            if (call.runtimeCall)
            {
                dstring opName = (cast(Identifier) call.fn).value;
                if (call.args.length == 1)
                {
                    AnsScalarType a0 = inferAnsExprType(call.args[0], localTypes, paramTypes, rejectReason);
                    if (opName == "delegua_op_not" && a0 == AnsScalarType.Bool)
                        return AnsScalarType.Bool;
                    if (opName == "delegua_op_bnt" && a0 == AnsScalarType.Int64)
                        return AnsScalarType.Int64;
                    rejectReason = "op-unario-nao-ans";
                    return AnsScalarType.None;
                }
                if (call.args.length == 2)
                {
                    AnsScalarType lt = inferAnsExprType(call.args[0], localTypes, paramTypes, rejectReason);
                    AnsScalarType rt = inferAnsExprType(call.args[1], localTypes, paramTypes, rejectReason);
                    if (lt == AnsScalarType.None || rt == AnsScalarType.None)
                        return AnsScalarType.None;
                    bool bothInt = (lt == AnsScalarType.Int64 && rt == AnsScalarType.Int64);
                    bool anyFloat = (lt == AnsScalarType.Float64 || rt == AnsScalarType.Float64)
                        && (lt == AnsScalarType.Int64 || lt == AnsScalarType.Float64)
                        && (rt == AnsScalarType.Int64 || rt == AnsScalarType.Float64);
                    switch (opName)
                    {
                        case "delegua_op_add":
                        case "delegua_op_sub":
                        case "delegua_op_mul":
                            if (bothInt)
                                return AnsScalarType.Int64;
                            if (anyFloat)
                                return AnsScalarType.Float64;
                            rejectReason = "aritmetica-nao-numerica";
                            return AnsScalarType.None;
                        case "delegua_op_div":
                            // Em Delégua, int / int pode retornar inteiro ou real dinamicamente!
                            // Apenas especializamos divisão quando pelo menos um operando é real (f64).
                            if (anyFloat)
                                return AnsScalarType.Float64;
                            rejectReason = "div-inteira-dinamica";
                            return AnsScalarType.None;
                        case "delegua_op_idiv":
                        case "delegua_op_mod":
                        case "delegua_op_bor":
                        case "delegua_op_bnd":
                        case "delegua_op_bxr":
                        case "delegua_op_shl":
                        case "delegua_op_shr":
                            if (bothInt)
                                return AnsScalarType.Int64;
                            rejectReason = "bitwise-nao-inteiro";
                            return AnsScalarType.None;
                        case "delegua_op_lt":
                        case "delegua_op_le":
                        case "delegua_op_gt":
                        case "delegua_op_ge":
                            if (bothInt || anyFloat)
                                return AnsScalarType.Bool;
                            rejectReason = "comparacao-nao-numerica";
                            return AnsScalarType.None;
                        case "delegua_op_eq":
                        case "delegua_op_neq":
                            if (bothInt || anyFloat || (lt == AnsScalarType.Bool && rt == AnsScalarType.Bool))
                                return AnsScalarType.Bool;
                            rejectReason = "igualdade-nao-escalar";
                            return AnsScalarType.None;
                        default:
                            rejectReason = "op-runtime-nao-ans";
                            return AnsScalarType.None;
                    }
                }
                rejectReason = "op-aridade-nao-ans";
                return AnsScalarType.None;
            }
            // Conversões escalares diretas inteiro(x) / real(x)
            if (Identifier fnId = cast(Identifier) call.fn)
            {
                if (fnId.functionRef !is null && fnId.functionRef.builtinName.length
                        && call.args.length == 1 && !call.args.anySpread())
                {
                    dstring b = fnId.functionRef.builtinName;
                    if (b == "real"d || b == "numero"d || b == "número"d)
                    {
                        AnsScalarType at = inferAnsExprType(call.args[0], localTypes, paramTypes, rejectReason);
                        if (at == AnsScalarType.Int64 || at == AnsScalarType.Float64)
                            return AnsScalarType.Float64;
                    }
                }
            }
            // Chamada direta intra-módulo (Identifier) a outra função ANS
            if (cast(Identifier) call.fn !is null)
            {
                FnDecl target = resolveStaticCallee(call);
                if (target !is null && target in plan.fnSummaries)
                {
                    FunctionMemorySummary* tsum = target in plan.fnSummaries;
                    if (tsum.ansEligible && call.args.length == tsum.ansParamTypes.length)
                    {
                        foreach (size_t i, Node arg; call.args)
                        {
                            AnsScalarType at = inferAnsExprType(arg, localTypes, paramTypes, rejectReason);
                            AnsScalarType expected = tsum.ansParamTypes[i];
                            bool compat = (at == expected)
                                || (expected == AnsScalarType.Float64 && at == AnsScalarType.Int64);
                            if (!compat)
                            {
                                rejectReason = "arg-chamada-ans-incompativel";
                                return AnsScalarType.None;
                            }
                        }
                        return tsum.ansReturnType;
                    }
                }
            }
            rejectReason = "chamada-nao-ans";
            return AnsScalarType.None;
        }
        rejectReason = "expressao-nao-ans";
        return AnsScalarType.None;
    }

    bool verifyAnsStmt(Node stmt, FunctionMemorySummary* sum, ref AnsScalarType[VarDecl] localTypes,
            ref AnsScalarType[FnArg] paramTypes, ref string rejectReason)
    {
        if (stmt is null || stmt.kind == NodeKind.NaN)
            return true;
        switch (stmt.kind)
        {
            case NodeKind.SequenceStmt:
                foreach (Node s; (cast(SequenceStmt) stmt).body)
                    if (!verifyAnsStmt(s, sum, localTypes, paramTypes, rejectReason))
                        return false;
                return true;
            case NodeKind.BlockStmt:
                foreach (Node s; (cast(BlockStmt) stmt).body)
                    if (!verifyAnsStmt(s, sum, localTypes, paramTypes, rejectReason))
                        return false;
                return true;
            case NodeKind.VarDecl:
                VarDecl vd = cast(VarDecl) stmt;
                if (vd.uninitialized)
                {
                    rejectReason = "var-nao-inicializada";
                    return false;
                }
                AnsScalarType initT = inferAnsExprType(vd.value, localTypes, paramTypes, rejectReason);
                if (initT == AnsScalarType.None || initT == AnsScalarType.Void)
                    return false;
                AnsScalarType declT = vd.type_expr !is null ? classifyAnsType(vd.type_expr, false) : initT;
                if (declT == AnsScalarType.None)
                {
                    rejectReason = "var-tipo-nao-escalar";
                    return false;
                }
                if (declT != initT && !(declT == AnsScalarType.Float64 && initT == AnsScalarType.Int64))
                {
                    rejectReason = "var-init-incompativel";
                    return false;
                }
                localTypes[vd] = declT;
                return true;
            case NodeKind.AssignStmt:
                AssignStmt ass = cast(AssignStmt) stmt;
                Identifier lhs = cast(Identifier) ass.left;
                if (lhs is null)
                {
                    rejectReason = "assign-nao-identificador";
                    return false;
                }
                AnsScalarType lt = inferAnsExprType(lhs, localTypes, paramTypes, rejectReason);
                AnsScalarType rt = inferAnsExprType(ass.value, localTypes, paramTypes, rejectReason);
                if (lt == AnsScalarType.None || rt == AnsScalarType.None || rt == AnsScalarType.Void)
                    return false;
                if (lt != rt && !(lt == AnsScalarType.Float64 && rt == AnsScalarType.Int64))
                {
                    rejectReason = "assign-incompativel";
                    return false;
                }
                return true;
            case NodeKind.ReturnStmt:
                ReturnStmt ret = cast(ReturnStmt) stmt;
                if (ret.collectionReturn)
                {
                    rejectReason = "retorno-colecao";
                    return false;
                }
                if (sum.ansReturnType == AnsScalarType.Void)
                {
                    if (ret.val !is null && cast(NullLit) ret.val is null)
                    {
                        rejectReason = "retorno-valor-em-vazio";
                        return false;
                    }
                    return true;
                }
                if (ret.val is null)
                {
                    rejectReason = "retorno-vazio-em-escalar";
                    return false;
                }
                AnsScalarType vt = inferAnsExprType(ret.val, localTypes, paramTypes, rejectReason);
                if (vt != sum.ansReturnType
                        && !(sum.ansReturnType == AnsScalarType.Float64 && vt == AnsScalarType.Int64))
                {
                    rejectReason = "retorno-tipo-incompativel";
                    return false;
                }
                return true;
            case NodeKind.IfStmt:
                IfStmt ifs = cast(IfStmt) stmt;
                if (ifs.expr !is null)
                {
                    AnsScalarType ct = inferAnsExprType(ifs.expr, localTypes, paramTypes, rejectReason);
                    if (ct != AnsScalarType.Bool)
                    {
                        rejectReason = "condicao-if-nao-booleana";
                        return false;
                    }
                }
                foreach (Node s; ifs.body)
                    if (!verifyAnsStmt(s, sum, localTypes, paramTypes, rejectReason))
                        return false;
                if (ifs._else !is null)
                    if (!verifyAnsStmt(ifs._else, sum, localTypes, paramTypes, rejectReason))
                        return false;
                return true;
            case NodeKind.WhileStmt:
                WhileStmt ws = cast(WhileStmt) stmt;
                AnsScalarType wt = inferAnsExprType(ws.expr, localTypes, paramTypes, rejectReason);
                if (wt != AnsScalarType.Bool)
                {
                    rejectReason = "condicao-while-nao-booleana";
                    return false;
                }
                foreach (Node s; ws.body)
                    if (!verifyAnsStmt(s, sum, localTypes, paramTypes, rejectReason))
                        return false;
                return true;
            case NodeKind.DoStmt:
                DoStmt ds = cast(DoStmt) stmt;
                foreach (Node s; ds.body)
                    if (!verifyAnsStmt(s, sum, localTypes, paramTypes, rejectReason))
                        return false;
                AnsScalarType dt = inferAnsExprType(ds.condition, localTypes, paramTypes, rejectReason);
                if (dt != AnsScalarType.Bool)
                {
                    rejectReason = "condicao-do-nao-booleana";
                    return false;
                }
                return true;
            case NodeKind.ForStmt:
                ForStmt fs = cast(ForStmt) stmt;
                if (fs.init !is null && !verifyAnsStmt(fs.init, sum, localTypes, paramTypes, rejectReason))
                    return false;
                if (fs.condition !is null)
                {
                    AnsScalarType ft = inferAnsExprType(fs.condition, localTypes, paramTypes, rejectReason);
                    if (ft != AnsScalarType.Bool)
                    {
                        rejectReason = "condicao-for-nao-booleana";
                        return false;
                    }
                }
                if (fs.step !is null && !verifyAnsStmt(fs.step, sum, localTypes, paramTypes, rejectReason))
                    return false;
                foreach (Node s; fs.body)
                    if (!verifyAnsStmt(s, sum, localTypes, paramTypes, rejectReason))
                        return false;
                return true;
            case NodeKind.BreakStmt:
            case NodeKind.ContinueStmt:
                return true;
            case NodeKind.UnaryExpr:
                AnsScalarType ut = inferAnsExprType(stmt, localTypes, paramTypes, rejectReason);
                return ut != AnsScalarType.None;
            case NodeKind.CallExpr:
                AnsScalarType ct = inferAnsExprType(stmt, localTypes, paramTypes, rejectReason);
                return ct != AnsScalarType.None;
            default:
                rejectReason = "comando-nao-ans";
                return false;
        }
    }

    bool verifyAnsBody(FnDecl fn, FunctionMemorySummary* sum, ref string rejectReason)
    {
        AnsScalarType[VarDecl] localTypes;
        AnsScalarType[FnArg] paramTypes;
        foreach (size_t i, FnArg arg; fn.args)
            paramTypes[arg] = sum.ansParamTypes[i];
        foreach (Node st; fn.body)
            if (!verifyAnsStmt(st, sum, localTypes, paramTypes, rejectReason))
                return false;
        return true;
    }

    /// Conta campos de instância de uma classe fechada (+ superclasses + mixins).
    static size_t countClassInstanceSlots(ClassDecl c, ref bool[ClassDecl] seen)
    {
        if (c is null || c in seen)
            return 0;
        seen[c] = true;
        size_t total = 0;
        foreach (ClassField f; c.fields)
            if (!f.isEnum && !f.isStatic)
                total++;
        if (c.superClass !is null)
            total += countClassInstanceSlots(c.superClass, seen);
        foreach (ClassDecl mix; c.mixins)
            total += countClassInstanceSlots(mix, seen);
        return total;
    }

    static bool classHasCustomAccessorsOrDestructor(ClassDecl c, ref bool[ClassDecl] seen)
    {
        if (c is null || c in seen)
            return false;
        seen[c] = true;
        foreach (ClassField f; c.fields)
            if (f.customAccess)
                return true;
        foreach (FnDecl m; c.methods)
            if (m.fn == "destrutor"d)
                return true;
        if (c.superClass !is null && classHasCustomAccessorsOrDestructor(c.superClass, seen))
            return true;
        foreach (ClassDecl mix; c.mixins)
            if (classHasCustomAccessorsOrDestructor(mix, seen))
                return true;
        return false;
    }

    /// Verifica conservadoramente se uma variável local `target` NUNCA escapa do escopo.
    bool proveVarNoEscape(VarDecl target, Node[] scopeStmts, bool allowIndexReadWrite,
            bool allowFieldAccessOnClosedClass, ClassDecl closedClass)
    {
        bool escaped = false;
        bool reassigned = false;
        bool[Node] seen;

        bool isTargetIdent(Node n)
        {
            Identifier id = cast(Identifier) n;
            return id !is null && id.variableRef is target;
        }

        void checkNode(Node n, Node parent)
        {
            if (n is null || escaped || n in seen)
                return;
            seen[n] = true;

            if (VarDecl vd = cast(VarDecl) n)
            {
                if (vd is target)
                    return; // A própria inicialização é validada fora
                if (vd.value !is null)
                    checkNode(vd.value, vd);
                return;
            }
            if (cast(FnDecl) n !is null || cast(ClassDecl) n !is null)
                return;

            if (Identifier id = cast(Identifier) n)
            {
                if (id.variableRef !is target)
                    return;
                // Usos seguros permitidos para `target`:
                // 1) Base de leitura/escrita de campo `target.campo` em classe fechada
                if (MemberExpr mem = cast(MemberExpr) parent)
                {
                    if (allowFieldAccessOnClosedClass && mem.left is id)
                        return;
                    escaped = true;
                    return;
                }
                // 2) Base de leitura/escrita de índice `target[i]` em vetor/tupla local
                if (IndexExpr idx = cast(IndexExpr) parent)
                {
                    if (allowIndexReadWrite && idx.value is id)
                        return;
                    escaped = true;
                    return;
                }
                // 3) Argumento de chamada cuja posição foi provada não-escape (verificado em CallExpr)
                // Qualquer outro uso (ReturnStmt, AssignStmt RHS, ArrayLit, MapLit, ThrowStmt, etc.) escapa!
                escaped = true;
                return;
            }

            if (AssignStmt ass = cast(AssignStmt) n)
            {
                if (isTargetIdent(ass.left))
                {
                    reassigned = true;
                    escaped = true;
                    return;
                }
                if (isTargetIdent(ass.value))
                {
                    escaped = true;
                    return;
                }
                checkNode(ass.left, ass);
                checkNode(ass.value, ass);
                return;
            }

            if (MemberExpr mem = cast(MemberExpr) n)
            {
                // Se `target.campo` aparece fora de chamada ou leitura/escrita direta de campo (ex.: método ligado),
                // precisamos checar se `right` é um campo real da classe fechada!
                if (isTargetIdent(mem.left))
                {
                    if (!allowFieldAccessOnClosedClass || closedClass is null)
                    {
                        escaped = true;
                        return;
                    }
                    Identifier rightId = cast(Identifier) mem.right;
                    if (rightId is null)
                    {
                        escaped = true;
                        return;
                    }
                    // Se o pai é CallExpr onde `mem` é `call.fn`, será tratado pelo ramo CallExpr.
                    if (CallExpr pCall = cast(CallExpr) parent)
                    {
                        if (pCall.fn is mem)
                            return;
                    }
                    ClassMember cm = resolveClassMember(closedClass, rightId.value);
                    if (cm.field is null || cm.field.isStatic || cm.field.isEnum)
                    {
                        // Pode estar extraindo um método ligado (ligar(f, isto)) que retém ponteiro para target!
                        escaped = true;
                        return;
                    }
                    return;
                }
                checkNode(mem.left, mem);
                return;
            }

            if (CallExpr call = cast(CallExpr) n)
            {
                // Caso especial 1: `tamanho(target)` ou `target.tamanho()` / `target.adicionar(x)` / `target.empilhar(x)`
                if (Identifier fnId = cast(Identifier) call.fn)
                {
                    if (fnId.functionRef !is null && fnId.functionRef.builtinName == "tamanho"d
                            && call.args.length == 1 && isTargetIdent(call.args[0]))
                    {
                        return;
                    }
                }
                if (MemberExpr mem = cast(MemberExpr) call.fn)
                {
                    if (isTargetIdent(mem.left))
                    {
                        Identifier rightId = cast(Identifier) mem.right;
                        if (rightId !is null && allowIndexReadWrite)
                        {
                            dstring mname = rightId.value;
                            if (mname == "tamanho"d || mname == "adicionar"d || mname == "empilhar"d
                                    || mname == "removerUltimo"d || mname == "removerPrimeiro"d
                                    || mname == "somar"d || mname == "limpar"d || mname == "inverter"d)
                            {
                                // Ainda verifica se `target` aparece nos argumentos (ex: `v.adicionar(v)` = auto-escape!)
                                foreach (Node arg; call.args)
                                    checkNode(arg, call);
                                return;
                            }
                        }
                        if (rightId !is null && allowFieldAccessOnClosedClass && closedClass !is null)
                        {
                            ClassMember cm = resolveClassMember(closedClass, rightId.value);
                            if (cm.method !is null && !cm.method.isStatic && !cm.method.isAbstract
                                    && !hasDecoratorEnvelope(cm.method))
                            {
                                // Verifica se `isto` escapa dentro do método!
                                if (!methodEscapesSelf(cm.method))
                                {
                                    foreach (Node arg; call.args)
                                        checkNode(arg, call);
                                    return;
                                }
                            }
                        }
                        escaped = true;
                        return;
                    }
                }
                // Caso especial 2: chamada estática a função cujo parâmetro correspondente não escapa
                FnDecl callee = resolveStaticCallee(call);
                if (callee !is null && callee in plan.fnSummaries)
                {
                    FunctionMemorySummary* csum = callee in plan.fnSummaries;
                    checkNode(call.fn, call);
                    foreach (size_t i, Node arg; call.args)
                    {
                        if (isTargetIdent(arg))
                        {
                            if (i >= csum.paramEscapes.length || csum.paramEscapes[i])
                            {
                                escaped = true;
                                return;
                            }
                        }
                        else
                        {
                            checkNode(arg, call);
                        }
                    }
                    return;
                }
                // Qualquer outra chamada (dinâmica/builtin) assume escape conservador se target for argumento
                checkNode(call.fn, call);
                foreach (Node arg; call.args)
                    checkNode(arg, call);
                return;
            }

            foreach (Node ch; childNodes(n))
                checkNode(ch, n);
        }

        foreach (Node st; scopeStmts)
            checkNode(st, null);

        return !escaped && !reassigned;
    }

    /// Verifica se um método de classe fechada nunca escapa `isto`.
    bool methodEscapesSelf(FnDecl method)
    {
        if (method is null || method.isAsync || method.isAbstract || method.foreignSymbol.length
                || hasDecoratorEnvelope(method))
            return true;
        bool escapes = false;
        bool[Node] seen;

        bool isSelf(Node n)
        {
            Identifier id = cast(Identifier) n;
            return id !is null && id.value == "isto"d && id.variableRef is null && id.parameterRef is null;
        }

        void scan(Node n, Node parent)
        {
            if (n is null || escapes || n in seen)
                return;
            seen[n] = true;
            if (n !is method && (cast(FnDecl) n !is null || cast(ClassDecl) n !is null))
                return;
            if (isSelf(n))
            {
                if (MemberExpr m = cast(MemberExpr) parent)
                {
                    if (m.left is n && method.ownerClass !is null)
                    {
                        Identifier rid = cast(Identifier) m.right;
                        if (rid !is null)
                        {
                            ClassMember cm = resolveClassMember(method.ownerClass, rid.value);
                            if (cm.field !is null && !cm.field.isStatic && !cm.field.isEnum)
                                return;
                        }
                    }
                }
                escapes = true;
                return;
            }
            foreach (Node ch; childNodes(n))
                scan(ch, n);
        }

        foreach (Node st; method.body)
            scan(st, null);
        return escapes;
    }

    void analyzeLocalAllocationsInBlock(Node[] stmts, bool inTryFunction, bool inLoop,
            bool inAsyncFunction, bool isModuleTopLevel)
    {
        if (inAsyncFunction || isModuleTopLevel)
            return;

        foreach (size_t i, Node st; stmts)
        {
            if (VarDecl vd = cast(VarDecl) st)
            {
                if (vd.uninitialized || vd.value is null)
                    continue;

                // Candidato A: Instanciação direta de classe fechada -> Stack Allocation automática
                if (plan.config.enableStackAlloc && !inLoop)
                {
                    if (CallExpr ctorCall = cast(CallExpr) vd.value)
                    {
                        if (!ctorCall.runtimeCall && !ctorCall.args.anySpread())
                        {
                            ClassDecl cls = null;
                            if (Identifier cid = cast(Identifier) ctorCall.fn)
                                cls = cid.classRef;
                            if (cls !is null && !cls.isAbstract && !cls.isInterface && !cls.isForeign
                                    && !cls.isValueType && !cls.signature.builtinName.length
                                    && cls !in plan.classesWithSubclasses)
                            {
                                bool[ClassDecl] accSeen;
                                bool[ClassDecl] slotSeen;
                                size_t totalSlots = countClassInstanceSlots(cls, slotSeen);
                                bool hasCustom = classHasCustomAccessorsOrDestructor(cls, accSeen);
                                bool ctorSafe = true;
                                ClassMember ctorMember = resolveClassMember(cls, "construtor"d);
                                if (ctorMember.method !is null)
                                    ctorSafe = !methodEscapesSelf(ctorMember.method);
                                bool initSafe = true;
                                foreach (ClassField f; cls.fields)
                                    if (f.initializer !is null && methodEscapesSelf(f.initializer))
                                        initSafe = false;

                                if (!hasCustom && ctorSafe && initSafe && totalSlots <= 32)
                                {
                                    if (proveVarNoEscape(vd, stmts[i + 1 .. $], false, true, cls))
                                    {
                                        LocalAllocPlan lp;
                                        lp.decl = vd;
                                        lp.domain = StorageDomain.StackLocal;
                                        lp.escape = EscapeState.NoEscape;
                                        lp.ownership = OwnershipMode.ExclusiveLocal;
                                        lp.stackClass = cls;
                                        lp.stackSlots = totalSlots;
                                        lp.reason = "classe-fechada-nao-escapa";
                                        plan.localPlans[vd] = lp;
                                        plan.stackObjectsCount++;
                                        plan.stackObjectNames ~= vd.name.to!string ~ ":" ~ cls.name.to!string;
                                        continue;
                                    }
                                    else
                                    {
                                        plan.conservativeFallbacksCount++;
                                    }
                                }
                            }
                        }
                    }
                }

                // Candidato B: Vetor/Tupla local que não escapa -> Liberação determinística no fim do bloco
                if (plan.config.enableDetFree && !inTryFunction)
                {
                    bool isFreshArr = false;
                    if (ArrayLit al = cast(ArrayLit) vd.value)
                    {
                        if (!al.elements.anySpread())
                            isFreshArr = true;
                    }
                    if (isFreshArr)
                    {
                        // Apenas se não há comandos de salto complexos fora do bloco ou dentro de sub-blocos que
                        // precisem ser tratados — o codegen emite liberação em saída de bloco + return/break/continue.
                        if (proveVarNoEscape(vd, stmts[i + 1 .. $], true, false, null))
                        {
                            LocalAllocPlan lp;
                            lp.decl = vd;
                            lp.domain = StorageDomain.DeterministicHeap;
                            lp.escape = EscapeState.NoEscape;
                            lp.ownership = OwnershipMode.ExclusiveLocal;
                            lp.freeAtScopeExit = true;
                            lp.reason = "colecao-local-exclusiva";
                            plan.localPlans[vd] = lp;
                            plan.detFreeVarsCount++;
                            plan.detFreeVarNames ~= vd.name.to!string;
                        }
                        else
                        {
                            plan.conservativeFallbacksCount++;
                        }
                    }
                }
            }
            else if (BlockStmt blk = cast(BlockStmt) st)
            {
                analyzeLocalAllocationsInBlock(blk.body, inTryFunction, inLoop, inAsyncFunction, false);
            }
            else if (IfStmt ifs = cast(IfStmt) st)
            {
                analyzeLocalAllocationsInBlock(ifs.body, inTryFunction, inLoop, inAsyncFunction, false);
                if (ifs._else !is null)
                    analyzeLocalAllocationsInBlock([cast(Node) ifs._else], inTryFunction, inLoop,
                            inAsyncFunction, false);
            }
            else if (WhileStmt ws = cast(WhileStmt) st)
            {
                analyzeLocalAllocationsInBlock(ws.body, inTryFunction, true, inAsyncFunction, false);
            }
            else if (ForStmt fs = cast(ForStmt) st)
            {
                analyzeLocalAllocationsInBlock(fs.body, inTryFunction, true, inAsyncFunction, false);
            }
            else if (DoStmt ds = cast(DoStmt) st)
            {
                analyzeLocalAllocationsInBlock(ds.body, inTryFunction, true, inAsyncFunction, false);
            }
            else if (EachStmt es = cast(EachStmt) st)
            {
                analyzeLocalAllocationsInBlock(es.body, inTryFunction, true, inAsyncFunction, false);
            }
        }
    }

    static bool containsTry(Node[] stmts)
    {
        bool found = false;
        bool[Node] seen;
        void scan(Node n)
        {
            if (n is null || found || n in seen)
                return;
            seen[n] = true;
            if (cast(FnDecl) n !is null || cast(ClassDecl) n !is null)
                return;
            if (cast(TryStmt) n !is null)
            {
                found = true;
                return;
            }
            foreach (Node ch; childNodes(n))
                scan(ch);
        }

        foreach (Node st; stmts)
            scan(st);
        return found;
    }

public:
    MemoryPlan analyze(Program prog, MemoryOptConfig cfg = MemoryOptConfig.init)
    {
        plan = new MemoryPlan(cfg);
        bool[Node] visited;
        collectProgramDecls(prog, visited);
        buildCallGraph();
        FnDecl[][] sccs = computeTarjanSCCs();
        initializeSummaries(sccs);
        runFixedPointSummaries(sccs);
        analyzeAnsEligibility();

        foreach (FnDecl fn; allFns)
        {
            if (fn.isNative || fn.isAsync || fn.isAbstract || fn.foreignSymbol.length)
                continue;
            if (fn.ownerClass !is null && fn.ownerClass.isValueType)
                continue;
            const(FunctionMemorySummary)* sum = fn in plan.fnSummaries;
            if (sum !is null && sum.ansEligible)
                continue;
            analyzeLocalAllocationsInBlock(fn.body, containsTry(fn.body), false, false, false);
        }

        // Também analisa blocos do programa principal (delegua_main)
        analyzeLocalAllocationsInBlock(prog.body, containsTry(prog.body), false, false, false);
        return plan;
    }
}

private bool anySpread(Node[] nodes)
{
    foreach (Node n; nodes)
        if (n !is null && n.kind == NodeKind.SpreadExpr)
            return true;
    return false;
}

MemoryPlan analyzeHybridMemory(Program prog, MemoryOptConfig cfg = MemoryOptConfig.init)
{
    InterproceduralMemoryAnalyzer analyzer = new InterproceduralMemoryAnalyzer();
    return analyzer.analyze(prog, cfg);
}
