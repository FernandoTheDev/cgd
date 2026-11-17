module ctfe.compile;

import std.format;
import std.exception : enforce;

import frontend.lexer.token : Position, TokenKind;
import std.conv : to;
import frontend.parser;
import frontend.type_expr;
import ctfe;

final class CTFECompile
{
    size_t[dstring] fnVars;

    dstring label;
    size_t tmp, nextSlot;
    VMInstruction[][dstring] instructions;
    dstring[] labelOrder;

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

                compile(bexpr.left);
                compile(bexpr.right);

                VMOpCode[TokenKind] operators = [
                    TokenKind.Star: VMOpCode.Mul, TokenKind.Plus: VMOpCode.Add,
                    TokenKind.Slash: VMOpCode.Div, TokenKind.IntDiv: VMOpCode.IDiv,
                    TokenKind.Minus: VMOpCode.Sub, TokenKind.Modulo: VMOpCode.Mod,

                    TokenKind.LEquals: VMOpCode.Le, TokenKind.LThan: VMOpCode.Lt,
                    TokenKind.GEquals: VMOpCode.Ge, TokenKind.GThan: VMOpCode.Gt,
                    TokenKind.EEquals: VMOpCode.Eq, TokenKind.NEquals: VMOpCode.Neq,

                    TokenKind.BITAnd: VMOpCode.BAnd, TokenKind.BITOr: VMOpCode.BOr,
                    TokenKind.BITXor: VMOpCode.BXor, TokenKind.BITSL: VMOpCode.Shl,
                    TokenKind.BITSR: VMOpCode.Shr,
                ];

                return emit(VMInstruction.instr(operators[bexpr.op]));

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
                enforce(slot !is null, "Símbolo sem slot na avaliação em tempo de compilação.");
                return emit(VMInstruction.instr(VMOpCode.Load, *slot));

            case NodeKind.CallExpr:
                CallExpr call = cast(CallExpr) node;
                dstring name = (cast(Identifier) call.fn).functionRef.linkName;

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
                compileBody(wstmt.body);

                // volta pro inicio
                emit(VMInstruction.instr(VMOpCode.Jmp, CGDValue.texto(l0)));

                enterLabel(l2);
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

        throw new Exception("Resultado não representável na CTFE.");
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
            if (cast(CallExpr) child || cast(BinaryExpr) child || cast(UnaryExpr) child
                    || cast(Identifier) child || cast(AssignStmt) child || cast(IntLit) child
                    || cast(DoubleLit) child || cast(StringLit) child || cast(BoolLit) child)
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
