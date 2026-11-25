module frontend.conditional;

import driver.target_info;
import errors;
import frontend.lexer.token : Position, TokenKind;
import frontend.parser.ast;
import frontend.type_expr : TypeExprNamed;
import frontend.type_sema : TypeSemaBase;
import std.conv : to;
import std.format : format;

private enum ConstKind : ubyte
{
    None,
    Bool,
    Int,
    Double,
    String
}

private struct ConstVal
{
    ConstKind kind;
    bool b;
    long i;
    double d;
    dstring s;
    bool dependsOnTarget;

    static ConstVal makeBool(bool v, bool fromTarget = false)
    {
        ConstVal c;
        c.kind = ConstKind.Bool;
        c.b = v;
        c.dependsOnTarget = fromTarget;
        return c;
    }

    static ConstVal makeInt(long v, bool fromTarget = false)
    {
        ConstVal c;
        c.kind = ConstKind.Int;
        c.i = v;
        c.dependsOnTarget = fromTarget;
        return c;
    }

    static ConstVal makeDouble(double v, bool fromTarget = false)
    {
        ConstVal c;
        c.kind = ConstKind.Double;
        c.d = v;
        c.dependsOnTarget = fromTarget;
        return c;
    }

    static ConstVal makeString(dstring v, bool fromTarget = false)
    {
        ConstVal c;
        c.kind = ConstKind.String;
        c.s = v;
        c.dependsOnTarget = fromTarget;
        return c;
    }

    bool valid() const
    {
        return kind != ConstKind.None;
    }

    Node toLiteral(Position pos) const
    {
        final switch (kind)
        {
            case ConstKind.None:
                return null;
            case ConstKind.Bool:
                return new BoolLit(b, pos);
            case ConstKind.Int:
                return new IntLit(i, pos);
            case ConstKind.Double:
                return new DoubleLit(d, pos);
            case ConstKind.String:
                return new StringLit(s, pos);
        }
    }
}

/// Avalia compilação condicional estrutural (`@quando(...)`, `Compilacao.*` e `se` dependente de alvo)
/// ANTES do carregamento de módulos e da análise semântica.
final class ConditionalEvaluator
{
private:
    TargetInfo target;
    Diagnostics diag;
    ConstVal[dstring][] constScopes;

    void pushScope()
    {
        constScopes ~= cast(ConstVal[dstring]) null;
    }

    void popScope()
    {
        if (constScopes.length > 0)
            constScopes.length--;
    }

    void setConst(dstring name, ConstVal val)
    {
        if (constScopes.length > 0)
            constScopes[$ - 1][name] = val;
    }

    void clearConst(dstring name)
    {
        if (constScopes.length > 0)
            constScopes[$ - 1].remove(name);
    }

    ConstVal lookupConst(dstring name)
    {
        foreach_reverse (ConstVal[dstring] sc; constScopes)
            if (ConstVal* found = name in sc)
                return *found;
        return ConstVal.init;
    }

    bool isCompilacaoCall(CallExpr call, out dstring methodName)
    {
        methodName = ""d;
        if (call is null)
            return false;
        MemberExpr member = cast(MemberExpr) call.fn;
        if (member is null)
            return false;
        Identifier left = cast(Identifier) member.left;
        Identifier right = cast(Identifier) member.right;
        if (left is null || right is null)
            return false;
        if (left.value != "Compilacao"d && left.value != "Compilação"d)
            return false;
        methodName = right.value;
        return true;
    }

    ConstVal evalCompilacaoCall(CallExpr call, dstring methodName)
    {
        switch (methodName)
        {
            case "sistemaOperacional"d:
                if (call.args.length != 0)
                {
                    diag.errorCode(call.pos, invalidCompileQuery, methodName);
                    return ConstVal.init;
                }
                return ConstVal.makeString(target.os.to!dstring, true);
            case "arquitetura"d:
                if (call.args.length != 0)
                {
                    diag.errorCode(call.pos, invalidCompileQuery, methodName);
                    return ConstVal.init;
                }
                return ConstVal.makeString(target.arch.to!dstring, true);
            case "tamanhoPonteiro"d:
                if (call.args.length != 0)
                {
                    diag.errorCode(call.pos, invalidCompileQuery, methodName);
                    return ConstVal.init;
                }
                return ConstVal.makeInt(target.pointerBits, true);
            case "abi"d:
                if (call.args.length != 0)
                {
                    diag.errorCode(call.pos, invalidCompileQuery, methodName);
                    return ConstVal.init;
                }
                return ConstVal.makeString(target.abi.to!dstring, true);
            case "compiladorC"d:
                if (call.args.length != 0)
                {
                    diag.errorCode(call.pos, invalidCompileQuery, methodName);
                    return ConstVal.init;
                }
                return ConstVal.makeString(target.cCompiler.to!dstring, true);
            case "modo"d:
                if (call.args.length != 0)
                {
                    diag.errorCode(call.pos, invalidCompileQuery, methodName);
                    return ConstVal.init;
                }
                return ConstVal.makeString(target.mode.to!dstring, true);
            case "temRecurso"d:
                if (call.args.length != 1)
                {
                    diag.errorCode(call.pos, invalidCompileQuery, methodName);
                    return ConstVal.init;
                }
                ConstVal arg = evalConst(call.args[0]);
                if (arg.kind != ConstKind.String)
                {
                    diag.errorCode(call.pos, invalidCompileQuery, methodName);
                    return ConstVal.init;
                }
                return ConstVal.makeBool(target.hasFeature(arg.s.to!string), true);
            default:
                diag.errorCode(call.pos, invalidCompileQuery, methodName);
                return ConstVal.init;
        }
    }

    ConstVal evalConst(Node node)
    {
        if (node is null)
            return ConstVal.init;
        if (BoolLit b = cast(BoolLit) node)
            return ConstVal.makeBool(b.value);
        if (IntLit n = cast(IntLit) node)
            return ConstVal.makeInt(n.value);
        if (DoubleLit d = cast(DoubleLit) node)
            return ConstVal.makeDouble(d.value);
        if (StringLit s = cast(StringLit) node)
            return ConstVal.makeString(s.value);
        if (Identifier id = cast(Identifier) node)
            return lookupConst(id.value);
        if (CallExpr call = cast(CallExpr) node)
        {
            dstring methodName;
            if (isCompilacaoCall(call, methodName))
                return evalCompilacaoCall(call, methodName);
            return ConstVal.init;
        }
        if (UnaryExpr un = cast(UnaryExpr) node)
        {
            ConstVal v = evalConst(un.value);
            if (!v.valid())
                return ConstVal.init;
            if (un.op == TokenKind.Bang && v.kind == ConstKind.Bool)
                return ConstVal.makeBool(!v.b, v.dependsOnTarget);
            if (un.op == TokenKind.Minus && v.kind == ConstKind.Int)
                return ConstVal.makeInt(-v.i, v.dependsOnTarget);
            if (un.op == TokenKind.Minus && v.kind == ConstKind.Double)
                return ConstVal.makeDouble(-v.d, v.dependsOnTarget);
            if (un.op == TokenKind.Plus && (v.kind == ConstKind.Int || v.kind == ConstKind.Double))
                return v;
            return ConstVal.init;
        }
        if (BinaryExpr bin = cast(BinaryExpr) node)
        {
            ConstVal l = evalConst(bin.left);
            if (!l.valid())
                return ConstVal.init;
            if (bin.op == TokenKind.And && l.kind == ConstKind.Bool)
            {
                if (!l.b)
                    return ConstVal.makeBool(false, l.dependsOnTarget);
                ConstVal r = evalConst(bin.right);
                if (r.kind == ConstKind.Bool)
                    return ConstVal.makeBool(r.b, l.dependsOnTarget || r.dependsOnTarget);
                return ConstVal.init;
            }
            if (bin.op == TokenKind.Or && l.kind == ConstKind.Bool)
            {
                if (l.b)
                    return ConstVal.makeBool(true, l.dependsOnTarget);
                ConstVal r = evalConst(bin.right);
                if (r.kind == ConstKind.Bool)
                    return ConstVal.makeBool(r.b, l.dependsOnTarget || r.dependsOnTarget);
                return ConstVal.init;
            }
            ConstVal r = evalConst(bin.right);
            if (!r.valid())
                return ConstVal.init;
            bool dep = l.dependsOnTarget || r.dependsOnTarget;
            if (bin.op == TokenKind.EEquals || bin.op == TokenKind.NEquals)
            {
                bool eq;
                if (l.kind == ConstKind.String && r.kind == ConstKind.String)
                    eq = l.s == r.s;
                else if (l.kind == ConstKind.Int && r.kind == ConstKind.Int)
                    eq = l.i == r.i;
                else if (l.kind == ConstKind.Bool && r.kind == ConstKind.Bool)
                    eq = l.b == r.b;
                else if ((l.kind == ConstKind.Int || l.kind == ConstKind.Double)
                        && (r.kind == ConstKind.Int || r.kind == ConstKind.Double))
                {
                    double lv = l.kind == ConstKind.Double ? l.d : cast(double) l.i;
                    double rv = r.kind == ConstKind.Double ? r.d : cast(double) r.i;
                    eq = lv == rv;
                }
                else
                    return ConstVal.init;
                return ConstVal.makeBool(bin.op == TokenKind.EEquals ? eq : !eq, dep);
            }
            if (l.kind == ConstKind.Int && r.kind == ConstKind.Int)
            {
                switch (bin.op)
                {
                    case TokenKind.Plus:
                        return ConstVal.makeInt(l.i + r.i, dep);
                    case TokenKind.Minus:
                        return ConstVal.makeInt(l.i - r.i, dep);
                    case TokenKind.Star:
                        return ConstVal.makeInt(l.i * r.i, dep);
                    case TokenKind.IntDiv:
                        return r.i != 0 ? ConstVal.makeInt(l.i / r.i, dep) : ConstVal.init;
                    case TokenKind.Modulo:
                        return r.i != 0 ? ConstVal.makeInt(l.i % r.i, dep) : ConstVal.init;
                    case TokenKind.LThan:
                        return ConstVal.makeBool(l.i < r.i, dep);
                    case TokenKind.LEquals:
                        return ConstVal.makeBool(l.i <= r.i, dep);
                    case TokenKind.GThan:
                        return ConstVal.makeBool(l.i > r.i, dep);
                    case TokenKind.GEquals:
                        return ConstVal.makeBool(l.i >= r.i, dep);
                    default:
                        return ConstVal.init;
                }
            }
            if (l.kind == ConstKind.String && r.kind == ConstKind.String && bin.op == TokenKind.Plus)
                return ConstVal.makeString(l.s ~ r.s, dep);
            return ConstVal.init;
        }
        if (ConditionalExpr cond = cast(ConditionalExpr) node)
        {
            ConstVal c = evalConst(cond.condition);
            if (c.kind != ConstKind.Bool)
                return ConstVal.init;
            ConstVal branch = evalConst(c.b ? cond.yes : cond.no);
            if (!branch.valid())
                return ConstVal.init;
            branch.dependsOnTarget = branch.dependsOnTarget || c.dependsOnTarget;
            return branch;
        }
        return ConstVal.init;
    }

    /// Avalia todos os decoradores `@quando(...)` de uma declaração ou membro.
    /// Retorna `true` se o item deve ser mantido, `false` se deve ser excluído estruturalmente.
    bool evaluateWhenDecorators(ref Decorator[] decorators, Position pos)
    {
        if (!decorators.length)
            return true;
        Decorator[] kept;
        bool keep = true;
        foreach (Decorator d; decorators)
        {
            if (d.name != "quando"d)
            {
                kept ~= d;
                continue;
            }
            if (d.values.length != 1 || (d.keys.length > 0 && d.keys[0].length > 0))
            {
                diag.errorCode(pos, conditionalArity);
                keep = false;
                continue;
            }
            ConstVal result = evalConst(d.values[0]);
            if (result.kind != ConstKind.Bool)
            {
                diag.errorCode(pos, conditionalNonConstant,
                        result.valid() ? "esperado valor lógico" : "expressão depende de estado em execução");
                keep = false;
                continue;
            }
            if (!result.b)
                keep = false;
        }
        decorators = kept;
        return keep;
    }

    Node rewriteExpr(Node node)
    {
        if (node is null)
            return null;
        if (CallExpr call = cast(CallExpr) node)
        {
            dstring methodName;
            if (isCompilacaoCall(call, methodName))
            {
                ConstVal val = evalCompilacaoCall(call, methodName);
                if (val.valid())
                    return val.toLiteral(call.pos);
                return call;
            }
            call.fn = rewriteExpr(call.fn);
            foreach (ref Node arg; call.args)
                arg = rewriteExpr(arg);
            return call;
        }
        if (BinaryExpr bin = cast(BinaryExpr) node)
        {
            bin.left = rewriteExpr(bin.left);
            bin.right = rewriteExpr(bin.right);
            return bin;
        }
        if (UnaryExpr un = cast(UnaryExpr) node)
        {
            un.value = rewriteExpr(un.value);
            return un;
        }
        if (ConditionalExpr cond = cast(ConditionalExpr) node)
        {
            ConstVal c = evalConst(cond.condition);
            if (c.kind == ConstKind.Bool && c.dependsOnTarget)
                return rewriteExpr(c.b ? cond.yes : cond.no);
            cond.condition = rewriteExpr(cond.condition);
            cond.yes = rewriteExpr(cond.yes);
            cond.no = rewriteExpr(cond.no);
            return cond;
        }
        if (MemberExpr m = cast(MemberExpr) node)
        {
            m.left = rewriteExpr(m.left);
            return m;
        }
        if (IndexExpr idx = cast(IndexExpr) node)
        {
            idx.value = rewriteExpr(idx.value);
            idx.idx = rewriteExpr(idx.idx);
            return idx;
        }
        if (ArrayLit arr = cast(ArrayLit) node)
        {
            foreach (ref Node el; arr.elements)
                el = rewriteExpr(el);
            return arr;
        }
        if (MapLit map = cast(MapLit) node)
        {
            foreach (ref Node k; map.keys)
                k = rewriteExpr(k);
            foreach (ref Node v; map.values)
                v = rewriteExpr(v);
            return map;
        }
        if (SliceExpr sl = cast(SliceExpr) node)
        {
            sl.value = rewriteExpr(sl.value);
            sl.start = rewriteExpr(sl.start);
            sl.end = rewriteExpr(sl.end);
            sl.step = rewriteExpr(sl.step);
            return sl;
        }
        if (SpreadExpr sp = cast(SpreadExpr) node)
        {
            sp.value = rewriteExpr(sp.value);
            return sp;
        }
        if (TypeOfExpr tof = cast(TypeOfExpr) node)
        {
            tof.value = rewriteExpr(tof.value);
            return tof;
        }
        if (AwaitExpr aw = cast(AwaitExpr) node)
        {
            aw.value = rewriteExpr(aw.value);
            return aw;
        }
        if (RoutineExpr rt = cast(RoutineExpr) node)
        {
            rt.call = cast(CallExpr) rewriteExpr(rt.call);
            return rt;
        }
        if (Comprehension comp = cast(Comprehension) node)
        {
            comp.iterable = rewriteExpr(comp.iterable);
            comp.value = rewriteExpr(comp.value);
            comp.condition = rewriteExpr(comp.condition);
            return comp;
        }
        if (FunctionExpr fe = cast(FunctionExpr) node)
        {
            processFunction(fe.declaration);
            return fe;
        }
        if (AssignStmt ass = cast(AssignStmt) node)
        {
            ass.left = rewriteExpr(ass.left);
            ass.value = rewriteExpr(ass.value);
            return ass;
        }
        return node;
    }

    void processClass(ClassDecl cls)
    {
        ClassField[] keptFields;
        foreach (ClassField field; cls.fields)
        {
            if (!evaluateWhenDecorators(field.decorators, field.pos))
                continue;
            if (field.value !is null)
                field.value = rewriteExpr(field.value);
            keptFields ~= field;
        }
        cls.fields = keptFields;

        FnDecl[] keptMethods;
        foreach (FnDecl method; cls.methods)
        {
            if (!evaluateWhenDecorators(method.decorators, method.pos))
                continue;
            processFunction(method);
            keptMethods ~= method;
        }
        cls.methods = keptMethods;
    }

    void processFunction(FnDecl fn)
    {
        pushScope();
        scope (exit)
            popScope();
        foreach (FnArg arg; fn.args)
        {
            clearConst(arg.name);
            if (arg.value !is null)
                arg.value = rewriteExpr(arg.value);
        }
        fn.body = processBody(fn.body, false);
    }

    Node[] processIfStmt(IfStmt branch, bool flattenTopLevel)
    {
        if (branch is null)
            return [];
        if (branch.expr is null)
        {
            // Ramo `senao` puro
            Node[] bodyNodes = processBody(branch.body, flattenTopLevel);
            if (flattenTopLevel)
                return bodyNodes;
            return [cast(Node) new BlockStmt(bodyNodes, branch.pos)];
        }
        ConstVal cond = evalConst(branch.expr);
        if (cond.kind == ConstKind.Bool && cond.dependsOnTarget)
        {
            if (cond.b)
            {
                Node[] active = processBody(branch.body, flattenTopLevel);
                if (flattenTopLevel)
                    return active;
                return [cast(Node) new BlockStmt(active, branch.pos)];
            }
            if (branch._else !is null)
                return processIfStmt(branch._else, flattenTopLevel);
            return [];
        }
        branch.expr = rewriteExpr(branch.expr);
        pushScope();
        branch.body = processBody(branch.body, false);
        popScope();
        if (branch._else !is null)
        {
            if (branch._else.expr !is null)
            {
                ConstVal elseCond = evalConst(branch._else.expr);
                if (elseCond.kind == ConstKind.Bool && elseCond.dependsOnTarget)
                {
                    Node[] resolved = processIfStmt(branch._else, false);
                    if (resolved.length == 0)
                        branch._else = null;
                    else
                        branch._else = new IfStmt(null, resolved, null, branch._else.pos);
                }
                else
                {
                    Node[] elseNodes = processIfStmt(branch._else, false);
                    branch._else = elseNodes.length ? cast(IfStmt) elseNodes[0] : null;
                }
            }
            else
            {
                pushScope();
                branch._else.body = processBody(branch._else.body, false);
                popScope();
            }
        }
        return [cast(Node) branch];
    }

    Node[] processBody(Node[] nodes, bool isTopLevel)
    {
        Node[] result;
        foreach (Node node; nodes)
        {
            if (node is null)
                continue;
            if (!evaluateWhenDecorators(node.decorators, node.pos))
                continue;

            if (IfStmt branch = cast(IfStmt) node)
            {
                result ~= processIfStmt(branch, isTopLevel);
                continue;
            }
            if (VarDecl varDecl = cast(VarDecl) node)
            {
                if (varDecl.isConst && !varDecl.isEnum && !varDecl.uninitialized)
                {
                    ConstVal val = evalConst(varDecl.value);
                    if (val.valid())
                        setConst(varDecl.name, val);
                }
                else
                {
                    clearConst(varDecl.name);
                }
                varDecl.value = rewriteExpr(varDecl.value);
                result ~= varDecl;
                continue;
            }
            if (FnDecl fn = cast(FnDecl) node)
            {
                processFunction(fn);
                result ~= fn;
                continue;
            }
            if (ClassDecl cls = cast(ClassDecl) node)
            {
                processClass(cls);
                result ~= cls;
                continue;
            }
            if (BlockStmt blk = cast(BlockStmt) node)
            {
                pushScope();
                blk.body = processBody(blk.body, false);
                popScope();
                result ~= blk;
                continue;
            }
            if (SequenceStmt seq = cast(SequenceStmt) node)
            {
                seq.body = processBody(seq.body, isTopLevel);
                result ~= seq;
                continue;
            }
            if (WhileStmt w = cast(WhileStmt) node)
            {
                w.expr = rewriteExpr(w.expr);
                pushScope();
                w.body = processBody(w.body, false);
                popScope();
                result ~= w;
                continue;
            }
            if (ForStmt f = cast(ForStmt) node)
            {
                pushScope();
                if (f.init !is null)
                {
                    Node[] initList = processBody([f.init], false);
                    f.init = initList.length ? initList[0] : null;
                }
                f.condition = rewriteExpr(f.condition);
                f.step = rewriteExpr(f.step);
                f.body = processBody(f.body, false);
                popScope();
                result ~= f;
                continue;
            }
            if (DoStmt d = cast(DoStmt) node)
            {
                pushScope();
                d.body = processBody(d.body, false);
                popScope();
                d.condition = rewriteExpr(d.condition);
                result ~= d;
                continue;
            }
            if (EachStmt e = cast(EachStmt) node)
            {
                e.iterable = rewriteExpr(e.iterable);
                pushScope();
                clearConst(e.name);
                e.body = processBody(e.body, false);
                popScope();
                result ~= e;
                continue;
            }
            if (SwitchStmt sw = cast(SwitchStmt) node)
            {
                sw.value = rewriteExpr(sw.value);
                foreach (ref SwitchCase c; sw.cases)
                {
                    foreach (ref Node v; c.values)
                        v = rewriteExpr(v);
                    pushScope();
                    c.body = processBody(c.body, false);
                    popScope();
                }
                pushScope();
                sw.fallback = processBody(sw.fallback, false);
                popScope();
                result ~= sw;
                continue;
            }
            if (TryStmt t = cast(TryStmt) node)
            {
                pushScope();
                t.body = processBody(t.body, false);
                popScope();
                foreach (ref CatchClause c; t.catches)
                {
                    pushScope();
                    c.body = processBody(c.body, false);
                    popScope();
                }
                pushScope();
                t.finalBody = processBody(t.finalBody, false);
                popScope();
                result ~= t;
                continue;
            }
            if (ThrowStmt th = cast(ThrowStmt) node)
            {
                th.value = rewriteExpr(th.value);
                result ~= th;
                continue;
            }
            if (ReturnStmt ret = cast(ReturnStmt) node)
            {
                ret.val = rewriteExpr(ret.val);
                result ~= ret;
                continue;
            }
            result ~= rewriteExpr(node);
        }
        return result;
    }

public:
    this(TargetInfo target, Diagnostics diag)
    {
        this.target = target;
        this.diag = diag;
    }

    void run(Program program)
    {
        if (program is null)
            return;
        pushScope();
        scope (exit)
            popScope();
        program.body = processBody(program.body, true);
    }
}

void applyConditionalCompilation(Program program, TargetInfo target, Diagnostics diag)
{
    new ConditionalEvaluator(target, diag).run(program);
}
