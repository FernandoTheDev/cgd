module opt.constant_folding;

import frontend;
import frontend.semantic.constants;
import middle.rewrite;
import ctfe;
import ctfe.evaluation;
import std.math : isFinite;

/// Dobra somente valores demonstravelmente literais. Não consulta símbolos por nome.
final class CgdConstantFolding : AstRewriter
{
    private CTFEContext ctfe;
    private Program program;
    size_t changes;

    this(Program program, CTFEContext ctfe)
    {
        this.program = program;
        this.ctfe = ctfe;
    }

    private bool typedConstantMatches(VarDecl declaration)
    {
        if (declaration.type_expr is null)
            return true;
        dstring name = declaration.type_expr.toStr();
        Node value = declaration.value;
        if (cast(IntLit) value)
            return name == "inteiro" || name == "numero" || name == "número" || name == "longo" || name == "qualquer";
        if (cast(DoubleLit) value)
            return name == "real" || name == "decimal" || name == "qualquer";
        if (cast(StringLit) value)
            return name == "texto" || name == "qualquer";
        if (cast(BoolLit) value)
            return name == "logico" || name == "lógico" || name == "booleano" || name == "binario"
                || name == "binário" || name == "qualquer";
        if (cast(NullLit) value)
            return name == "nulo" || name == "qualquer";
        return false;
    }

    override protected Node transform(Node node)
    {
        Node result;
        if (Identifier id = cast(Identifier) node)
        {
            VarDecl declaration = id.variableRef;
            // Propaga somente literais que já satisfazem o tipo declarado sem conversão.
            if (declaration !is null && declaration.isConst && typedConstantMatches(declaration))
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
        else if (MemberExpr member = cast(MemberExpr) node)
        {
            if (member.enumValue !is null)
                result = new IntLit(member.enumValue.value, node.pos);
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
                if (unary.op == TokenKind.BITNot)
                    result = new IntLit(~value.value, node.pos);
            }
            if (DoubleLit value = cast(DoubleLit) unary.value)
            {
                if (unary.op == TokenKind.Minus)
                    result = new DoubleLit(-value.value, node.pos);
                if (unary.op == TokenKind.Plus)
                    result = new DoubleLit(value.value, node.pos);
            }
        }
        else if (ConditionalExpr conditional = cast(ConditionalExpr) node)
        {
            if (BoolLit condition = cast(BoolLit) conditional.condition)
                result = condition.value ? conditional.yes : conditional.no;
        }
        else if (CallExpr call = cast(CallExpr) node)
            result = evaluatePureCall(call, ctfe);
        if (BinaryExpr binary = cast(BinaryExpr) node)
        {
            if (BoolLit left = cast(BoolLit) binary.left)
            {
                if (binary.op == TokenKind.And)
                    result = left.value ? binary.right : new BoolLit(false, node.pos);
                if (binary.op == TokenKind.Or)
                    result = left.value ? new BoolLit(true, node.pos) : binary.right;
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
