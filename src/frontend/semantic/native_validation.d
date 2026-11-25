module frontend.semantic.native_validation;

import diagnostics.catalog;
import errors;
import frontend.lexer.token : Position, TokenKind;
import frontend.parser.ast;
import frontend.semantic.value_types;
import frontend.type_sema;
import std.conv : to;

/// Nomes dos casts explícitos de tipos C nativos.
bool isNativeCastName(dstring name)
{
    switch (name)
    {
        case "ci8":
        case "cu8":
        case "ci16":
        case "cu16":
        case "ci32":
        case "cu32":
        case "ci64":
        case "cu64":
        case "cchar":
        case "cschar":
        case "cuchar":
        case "cshort":
        case "cushort":
        case "cint":
        case "cuint":
        case "clong":
        case "culong":
        case "csize":
        case "cf32":
        case "cf64":
        case "cfloat":
        case "cdouble":
        case "cbool":
            return true;
        default:
            return false;
    }
}

/// Funções matemáticas intrínsecas suportadas diretamente via `<math.h>` em `@nativo`.
bool isNativeMathIntrinsic(dstring modName, dstring fnName)
{
    if (modName != "Matematica"d && modName != "Matemática"d)
        return false;
    switch (fnName)
    {
        case "raiz":
        case "raizQuadrada":
        case "seno":
        case "cosseno":
        case "tangente":
        case "absoluto":
        case "piso":
        case "teto":
        case "arredondar":
        case "potencia":
        case "potência":
        case "logaritmo":
        case "exponencial":
        case "minimo":
        case "mínimo":
        case "maximo":
        case "máximo":
        case "arcoSeno":
        case "arcoCosseno":
        case "arcoTangente":
        case "arcoTangente2":
            return true;
        default:
            return false;
    }
}

/// Verifica se uma conversão implícita entre tipos C em `@nativo` é potencialmente insegura.
bool isUnsafeImplicitNativeConversion(TypeSema expected, Node valueNode, TypeSema actual)
{
    if (expected is null || actual is null)
        return false;
    TypeSemaNative dst = cast(TypeSemaNative) expected;
    if (dst is null)
        return false;

    // Literais inteiros constantes que cabem no tipo de destino são seguros.
    if (IntLit lit = cast(IntLit) valueNode)
    {
        if (dst.isFloat())
            return false;
        if (dst.isUnsigned())
            return lit.value < 0;
        if (dst.scalar == NativeScalarKind.I8)
            return lit.value < byte.min || lit.value > byte.max;
        if (dst.scalar == NativeScalarKind.I16 || dst.scalar == NativeScalarKind.CShort)
            return lit.value < short.min || lit.value > short.max;
        if (dst.scalar == NativeScalarKind.I32 || dst.scalar == NativeScalarKind.CInt)
            return lit.value < int.min || lit.value > int.max;
        return false;
    }
    if (DoubleLit flit = cast(DoubleLit) valueNode)
    {
        return !dst.isFloat();
    }
    if (cast(BoolLit) valueNode !is null)
        return !dst.isBool();

    TypeSemaNative src = cast(TypeSemaNative) actual;
    if (src !is null)
    {
        if (src.scalar == dst.scalar)
            return false;
        // Float -> Inteiro exige cast explícito
        if (src.isFloat() && dst.isInteger())
            return true;
        // Bool <-> Numérico exige cast explícito
        if (src.isBool() != dst.isBool())
            return true;
        // Narrowing de float (cf64 -> cf32) exige cast explícito
        if (src.isFloat() && dst.isFloat() && src.bitWidth() > dst.bitWidth())
            return true;
        // Narrowing inteiro (ex.: ci64 -> ci32, ci32 -> ci8) exige cast explícito
        if (src.isInteger() && dst.isInteger() && src.bitWidth() > dst.bitWidth())
            return true;
        // Troca de sinal (signed <-> unsigned) exige cast explícito
        if (src.isInteger() && dst.isInteger() && src.isUnsigned() != dst.isUnsigned())
            return true;
        return false;
    }

    if (TypeSemaBuiltin b = cast(TypeSemaBuiltin) actual)
    {
        if (b.base == TypeSemaBase.Double && dst.isInteger())
            return true;
        if (b.base == TypeSemaBase.Bool && !dst.isBool())
            return true;
        if (b.base == TypeSemaBase.Int && dst.isBool())
            return true;
    }
    return false;
}

final class NativeValidator
{
private:
    Diagnostics diag;
    bool[Node] visited;
    FnDecl currentNativeFn;

    bool isEligibleNativeMethod(FnDecl fn)
    {
        if (fn is null)
            return false;
        if (fn.isNative)
            return true;
        if (fn.ownerClass !is null && fn.ownerClass.isValueType && !fn.accessor && !fn.isAbstract)
            return true;
        if (fn.ownerClass !is null && fn.ownerClass.isForeign && !fn.foreignManaged)
            return true;
        return false;
    }

    bool isStringNativaFactoryCall(CallExpr call)
    {
        MemberExpr m = cast(MemberExpr) call.fn;
        if (m is null)
            return false;
        Identifier left = cast(Identifier) m.left;
        Identifier right = cast(Identifier) m.right;
        return left !is null && right !is null && left.value == "StringNativa"d
            && (right.value == "criar"d || right.value == "vazia"d);
    }

    bool isNativeContainerMethodCall(CallExpr call)
    {
        MemberExpr m = cast(MemberExpr) call.fn;
        if (m is null || m.left is null)
            return false;
        if (cast(TypeSemaNativeContainer) m.left.type_sema !is null)
            return true;
        if (Identifier id = cast(Identifier) m.left)
        {
            if (id.value == "StringNativa"d || id.value == "VisaoTexto"d
                    || id.value == "ResultadoNativo"d || id.value == "OpcionalNativo"d
                    || id.value == "VetorNativo"d || id.value == "MapaNativo"d
                    || id.value == "MatrizNativa"d || id.value == "FatiaNativa"d)
                return true;
        }
        return false;
    }

    void checkConversion(Position pos, TypeSema expected, Node val)
    {
        if (expected is null || val is null)
            return;
        if (isUnsafeImplicitNativeConversion(expected, val, val.type_sema))
            diag.errorCode(pos, nativeUnsafeConversion,
                    val.type_sema is null ? "desconhecido"d : val.type_sema.toStr(), expected.toStr());
    }

    void validateExpr(Node node)
    {
        if (node is null)
            return;
        switch (node.kind)
        {
            case NodeKind.IntLit:
            case NodeKind.DoubleLit:
            case NodeKind.BoolLit:
            case NodeKind.NaN:
                return;
            case NodeKind.StringLit:
                diag.errorCode(node.pos, nativeUnsupportedOp,
                        "literal de texto gerenciado (use StringNativa.criar(\"...\") ou VisaoTexto)");
                return;
            case NodeKind.NullLit:
                diag.errorCode(node.pos, nativeUnsupportedOp, "nulo gerenciado (use OpcionalNativo<T>)");
                return;
            case NodeKind.ArrayLit:
                diag.errorCode(node.pos, nativeUnsupportedOp,
                        "vetor literal gerenciado no GC (use VetorNativo<T>)");
                return;
            case NodeKind.MapLit:
                diag.errorCode(node.pos, nativeUnsupportedOp,
                        "dicionário gerenciado no GC (use MapaNativo<K, V>)");
                return;
            case NodeKind.TupleLit:
                diag.errorCode(node.pos, nativeUnsupportedOp, "tupla gerenciada no GC");
                return;
            case NodeKind.FunctionExpr:
                diag.errorCode(node.pos, nativeUnsupportedOp, "função anônima / closure");
                return;
            case NodeKind.AwaitExpr:
                diag.errorCode(node.pos, nativeUnsupportedOp, "aguardar em função @nativo");
                return;
            case NodeKind.RoutineExpr:
                diag.errorCode(node.pos, nativeUnsupportedOp, "rotina paralela gerenciada em função @nativo");
                return;
            case NodeKind.ImportExpr:
                diag.errorCode(node.pos, nativeUnsupportedOp, "importação dentro de @nativo");
                return;
            case NodeKind.TypeOfExpr:
                diag.errorCode(node.pos, nativeUnsupportedOp, "tipo() dinâmico em @nativo");
                return;
            case NodeKind.SliceExpr:
                diag.errorCode(node.pos, nativeUnsupportedOp, "fatiamento dinâmico (use .fatia(inicio, fim))");
                return;
            case NodeKind.SpreadExpr:
                diag.errorCode(node.pos, nativeUnsupportedOp, "espalhamento dinâmico");
                return;
            case NodeKind.Comprehension:
            case NodeKind.LoopExpr:
                diag.errorCode(node.pos, nativeUnsupportedOp, "compreensão de vetor gerenciada");
                return;
            case NodeKind.TryStmt:
            case NodeKind.ThrowStmt:
                diag.errorCode(node.pos, nativeUnsupportedOp, "exceções gerenciadas tente/pegue/falhar");
                return;
            case NodeKind.Identifier:
                Identifier id = cast(Identifier) node;
                if (id.value == "isto"d)
                    return;
                if (id.variableRef !is null && !id.variableRef.isEnum)
                {
                    if (id.type_sema !is null && !isStaticNativeLayoutType(id.type_sema, false))
                        diag.errorCode(id.pos, nativeInvalidType, id.type_sema.toStr());
                }
                return;
            case NodeKind.BinaryExpr:
                BinaryExpr bin = cast(BinaryExpr) node;
                if (bin.op == TokenKind.Coalesce || bin.op == TokenKind.In)
                {
                    diag.errorCode(bin.pos, nativeUnsupportedOp, "operador dinâmico em/??");
                    return;
                }
                if (bin.resolvedOperator !is null && !isEligibleNativeMethod(bin.resolvedOperator))
                {
                    dstring clsName = bin.resolvedOperator.ownerClass !is null
                        ? bin.resolvedOperator.ownerClass.name : "classe"d;
                    diag.errorCode(bin.pos, incompatibleNativeOperator, bin.resolvedOperator.operatorSymbol,
                            clsName, "método operador não é elegível para compilação nativa");
                }
                validateExpr(bin.left);
                validateExpr(bin.right);
                return;
            case NodeKind.UnaryExpr:
                UnaryExpr un = cast(UnaryExpr) node;
                if (un.resolvedOperator !is null && !isEligibleNativeMethod(un.resolvedOperator))
                {
                    dstring clsName = un.resolvedOperator.ownerClass !is null
                        ? un.resolvedOperator.ownerClass.name : "classe"d;
                    diag.errorCode(un.pos, incompatibleNativeOperator, un.resolvedOperator.operatorSymbol,
                            clsName, "operador unário não é elegível para compilação nativa");
                }
                validateExpr(un.value);
                return;
            case NodeKind.ConditionalExpr:
                ConditionalExpr c = cast(ConditionalExpr) node;
                validateExpr(c.condition);
                validateExpr(c.yes);
                validateExpr(c.no);
                return;
            case NodeKind.MemberExpr:
                MemberExpr m = cast(MemberExpr) node;
                if (m.enumValue !is null)
                    return;
                validateExpr(m.left);
                return;
            case NodeKind.IndexExpr:
                IndexExpr idx = cast(IndexExpr) node;
                if (idx.resolvedOperator !is null && !isEligibleNativeMethod(idx.resolvedOperator))
                {
                    dstring clsName = idx.resolvedOperator.ownerClass !is null
                        ? idx.resolvedOperator.ownerClass.name : "classe"d;
                    diag.errorCode(idx.pos, incompatibleNativeOperator, "[]"d, clsName,
                            "operador de indexação não é elegível para compilação nativa");
                }
                else if (idx.resolvedOperator is null && idx.value !is null
                        && cast(TypeSemaNativeContainer) idx.value.type_sema is null)
                {
                    diag.errorCode(idx.pos, nativeUnsupportedOp,
                            "indexação de coleção gerenciada em @nativo (use VetorNativo/FatiaNativa/MapaNativo)");
                }
                validateExpr(idx.value);
                validateExpr(idx.idx);
                return;
            case NodeKind.CallExpr:
                validateCall(cast(CallExpr) node);
                return;
            case NodeKind.VarDecl:
                VarDecl v = cast(VarDecl) node;
                if (v.isEnum)
                    return;
                if (v.type_sema is null || !isStaticNativeLayoutType(v.type_sema, false))
                    diag.errorCode(v.pos, nativeInvalidType,
                            v.type_sema is null ? "qualquer"d : v.type_sema.toStr());
                if (!v.uninitialized && v.value !is null)
                {
                    validateExpr(v.value);
                    checkConversion(v.pos, v.type_sema, v.value);
                }
                return;
            case NodeKind.AssignStmt:
                AssignStmt ass = cast(AssignStmt) node;
                if (ass.resolvedIndexSetOperator !is null)
                {
                    if (!isEligibleNativeMethod(ass.resolvedIndexSetOperator))
                    {
                        dstring clsName = ass.resolvedIndexSetOperator.ownerClass !is null
                            ? ass.resolvedIndexSetOperator.ownerClass.name : "classe"d;
                        diag.errorCode(ass.pos, incompatibleNativeOperator, "[]="d, clsName,
                                "operador []= não é elegível para compilação nativa");
                    }
                    if (IndexExpr idx = cast(IndexExpr) ass.left)
                    {
                        validateExpr(idx.value);
                        validateExpr(idx.idx);
                    }
                    validateExpr(ass.value);
                    return;
                }
                validateExpr(ass.left);
                validateExpr(ass.value);
                if (ass.op == TokenKind.Equals)
                    checkConversion(ass.pos, ass.left.type_sema, ass.value);
                return;
            case NodeKind.ReturnStmt:
                ReturnStmt ret = cast(ReturnStmt) node;
                if (ret.val !is null)
                {
                    validateExpr(ret.val);
                    if (currentNativeFn !is null)
                        checkConversion(ret.pos, currentNativeFn.type_sema, ret.val);
                }
                return;
            case NodeKind.IfStmt:
                IfStmt branch = cast(IfStmt) node;
                if (branch.expr !is null)
                    validateExpr(branch.expr);
                foreach (Node child; branch.body)
                    validateExpr(child);
                if (branch._else !is null)
                    validateExpr(branch._else);
                return;
            case NodeKind.WhileStmt:
                WhileStmt w = cast(WhileStmt) node;
                validateExpr(w.expr);
                foreach (Node child; w.body)
                    validateExpr(child);
                return;
            case NodeKind.ForStmt:
                ForStmt f = cast(ForStmt) node;
                validateExpr(f.init);
                validateExpr(f.condition);
                validateExpr(f.step);
                foreach (Node child; f.body)
                    validateExpr(child);
                return;
            case NodeKind.DoStmt:
                DoStmt d = cast(DoStmt) node;
                foreach (Node child; d.body)
                    validateExpr(child);
                validateExpr(d.condition);
                return;
            case NodeKind.EachStmt:
                EachStmt e = cast(EachStmt) node;
                validateExpr(e.iterable);
                if (e.iterable !is null && cast(TypeSemaNativeContainer) e.iterable.type_sema is null)
                    diag.errorCode(e.pos, nativeUnsupportedOp,
                            "para cada sobre coleção gerenciada em @nativo (use VetorNativo/FatiaNativa)");
                foreach (Node child; e.body)
                    validateExpr(child);
                return;
            case NodeKind.SwitchStmt:
                SwitchStmt sw = cast(SwitchStmt) node;
                validateExpr(sw.value);
                foreach (SwitchCase c; sw.cases)
                {
                    foreach (Node v; c.values)
                        validateExpr(v);
                    foreach (Node child; c.body)
                        validateExpr(child);
                }
                foreach (Node child; sw.fallback)
                    validateExpr(child);
                return;
            case NodeKind.BlockStmt:
                foreach (Node child; (cast(BlockStmt) node).body)
                    validateExpr(child);
                return;
            case NodeKind.SequenceStmt:
                foreach (Node child; (cast(SequenceStmt) node).body)
                    validateExpr(child);
                return;
            case NodeKind.BreakStmt:
            case NodeKind.ContinueStmt:
                return;
            default:
                diag.errorCode(node.pos, nativeUnsupportedOp, node.kind.to!string);
                return;
        }
    }

    void validateCall(CallExpr call)
    {
        // 1) Cast explícito de tipo C: ci32(x), cf64(x), etc.
        if (Identifier id = cast(Identifier) call.fn)
        {
            if (isNativeCastName(id.value))
            {
                foreach (Node arg; call.args)
                    validateExpr(arg);
                return;
            }
            // 2) Construtor de classe @pilha
            if (id.classRef !is null)
            {
                if (!id.classRef.isValueType)
                {
                    diag.errorCode(call.pos, nativeForbiddenCall, id.value);
                    return;
                }
                foreach (Node arg; call.args)
                    validateExpr(arg);
                return;
            }
            // 3) Função livre @nativo
            if (id.functionRef !is null)
            {
                if (call.builtinCall || !isEligibleNativeMethod(id.functionRef))
                {
                    diag.errorCode(call.pos, nativeForbiddenCall, id.value);
                    return;
                }
                foreach (size_t i, Node arg; call.args)
                {
                    validateExpr(arg);
                    if (i < id.functionRef.args.length)
                        checkConversion(arg.pos, id.functionRef.args[i].type_sema, arg);
                }
                return;
            }
            // 4) Construtor de container nativo (ex.: VetorNativo<ci64>())
            if (cast(TypeSemaNativeContainer) call.type_sema !is null)
            {
                foreach (Node arg; call.args)
                    validateExpr(arg);
                return;
            }
            diag.errorCode(call.pos, nativeForbiddenCall, id.value);
            return;
        }

        // 5) Chamada de membro (Matematica.raiz, método de @pilha, método de container nativo, FFI C)
        if (MemberExpr m = cast(MemberExpr) call.fn)
        {
            Identifier leftId = cast(Identifier) m.left;
            Identifier rightId = cast(Identifier) m.right;
            if (leftId !is null && rightId !is null && isNativeMathIntrinsic(leftId.value, rightId.value))
            {
                foreach (Node arg; call.args)
                    validateExpr(arg);
                return;
            }
            if (isStringNativaFactoryCall(call))
            {
                // Fronteira explícita: StringNativa.criar("literal") aceita StringLit literal!
                foreach (Node arg; call.args)
                    if (cast(StringLit) arg is null)
                        validateExpr(arg);
                return;
            }
            if (isNativeContainerMethodCall(call))
            {
                if (m.left !is null && cast(TypeSemaNativeContainer) m.left.type_sema !is null)
                    validateExpr(m.left);
                foreach (Node arg; call.args)
                {
                    // Permitir literal de chave em MapaNativo<StringNativa, V>.definir("k", v) / obter("k")
                    if (cast(StringLit) arg !is null && m.left !is null)
                    {
                        if (TypeSemaNativeContainer nc = cast(TypeSemaNativeContainer) m.left.type_sema)
                            if (nc.containerKind == NativeContainerKind.MapaNativo
                                    || nc.containerKind == NativeContainerKind.StringNativa
                                    || nc.containerKind == NativeContainerKind.VisaoTexto)
                                continue;
                    }
                    validateExpr(arg);
                }
                return;
            }
            if (rightId !is null && rightId.classRef !is null && rightId.classRef.isValueType)
            {
                foreach (Node arg; call.args)
                    validateExpr(arg);
                return;
            }
            if (rightId !is null && rightId.functionRef !is null && isEligibleNativeMethod(rightId.functionRef))
            {
                if (!rightId.functionRef.isStatic)
                    validateExpr(m.left);
                foreach (size_t i, Node arg; call.args)
                {
                    validateExpr(arg);
                    if (i < rightId.functionRef.args.length)
                        checkConversion(arg.pos, rightId.functionRef.args[i].type_sema, arg);
                }
                return;
            }
            dstring targetName = rightId !is null ? rightId.value : "<membro>"d;
            diag.errorCode(call.pos, nativeForbiddenCall, targetName);
            return;
        }

        diag.errorCode(call.pos, nativeForbiddenCall, "<chamada indireta>");
    }

    void validateNativeFn(FnDecl fn)
    {
        if (fn.isAsync)
        {
            diag.errorCode(fn.pos, nativeInvalidTarget, "função assíncrona não suporta @nativo");
            return;
        }
        if (fn.isAbstract)
        {
            diag.errorCode(fn.pos, nativeInvalidTarget, "método abstrato não suporta @nativo");
            return;
        }
        if (fn.decoratorEnvelope)
        {
            diag.errorCode(fn.pos, nativeInvalidTarget, "envelope de decorador não suporta @nativo");
            return;
        }
        foreach (Decorator d; fn.decorators)
            if (d.envelope !is null)
            {
                diag.errorCode(fn.pos, nativeInvalidTarget, "função com envelope de decorador dinâmico");
                return;
            }

        foreach (FnArg arg; fn.args)
        {
            if (arg.rest)
                diag.errorCode(arg.pos, nativeUnsupportedOp, "parâmetro variádico (...rest)");
            if (arg.type_sema is null || !isStaticNativeLayoutType(arg.type_sema, false))
                diag.errorCode(arg.pos, nativeInvalidType,
                        arg.type_sema is null ? "qualquer"d : arg.type_sema.toStr());
        }
        if (fn.type_sema is null || !isStaticNativeLayoutType(fn.type_sema, true))
            diag.errorCode(fn.pos, nativeInvalidType,
                    fn.type_sema is null ? "qualquer"d : fn.type_sema.toStr());

        FnDecl prev = currentNativeFn;
        currentNativeFn = fn;
        scope (exit)
            currentNativeFn = prev;

        foreach (Node stmt; fn.body)
            validateExpr(stmt);
    }

    void visit(Node node)
    {
        if (node is null || node in visited)
            return;
        visited[node] = true;
        if (FnDecl fn = cast(FnDecl) node)
        {
            if (fn.isNative && !fn.builtinName.length)
                validateNativeFn(fn);
        }
        foreach (Node child; childNodes(node))
            visit(child);
    }

public:
    this(Diagnostics diag)
    {
        this.diag = diag;
    }

    void analyze(Program program)
    {
        visit(program);
    }
}

void validateNativeFunctions(Program program, Diagnostics diag)
{
    new NativeValidator(diag).analyze(program);
}
