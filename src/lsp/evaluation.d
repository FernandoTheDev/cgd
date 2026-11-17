module lsp.evaluation;

import frontend;
import ctfe.context;
import ctfe.compile;
import std.math : isFinite;
import ctfe.evaluation;
import ctfe.prepare : prepareCTFE;
import frontend.semantic.constants;
import std.conv : to;
import std.json : JSONValue;

/// Avalia cópias de expressões primitivas. Nunca reescreve a AST do documento.
final class ConstantPreview
{
    private CTFEContext context;
    private Node[Node] cache;
    private bool[Node] active;
    private size_t remaining;
    private size_t instructions = 100_000;

    this(FnDecl[] functions)
    {
        context = new CTFEContext;
        prepareCTFE(context, functions);
    }

    Node evaluate(Node expression)
    {
        remaining = 512;
        return value(expression, 0);
    }

    private Node value(Node node, size_t depth)
    {
        if (node is null || depth > 64 || !remaining || node in active)
            return null;
        remaining--;
        if (Node* known = node in cache)
            return *known;
        active[node] = true;
        scope (exit)
            active.remove(node);
        Node result;
        if (cast(IntLit) node || cast(DoubleLit) node || cast(BoolLit) node || cast(StringLit) node || cast(NullLit) node)
            result = node;
        else if (MemberExpr member = cast(MemberExpr) node)
            result = member.enumValue;
        else if (Identifier id = cast(Identifier) node)
        {
            if (id.variableRef !is null && id.variableRef.isConst)
            {
                result = value(id.variableRef.value, depth + 1);
                if (result !is null && id.variableRef.type_expr !is null)
                    try
                        validateCTFEValue(CTFECompile.nodeToCgdValue(result), id.variableRef.type_expr.toStr());
                    catch (Exception)
                        result = null;
            }
        }
        else if (BinaryExpr binary = cast(BinaryExpr) node)
        {
            Node left = value(binary.left, depth + 1);
            if (left !is null)
            {
                bool truth = !cast(NullLit) left && !(cast(BoolLit) left && !(cast(BoolLit) left).value);
                if (binary.op == TokenKind.And || binary.op == TokenKind.Or || binary.op == TokenKind.Coalesce)
                {
                    bool useRight = binary.op == TokenKind.And ? truth : binary.op == TokenKind.Or
                        ? !truth : cast(NullLit) left !is null;
                    result = useRight ? value(binary.right, depth + 1) : left;
                }
                else if (Node right = value(binary.right, depth + 1))
                    result = foldBinary(new BinaryExpr(left, right, binary.op, binary.pos));
            }
        }
        else if (ConditionalExpr conditional = cast(ConditionalExpr) node)
        {
            if (Node condition = value(conditional.condition, depth + 1))
            {
                bool truth = !cast(NullLit) condition && !(cast(BoolLit) condition && !(cast(BoolLit) condition).value);
                result = value(truth ? conditional.yes : conditional.no, depth + 1);
            }
        }
        else if (UnaryExpr unary = cast(UnaryExpr) node)
        {
            Node operand = value(unary.value, depth + 1);
            if (IntLit number = cast(IntLit) operand)
            {
                if (unary.op == TokenKind.Minus && number.value != long.min)
                    result = new IntLit(-number.value, unary.pos);
                if (unary.op == TokenKind.Plus)
                    result = operand;
            }
            if (BoolLit boolean = cast(BoolLit) operand)
                if (unary.op == TokenKind.Bang)
                    result = new BoolLit(!boolean.value, unary.pos);
        }
        else if (CallExpr call = cast(CallExpr) node)
        {
            Node[] arguments;
            foreach (Node argument; call.args)
            {
                Node literal = value(argument, depth + 1);
                if (literal is null)
                    return null;
                arguments ~= literal;
            }
            if (instructions)
            {
                CallExpr copy = new CallExpr(call.fn, arguments, call.pos);
                context.remainingInstructions = instructions;
                result = evaluatePureCall(copy, context, instructions);
                instructions = context.remainingInstructions;
            }
        }
        if (DoubleLit number = cast(DoubleLit) result)
            if (!isFinite(number.value))
                result = null;
        cache[node] = result;
        return result;
    }
}

string previewText(Node value)
{
    if (cast(NullLit) value)
        return "nulo";
    if (IntLit integer = cast(IntLit) value)
        return integer.value.to!string;
    if (DoubleLit number = cast(DoubleLit) value)
        return number.value.to!string;
    if (BoolLit boolean = cast(BoolLit) value)
        return boolean.value ? "verdadeiro" : "falso";
    if (StringLit text = cast(StringLit) value)
    {
        if (text.value.length > 256)
            return JSONValue(text.value[0 .. 256].to!string).toString() ~ " …";
        return JSONValue(text.value.to!string).toString();
    }
    return "";
}
