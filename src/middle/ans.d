module middle.ans;

import backend.c.utils;
import frontend.lexer.token : TokenKind;
import frontend.parser.ast;
import frontend.semantic.interprocedural : classifyAnsType;
import frontend.type_expr;
import middle.memory_model;
import std.array : join;
import std.conv : to;
import std.math : isFinite;
import std.algorithm : canFind;

/// Gerador de Especialização Nativa Automática (ANS) para funções Delégua puramente escalares.
/// Preserva 100% da semântica observável da linguagem:
///   - Overflow assinado de 64 bits verificado via intrinsics (`__builtin_*_overflow`) -> `delegua_panic`
///   - Divisão/módulo por zero e `INT64_MIN / -1` -> `delegua_panic`
///   - Deslocamento fora de `0..63` -> `delegua_panic`
///   - Limite de recursão (`delegua_call_depth >= 1024`) preservado em funções recursivas
///   - Safepoints cooperativos amortizados em laços
final class AnsCodegen
{
private:
    MemoryPlan plan;
    size_t tmpId;
    bool helpersEmitted;
    dstring[] prototypes;
    dstring[] definitions;
    dstring[] loopContinueLabels;
    bool[FnDecl] emittedFns;

    static dstring cType(AnsScalarType t)
    {
        final switch (t)
        {
            case AnsScalarType.Int64:
                return "i64"d;
            case AnsScalarType.Float64:
                return "f64"d;
            case AnsScalarType.Bool:
                return "bool"d;
            case AnsScalarType.Void:
                return "void"d;
            case AnsScalarType.None:
                return "delegua_value"d;
        }
    }

    static dstring boxValue(AnsScalarType t, dstring expr)
    {
        final switch (t)
        {
            case AnsScalarType.Int64:
                return formatD("create_num(%s)", expr);
            case AnsScalarType.Float64:
                return formatD("create_real(%s)", expr);
            case AnsScalarType.Bool:
                return formatD("create_bool(%s)", expr);
            case AnsScalarType.Void:
                return "create_nulo()"d;
            case AnsScalarType.None:
                return expr;
        }
    }

    static dstring unboxValue(AnsScalarType t, dstring expr)
    {
        final switch (t)
        {
            case AnsScalarType.Int64:
                return formatD("(%s).value.num", expr);
            case AnsScalarType.Float64:
                return formatD("((%s).type == DELEGUA_T_NUM ? (f64)(%s).value.num : (%s).value.real)",
                        expr, expr, expr);
            case AnsScalarType.Bool:
                return formatD("(%s).value.b1", expr);
            case AnsScalarType.Void:
            case AnsScalarType.None:
                return expr;
        }
    }

    static dstring ansFnSym(FnDecl fn)
    {
        return "cgd_ans_"d ~ cName(fn.linkName);
    }

    void ensureHelpers()
    {
        if (helpersEmitted)
            return;
        helpersEmitted = true;
        prototypes ~= q"C
/* === CGD Automatic Native Specialization (ANS) Checked Helpers === */
#if defined(__GNUC__) || defined(__clang__)
#define CGD_ANS_HELPER static inline __attribute__((unused))
#else
#define CGD_ANS_HELPER static inline
#endif
CGD_ANS_HELPER i64 cgd_ans_iadd(i64 a, i64 b) {
#if defined(__GNUC__) || defined(__clang__)
    i64 res;
    if (DELEGUA_UNLIKELY(__builtin_add_overflow(a, b, &res)))
        delegua_panic("Overflow inteiro.");
    return res;
#else
    if ((b > 0 && a > INT64_MAX - b) || (b < 0 && a < INT64_MIN - b))
        delegua_panic("Overflow inteiro.");
    return a + b;
#endif
}
CGD_ANS_HELPER i64 cgd_ans_isub(i64 a, i64 b) {
#if defined(__GNUC__) || defined(__clang__)
    i64 res;
    if (DELEGUA_UNLIKELY(__builtin_sub_overflow(a, b, &res)))
        delegua_panic("Overflow inteiro.");
    return res;
#else
    if ((b < 0 && a > INT64_MAX + b) || (b > 0 && a < INT64_MIN + b))
        delegua_panic("Overflow inteiro.");
    return a - b;
#endif
}
CGD_ANS_HELPER i64 cgd_ans_imul(i64 a, i64 b) {
#if defined(__GNUC__) || defined(__clang__)
    i64 res;
    if (DELEGUA_UNLIKELY(__builtin_mul_overflow(a, b, &res)))
        delegua_panic("Overflow inteiro.");
    return res;
#else
    if (a > 0) {
        if ((b > 0 && a > INT64_MAX / b) || (b < 0 && b < INT64_MIN / a))
            delegua_panic("Overflow inteiro.");
    } else if (a < 0) {
        if ((b > 0 && a < INT64_MIN / b) || (b < 0 && b < INT64_MAX / a))
            delegua_panic("Overflow inteiro.");
    }
    return a * b;
#endif
}
CGD_ANS_HELPER i64 cgd_ans_idiv(i64 a, i64 b) {
    if (DELEGUA_UNLIKELY(b == 0))
        delegua_panic("Divisão por zero.");
    if (DELEGUA_UNLIKELY(a == INT64_MIN && b == -1))
        delegua_panic("Overflow na divisão inteira.");
    return a / b;
}
CGD_ANS_HELPER i64 cgd_ans_imod(i64 a, i64 b) {
    if (DELEGUA_UNLIKELY(b == 0))
        delegua_panic("Divisão por zero.");
    if (DELEGUA_UNLIKELY(a == INT64_MIN && b == -1))
        return 0;
    return a % b;
}
CGD_ANS_HELPER f64 cgd_ans_fdiv(f64 a, f64 b) {
    if (DELEGUA_UNLIKELY(b == 0.0))
        delegua_panic("Divisão por zero.");
    return a / b;
}
CGD_ANS_HELPER i64 cgd_ans_shl(i64 a, i64 b) {
    if (DELEGUA_UNLIKELY(b < 0 || b >= 64))
        delegua_panic("Deslocamento fora do intervalo 0..63.");
    u64 bits = (u64)a << (u64)b;
    i64 res;
    memcpy(&res, &bits, sizeof(res));
    return res;
}
CGD_ANS_HELPER i64 cgd_ans_shr(i64 a, i64 b) {
    if (DELEGUA_UNLIKELY(b < 0 || b >= 64))
        delegua_panic("Deslocamento fora do intervalo 0..63.");
    return a >> b;
}
C"d;
    }

    AnsScalarType exprType(Node expr, ref AnsScalarType[VarDecl] locals,
            ref AnsScalarType[FnArg] params)
    {
        if (expr is null)
            return AnsScalarType.Void;
        if (cast(IntLit) expr !is null)
            return AnsScalarType.Int64;
        if (cast(DoubleLit) expr !is null)
            return AnsScalarType.Float64;
        if (cast(BoolLit) expr !is null)
            return AnsScalarType.Bool;
        if (Identifier id = cast(Identifier) expr)
        {
            if (id.parameterRef !is null)
                if (AnsScalarType* pt = id.parameterRef in params)
                    return *pt;
            if (id.variableRef !is null)
                if (AnsScalarType* vt = id.variableRef in locals)
                    return *vt;
            return AnsScalarType.None;
        }
        if (MemberExpr mem = cast(MemberExpr) expr)
            return mem.enumValue !is null ? AnsScalarType.Int64 : AnsScalarType.None;
        if (UnaryExpr un = cast(UnaryExpr) expr)
            return exprType(un.value, locals, params);
        if (BinaryExpr bin = cast(BinaryExpr) expr)
            return AnsScalarType.Bool;
        if (ConditionalExpr cond = cast(ConditionalExpr) expr)
            return exprType(cond.yes, locals, params);
        if (CallExpr call = cast(CallExpr) expr)
        {
            if (call.runtimeCall)
            {
                dstring op = (cast(Identifier) call.fn).value;
                if (op == "delegua_op_not" || op == "delegua_op_lt" || op == "delegua_op_le"
                        || op == "delegua_op_gt" || op == "delegua_op_ge"
                        || op == "delegua_op_eq" || op == "delegua_op_neq")
                    return AnsScalarType.Bool;
                if (op == "delegua_op_div")
                    return AnsScalarType.Float64;
                if (op == "delegua_op_add" || op == "delegua_op_sub" || op == "delegua_op_mul")
                {
                    AnsScalarType lt = exprType(call.args[0], locals, params);
                    AnsScalarType rt = exprType(call.args[1], locals, params);
                    return (lt == AnsScalarType.Float64 || rt == AnsScalarType.Float64)
                        ? AnsScalarType.Float64 : AnsScalarType.Int64;
                }
                return AnsScalarType.Int64;
            }
            if (Identifier fnId = cast(Identifier) call.fn)
            {
                if (fnId.functionRef !is null && fnId.functionRef.builtinName.length)
                    return AnsScalarType.Float64;
                if (fnId.functionRef !is null)
                {
                    const(FunctionMemorySummary)* ts = plan.summaryOf(fnId.functionRef);
                    if (ts !is null && ts.ansEligible)
                        return ts.ansReturnType;
                }
            }
        }
        return AnsScalarType.None;
    }

    dstring emitExpr(Node expr, ref AnsScalarType[VarDecl] locals, ref AnsScalarType[FnArg] params,
            AnsScalarType coerceTo = AnsScalarType.None)
    {
        dstring raw = emitExprRaw(expr, locals, params);
        if (coerceTo == AnsScalarType.Float64 && exprType(expr, locals, params) == AnsScalarType.Int64)
            return formatD("((f64)(%s))", raw);
        return raw;
    }

    dstring emitExprRaw(Node expr, ref AnsScalarType[VarDecl] locals, ref AnsScalarType[FnArg] params)
    {
        if (IntLit il = cast(IntLit) expr)
            return il.value == long.min ? "INT64_MIN"d : formatD("INT64_C(%s)", il.value);
        if (DoubleLit dl = cast(DoubleLit) expr)
        {
            dstring lit = formatD("%.17g", dl.value);
            if (!lit.canFind('.') && !lit.canFind('e') && !lit.canFind('E'))
                lit ~= ".0";
            return lit;
        }
        if (BoolLit bl = cast(BoolLit) expr)
            return bl.value ? "true"d : "false"d;
        if (Identifier id = cast(Identifier) expr)
            return cName(id.value);
        if (MemberExpr mem = cast(MemberExpr) expr)
            if (mem.enumValue !is null)
                return formatD("INT64_C(%s)", mem.enumValue.value);
        if (UnaryExpr un = cast(UnaryExpr) expr)
        {
            dstring target = emitExprRaw(un.value, locals, params);
            AnsScalarType t = exprType(un.value, locals, params);
            if (un.op == TokenKind.PPlus || un.op == TokenKind.MMinus)
            {
                dstring step = t == AnsScalarType.Float64
                    ? (un.op == TokenKind.PPlus ? formatD("(%s + 1.0)", target) : formatD("(%s - 1.0)", target))
                    : (un.op == TokenKind.PPlus
                        ? formatD("cgd_ans_iadd(%s, INT64_C(1))", target)
                        : formatD("cgd_ans_isub(%s, INT64_C(1))", target));
                if (!un.post)
                    return formatD("(%s = %s)", target, step);
                // Pós-incremento/decremento como expressão
                dstring opStr = un.op == TokenKind.PPlus ? "1"d : "-1"d;
                if (t == AnsScalarType.Float64)
                    return un.op == TokenKind.PPlus ? formatD("(%s++)", target) : formatD("(%s--)", target);
                return formatD("(%s = %s, %s - (%s))", target, step, target, opStr);
            }
        }
        if (BinaryExpr bin = cast(BinaryExpr) expr)
        {
            dstring l = emitExprRaw(bin.left, locals, params);
            dstring r = emitExprRaw(bin.right, locals, params);
            return bin.op == TokenKind.And ? formatD("((%s) && (%s))", l, r) : formatD("((%s) || (%s))", l, r);
        }
        if (ConditionalExpr cond = cast(ConditionalExpr) expr)
        {
            dstring c = emitExprRaw(cond.condition, locals, params);
            dstring y = emitExprRaw(cond.yes, locals, params);
            dstring n = emitExprRaw(cond.no, locals, params);
            return formatD("((%s) ? (%s) : (%s))", c, y, n);
        }
        if (CallExpr call = cast(CallExpr) expr)
        {
            if (call.runtimeCall)
            {
                dstring op = (cast(Identifier) call.fn).value;
                if (call.args.length == 1)
                {
                    dstring a0 = emitExprRaw(call.args[0], locals, params);
                    if (op == "delegua_op_not")
                        return formatD("(!(%s))", a0);
                    if (op == "delegua_op_bnt")
                        return formatD("(~(%s))", a0);
                }
                if (call.args.length == 2)
                {
                    AnsScalarType lt = exprType(call.args[0], locals, params);
                    AnsScalarType rt = exprType(call.args[1], locals, params);
                    bool useFloat = (lt == AnsScalarType.Float64 || rt == AnsScalarType.Float64
                            || op == "delegua_op_div");
                    dstring l = useFloat ? emitExpr(call.args[0], locals, params, AnsScalarType.Float64)
                                         : emitExprRaw(call.args[0], locals, params);
                    dstring r = useFloat ? emitExpr(call.args[1], locals, params, AnsScalarType.Float64)
                                         : emitExprRaw(call.args[1], locals, params);
                    switch (op)
                    {
                        case "delegua_op_add":
                            return useFloat ? formatD("((%s) + (%s))", l, r)
                                            : formatD("cgd_ans_iadd(%s, %s)", l, r);
                        case "delegua_op_sub":
                            return useFloat ? formatD("((%s) - (%s))", l, r)
                                            : formatD("cgd_ans_isub(%s, %s)", l, r);
                        case "delegua_op_mul":
                            return useFloat ? formatD("((%s) * (%s))", l, r)
                                            : formatD("cgd_ans_imul(%s, %s)", l, r);
                        case "delegua_op_div":
                            return formatD("cgd_ans_fdiv(%s, %s)", l, r);
                        case "delegua_op_idiv":
                            return formatD("cgd_ans_idiv(%s, %s)", l, r);
                        case "delegua_op_mod":
                            return formatD("cgd_ans_imod(%s, %s)", l, r);
                        case "delegua_op_bor":
                            return formatD("((%s) | (%s))", l, r);
                        case "delegua_op_bnd":
                            return formatD("((%s) & (%s))", l, r);
                        case "delegua_op_bxr":
                            return formatD("((%s) ^ (%s))", l, r);
                        case "delegua_op_shl":
                            return formatD("cgd_ans_shl(%s, %s)", l, r);
                        case "delegua_op_shr":
                            return formatD("cgd_ans_shr(%s, %s)", l, r);
                        case "delegua_op_lt":
                            return formatD("((%s) < (%s))", l, r);
                        case "delegua_op_le":
                            return formatD("((%s) <= (%s))", l, r);
                        case "delegua_op_gt":
                            return formatD("((%s) > (%s))", l, r);
                        case "delegua_op_ge":
                            return formatD("((%s) >= (%s))", l, r);
                        case "delegua_op_eq":
                            return formatD("((%s) == (%s))", l, r);
                        case "delegua_op_neq":
                            return formatD("((%s) != (%s))", l, r);
                        default:
                            break;
                    }
                }
            }
            if (Identifier fnId = cast(Identifier) call.fn)
            {
                if (fnId.functionRef !is null && fnId.functionRef.builtinName.length
                        && call.args.length == 1)
                {
                    return formatD("((f64)(%s))", emitExprRaw(call.args[0], locals, params));
                }
                if (fnId.functionRef !is null)
                {
                    FnDecl target = fnId.functionRef;
                    const(FunctionMemorySummary)* ts = plan.summaryOf(target);
                    if (ts !is null && ts.ansEligible)
                    {
                        ensureFunctionEmitted(target);
                        plan.ansCallSitesCount++;
                        dstring[] argExprs;
                        foreach (size_t i, Node a; call.args)
                            argExprs ~= emitExpr(a, locals, params, ts.ansParamTypes[i]);
                        return formatD("%s(%s)", ansFnSym(target), argExprs.join(", "));
                    }
                }
            }
        }
        return "0"d;
    }

    dstring emitStmt(Node stmt, const(FunctionMemorySummary)* sum, ref AnsScalarType[VarDecl] locals,
            ref AnsScalarType[FnArg] params, bool trackRecursion)
    {
        if (stmt is null || stmt.kind == NodeKind.NaN)
            return ""d;
        switch (stmt.kind)
        {
            case NodeKind.SequenceStmt:
                dstring[] outLines;
                foreach (Node s; (cast(SequenceStmt) stmt).body)
                    outLines ~= emitStmt(s, sum, locals, params, trackRecursion);
                return outLines.join("\n");
            case NodeKind.BlockStmt:
                dstring[] outLines;
                foreach (Node s; (cast(BlockStmt) stmt).body)
                    outLines ~= emitStmt(s, sum, locals, params, trackRecursion);
                return "{\n"d ~ outLines.join("\n") ~ "\n}"d;
            case NodeKind.VarDecl:
                VarDecl vd = cast(VarDecl) stmt;
                AnsScalarType initT = exprType(vd.value, locals, params);
                AnsScalarType declT = vd.type_expr !is null ? classifyAnsType(vd.type_expr, false) : initT;
                locals[vd] = declT;
                return formatD("%s %s = %s;", cType(declT), cName(vd.name),
                        emitExpr(vd.value, locals, params, declT));
            case NodeKind.AssignStmt:
                AssignStmt ass = cast(AssignStmt) stmt;
                Identifier lhs = cast(Identifier) ass.left;
                AnsScalarType lt = exprType(lhs, locals, params);
                return formatD("%s = %s;", cName(lhs.value), emitExpr(ass.value, locals, params, lt));
            case NodeKind.ReturnStmt:
                ReturnStmt ret = cast(ReturnStmt) stmt;
                if (sum.ansReturnType == AnsScalarType.Void)
                    return trackRecursion ? "{ delegua_call_depth--; return; }"d : "return;"d;
                dstring v = emitExpr(ret.val, locals, params, sum.ansReturnType);
                if (trackRecursion)
                {
                    dstring tmpName = formatD("cgd_ans_ret_%s", tmpId++);
                    return formatD("{ %s %s = %s; delegua_call_depth--; return %s; }",
                            cType(sum.ansReturnType), tmpName, v, tmpName);
                }
                return formatD("return %s;", v);
            case NodeKind.IfStmt:
                IfStmt ifs = cast(IfStmt) stmt;
                dstring[] bodyLines;
                foreach (Node s; ifs.body)
                    bodyLines ~= emitStmt(s, sum, locals, params, trackRecursion);
                if (ifs.expr is null)
                    return "{\n"d ~ bodyLines.join("\n") ~ "\n}"d;
                dstring cond = emitExprRaw(ifs.expr, locals, params);
                dstring res = formatD("if (%s) {\n%s\n}", cond, bodyLines.join("\n"));
                if (ifs._else !is null)
                    res ~= " else "d ~ emitStmt(ifs._else, sum, locals, params, trackRecursion);
                return res;
            case NodeKind.WhileStmt:
                WhileStmt ws = cast(WhileStmt) stmt;
                dstring spVar = formatD("cgd_sp_%s", tmpId++);
                loopContinueLabels ~= ""d;
                dstring[] bodyLines;
                if (plan.config.enableSafepoints)
                    bodyLines ~= formatD("if (DELEGUA_UNLIKELY((++%s & 1023U) == 0)) cgd_gc_safepoint();", spVar);
                foreach (Node s; ws.body)
                    bodyLines ~= emitStmt(s, sum, locals, params, trackRecursion);
                loopContinueLabels.length--;
                dstring spDecl = plan.config.enableSafepoints ? formatD("unsigned %s = 0;\n", spVar) : ""d;
                return formatD("{ %swhile (%s) {\n%s\n} }", spDecl,
                        emitExprRaw(ws.expr, locals, params), bodyLines.join("\n"));
            case NodeKind.DoStmt:
                DoStmt ds = cast(DoStmt) stmt;
                dstring spVar = formatD("cgd_sp_%s", tmpId++);
                loopContinueLabels ~= ""d;
                dstring[] bodyLines;
                if (plan.config.enableSafepoints)
                    bodyLines ~= formatD("if (DELEGUA_UNLIKELY((++%s & 1023U) == 0)) cgd_gc_safepoint();", spVar);
                foreach (Node s; ds.body)
                    bodyLines ~= emitStmt(s, sum, locals, params, trackRecursion);
                loopContinueLabels.length--;
                dstring spDecl = plan.config.enableSafepoints ? formatD("unsigned %s = 0;\n", spVar) : ""d;
                return formatD("{ %sdo {\n%s\n} while (%s); }", spDecl, bodyLines.join("\n"),
                        emitExprRaw(ds.condition, locals, params));
            case NodeKind.ForStmt:
                ForStmt fs = cast(ForStmt) stmt;
                dstring initStr = fs.init !is null ? emitStmt(fs.init, sum, locals, params, trackRecursion) : ""d;
                dstring condStr = fs.condition !is null ? emitExprRaw(fs.condition, locals, params) : "1"d;
                dstring stepStr = fs.step !is null ? emitStmt(fs.step, sum, locals, params, trackRecursion) : ""d;
                dstring spVar = formatD("cgd_sp_%s", tmpId++);
                dstring contLbl = formatD("cgd_ans_cont_%s", tmpId++);
                loopContinueLabels ~= contLbl;
                dstring[] bodyLines;
                if (plan.config.enableSafepoints)
                    bodyLines ~= formatD("if (DELEGUA_UNLIKELY((++%s & 1023U) == 0)) cgd_gc_safepoint();", spVar);
                foreach (Node s; fs.body)
                    bodyLines ~= emitStmt(s, sum, locals, params, trackRecursion);
                loopContinueLabels.length--;
                dstring spDecl = plan.config.enableSafepoints ? formatD("unsigned %s = 0;\n", spVar) : ""d;
                return formatD("{\n%s\n%swhile (%s) {\n%s\n%s: ;\n%s\n}\n}", initStr, spDecl, condStr,
                        bodyLines.join("\n"), contLbl, stepStr);
            case NodeKind.BreakStmt:
                return "break;"d;
            case NodeKind.ContinueStmt:
                if (loopContinueLabels.length > 0 && loopContinueLabels[$ - 1].length > 0)
                    return formatD("goto %s;", loopContinueLabels[$ - 1]);
                return "continue;"d;
            case NodeKind.UnaryExpr:
                UnaryExpr un = cast(UnaryExpr) stmt;
                dstring target = emitExprRaw(un.value, locals, params);
                AnsScalarType t = exprType(un.value, locals, params);
                if (t == AnsScalarType.Float64)
                    return un.op == TokenKind.PPlus ? formatD("%s += 1.0;", target) : formatD("%s -= 1.0;", target);
                return un.op == TokenKind.PPlus
                    ? formatD("%s = cgd_ans_iadd(%s, INT64_C(1));", target, target)
                    : formatD("%s = cgd_ans_isub(%s, INT64_C(1));", target, target);
            case NodeKind.CallExpr:
                return formatD("(void)(%s);", emitExprRaw(stmt, locals, params));
            default:
                return ""d;
        }
    }

public:
    this(MemoryPlan plan)
    {
        this.plan = plan;
    }

    bool canSpecialize(FnDecl fn) const
    {
        return plan !is null && plan.isAnsFunction(fn);
    }

    /// Garante que o protótipo e a definição da versão especializada `cgd_ans_<fn>` sejam emitidos.
    void ensureFunctionEmitted(FnDecl fn)
    {
        if (!canSpecialize(fn) || fn in emittedFns)
            return;
        emittedFns[fn] = true;
        ensureHelpers();

        const(FunctionMemorySummary)* sum = plan.summaryOf(fn);
        dstring sym = ansFnSym(fn);
        dstring retC = cType(sum.ansReturnType);

        dstring[] paramDecls;
        AnsScalarType[FnArg] paramMap;
        foreach (size_t i, FnArg arg; fn.args)
        {
            paramDecls ~= formatD("%s %s", cType(sum.ansParamTypes[i]), cName(arg.name));
            paramMap[arg] = sum.ansParamTypes[i];
        }
        dstring sig = formatD("static %s %s(%s)", retC, sym,
                paramDecls.length ? paramDecls.join(", ") : "void"d);
        prototypes ~= sig ~ ";";

        AnsScalarType[VarDecl] localMap;
        bool trackRecursion = sum.isRecursive;
        dstring[] bodyLines;
        if (trackRecursion)
        {
            bodyLines ~= "if (DELEGUA_UNLIKELY(delegua_call_depth >= 1024)) delegua_panic(\"Limite de recursão em execução excedido.\");"d;
            bodyLines ~= "delegua_call_depth++;"d;
        }
        foreach (Node st; fn.body)
            bodyLines ~= emitStmt(st, sum, localMap, paramMap, trackRecursion);

        // Retorno implícito de segurança no fim do corpo
        if (sum.ansReturnType == AnsScalarType.Void)
        {
            if (trackRecursion)
                bodyLines ~= "delegua_call_depth--;"d;
        }
        else
        {
            if (trackRecursion)
                bodyLines ~= "delegua_call_depth--;"d;
            if (sum.ansReturnType == AnsScalarType.Int64)
                bodyLines ~= "return 0;"d;
            else if (sum.ansReturnType == AnsScalarType.Float64)
                bodyLines ~= "return 0.0;"d;
            else if (sum.ansReturnType == AnsScalarType.Bool)
                bodyLines ~= "return false;"d;
        }

        definitions ~= sig ~ " {\n"d ~ bodyLines.join("\n") ~ "\n}\n"d;
    }

    /// Emite o wrapper gerenciado `delegua_value <fn>(sz argc, delegua_value *argv)` delegando para `cgd_ans_<fn>`.
    dstring emitManagedWrapper(FnDecl fn, dstring managedProto)
    {
        ensureFunctionEmitted(fn);
        const(FunctionMemorySummary)* sum = plan.summaryOf(fn);
        dstring[] lines;
        lines ~= managedProto ~ " {"d;
        lines ~= "(void)argc; (void)argv;"d;
        dstring[] callArgs;
        foreach (size_t i, FnArg arg; fn.args)
        {
            AnsScalarType pt = sum.ansParamTypes[i];
            dstring argVal = formatD("argv[%s]", i);
            dstring checkedArg = argVal;
            if (pt == AnsScalarType.Int64)
                checkedArg = formatD("delegua_assegurar_inteiro(%s)", argVal);
            else if (pt == AnsScalarType.Float64)
                checkedArg = formatD("delegua_assegurar_real(%s)", argVal);
            else if (pt == AnsScalarType.Bool)
                checkedArg = formatD("delegua_assegurar_logico(%s)", argVal);
            dstring tmpV = formatD("cgd_wa_%s", i);
            lines ~= formatD("delegua_value %s = %s;", tmpV, checkedArg);
            callArgs ~= unboxValue(pt, tmpV);
        }
        dstring callExpr = formatD("%s(%s)", ansFnSym(fn), callArgs.join(", "));
        if (sum.ansReturnType == AnsScalarType.Void)
        {
            lines ~= callExpr ~ ";"d;
            lines ~= "return create_nulo();"d;
        }
        else
        {
            lines ~= formatD("return %s;", boxValue(sum.ansReturnType, callExpr));
        }
        lines ~= "}"d;
        return lines.join("\n");
    }

    /// Emite uma chamada direta a `cgd_ans_<fn>` a partir de código gerenciado,
    /// retornando `delegua_value` (evitando `delegua_chamar_direto` e array temporário de `argv`).
    dstring emitDirectCallFromManaged(FnDecl fn, dstring[] compiledArgs)
    {
        ensureFunctionEmitted(fn);
        const(FunctionMemorySummary)* sum = plan.summaryOf(fn);
        plan.ansCallSitesCount++;
        dstring[] unboxedArgs;
        foreach (size_t i, dstring ca; compiledArgs)
        {
            AnsScalarType pt = sum.ansParamTypes[i];
            if (pt == AnsScalarType.Int64)
                unboxedArgs ~= formatD("delegua_assegurar_inteiro(%s).value.num", ca);
            else if (pt == AnsScalarType.Float64)
                unboxedArgs ~= formatD("delegua_conv_real(delegua_assegurar_real(%s)).value.real", ca);
            else if (pt == AnsScalarType.Bool)
                unboxedArgs ~= formatD("delegua_assegurar_logico(%s).value.b1", ca);
        }
        dstring callExpr = formatD("%s(%s)", ansFnSym(fn), unboxedArgs.join(", "));
        if (sum.ansReturnType == AnsScalarType.Void)
            return formatD("(%s, create_nulo())", callExpr);
        return boxValue(sum.ansReturnType, callExpr);
    }

    dstring emitPrototypes() const
    {
        return prototypes.length ? prototypes.join("\n") ~ "\n"d : ""d;
    }

    dstring emitDefinitions() const
    {
        return definitions.length ? definitions.join("\n") ~ "\n"d : ""d;
    }
}
