module frontend.semantic.constants;

import frontend.parser;
import frontend.lexer;
import utils : as;

/// Operações primitivas comprovadas. Não lê estado, não chama funções nem altera a AST.
Node literal(Node node)
{
    if (node is null)
        return null;
    switch (node.kind)
    {
        case NodeKind.IntLit:
        case NodeKind.DoubleLit:
        case NodeKind.BoolLit:
        case NodeKind.StringLit:
        case NodeKind.NullLit:
            return node;
        default:
            return null;
    }
}

Node foldBinary(BinaryExpr expr)
{
    Node l = literal(expr.left);
    Node r = literal(expr.right);

    if (l is null || r is null)
        return null;

    // promoção: int op double → double
    if (l.kind == NodeKind.IntLit && r.kind == NodeKind.DoubleLit)
        l = new DoubleLit(cast(double)(as!IntLit(l)).value, l.pos);
    else if (l.kind == NodeKind.DoubleLit && r.kind == NodeKind.IntLit)
        r = new DoubleLit(cast(double)(as!IntLit(r)).value, r.pos);

    if (l.kind != r.kind)
        return null;

    Node fold(T)(string op)
    {
        static if (is(T == IntLit))
        {
            import std.bigint : BigInt;
            import std.conv : to;

            BigInt a = BigInt((as!IntLit(l)).value), b = BigInt((as!IntLit(r)).value);
            BigInt value;
            switch (op)
            {
                case "+":
                    value = a + b;
                    break;
                case "-":
                    value = a - b;
                    break;
                case "*":
                    value = a * b;
                    break;
                case "/":
                    if (b == 0 || (a == BigInt(long.min) && b == -1))
                        return null;
                    if (a % b != 0)
                        return new DoubleLit(cast(double)(as!IntLit(l)).value / (as!IntLit(r)).value, expr.pos);
                    value = a / b;
                    break;
                case "%":
                    if (b == 0)
                        return null;
                    value = a % b;
                    break;
                case "!=":
                    return new BoolLit(a != b, expr.pos);
                case "<":
                    return new BoolLit(a < b, expr.pos);
                case ">":
                    return new BoolLit(a > b, expr.pos);
                case "<=":
                    return new BoolLit(a <= b, expr.pos);
                case ">=":
                    return new BoolLit(a >= b, expr.pos);
                case "==":
                    return new BoolLit(a == b, expr.pos);
                default:
                    return null;
            }
            if (value < BigInt(long.min) || value > BigInt(long.max))
                return null;
            return new IntLit(value.toLong(), expr.pos);
        }
        else
        {
            double a = (as!DoubleLit(l)).value, b = (as!DoubleLit(r)).value;
            switch (op)
            {
                case "+":
                    return new DoubleLit(a + b, expr.pos);
                case "-":
                    return new DoubleLit(a - b, expr.pos);
                case "*":
                    return new DoubleLit(a * b, expr.pos);
                case "/":
                    return b == 0 ? null : new DoubleLit(a / b, expr.pos);
                case "!=":
                    return new BoolLit(a != b, expr.pos);
                case "<":
                    return new BoolLit(a < b, expr.pos);
                case ">":
                    return new BoolLit(a > b, expr.pos);
                case "<=":
                    return new BoolLit(a <= b, expr.pos);
                case ">=":
                    return new BoolLit(a >= b, expr.pos);
                case "==":
                    return new BoolLit(a == b, expr.pos);
                default:
                    return null;
            }
        }
    }

    string op;
    switch (expr.op) with (TokenKind)
    {
        case Plus:
            op = "+";
            break;
        case Minus:
            op = "-";
            break;
        case Star:
            op = "*";
            break;
        case Slash:
            op = "/";
            break;
        case LThan:
            op = "<";
            break;
        case GThan:
            op = ">";
            break;
        case LEquals:
            op = "<=";
            break;
        case GEquals:
            op = ">=";
            break;
        case Modulo:
            op = "%";
            break;
        case NEquals:
            op = "!=";
            break;
        case EEquals:
            op = "==";
            break;
        default:
            return null;
    }

    if (l.kind == NodeKind.StringLit && r.kind == NodeKind.StringLit)
    {
        dstring s1 = (cast(StringLit) l).value;
        dstring s2 = (cast(StringLit) r).value;
        if (op == "+")
        {
            if (s1.length > 1_048_576 || s2.length > 1_048_576 - s1.length)
                return null;
            return new StringLit(s1 ~ s2, l.pos);
        }
        if (op == "==" || op == "!=")
            return new BoolLit(op == "==" ? s1 == s2 : s1 != s2, expr.pos);
        if (op == "<")
            return new BoolLit(s1 < s2, expr.pos);
        if (op == "<=")
            return new BoolLit(s1 <= s2, expr.pos);
        if (op == ">")
            return new BoolLit(s1 > s2, expr.pos);
        if (op == ">=")
            return new BoolLit(s1 >= s2, expr.pos);
    }

    if ((op == "==" || op == "!=") && (l.kind == NodeKind.BoolLit || l.kind == NodeKind.NullLit))
    {
        bool same = l.kind == NodeKind.NullLit || (cast(BoolLit) l).value == (cast(BoolLit) r).value;
        return new BoolLit(op == "==" ? same : !same, expr.pos);
    }
    if (l.kind == NodeKind.IntLit)
        return fold!IntLit(op);

    if (l.kind == NodeKind.DoubleLit)
        return fold!DoubleLit(op);

    return null;
}
