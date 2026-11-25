module frontend.semantic.ownership;

import diagnostics.catalog;
import errors;
import frontend.lexer.token : Position, TokenKind;
import frontend.parser.ast;
import frontend.semantic.value_types;
import frontend.type_sema;
import std.algorithm : canFind;
import std.conv : to;

enum VarState : ubyte
{
    Copy,
    Uninitialized,
    Owned,
    Moved,
    Freed,
    View,
}

/// Modo de uso inferido para cada parâmetro `Owned` de uma função.
enum ParamMode : ubyte
{
    ReadBorrow,
    MutBorrow,
    Consume,
}

private struct TrackedVar
{
    dstring name;
    TypeSema type;
    VarState state;
    size_t scopeDepth;
    Object borrowOwner; // Para `View`: variável dona da qual empresta
    dstring borrowOwnerName;
    bool isParam;
    Position statePos;
}

private struct ActiveBorrow
{
    Object borrower; // VarDecl da visão ou nó EachStmt da iteração
    dstring borrowerName;
    size_t scopeDepth;
}

/// Resultado da análise de ownership consumido pelo codegen para RAII automático.
final class OwnershipInfo
{
    /// Parâmetros inferidos como Borrow vs Consume por função.
    ParamMode[][FnDecl] paramModes;
    /// Variáveis que sofreram move/transferência em pontos específicos (para o codegen marcar flag de move).
    bool[Object] movedSomewhere;
    /// Variáveis que tiveram liberação explícita `.liberar()`.
    bool[Object] freedSomewhere;
}

private bool isMutatingContainerMethod(dstring name)
{
    switch (name)
    {
        case "adicionar":
        case "removerUltimo":
        case "limpar":
        case "reservar":
        case "definir":
        case "remover":
        case "anexar":
        case "liberar":
        case "definirElemento":
            return true;
        default:
            return false;
    }
}

private bool isViewProducingMethod(dstring name)
{
    return name == "fatia"d || name == "visao"d || name == "visão"d;
}

private bool isFreeMethod(dstring name)
{
    return name == "liberar"d || name == "destruir"d;
}

final class OwnershipAnalyzer
{
private:
    Diagnostics diag;
    OwnershipInfo info;
    bool[Node] visited;
    TrackedVar[Object] env;
    ActiveBorrow[][Object] borrows;
    size_t scopeDepth;
    FnDecl currentFn;
    bool dryRun;

    ParamMode[] inferFunctionParamModes(FnDecl fn)
    {
        if (fn is null)
            return null;
        if (ParamMode[]* cached = fn in info.paramModes)
            return *cached;

        ParamMode[] modes = new ParamMode[fn.args.length];
        foreach (size_t i, FnArg arg; fn.args)
        {
            modes[i] = ParamMode.ReadBorrow;
            if (!hasOwnershipResource(arg.type_sema))
                continue;
            // Inspeciona o corpo da função para inferir se o parâmetro é consumido, mutado ou apenas lido.
            bool consumed = false;
            bool mutated = false;
            bool[Node] seen;

            void scan(Node n)
            {
                if (n is null || n in seen)
                    return;
                seen[n] = true;
                if (ReturnStmt ret = cast(ReturnStmt) n)
                {
                    if (Identifier id = cast(Identifier) ret.val)
                        if (id.parameterRef is arg)
                            consumed = true;
                }
                else if (VarDecl vd = cast(VarDecl) n)
                {
                    if (Identifier id = cast(Identifier) vd.value)
                        if (id.parameterRef is arg)
                            consumed = true;
                }
                else if (AssignStmt ass = cast(AssignStmt) n)
                {
                    if (Identifier id = cast(Identifier) ass.value)
                        if (id.parameterRef is arg)
                            consumed = true;
                    if (Identifier lid = cast(Identifier) ass.left)
                        if (lid.parameterRef is arg)
                            mutated = true;
                    if (IndexExpr lidx = cast(IndexExpr) ass.left)
                        if (Identifier baseId = cast(Identifier) lidx.value)
                            if (baseId.parameterRef is arg)
                                mutated = true;
                }
                else if (CallExpr call = cast(CallExpr) n)
                {
                    if (MemberExpr m = cast(MemberExpr) call.fn)
                    {
                        if (Identifier recv = cast(Identifier) m.left)
                            if (Identifier meth = cast(Identifier) m.right)
                                if (recv.parameterRef is arg)
                                {
                                    if (isFreeMethod(meth.value))
                                        consumed = true;
                                    else if (isMutatingContainerMethod(meth.value))
                                        mutated = true;
                                }
                    }
                    else if (Identifier fnId = cast(Identifier) call.fn)
                    {
                        if (fnId.value == "destruir"d && call.args.length == 1)
                            if (Identifier a0 = cast(Identifier) call.args[0])
                                if (a0.parameterRef is arg)
                                    consumed = true;
                    }
                }
                foreach (Node ch; childNodes(n))
                    scan(ch);
            }

            foreach (Node st; fn.body)
                scan(st);
            if (consumed)
                modes[i] = ParamMode.Consume;
            else if (mutated)
                modes[i] = ParamMode.MutBorrow;
            else
                modes[i] = ParamMode.ReadBorrow;
        }
        info.paramModes[fn] = modes;
        return modes;
    }

    TrackedVar[Object] cloneEnv()
    {
        TrackedVar[Object] copy;
        foreach (Object k, TrackedVar v; env)
            copy[k] = v;
        return copy;
    }

    ActiveBorrow[][Object] cloneBorrows()
    {
        ActiveBorrow[][Object] copy;
        foreach (Object k, ActiveBorrow[] list; borrows)
            copy[k] = list.dup;
        return copy;
    }

    void mergeEnvs(TrackedVar[Object] a, TrackedVar[Object] b)
    {
        TrackedVar[Object] merged;
        foreach (Object k, TrackedVar va; a)
        {
            TrackedVar* vb = k in b;
            if (vb is null)
            {
                merged[k] = va;
                continue;
            }
            TrackedVar res = va;
            // Estado conservador: se qualquer ramo liberou ou moveu, não pode ser usado sem reatribuição.
            if (va.state == VarState.Freed || vb.state == VarState.Freed)
                res.state = VarState.Freed;
            else if (va.state == VarState.Moved || vb.state == VarState.Moved)
                res.state = VarState.Moved;
            else if (va.state == VarState.Uninitialized || vb.state == VarState.Uninitialized)
                res.state = VarState.Uninitialized;
            else
                res.state = va.state;
            merged[k] = res;
        }
        env = merged;
    }

    bool nodeUsesKey(Node node, Object target)
    {
        if (node is null || target is null)
            return false;
        if (Identifier id = cast(Identifier) node)
            if (identKey(id) is target)
                return true;
        foreach (Node ch; childNodes(node))
            if (nodeUsesKey(ch, target))
                return true;
        return false;
    }

    bool stmtsUseKey(Node[] stmts, Object target)
    {
        foreach (Node s; stmts)
            if (nodeUsesKey(s, target))
                return true;
        return false;
    }

    /// Libera empréstimos de visões locais (NLL) que não são mais referenciadas no restante do bloco.
    void expireDeadViewBorrows(Node[] remaining)
    {
        foreach (Object owner, ref ActiveBorrow[] list; borrows)
        {
            ActiveBorrow[] kept;
            foreach (ActiveBorrow b; list)
            {
                if (b.scopeDepth == scopeDepth && cast(VarDecl) b.borrower !is null)
                {
                    if (!stmtsUseKey(remaining, b.borrower))
                        continue;
                }
                kept ~= b;
            }
            list = kept;
        }
    }

    void analyzeStmtList(Node[] stmts)
    {
        foreach (size_t i, Node st; stmts)
        {
            expireDeadViewBorrows(stmts[i .. $]);
            analyzeExpr(st);
        }
    }

    bool alwaysTerminates(Node[] stmts)
    {
        foreach (Node st; stmts)
        {
            if (cast(ReturnStmt) st !is null || cast(ThrowStmt) st !is null
                    || st.kind == NodeKind.BreakStmt || st.kind == NodeKind.ContinueStmt)
                return true;
            if (IfStmt ifs = cast(IfStmt) st)
            {
                if (ifs._else !is null && alwaysTerminates(ifs.body))
                {
                    if (ifs._else.expr !is null)
                    {
                        if (alwaysTerminates([cast(Node) ifs._else]))
                            return true;
                    }
                    else if (alwaysTerminates(ifs._else.body))
                        return true;
                }
            }
        }
        return false;
    }

    void releaseBorrowsAtDepth(size_t depth)
    {
        foreach (Object owner, ref ActiveBorrow[] list; borrows)
        {
            ActiveBorrow[] kept;
            foreach (ActiveBorrow b; list)
                if (b.scopeDepth < depth)
                    kept ~= b;
            list = kept;
        }
    }

    void releaseBorrower(Object borrower)
    {
        foreach (Object owner, ref ActiveBorrow[] list; borrows)
        {
            ActiveBorrow[] kept;
            foreach (ActiveBorrow b; list)
                if (b.borrower !is borrower)
                    kept ~= b;
            list = kept;
        }
    }

    bool hasActiveBorrows(Object owner, out dstring borrowerName)
    {
        borrowerName = ""d;
        if (ActiveBorrow[]* list = owner in borrows)
            if ((*list).length > 0)
            {
                borrowerName = (*list)[0].borrowerName;
                return true;
            }
        return false;
    }

    Object identKey(Identifier id)
    {
        if (id is null)
            return null;
        if (id.variableRef !is null)
            return id.variableRef;
        if (id.parameterRef !is null)
            return id.parameterRef;
        return null;
    }

    void checkAliveForRead(Identifier id)
    {
        Object key = identKey(id);
        if (key is null)
            return;
        TrackedVar* tv = key in env;
        if (tv is null)
            return;
        if (tv.state == VarState.Moved)
        {
            if (!dryRun)
                diag.errorCode(id.pos, useAfterMove, tv.name);
        }
        else if (tv.state == VarState.Freed)
        {
            if (!dryRun)
                diag.errorCode(id.pos, useAfterFree, tv.name);
        }
        else if (tv.state == VarState.Uninitialized)
        {
            if (!dryRun)
                diag.errorCode(id.pos, uninitializedNativeUse, tv.name);
        }
        else if (tv.state == VarState.View && tv.borrowOwner !is null)
        {
            if (TrackedVar* owner = tv.borrowOwner in env)
            {
                if (owner.state == VarState.Freed)
                {
                    if (!dryRun)
                        diag.errorCode(id.pos, useAfterFree, owner.name);
                }
                else if (owner.state == VarState.Moved)
                {
                    if (!dryRun)
                        diag.errorCode(id.pos, useAfterMove, owner.name);
                }
            }
        }
    }

    void checkCanMutate(Object key, Position pos, dstring name)
    {
        if (key is null)
            return;
        TrackedVar* tv = key in env;
        if (tv !is null)
        {
            if (tv.state == VarState.Moved)
            {
                if (!dryRun)
                    diag.errorCode(pos, useAfterMove, tv.name);
                return;
            }
            if (tv.state == VarState.Freed)
            {
                if (!dryRun)
                    diag.errorCode(pos, useAfterFree, tv.name);
                return;
            }
        }
        dstring borrower;
        if (hasActiveBorrows(key, borrower))
        {
            if (!dryRun)
                diag.errorCode(pos, mutableBorrowConflict, name, borrower);
        }
    }

    void consumeNode(Node value, Position pos)
    {
        if (value is null)
            return;
        if (Identifier id = cast(Identifier) value)
        {
            Object key = identKey(id);
            if (key is null)
                return;
            TrackedVar* tv = key in env;
            if (tv is null || !hasOwnershipResource(tv.type))
                return;
            if (tv.state == VarState.Moved)
            {
                if (!dryRun)
                    diag.errorCode(pos, useAfterMove, tv.name);
                return;
            }
            if (tv.state == VarState.Freed)
            {
                if (!dryRun)
                    diag.errorCode(pos, useAfterFree, tv.name);
                return;
            }
            if (tv.state == VarState.Uninitialized)
            {
                if (!dryRun)
                    diag.errorCode(pos, uninitializedNativeUse, tv.name);
                return;
            }
            dstring borrower;
            if (hasActiveBorrows(key, borrower))
            {
                if (!dryRun)
                    diag.errorCode(pos, mutableBorrowConflict, tv.name, borrower);
                return;
            }
            tv.state = VarState.Moved;
            tv.statePos = pos;
            info.movedSomewhere[key] = true;
            return;
        }
        // Mover campo ou elemento de container de tipo proprietário sem .clonar() é cópia implícita proibida!
        if ((cast(MemberExpr) value !is null || cast(IndexExpr) value !is null)
                && hasOwnershipResource(value.type_sema))
        {
            if (!dryRun)
                diag.errorCode(pos, forbiddenImplicitCopy, value.type_sema.toStr());
        }
    }

    /// Determina se uma expressão produz uma visão emprestada e qual o dono de origem.
    bool extractBorrowOrigin(Node expr, out Object ownerKey, out dstring ownerName, out bool isTemporary)
    {
        ownerKey = null;
        ownerName = ""d;
        isTemporary = false;
        if (expr is null)
            return false;
        if (Identifier id = cast(Identifier) expr)
        {
            Object key = identKey(id);
            if (key !is null)
                if (TrackedVar* tv = key in env)
                    if (tv.state == VarState.View)
                    {
                        ownerKey = tv.borrowOwner;
                        ownerName = tv.borrowOwnerName;
                        return true;
                    }
            return false;
        }
        if (CallExpr call = cast(CallExpr) expr)
        {
            if (MemberExpr m = cast(MemberExpr) call.fn)
                if (Identifier meth = cast(Identifier) m.right)
                    if (isViewProducingMethod(meth.value))
                    {
                        if (Identifier recv = cast(Identifier) m.left)
                        {
                            ownerKey = identKey(recv);
                            ownerName = recv.value;
                            return true;
                        }
                        isTemporary = true;
                        ownerName = "<temporário>"d;
                        return true;
                    }
        }
        return false;
    }

    void checkStaticContainerBounds(CallExpr call)
    {
        MemberExpr m = cast(MemberExpr) call.fn;
        if (m is null || m.left is null)
            return;
        Identifier meth = cast(Identifier) m.right;
        if (meth is null)
            return;
        TypeSemaNativeContainer nc = cast(TypeSemaNativeContainer) m.left.type_sema;
        if (nc is null)
            return;
        dstring targetName = (cast(Identifier) m.left) !is null ? (cast(Identifier) m.left).value : nc.toStr();
        if ((meth.value == "obter"d || meth.value == "definir"d || meth.value == "reservar"d)
                && call.args.length >= 1)
        {
            if (IntLit idx = cast(IntLit) call.args[0])
            {
                if (idx.value < 0)
                {
                    if (!dryRun)
                        diag.errorCode(call.args[0].pos, nativeBoundsOrOverflow, targetName,
                                "índice ou capacidade negativa constante");
                }
            }
            else if (UnaryExpr un = cast(UnaryExpr) call.args[0])
            {
                if (un.op == TokenKind.Minus && cast(IntLit) un.value !is null)
                    if (!dryRun)
                        diag.errorCode(call.args[0].pos, nativeBoundsOrOverflow, targetName,
                                "índice ou capacidade negativa constante");
            }
        }
        if (meth.value == "fatia"d && call.args.length == 2)
        {
            IntLit a = cast(IntLit) call.args[0];
            IntLit b = cast(IntLit) call.args[1];
            if (a !is null && b !is null && (a.value < 0 || b.value < a.value))
            {
                if (!dryRun)
                    diag.errorCode(call.pos, nativeBoundsOrOverflow, targetName,
                            "intervalo de fatia inválido (inicio < 0 ou fim < inicio)");
            }
        }
    }

    void analyzeExpr(Node node)
    {
        if (node is null)
            return;
        switch (node.kind)
        {
            case NodeKind.IntLit:
            case NodeKind.DoubleLit:
            case NodeKind.BoolLit:
            case NodeKind.StringLit:
            case NodeKind.NullLit:
            case NodeKind.NaN:
            case NodeKind.BreakStmt:
            case NodeKind.ContinueStmt:
                return;

            case NodeKind.Identifier:
                checkAliveForRead(cast(Identifier) node);
                return;

            case NodeKind.BinaryExpr:
                BinaryExpr bin = cast(BinaryExpr) node;
                analyzeExpr(bin.left);
                analyzeExpr(bin.right);
                return;

            case NodeKind.UnaryExpr:
                UnaryExpr un = cast(UnaryExpr) node;
                analyzeExpr(un.value);
                return;

            case NodeKind.ConditionalExpr:
                ConditionalExpr c = cast(ConditionalExpr) node;
                analyzeExpr(c.condition);
                TrackedVar[Object] savedEnv = cloneEnv();
                ActiveBorrow[][Object] savedBorrows = cloneBorrows();
                analyzeExpr(c.yes);
                TrackedVar[Object] yesEnv = cloneEnv();
                env = savedEnv;
                borrows = savedBorrows;
                analyzeExpr(c.no);
                mergeEnvs(yesEnv, env);
                return;

            case NodeKind.MemberExpr:
                MemberExpr m = cast(MemberExpr) node;
                if (m.enumValue is null)
                    analyzeExpr(m.left);
                return;

            case NodeKind.IndexExpr:
                IndexExpr idx = cast(IndexExpr) node;
                analyzeExpr(idx.value);
                analyzeExpr(idx.idx);
                if (idx.value !is null && cast(TypeSemaNativeContainer) idx.value.type_sema !is null)
                {
                    if (UnaryExpr un = cast(UnaryExpr) idx.idx)
                        if (un.op == TokenKind.Minus && cast(IntLit) un.value !is null)
                            if (!dryRun)
                                diag.errorCode(idx.idx.pos, nativeBoundsOrOverflow,
                                        idx.value.type_sema.toStr(), "índice negativo constante em container nativo");
                }
                return;

            case NodeKind.ArrayLit:
                ArrayLit arr = cast(ArrayLit) node;
                foreach (Node el; arr.elements)
                {
                    analyzeExpr(el);
                    if (isBorrowedViewType(el.type_sema))
                    {
                        if (!dryRun)
                            diag.errorCode(el.pos, unsafeEscape, el.type_sema.toStr(),
                                    "visão emprestada não pode escapar para vetor gerenciado");
                    }
                    else if (hasOwnershipResource(el.type_sema))
                        consumeNode(el, el.pos);
                }
                return;

            case NodeKind.MapLit:
                MapLit map = cast(MapLit) node;
                foreach (Node k; map.keys)
                    analyzeExpr(k);
                foreach (Node v; map.values)
                {
                    analyzeExpr(v);
                    if (isBorrowedViewType(v.type_sema))
                        if (!dryRun)
                            diag.errorCode(v.pos, unsafeEscape, v.type_sema.toStr(),
                                    "visão emprestada não pode escapar para dicionário gerenciado");
                }
                return;

            case NodeKind.TupleLit:
                TupleLit t = cast(TupleLit) node;
                foreach (Node el; t.elements)
                    analyzeExpr(el);
                return;

            case NodeKind.FunctionExpr:
                FunctionExpr fe = cast(FunctionExpr) node;
                analyzeFunction(fe.declaration);
                return;

            case NodeKind.CallExpr:
                analyzeCall(cast(CallExpr) node);
                return;

            case NodeKind.VarDecl:
                analyzeVarDecl(cast(VarDecl) node);
                return;

            case NodeKind.AssignStmt:
                analyzeAssign(cast(AssignStmt) node);
                return;

            case NodeKind.ReturnStmt:
                analyzeReturn(cast(ReturnStmt) node);
                return;

            case NodeKind.IfStmt:
                analyzeIf(cast(IfStmt) node);
                return;

            case NodeKind.WhileStmt:
                analyzeWhile(cast(WhileStmt) node);
                return;

            case NodeKind.ForStmt:
                analyzeFor(cast(ForStmt) node);
                return;

            case NodeKind.DoStmt:
                analyzeDo(cast(DoStmt) node);
                return;

            case NodeKind.EachStmt:
                analyzeEach(cast(EachStmt) node);
                return;

            case NodeKind.SwitchStmt:
                analyzeSwitch(cast(SwitchStmt) node);
                return;

            case NodeKind.TryStmt:
                analyzeTry(cast(TryStmt) node);
                return;

            case NodeKind.ThrowStmt:
                analyzeExpr((cast(ThrowStmt) node).value);
                return;

            case NodeKind.BlockStmt:
                scopeDepth++;
                analyzeStmtList((cast(BlockStmt) node).body);
                releaseBorrowsAtDepth(scopeDepth);
                scopeDepth--;
                return;

            case NodeKind.SequenceStmt:
                foreach (Node st; (cast(SequenceStmt) node).body)
                    analyzeExpr(st);
                return;

            case NodeKind.FnDecl:
                analyzeFunction(cast(FnDecl) node);
                return;

            case NodeKind.ClassDecl:
                ClassDecl cls = cast(ClassDecl) node;
                foreach (FnDecl m; cls.methods)
                    analyzeFunction(m);
                return;

            case NodeKind.AwaitExpr:
                analyzeExpr((cast(AwaitExpr) node).value);
                return;

            case NodeKind.RoutineExpr:
                analyzeExpr((cast(RoutineExpr) node).call);
                return;

            case NodeKind.SliceExpr:
                SliceExpr sl = cast(SliceExpr) node;
                analyzeExpr(sl.value);
                analyzeExpr(sl.start);
                analyzeExpr(sl.end);
                analyzeExpr(sl.step);
                return;

            case NodeKind.SpreadExpr:
                analyzeExpr((cast(SpreadExpr) node).value);
                return;

            case NodeKind.TypeOfExpr:
                analyzeExpr((cast(TypeOfExpr) node).value);
                return;

            case NodeKind.Comprehension:
                Comprehension comp = cast(Comprehension) node;
                analyzeExpr(comp.iterable);
                analyzeExpr(comp.value);
                analyzeExpr(comp.condition);
                return;

            case NodeKind.LoopExpr:
                analyzeExpr((cast(LoopExpr) node).loop);
                return;

            default:
                return;
        }
    }

    void analyzeCall(CallExpr call)
    {
        if (call is null)
            return;

        // Verificar `destruir(x)` explícito
        if (Identifier fnId = cast(Identifier) call.fn)
        {
            if (fnId.value == "destruir"d && call.args.length == 1)
            {
                if (Identifier targetId = cast(Identifier) call.args[0])
                {
                    Object key = identKey(targetId);
                    if (key !is null)
                        if (TrackedVar* tv = key in env)
                        {
                            // Classes gerenciadas GC preservam destruir() idempotente por contrato legado;
                            // o bloqueio de double-free estático aplica-se a recursos proprietários nativos.
                            if (!hasOwnershipResource(tv.type))
                                return;
                            if (tv.state == VarState.Freed)
                            {
                                if (!dryRun)
                                    diag.errorCode(call.pos, doubleFree, tv.name);
                                return;
                            }
                            if (tv.state == VarState.Moved)
                            {
                                if (!dryRun)
                                    diag.errorCode(call.pos, useAfterMove, tv.name);
                                return;
                            }
                            dstring borrower;
                            if (hasActiveBorrows(key, borrower))
                            {
                                if (!dryRun)
                                    diag.errorCode(call.pos, mutableBorrowConflict, tv.name, borrower);
                                return;
                            }
                            tv.state = VarState.Freed;
                            tv.statePos = call.pos;
                            info.freedSomewhere[key] = true;
                            return;
                        }
                }
            }
        }

        // Chamada de método em container ou objeto
        if (MemberExpr m = cast(MemberExpr) call.fn)
        {
            checkStaticContainerBounds(call);
            Identifier meth = cast(Identifier) m.right;
            if (Identifier recv = cast(Identifier) m.left)
            {
                Object recvKey = identKey(recv);
                if (meth !is null && recvKey !is null)
                {
                    TrackedVar* tv = recvKey in env;
                    if (tv !is null && hasOwnershipResource(tv.type))
                    {
                        if (isFreeMethod(meth.value))
                        {
                            if (tv.state == VarState.Freed)
                            {
                                if (!dryRun)
                                    diag.errorCode(call.pos, doubleFree, tv.name);
                                return;
                            }
                            if (tv.state == VarState.Moved)
                            {
                                if (!dryRun)
                                    diag.errorCode(call.pos, useAfterMove, tv.name);
                                return;
                            }
                            dstring borrower;
                            if (hasActiveBorrows(recvKey, borrower))
                            {
                                if (!dryRun)
                                    diag.errorCode(call.pos, mutableBorrowConflict, tv.name, borrower);
                                return;
                            }
                            tv.state = VarState.Freed;
                            tv.statePos = call.pos;
                            info.freedSomewhere[recvKey] = true;
                            return;
                        }
                        if (isMutatingContainerMethod(meth.value))
                        {
                            checkCanMutate(recvKey, call.pos, tv.name);
                        }
                        else
                        {
                            checkAliveForRead(recv);
                        }
                    }
                    else
                    {
                        analyzeExpr(m.left);
                    }
                }
                else
                {
                    analyzeExpr(m.left);
                }
            }
            else
            {
                analyzeExpr(m.left);
            }

            // Analisar argumentos; se o método for `adicionar`/`definir` em container de tipo `Owned`, consome argumento!
            bool consumesValArg = false;
            size_t consumeArgIdx = 0;
            if (meth !is null && m.left !is null)
            {
                if (TypeSemaNativeContainer nc = cast(TypeSemaNativeContainer) m.left.type_sema)
                {
                    if (nc.containerKind == NativeContainerKind.VetorNativo && meth.value == "adicionar"d
                            && nc.typeArgs.length == 1 && hasOwnershipResource(nc.typeArgs[0]))
                    {
                        consumesValArg = true;
                        consumeArgIdx = 0;
                    }
                    else if (nc.containerKind == NativeContainerKind.MapaNativo && meth.value == "definir"d)
                    {
                        if (nc.typeArgs.length == 2)
                        {
                            foreach (size_t ai, Node arg; call.args)
                            {
                                analyzeExpr(arg);
                                if (ai == 0 && hasOwnershipResource(nc.typeArgs[0])
                                        && cast(StringLit) arg is null)
                                    consumeNode(arg, arg.pos);
                                if (ai == 1 && hasOwnershipResource(nc.typeArgs[1]))
                                    consumeNode(arg, arg.pos);
                            }
                            return;
                        }
                    }
                }
            }

            FnDecl targetMethod = meth !is null ? meth.functionRef : null;
            ParamMode[] modes = targetMethod !is null ? inferFunctionParamModes(targetMethod) : null;
            foreach (size_t i, Node arg; call.args)
            {
                analyzeExpr(arg);
                if (consumesValArg && i == consumeArgIdx)
                    consumeNode(arg, arg.pos);
                else if (i < modes.length && modes[i] == ParamMode.Consume)
                    consumeNode(arg, arg.pos);
                else if (i < modes.length && modes[i] == ParamMode.MutBorrow)
                {
                    if (Identifier argId = cast(Identifier) arg)
                        checkCanMutate(identKey(argId), arg.pos, argId.value);
                }
            }
            return;
        }

        // Chamada direta a função livre ou construtor
        FnDecl targetFn = null;
        if (Identifier fnId = cast(Identifier) call.fn)
            targetFn = fnId.functionRef;
        else
            analyzeExpr(call.fn);

        // Construção de classe `@pilha` com campos `Owned`: consome argumentos `Owned`
        if (targetFn !is null && targetFn.classFactory !is null && targetFn.classFactory.isValueType)
        {
            foreach (size_t i, Node arg; call.args)
            {
                analyzeExpr(arg);
                if (hasOwnershipResource(arg.type_sema))
                    consumeNode(arg, arg.pos);
            }
            return;
        }

        ParamMode[] modes = targetFn !is null && !targetFn.builtinName.length
            ? inferFunctionParamModes(targetFn) : null;

        // Detecta aliasing mutável simultâneo na mesma chamada (ex.: f(v, v) onde f muta um deles)
        Object[] mutBorrowedArgs;
        foreach (size_t i, Node arg; call.args)
        {
            analyzeExpr(arg);
            if (i < modes.length)
            {
                if (modes[i] == ParamMode.Consume)
                    consumeNode(arg, arg.pos);
                else if (modes[i] == ParamMode.MutBorrow)
                {
                    if (Identifier argId = cast(Identifier) arg)
                    {
                        Object k = identKey(argId);
                        if (k !is null)
                        {
                            if (mutBorrowedArgs.canFind(k))
                            {
                                if (!dryRun)
                                    diag.errorCode(arg.pos, mutableBorrowConflict, argId.value, argId.value);
                            }
                            checkCanMutate(k, arg.pos, argId.value);
                            mutBorrowedArgs ~= k;
                        }
                    }
                }
            }
            else if (Identifier argId = cast(Identifier) arg)
            {
                Object k = identKey(argId);
                if (k !is null && mutBorrowedArgs.canFind(k))
                    if (!dryRun)
                        diag.errorCode(arg.pos, mutableBorrowConflict, argId.value, argId.value);
            }
        }
        // Também checa se um argumento anterior (ReadBorrow) conflita com um MutBorrow posterior do mesmo objeto
        if (mutBorrowedArgs.length > 0)
        {
            foreach (size_t i, Node arg; call.args)
            {
                if (i < modes.length && modes[i] == ParamMode.ReadBorrow)
                    if (Identifier argId = cast(Identifier) arg)
                        if (mutBorrowedArgs.canFind(identKey(argId)))
                            if (!dryRun)
                                diag.errorCode(arg.pos, mutableBorrowConflict, argId.value, argId.value);
            }
        }
    }

    void analyzeVarDecl(VarDecl varDecl)
    {
        if (varDecl is null || varDecl.isEnum)
            return;

        bool isOwned = hasOwnershipResource(varDecl.type_sema);
        bool isView = isBorrowedViewType(varDecl.type_sema);
        bool isNativeCtx = currentFn !is null && currentFn.isNative;

        if (varDecl.uninitialized || (isNativeCtx && varDecl.lackedExplicitInit))
        {
            if (isOwned || isView || cast(TypeSemaNative) varDecl.type_sema !is null
                    || (cast(TypeSemaClass) varDecl.type_sema !is null
                        && (cast(TypeSemaClass) varDecl.type_sema).declaration.isValueType))
            {
                env[varDecl] = TrackedVar(varDecl.name, varDecl.type_sema, VarState.Uninitialized,
                        scopeDepth, null, ""d, false, varDecl.pos);
            }
            return;
        }

        analyzeExpr(varDecl.value);

        if (isOwned)
        {
            consumeNode(varDecl.value, varDecl.pos);
            env[varDecl] = TrackedVar(varDecl.name, varDecl.type_sema, VarState.Owned,
                    scopeDepth, null, ""d, false, varDecl.pos);
            return;
        }

        if (isView)
        {
            Object ownerKey;
            dstring ownerName;
            bool isTemp;
            if (extractBorrowOrigin(varDecl.value, ownerKey, ownerName, isTemp))
            {
                if (isTemp)
                {
                    if (!dryRun)
                        diag.errorCode(varDecl.pos, danglingReturn, varDecl.name, ownerName);
                }
                else if (ownerKey !is null)
                {
                    borrows[ownerKey] ~= ActiveBorrow(varDecl, varDecl.name, scopeDepth);
                }
                env[varDecl] = TrackedVar(varDecl.name, varDecl.type_sema, VarState.View,
                        scopeDepth, ownerKey, ownerName, false, varDecl.pos);
            }
            else
            {
                env[varDecl] = TrackedVar(varDecl.name, varDecl.type_sema, VarState.View,
                        scopeDepth, null, ""d, false, varDecl.pos);
            }
            return;
        }

        env[varDecl] = TrackedVar(varDecl.name, varDecl.type_sema, VarState.Copy,
                scopeDepth, null, ""d, false, varDecl.pos);
    }

    void analyzeAssign(AssignStmt ass)
    {
        if (ass is null)
            return;
        analyzeExpr(ass.value);

        // Atribuição a campo de objeto: impedir escape de visão para campo de objeto!
        if (MemberExpr m = cast(MemberExpr) ass.left)
        {
            analyzeExpr(m.left);
            if (isBorrowedViewType(ass.value.type_sema))
            {
                if (!dryRun)
                    diag.errorCode(ass.pos, unsafeEscape, ass.value.type_sema.toStr(),
                            "visão emprestada não pode escapar por campo de objeto");
            }
            else if (hasOwnershipResource(ass.value.type_sema))
            {
                consumeNode(ass.value, ass.pos);
            }
            return;
        }

        // Atribuição a elemento indexado `v[i] = val`
        if (IndexExpr idx = cast(IndexExpr) ass.left)
        {
            if (Identifier baseId = cast(Identifier) idx.value)
                checkCanMutate(identKey(baseId), ass.pos, baseId.value);
            else
                analyzeExpr(idx.value);
            analyzeExpr(idx.idx);
            if (hasOwnershipResource(ass.value.type_sema))
                consumeNode(ass.value, ass.pos);
            return;
        }

        // Atribuição a variável simples `x = val`
        if (Identifier leftId = cast(Identifier) ass.left)
        {
            Object key = identKey(leftId);
            if (key is null)
                return;
            if (ass.op != TokenKind.Equals)
            {
                checkAliveForRead(leftId);
                return;
            }
            dstring borrower;
            if (hasActiveBorrows(key, borrower))
            {
                if (!dryRun)
                    diag.errorCode(ass.pos, mutableBorrowConflict, leftId.value, borrower);
            }
            TrackedVar* tv = key in env;
            if (tv !is null && hasOwnershipResource(tv.type))
            {
                consumeNode(ass.value, ass.pos);
                tv.state = VarState.Owned;
                tv.statePos = ass.pos;
                return;
            }
            if (tv !is null && isBorrowedViewType(tv.type))
            {
                releaseBorrower(key);
                Object ownerKey;
                dstring ownerName;
                bool isTemp;
                if (extractBorrowOrigin(ass.value, ownerKey, ownerName, isTemp))
                {
                    if (isTemp)
                    {
                        if (!dryRun)
                            diag.errorCode(ass.pos, danglingReturn, tv.name, ownerName);
                    }
                    else if (ownerKey !is null)
                    {
                        if (TrackedVar* ownerTv = ownerKey in env)
                        {
                            // Não permitir que uma visão de escopo externo aponte para dono de escopo interno!
                            if (ownerTv.scopeDepth > tv.scopeDepth)
                                if (!dryRun)
                                    diag.errorCode(ass.pos, unsafeEscape, tv.name,
                                            "visão sobrevive ao escopo do recurso '" ~ ownerTv.name.to!string ~ "'");
                        }
                        borrows[ownerKey] ~= ActiveBorrow(key, tv.name, tv.scopeDepth);
                    }
                    tv.borrowOwner = ownerKey;
                    tv.borrowOwnerName = ownerName;
                    tv.state = VarState.View;
                }
                return;
            }
            if (tv !is null && tv.state == VarState.Uninitialized)
                tv.state = VarState.Copy;
        }
    }

    void analyzeReturn(ReturnStmt ret)
    {
        if (ret is null || ret.val is null)
            return;
        analyzeExpr(ret.val);

        // Retorno de visão vinculada a recurso local ou temporário -> dangling reference!
        if (isBorrowedViewType(ret.val.type_sema))
        {
            Object ownerKey;
            dstring ownerName;
            bool isTemp;
            if (extractBorrowOrigin(ret.val, ownerKey, ownerName, isTemp))
            {
                if (isTemp)
                {
                    if (!dryRun)
                        diag.errorCode(ret.pos, danglingReturn, ret.val.type_sema.toStr(), ownerName);
                    return;
                }
                if (ownerKey !is null)
                    if (TrackedVar* ownerTv = ownerKey in env)
                        if (!ownerTv.isParam)
                        {
                            if (!dryRun)
                                diag.errorCode(ret.pos, danglingReturn,
                                        (cast(Identifier) ret.val) !is null
                                        ? (cast(Identifier) ret.val).value : ret.val.type_sema.toStr(),
                                        ownerTv.name);
                            return;
                        }
            }
        }

        // Retorno de struct @pilha contendo visão emprestada de recurso local -> escape inseguro!
        if (CallExpr ctorCall = cast(CallExpr) ret.val)
        {
            foreach (Node arg; ctorCall.args)
            {
                if (isBorrowedViewType(arg.type_sema))
                {
                    Object aOwner;
                    dstring aName;
                    bool aTemp;
                    if (extractBorrowOrigin(arg, aOwner, aName, aTemp))
                    {
                        bool localOwner = aTemp;
                        if (!localOwner && aOwner !is null)
                            if (TrackedVar* otv = aOwner in env)
                                localOwner = !otv.isParam;
                        if (localOwner)
                        {
                            if (!dryRun)
                                diag.errorCode(ret.pos, unsafeEscape, arg.type_sema.toStr(),
                                        "visão local não pode escapar dentro de valor retornado");
                            return;
                        }
                    }
                }
            }
        }

        // Retorno de valor `Owned`: transfere ownership com segurança para o chamador!
        if (hasOwnershipResource(ret.val.type_sema))
            consumeNode(ret.val, ret.pos);
    }

    void analyzeIf(IfStmt branch)
    {
        if (branch is null)
            return;
        if (branch.expr !is null)
            analyzeExpr(branch.expr);

        TrackedVar[Object] beforeEnv = cloneEnv();
        ActiveBorrow[][Object] beforeBorrows = cloneBorrows();

        scopeDepth++;
        analyzeStmtList(branch.body);
        releaseBorrowsAtDepth(scopeDepth);
        scopeDepth--;

        bool thenTerminates = alwaysTerminates(branch.body);
        TrackedVar[Object] thenEnv = cloneEnv();

        env = beforeEnv;
        borrows = beforeBorrows;
        bool elseTerminates = false;
        if (branch._else !is null)
        {
            if (branch._else.expr !is null)
            {
                analyzeIf(branch._else);
                elseTerminates = alwaysTerminates([cast(Node) branch._else]);
            }
            else
            {
                scopeDepth++;
                analyzeStmtList(branch._else.body);
                releaseBorrowsAtDepth(scopeDepth);
                scopeDepth--;
                elseTerminates = alwaysTerminates(branch._else.body);
            }
        }
        if (thenTerminates && !elseTerminates)
        {
            // Somente o ramo else/fallthrough continua após o if
        }
        else if (!thenTerminates && elseTerminates)
        {
            env = thenEnv;
        }
        else
        {
            mergeEnvs(thenEnv, env);
        }
    }

    void analyzeLoopBody(Node[] body)
    {
        // Passagem 1 + passagem 2 simulando segunda iteração para detectar move/free em loop de variável externa!
        scopeDepth++;
        analyzeStmtList(body);
        releaseBorrowsAtDepth(scopeDepth);
        scopeDepth--;

        TrackedVar[Object] afterFirst = cloneEnv();
        ActiveBorrow[][Object] afterFirstBorrows = cloneBorrows();
        scopeDepth++;
        analyzeStmtList(body);
        releaseBorrowsAtDepth(scopeDepth);
        scopeDepth--;
        mergeEnvs(afterFirst, env);
        borrows = afterFirstBorrows;
    }

    void analyzeWhile(WhileStmt w)
    {
        analyzeExpr(w.expr);
        analyzeLoopBody(w.body);
    }

    void analyzeFor(ForStmt f)
    {
        scopeDepth++;
        analyzeExpr(f.init);
        analyzeExpr(f.condition);
        analyzeLoopBody(f.body);
        analyzeExpr(f.step);
        releaseBorrowsAtDepth(scopeDepth);
        scopeDepth--;
    }

    void analyzeDo(DoStmt d)
    {
        analyzeLoopBody(d.body);
        analyzeExpr(d.condition);
    }

    void analyzeEach(EachStmt e)
    {
        analyzeExpr(e.iterable);
        scopeDepth++;
        Object iterOwner = null;
        if (Identifier iterId = cast(Identifier) e.iterable)
        {
            Object k = identKey(iterId);
            if (k !is null)
                if (TrackedVar* tv = k in env)
                    if (hasOwnershipResource(tv.type))
                    {
                        iterOwner = k;
                        borrows[k] ~= ActiveBorrow(e, "iteração 'para cada'"d, scopeDepth);
                    }
        }
        foreach (Node st; e.body)
            analyzeExpr(st);
        releaseBorrowsAtDepth(scopeDepth);
        scopeDepth--;
    }

    void analyzeSwitch(SwitchStmt sw)
    {
        analyzeExpr(sw.value);
        TrackedVar[Object] beforeEnv = cloneEnv();
        ActiveBorrow[][Object] beforeBorrows = cloneBorrows();
        TrackedVar[Object] combinedEnv = cloneEnv();
        bool first = true;
        foreach (SwitchCase c; sw.cases)
        {
            foreach (Node v; c.values)
                analyzeExpr(v);
            env = cloneEnvFrom(beforeEnv);
            borrows = cloneBorrowsFrom(beforeBorrows);
            scopeDepth++;
            foreach (Node st; c.body)
                analyzeExpr(st);
            releaseBorrowsAtDepth(scopeDepth);
            scopeDepth--;
            if (first)
            {
                combinedEnv = cloneEnv();
                first = false;
            }
            else
                mergeEnvs(combinedEnv, env);
            combinedEnv = cloneEnv();
        }
        if (sw.fallback.length)
        {
            env = cloneEnvFrom(beforeEnv);
            borrows = cloneBorrowsFrom(beforeBorrows);
            scopeDepth++;
            foreach (Node st; sw.fallback)
                analyzeExpr(st);
            releaseBorrowsAtDepth(scopeDepth);
            scopeDepth--;
            if (!first)
                mergeEnvs(combinedEnv, env);
        }
        else if (!first)
        {
            mergeEnvs(beforeEnv, combinedEnv);
        }
    }

    TrackedVar[Object] cloneEnvFrom(TrackedVar[Object] src)
    {
        TrackedVar[Object] copy;
        foreach (Object k, TrackedVar v; src)
            copy[k] = v;
        return copy;
    }

    ActiveBorrow[][Object] cloneBorrowsFrom(ActiveBorrow[][Object] src)
    {
        ActiveBorrow[][Object] copy;
        foreach (Object k, ActiveBorrow[] list; src)
            copy[k] = list.dup;
        return copy;
    }

    void analyzeTry(TryStmt t)
    {
        TrackedVar[Object] beforeEnv = cloneEnv();
        ActiveBorrow[][Object] beforeBorrows = cloneBorrows();
        scopeDepth++;
        foreach (Node st; t.body)
            analyzeExpr(st);
        releaseBorrowsAtDepth(scopeDepth);
        scopeDepth--;
        TrackedVar[Object] afterTry = cloneEnv();

        foreach (CatchClause c; t.catches)
        {
            env = cloneEnvFrom(beforeEnv);
            borrows = cloneBorrowsFrom(beforeBorrows);
            scopeDepth++;
            foreach (Node st; c.body)
                analyzeExpr(st);
            releaseBorrowsAtDepth(scopeDepth);
            scopeDepth--;
            mergeEnvs(afterTry, env);
            afterTry = cloneEnv();
        }
        env = afterTry;
        if (t.finalBody.length)
        {
            scopeDepth++;
            foreach (Node st; t.finalBody)
                analyzeExpr(st);
            releaseBorrowsAtDepth(scopeDepth);
            scopeDepth--;
        }
    }

    void analyzeFunction(FnDecl fn)
    {
        if (fn is null || fn in visited)
            return;
        visited[fn] = true;
        if (fn.builtinName.length || fn.isAbstract || fn.foreignSymbol.length)
            return;

        TrackedVar[Object] savedEnv = env;
        ActiveBorrow[][Object] savedBorrows = borrows;
        size_t savedDepth = scopeDepth;
        FnDecl savedFn = currentFn;

        env = null;
        borrows = null;
        scopeDepth = 1;
        currentFn = fn;
        scope (exit)
        {
            env = savedEnv;
            borrows = savedBorrows;
            scopeDepth = savedDepth;
            currentFn = savedFn;
        }

        foreach (FnArg arg; fn.args)
        {
            VarState st = hasOwnershipResource(arg.type_sema) ? VarState.Owned
                : isBorrowedViewType(arg.type_sema) ? VarState.View : VarState.Copy;
            env[arg] = TrackedVar(arg.name, arg.type_sema, st, 1, null, ""d, true, arg.pos);
        }

        analyzeStmtList(fn.body);
        releaseBorrowsAtDepth(1);
    }

    void visitModule(Node node)
    {
        if (node is null || node in visited)
            return;
        if (ModuleUnit mod = cast(ModuleUnit) node)
        {
            visited[node] = true;
            visitModule(mod.program);
            return;
        }
        if (Program prog = cast(Program) node)
        {
            visited[node] = true;
            TrackedVar[Object] savedEnv = env;
            ActiveBorrow[][Object] savedBorrows = borrows;
            size_t savedDepth = scopeDepth;
            env = null;
            borrows = null;
            scopeDepth = 0;
            scope (exit)
            {
                env = savedEnv;
                borrows = savedBorrows;
                scopeDepth = savedDepth;
            }
            foreach (Node st; prog.body)
            {
                if (ImportExpr imp = cast(ImportExpr) st)
                {
                    if (imp.target !is null)
                        visitModule(imp.target);
                }
                else if (VarDecl vd = cast(VarDecl) st)
                {
                    if (ImportExpr imp = cast(ImportExpr) vd.value)
                    {
                        if (imp.target !is null)
                            visitModule(imp.target);
                    }
                    analyzeExpr(vd);
                }
                else
                {
                    analyzeExpr(st);
                }
            }
            return;
        }
    }

public:
    this(Diagnostics diag)
    {
        this.diag = diag;
        this.info = new OwnershipInfo;
    }

    OwnershipInfo analyze(Program program)
    {
        visitModule(program);
        return info;
    }
}

OwnershipInfo analyzeOwnership(Program program, Diagnostics diag)
{
    return new OwnershipAnalyzer(diag).analyze(program);
}
