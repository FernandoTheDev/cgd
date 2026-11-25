module ctfe.compile;

import std.format;
import std.exception : enforce;

import frontend.lexer.token : Position, TokenKind;
import std.conv : to;
import frontend.parser;
import frontend.type_expr;
import ctfe;
import ctfe.evaluation : pureCallTarget;

final class CTFECompile
{
    size_t[dstring] fnVars;

    dstring label;
    size_t tmp, nextSlot;
    VMInstruction[][dstring] instructions;
    dstring[] labelOrder;
    dstring[] breakTargets;
    dstring[] continueTargets;

    pragma(inline, true) void emit(VMInstruction instr)
    {
        instructions[label] ~= instr;
    }

    pragma(inline, true) dstring newLabel()
    {
        dstring name = "_label"d ~ (tmp++).to!dstring;
        instructions[name] = (VMInstruction[]).init;
        return name;
    }

    pragma(inline, true) void enterLabel(dstring name)
    {
        label = name;
        labelOrder ~= name;
    }

    void compile(Node node)
    {
        switch (node.kind)
        {
            case NodeKind.ReturnStmt:
                compile((cast(ReturnStmt) node).val);
                return emit(VMInstruction.instr(VMOpCode.Ret));

            case NodeKind.VarDecl:
                VarDecl var = cast(VarDecl) node;
                if (var.isEnum)
                    return;
                dstring name = var.name;
                compile(var.value);
                emitTypeCheck(var.type_expr);
                fnVars[name] = nextSlot++;
                return emit(VMInstruction.instr(VMOpCode.Store, fnVars[name]));

            case NodeKind.MemberExpr:
                enforce((cast(MemberExpr) node).enumValue !is null, "Membro sem constante CTFE.");
                return compile((cast(MemberExpr) node).enumValue);
            case NodeKind.IntLit:
            case NodeKind.BoolLit:
            case NodeKind.StringLit:
            case NodeKind.DoubleLit:
                return emit(VMInstruction.instr(VMOpCode.Push, nodeToCgdValue(node)));

            case NodeKind.BinaryExpr:
                BinaryExpr bexpr = cast(BinaryExpr) node;

                if (bexpr.op == TokenKind.And)
                {
                    dstring shortLbl = newLabel();
                    dstring endLbl = newLabel();
                    compile(bexpr.left);
                    emit(VMInstruction.instr(VMOpCode.Jz, CGDValue.texto(shortLbl)));
                    compile(bexpr.right);
                    emit(VMInstruction.instr(VMOpCode.Jmp, CGDValue.texto(endLbl)));
                    enterLabel(shortLbl);
                    emit(VMInstruction.instr(VMOpCode.Push, CGDValue.logico(false)));
                    enterLabel(endLbl);
                    return;
                }
                if (bexpr.op == TokenKind.Or)
                {
                    dstring shortLbl = newLabel();
                    dstring endLbl = newLabel();
                    compile(bexpr.left);
                    emit(VMInstruction.instr(VMOpCode.Jnz, CGDValue.texto(shortLbl)));
                    compile(bexpr.right);
                    emit(VMInstruction.instr(VMOpCode.Jmp, CGDValue.texto(endLbl)));
                    enterLabel(shortLbl);
                    emit(VMInstruction.instr(VMOpCode.Push, CGDValue.logico(true)));
                    enterLabel(endLbl);
                    return;
                }

                compile(bexpr.left);
                compile(bexpr.right);

                VMOpCode[TokenKind] operators = [
                    TokenKind.Star: VMOpCode.Mul, TokenKind.Plus: VMOpCode.Add,
                    TokenKind.Slash: VMOpCode.Div, TokenKind.IntDiv: VMOpCode.IDiv,
                    TokenKind.Minus: VMOpCode.Sub, TokenKind.Modulo: VMOpCode.Mod,
                    TokenKind.Pow: VMOpCode.Pow,

                    TokenKind.LEquals: VMOpCode.Le, TokenKind.LThan: VMOpCode.Lt,
                    TokenKind.GEquals: VMOpCode.Ge, TokenKind.GThan: VMOpCode.Gt,
                    TokenKind.EEquals: VMOpCode.Eq, TokenKind.NEquals: VMOpCode.Neq,

                    TokenKind.BITAnd: VMOpCode.BAnd, TokenKind.BITOr: VMOpCode.BOr,
                    TokenKind.BITXor: VMOpCode.BXor, TokenKind.BITSL: VMOpCode.Shl,
                    TokenKind.BITSR: VMOpCode.Shr,
                ];

                return emit(VMInstruction.instr(operators[bexpr.op]));

            case NodeKind.ConditionalExpr:
                ConditionalExpr cond = cast(ConditionalExpr) node;
                dstring noLbl = newLabel();
                dstring endLbl = newLabel();
                compile(cond.condition);
                emit(VMInstruction.instr(VMOpCode.Jz, CGDValue.texto(noLbl)));
                compile(cond.yes);
                emit(VMInstruction.instr(VMOpCode.Jmp, CGDValue.texto(endLbl)));
                enterLabel(noLbl);
                compile(cond.no);
                enterLabel(endLbl);
                return;

            case NodeKind.ArrayLit:
                ArrayLit arr = cast(ArrayLit) node;
                foreach (Node el; arr.elements)
                    compile(el);
                return emit(VMInstruction.instr(VMOpCode.MakeArray, arr.elements.length));

            case NodeKind.IndexExpr:
                IndexExpr idx = cast(IndexExpr) node;
                compile(idx.value);
                compile(idx.idx);
                return emit(VMInstruction.instr(VMOpCode.IndexGet));

            case NodeKind.UnaryExpr:
                UnaryExpr un = cast(UnaryExpr) node;
                if (un.op == TokenKind.PPlus || un.op == TokenKind.MMinus)
                {
                    Identifier id = cast(Identifier) un.value;
                    size_t slot = fnVars[id.value];
                    size_t saved = nextSlot++;
                    emit(VMInstruction.instr(VMOpCode.Load, slot));
                    emit(VMInstruction.instr(VMOpCode.Store, saved));
                    emit(VMInstruction.instr(VMOpCode.Load, saved));
                    emit(VMInstruction.instr(VMOpCode.Push, CGDValue.inteiro(1)));
                    emit(VMInstruction.instr(un.op == TokenKind.PPlus ? VMOpCode.Add : VMOpCode.Sub));
                    emitTypeCheck(un.value.type_expr);
                    emit(VMInstruction.instr(VMOpCode.Store, slot));
                    return emit(VMInstruction.instr(VMOpCode.Load, un.post ? saved : slot));
                }
                compile(un.value);
                if (un.op == TokenKind.Plus)
                    return;
                VMOpCode[TokenKind] operators = [
                    TokenKind.Minus: VMOpCode.Neg, TokenKind.Bang: VMOpCode.Not,
                    TokenKind.BITNot: VMOpCode.BNot
                ];
                return emit(VMInstruction.instr(operators[un.op]));

            case NodeKind.Identifier:
                Identifier id = cast(Identifier) node;

                size_t* slot = id.value in fnVars;
                if (slot !is null)
                    return emit(VMInstruction.instr(VMOpCode.Load, *slot));
                if (id.variableRef !is null && id.variableRef.isConst && !id.variableRef.uninitialized
                        && id.variableRef.value !is null)
                {
                    CGDValue val = nodeToCgdValue(id.variableRef.value);
                    return emit(VMInstruction.instr(VMOpCode.Push, val));
                }
                enforce(false, "Símbolo sem slot na avaliação em tempo de compilação.");
                return;

            case NodeKind.CallExpr:
                CallExpr call = cast(CallExpr) node;
                FnDecl target = pureCallTarget(call);
                enforce(target !is null, "Chamada não suportada na avaliação em tempo de compilação.");
                dstring name = target.linkName;

                size_t[] arguments;
                foreach (Node child; call.args)
                {
                    compile(child);
                    size_t slot = nextSlot++;
                    emit(VMInstruction.instr(VMOpCode.Store, slot));
                    arguments ~= slot;
                }
                foreach_reverse (size_t slot; arguments)
                    emit(VMInstruction.instr(VMOpCode.Load, slot));

                emit(VMInstruction.instr(VMOpCode.Push, CGDValue.inteiro(cast(long) call.args.length)));
                return emit(VMInstruction.instr(VMOpCode.Call, name));

            case NodeKind.BlockStmt:
                compileBody((cast(BlockStmt) node).body);
                return;

            case NodeKind.IfStmt:
                IfStmt branch = cast(IfStmt) node;
                if (branch.expr is null)
                {
                    compileBody(branch.body);
                    return;
                }
                compile(branch.expr);
                dstring yes = newLabel(), no = newLabel(), end = newLabel();
                emit(VMInstruction.instr(VMOpCode.Jz, CGDValue.texto(no)));
                enterLabel(yes);
                compileBody(branch.body);
                emit(VMInstruction.instr(VMOpCode.Jmp, CGDValue.texto(end)));
                enterLabel(no);
                if (branch._else !is null)
                    compile(branch._else);
                enterLabel(end);
                return;

            case NodeKind.WhileStmt:
                WhileStmt wstmt = cast(WhileStmt) node;

                dstring l0 = newLabel();
                dstring l1 = newLabel();
                dstring l2 = newLabel();

                enterLabel(l0);
                compile(wstmt.expr);

                emit(VMInstruction.instr(VMOpCode.Jz, CGDValue.texto(l2)));

                enterLabel(l1);
                breakTargets ~= l2;
                continueTargets ~= l0;
                compileBody(wstmt.body);
                breakTargets.length--;
                continueTargets.length--;

                // volta pro inicio
                emit(VMInstruction.instr(VMOpCode.Jmp, CGDValue.texto(l0)));

                enterLabel(l2);
                return;

            case NodeKind.ForStmt:
                ForStmt fstmt = cast(ForStmt) node;
                size_t[dstring] savedVars = fnVars.dup;
                scope (exit)
                    fnVars = savedVars;
                if (fstmt.init !is null)
                {
                    compile(fstmt.init);
                    if (isExprResult(fstmt.init))
                        emit(VMInstruction.instr(VMOpCode.Drop));
                }
                dstring condLbl = newLabel();
                dstring stepLbl = newLabel();
                dstring endLbl = newLabel();
                enterLabel(condLbl);
                if (fstmt.condition !is null)
                {
                    compile(fstmt.condition);
                    emit(VMInstruction.instr(VMOpCode.Jz, CGDValue.texto(endLbl)));
                }
                breakTargets ~= endLbl;
                continueTargets ~= stepLbl;
                compileBody(fstmt.body);
                breakTargets.length--;
                continueTargets.length--;
                enterLabel(stepLbl);
                if (fstmt.step !is null)
                {
                    compile(fstmt.step);
                    if (isExprResult(fstmt.step))
                        emit(VMInstruction.instr(VMOpCode.Drop));
                }
                emit(VMInstruction.instr(VMOpCode.Jmp, CGDValue.texto(condLbl)));
                enterLabel(endLbl);
                return;

            case NodeKind.DoStmt:
                DoStmt dstmt = cast(DoStmt) node;
                dstring bodyLbl = newLabel();
                dstring condLbl = newLabel();
                dstring endLbl = newLabel();
                enterLabel(bodyLbl);
                breakTargets ~= endLbl;
                continueTargets ~= condLbl;
                compileBody(dstmt.body);
                breakTargets.length--;
                continueTargets.length--;
                enterLabel(condLbl);
                compile(dstmt.condition);
                emit(VMInstruction.instr(VMOpCode.Jnz, CGDValue.texto(bodyLbl)));
                enterLabel(endLbl);
                return;

            case NodeKind.BreakStmt:
                enforce(breakTargets.length > 0, "CTFE: sustar fora de laço/escolha.");
                return emit(VMInstruction.instr(VMOpCode.Jmp, CGDValue.texto(breakTargets[$ - 1])));

            case NodeKind.ContinueStmt:
                enforce(continueTargets.length > 0, "CTFE: continua fora de laço.");
                return emit(VMInstruction.instr(VMOpCode.Jmp, CGDValue.texto(continueTargets[$ - 1])));

            case NodeKind.SwitchStmt:
                SwitchStmt sw = cast(SwitchStmt) node;
                compile(sw.value);
                size_t discSlot = nextSlot++;
                emit(VMInstruction.instr(VMOpCode.Store, discSlot));
                dstring endLbl = newLabel();
                dstring fallbackLbl = newLabel();
                dstring[] caseBodyLabels;
                foreach (size_t ci, SwitchCase c; sw.cases)
                {
                    dstring bodyLbl = newLabel();
                    caseBodyLabels ~= bodyLbl;
                    foreach (Node v; c.values)
                    {
                        emit(VMInstruction.instr(VMOpCode.Load, discSlot));
                        compile(v);
                        emit(VMInstruction.instr(VMOpCode.Eq));
                        emit(VMInstruction.instr(VMOpCode.Jnz, CGDValue.texto(bodyLbl)));
                    }
                }
                emit(VMInstruction.instr(VMOpCode.Jmp, CGDValue.texto(fallbackLbl)));
                breakTargets ~= endLbl;
                foreach (size_t ci, SwitchCase c; sw.cases)
                {
                    enterLabel(caseBodyLabels[ci]);
                    compileBody(c.body);
                    emit(VMInstruction.instr(VMOpCode.Jmp, CGDValue.texto(endLbl)));
                }
                enterLabel(fallbackLbl);
                compileBody(sw.fallback);
                breakTargets.length--;
                enterLabel(endLbl);
                return;

            case NodeKind.AssignStmt:
                AssignStmt assignment = cast(AssignStmt) node;
                dstring name = (cast(Identifier) assignment.left).value;
                if (assignment.op != TokenKind.Equals)
                    emit(VMInstruction.instr(VMOpCode.Load, fnVars[name]));
                compile(assignment.value);
                if (assignment.op != TokenKind.Equals)
                {
                    VMOpCode[TokenKind] ops = [
                        TokenKind.PlusAssign: VMOpCode.Add, TokenKind.MinusAssign: VMOpCode.Sub,
                        TokenKind.MulAssign: VMOpCode.Mul, TokenKind.DivAssign: VMOpCode.Div,
                        TokenKind.ModAssign: VMOpCode.Mod
                    ];
                    emit(VMInstruction.instr(ops[assignment.op]));
                }
                emitTypeCheck(assignment.left.type_expr);
                emit(VMInstruction.instr(VMOpCode.Store, fnVars[name]));
                return emit(VMInstruction.instr(VMOpCode.Load, fnVars[name]));

            default:
                throw new Exception("Node não suportado para CTFE.");
        }
    }

    static CGDValue nodeToCgdValue(Node node)
    {
        if (node.kind == NodeKind.IntLit)
            return CGDValue.inteiro((cast(IntLit) node).value);

        if (node.kind == NodeKind.DoubleLit)
            return CGDValue.real_((cast(DoubleLit) node).value);

        if (node.kind == NodeKind.BoolLit)
            return CGDValue.logico((cast(BoolLit) node).value);

        if (node.kind == NodeKind.StringLit)
            return CGDValue.texto((cast(StringLit) node).value);

        if (node.kind == NodeKind.ArrayLit)
        {
            ArrayLit arr = cast(ArrayLit) node;
            CGDValue[] elems;
            foreach (Node el; arr.elements)
                elems ~= nodeToCgdValue(el);
            return CGDValue.vetor(elems);
        }

        throw new Exception("Valor não representável na CTFE.");
    }

    static Node cgdValueToNode(CGDValue value)
    {
        if (value.type == CGDTypeKind.Inteiro)
            return new IntLit(value.i, Position.init);

        if (value.type == CGDTypeKind.Logico)
            return new BoolLit(value.b1, Position.init);

        if (value.type == CGDTypeKind.Real)
            return new DoubleLit(value.d, Position.init);

        if (value.type == CGDTypeKind.Texto)
            return new StringLit(value.s, Position.init);

        if (value.type == CGDTypeKind.Vetor)
        {
            Node[] elems;
            foreach (CGDValue el; value.arr)
                elems ~= cgdValueToNode(el);
            return new ArrayLit(elems, Position.init);
        }

        throw new Exception("Resultado não representável na CTFE.");
    }

    private static bool isExprResult(Node child)
    {
        return cast(CallExpr) child !is null || cast(BinaryExpr) child !is null
            || cast(UnaryExpr) child !is null || cast(Identifier) child !is null
            || cast(AssignStmt) child !is null || cast(IntLit) child !is null
            || cast(DoubleLit) child !is null || cast(StringLit) child !is null
            || cast(BoolLit) child !is null || cast(ConditionalExpr) child !is null
            || cast(ArrayLit) child !is null || cast(IndexExpr) child !is null;
    }

    void emitTypeCheck(TypeExpr type)
    {
        if (type !is null)
            emit(VMInstruction.instr(VMOpCode.Validate, type.toStr()));
    }

    void compileBody(Node[] body)
    {
        size_t[dstring] bindings = fnVars.dup;
        scope (exit)
            fnVars = bindings;
        foreach (Node child; body)
        {
            compile(child);
            if (isExprResult(child))
                emit(VMInstruction.instr(VMOpCode.Drop));
        }
    }

    VMInstruction[] compile(FnDecl fn)
    {
        tmp = 0;
        nextSlot = 0;
        instructions = null;
        fnVars = null;
        labelOrder = null;
        label = null;

        enterLabel(newLabel());
        foreach (size_t i, FnArg arg; fn.args)
        {
            fnVars[arg.name] = nextSlot++;
            emit(VMInstruction.instr(VMOpCode.LoadParam, i));
            emitTypeCheck(arg.type_expr);
            emit(VMInstruction.instr(VMOpCode.Store, fnVars[arg.name]));
        }
        compileBody(fn.body);

        VMInstruction[] instrs = [];
        long[dstring] labels;
        long size;

        foreach (dstring key; labelOrder)
        {
            labels[key] = size;
            size += cast(long) instructions[key].length;
        }

        foreach (dstring key; labelOrder)
            instrs ~= instructions[key];

        foreach (size_t i, ref VMInstruction instr; instrs)
        {
            if (instr.opCode == VMOpCode.Jnz || instr.opCode == VMOpCode.Jz || instr.opCode == VMOpCode.Jmp)
            {
                // resolve o nome
                long addr = labels[instr.value.s];
                instr.param = addr;
            }
        }
        instrs ~= VMInstruction.instr(VMOpCode.Halt);

        return instrs;
    }
}
