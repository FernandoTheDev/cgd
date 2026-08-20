module ctfe.compile;

import std.format;
import std.stdio;

import frontend.lexer.token : Position, TokenKind;
import frontend.parser;
import ctfe;

final class CTFECompile
{
    size_t[dstring] fnArgs;
    size_t[dstring] fnVars;
    VMInstruction[] instructions;

    pragma(inline, true)
    void emit(VMInstruction instr)
    {
        instructions ~= instr;
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
                return emit(VMInstruction.instr(VMOpCode.PushInt, nodeToCgdValue(node)));

            case NodeKind.BinaryExpr:
                BinaryExpr bexpr = cast(BinaryExpr) node;

                compile(bexpr.left);
                compile(bexpr.right);

                VMOpCode[TokenKind] operators = [
                    TokenKind.Star: VMOpCode.Mul,
                    TokenKind.Plus: VMOpCode.Add,
                    TokenKind.Slash: VMOpCode.Div,
                    TokenKind.Minus: VMOpCode.Sub,
                ];

                return emit(VMInstruction.instr(operators[bexpr.op]));

            case NodeKind.Identifier:
                Identifier id = cast(Identifier) node;

                if (size_t* param = id.value in fnArgs)
                    return emit(VMInstruction.instr(VMOpCode.LoadParam, *param));
                
                return emit(VMInstruction.instr(VMOpCode.Load, fnVars[id.value]));

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

        // TODO: dar erro
        return CGDValue.inteiro(-1);
    }

    static Node cgdValueToNode(CGDValue value)
    {
        if (value.type == CGDTypeKind.Inteiro)
            return new IntLit(value.i, Position.init);

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
        instructions.length = 0;
        fnArgs = null;

        foreach (size_t i, FnArg arg; fn.args) 
            fnArgs[arg.name] = i;

        compileBody(fn.body);
        emit(VMInstruction.instr(VMOpCode.Halt));

        return instructions;
    }
}
