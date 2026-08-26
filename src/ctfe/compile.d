module ctfe.compile;

import std.format;
import std.stdio;

import frontend.lexer.token : Position, TokenKind;
import backend.c.utils : formatD;
import frontend.parser;
import ctfe;

final class CTFECompile
{
    size_t[dstring] fnArgs;
    size_t[dstring] fnVars;

    dstring label;
    size_t tmp;
    VMInstruction[][dstring] instructions;
    dstring[] labelOrder;

    pragma(inline, true)
    void emit(VMInstruction instr)
    {
        instructions[label] ~= instr;
    }

    pragma(inline, true)
    dstring newLabel()
    {
        dstring name = formatD("_label%d", tmp++);
        instructions[name] = (VMInstruction[]).init;
        return name;
    }

    pragma(inline, true)
    void enterLabel(dstring name)
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
                dstring name = var.name;
                fnVars[name] = fnVars.length;

                compile(var.value);
                return emit(VMInstruction.instr(VMOpCode.Store, fnVars[name]));

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
                    TokenKind.Star:     VMOpCode.Mul,
                    TokenKind.Plus:     VMOpCode.Add,
                    TokenKind.Slash:    VMOpCode.Div,
                    TokenKind.Minus:    VMOpCode.Sub,
                    TokenKind.Modulo:   VMOpCode.Mod,

                    TokenKind.LEquals:  VMOpCode.Le,
                    TokenKind.LThan:    VMOpCode.Lt,
                    TokenKind.GEquals:  VMOpCode.Ge,
                    TokenKind.GThan:    VMOpCode.Gt,
                    TokenKind.EEquals:  VMOpCode.Eq,
                    TokenKind.NEquals:  VMOpCode.Neq,

                    TokenKind.BITAnd:   VMOpCode.BAnd,
                    TokenKind.BITOr:    VMOpCode.BOr,
                    TokenKind.BITXor:   VMOpCode.BXor,
                    TokenKind.BITSL:    VMOpCode.Shl,
                    TokenKind.BITSR:    VMOpCode.Shr,
                ];


                return emit(VMInstruction.instr(operators[bexpr.op]));

            case NodeKind.UnaryExpr:
                UnaryExpr un = cast(UnaryExpr) node;

                compile(un.value);

                VMOpCode[TokenKind] operators = [
                    TokenKind.Minus: VMOpCode.Neg,
                    TokenKind.Bang:  VMOpCode.Not,
                    TokenKind.BITNot: VMOpCode.BNot,
                ];

                return emit(VMInstruction.instr(operators[un.op]));

            case NodeKind.Identifier:
                Identifier id = cast(Identifier) node;

                if (size_t* param = id.value in fnArgs)
                    return emit(VMInstruction.instr(VMOpCode.LoadParam, *param));
                
                return emit(VMInstruction.instr(VMOpCode.Load, fnVars[id.value]));

            case NodeKind.CallExpr:
                CallExpr call = cast(CallExpr) node;
                dstring name = (cast(Identifier) call.fn).value;

                //      x  y
                // call(1, 2)

                // emite de forma inversa pra manter a ordem
                // 2
                // 1

                foreach_reverse (Node child; call.args)
                    compile(child);

                emit(VMInstruction.instr(VMOpCode.Push, CGDValue.inteiro(cast(long) call.args.length)));
                return emit(VMInstruction.instr(VMOpCode.Call, name));

            case NodeKind.IfStmt:
                IfStmt ifstmt = cast(IfStmt) node;
                compile(ifstmt.expr);

                dstring l1 = newLabel();
                dstring l2 = newLabel();

                emit(VMInstruction.instr(VMOpCode.Jz, CGDValue.texto(l2)));

                enterLabel(l1);
                foreach (Node child; ifstmt.body)
                    compile(child);

                enterLabel(l2);

                // TODO: else
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
                foreach (Node child; wstmt.body)
                    compile(child);

                // volta pro inicio
                emit(VMInstruction.instr(VMOpCode.Jmp, CGDValue.texto(l0)));

                enterLabel(l2);
                return;

            case NodeKind.AssignStmt:
                AssignStmt ass = cast(AssignStmt) node;
                
                dstring name = (cast(Identifier) ass.left).value;
                compile(ass.value);

                return emit(VMInstruction.instr(VMOpCode.Store, fnVars[name]));

            default:
                writeln("Node não suportado para CTFE.");
                node.print();
                return;
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

        // TODO: dar erro
        return CGDValue.inteiro(-1);
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
        
        // TODO: dar erro
        return new IntLit(-1, Position.init);
    }

    void compileBody(Node[] body)
    {
        foreach (Node child; body)
            compile(child);
    }

    VMInstruction[] compile(FnDecl fn)
    {
        tmp = 0;
        instructions = null;
        fnArgs = null;
        fnVars = null;
        labelOrder = null;
        label = null;

        foreach (size_t i, FnArg arg; fn.args) 
            fnArgs[arg.name] = i;

        enterLabel(newLabel());
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

        // writeln("fun: ", fn.fn);

        foreach (size_t i, ref VMInstruction instr; instrs)
        {
            if (
                instr.opCode == VMOpCode.Jnz 
                || instr.opCode == VMOpCode.Jz 
                || instr.opCode == VMOpCode.Jmp
            )
            {
                // resolve o nome
                long addr = labels[instr.value.s];
                instr.param = addr;
            }
            // writeln(i, " ", instr);
        }
        instrs ~= VMInstruction.instr(VMOpCode.Halt);

        return instrs;
    }
}
