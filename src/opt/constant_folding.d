module opt.constant_folding;

import frontend;
import middle.rewrite;
import ctfe;
import utils;
import std.algorithm : all;
import std.array : array;
import std.algorithm.iteration : map;
import std.math : isFinite;

/// Dobra somente valores demonstravelmente literais. Não consulta símbolos por nome.
final class CgdConstantFolding : AstRewriter
{
    private CTFEContext ctfe;
    private Program program;
    size_t changes;

    this(Program program, Context context, CTFEContext ctfe)
    {
        this.program = program;
        this.ctfe = ctfe;
    }

    private Node literal(Node node)
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
                return new StringLit(s1 ~ s2, l.pos);
            if (op == "==" || op == "!=")
                return new BoolLit(op == "==" ? s1 == s2 : s1 != s2, expr.pos);
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

    override protected Node transform(Node node)
    {
        Node result;
        if (Identifier id = cast(Identifier) node)
        {
            VarDecl declaration = id.variableRef;
            // Tipos explícitos podem converter/verificar o valor: mantenha essa fronteira.
            if (declaration !is null && declaration.isConst && declaration.type_expr is null)
            {
                Node value = declaration.value;
                if (IntLit n = cast(IntLit) value)
                    result = new IntLit(n.value, node.pos);
                else if (DoubleLit n = cast(DoubleLit) value)
                    result = new DoubleLit(n.value, node.pos);
                else if (StringLit n = cast(StringLit) value)
                    result = new StringLit(n.value, node.pos);
                else if (BoolLit n = cast(BoolLit) value)
                    result = new BoolLit(n.value, node.pos);
                else if (cast(NullLit) value)
                    result = new NullLit(node.pos);
            }
        }
        else if (BinaryExpr binary = cast(BinaryExpr) node)
            result = foldBinary(binary);
        else if (UnaryExpr unary = cast(UnaryExpr) node)
        {
            if (BoolLit value = cast(BoolLit) unary.value)
                if (unary.op == TokenKind.Bang)
                    result = new BoolLit(!value.value, node.pos);
            if (IntLit value = cast(IntLit) unary.value)
            {
                if (unary.op == TokenKind.Minus && value.value != long.min)
                    result = new IntLit(-value.value, node.pos);
                if (unary.op == TokenKind.Plus)
                    result = new IntLit(value.value, node.pos);
            }
        }
        else if (ConditionalExpr conditional = cast(ConditionalExpr) node)
        {
            if (BoolLit condition = cast(BoolLit) conditional.condition)
                result = condition.value ? conditional.yes : conditional.no;
        }
        else if (CallExpr call = cast(CallExpr) node)
        {
            Identifier id = cast(Identifier) call.fn;
            // Identidade resolvida impede CTFE da função homônima de outro escopo.
            if (id !is null && id.functionRef !is null && ctfe !is null)
                if (SymbolFn* symbol = id.value in ctfe.symbols)
                    if ((*symbol).node is id.functionRef
                            && call.args.length == id.functionRef.args.length
                            && call.args.all!((Node arg) => literal(arg) !is null && arg.kind != NodeKind.NullLit))
                    {
                        try
                            result = ctfe.call(id.value,
                                    call.args.map!((Node arg) => CTFECompile.nodeToCgdValue(arg)).array);
                        catch (Exception)
                        {
                        } // Limites, contratos e falhas da avaliação preservam a chamada nativa.
                    }
        }
        if (BinaryExpr binary = cast(BinaryExpr) node)
        {
            if (BoolLit left = cast(BoolLit) binary.left)
            {
                if (binary.op == TokenKind.And && !left.value)
                    result = new BoolLit(false, node.pos);
                if (binary.op == TokenKind.Or && left.value)
                    result = new BoolLit(true, node.pos);
            }
            if (binary.op == TokenKind.Coalesce && literal(binary.left) !is null)
                result = binary.left.kind == NodeKind.NullLit ? binary.right : binary.left;
        }
        if (result is null)
            return node;
        if (DoubleLit number = cast(DoubleLit) result)
            if (!isFinite(number.value))
                return node;
        result.pos = node.pos;
        result.type_sema = node.type_sema;
        changes++;
        return result;
    }

    void opt()
    {
        rewrite(program);
    }
}
