module frontend.static_safety;

import frontend;
import opt.constant_folding;
import std.bigint : BigInt;
import std.conv : to;
import std.math : isFinite;
import std.string : toStringz;
import std.algorithm : any;

/// Provas locais, sem interpretar funções nem inferir conteúdos de objetos mutáveis.
/// Falhas em código protegido por pegue são avisos: podem ser intencionais.
class StaticSafety
{
    private Diagnostics diagnostics;
    private bool[Node] seen;
    private Node[Node] constants;
    private bool[Node] evaluating;
    private size_t protectedDepth;
    private FnDecl functionNode;

    this(Diagnostics diagnostics)
    {
        this.diagnostics = diagnostics;
    }

    private void issue(Args...)(Node node, MessageSpec message, Args args)
    {
        if (protectedDepth)
            diagnostics.warning(node.pos, "Falha estática em região tratável: " ~ formatMessage(message,
                    args), "W" ~ message.code[1 .. $]);
        else
            diagnostics.errorCode(node.pos, message, args);
    }

    private string formatMessage(Args...)(MessageSpec message, Args args)
    {
        import std.format : format;

        return format(message.message, args);
    }

    private Node constant(Node node)
    {
        if (node is null)
            return null;
        if (Node* cached = node in constants)
            return *cached;
        if (node in evaluating || evaluating.length >= 128)
            return null;
        evaluating[node] = true;
        scope (exit)
            evaluating.remove(node);
        Node value;
        switch (node.kind)
        {
            case NodeKind.IntLit:
            case NodeKind.DoubleLit:
            case NodeKind.BoolLit:
            case NodeKind.StringLit:
            case NodeKind.NullLit:
                value = node;
                break;
            case NodeKind.Identifier:
                VarDecl declaration = (cast(Identifier) node).variableRef;
                if (declaration !is null && declaration.isConst)
                    value = constant(declaration.value);
                break;
            case NodeKind.BinaryExpr:
                BinaryExpr binary = cast(BinaryExpr) node;
                Node left = constant(binary.left), right = constant(binary.right);
                if (left !is null && (binary.op == TokenKind.And || binary.op == TokenKind.Or
                        || binary.op == TokenKind.Coalesce))
                {
                    bool truth = left.kind != NodeKind.NullLit && !(cast(BoolLit) left && !(cast(BoolLit) left).value);
                    value = binary.op == TokenKind.And ? (truth ? right
                            : left) : binary.op == TokenKind.Or ? (truth ? left
                            : right) : left.kind == NodeKind.NullLit ? right : left;
                    break;
                }
                if (left !is null && right !is null)
                {
                    BinaryExpr clone = new BinaryExpr(left, right, binary.op, node.pos);
                    value = new CgdConstantFolding(null, null, null).foldBinary(clone);
                }
                break;
            case NodeKind.ConditionalExpr:
                ConditionalExpr condition = cast(ConditionalExpr) node;
                bool truth;
                if (knownTruth(condition.condition, truth))
                    value = constant(truth ? condition.yes : condition.no);
                break;
            case NodeKind.UnaryExpr:
                UnaryExpr unary = cast(UnaryExpr) node;
                Node operand = constant(unary.value);
                if (unary.op == TokenKind.Bang && operand !is null)
                {
                    bool truth = operand.kind != NodeKind.NullLit && !(cast(BoolLit) operand
                            && !(cast(BoolLit) operand).value);
                    value = new BoolLit(!truth, node.pos);
                }
                if (IntLit integer = cast(IntLit) operand)
                {
                    if (unary.op == TokenKind.Minus && integer.value != long.min)
                        value = new IntLit(-integer.value, node.pos);
                    else if (unary.op == TokenKind.Plus)
                        value = integer;
                }
                break;
            default:
                break;
        }
        constants[node] = value;
        return value;
    }

    private bool knownTruth(Node node, out bool truth)
    {
        Node value = constant(node);
        if (value is null)
            return false;
        truth = value.kind != NodeKind.NullLit && !(cast(BoolLit) value && !(cast(BoolLit) value).value);
        return true;
    }

    private string valueType(Node node)
    {
        if (cast(IntLit) node)
            return "inteiro";
        if (cast(DoubleLit) node)
            return "real";
        if (cast(StringLit) node)
            return "texto";
        if (cast(BoolLit) node)
            return "logico";
        return "nulo";
    }

    private void contract(Node value, TypeExpr type, Node origin)
    {
        if (value is null || type is null)
            return;
        if (TypeExprArray arrayType = cast(TypeExprArray) type)
        {
            if (TupleLit tuple = cast(TupleLit) value)
                issue(origin, typeContract, "vetor", "tupla");
            else if (ArrayLit literal = cast(ArrayLit) value)
                foreach (Node element; literal.elements)
                    contract(element, arrayType.base, origin);
            else if (Node literal = constant(value))
                        issue(origin, typeContract, "vetor", valueType(literal));
            return;
        }
        if (TypeExprTuple tupleType = cast(TypeExprTuple) type)
        {
            if (TupleLit literal = cast(TupleLit) value)
            {
                if (literal.elements.any!((Node e) => cast(SpreadExpr) e !is null))
                    return;
                if (literal.elements.length != tupleType.types.length)
                    issue(origin, typeContract, "tupla com aridade declarada", "tupla de outra aridade");
                else
                    foreach (size_t i, Node element; literal.elements)
                        contract(element, tupleType.types[i], origin);
            }
            else if (cast(ArrayLit) value || constant(value) !is null)
                issue(origin, typeContract, "tupla", "valor de outro tipo");
            return;
        }
        TypeExprNamed named = cast(TypeExprNamed) type;
        Node known = constant(value);
        if (named is null || known is null)
            return;
        bool valid = true;
        switch (named.name)
        {
            case "inteiro":
            case "longo":
                valid = known.kind == NodeKind.IntLit;
                break;
            case "numero":
            case "número":
            case "real":
            case "decimal":
                valid = known.kind == NodeKind.IntLit || known.kind == NodeKind.DoubleLit;
                break;
            case "texto":
                valid = known.kind == NodeKind.StringLit;
                break;
            case "logico":
            case "lógico":
            case "booleano":
            case "binario":
            case "binário":
                valid = known.kind == NodeKind.BoolLit;
                break;
            case "vazio":
                valid = known.kind == NodeKind.NullLit;
                break;
            case "funcao":
            case "função":
                valid = false;
                break;
            default:
                if (named.classLinkName.length)
                    valid = false;
                break;
        }
        if (!valid)
            issue(origin, typeContract, named.name.to!string, valueType(known));
    }

    private void checkBinary(BinaryExpr binary)
    {
        Node left = constant(binary.left), right = constant(binary.right);
        TokenKind op = binary.op;
        if (right !is null && (op == TokenKind.Slash || op == TokenKind.Modulo || op == TokenKind.IntDiv))
        {
            if ((cast(IntLit) right && (cast(IntLit) right).value == 0) || (cast(DoubleLit) right
                    && (cast(DoubleLit) right).value == 0))
                issue(binary, zeroDivision);
        }
        if (IntLit shift = cast(IntLit) right)
            if ((op == TokenKind.BITSL || op == TokenKind.BITSR) && (shift.value < 0 || shift.value >= 64))
                issue(binary, invalidShift);
        if (op == TokenKind.Modulo && (cast(DoubleLit) left || cast(DoubleLit) right))
            issue(binary, invalidOperation, "módulo exige inteiros");
        if (op == TokenKind.BITSL && ((left !is null && !cast(IntLit) left) || (right !is null && !cast(IntLit) right)))
            issue(binary, invalidOperation, "deslocamento esquerdo exige inteiros");
        IntLit a = cast(IntLit) left, b = cast(IntLit) right;
        if (a is null || b is null)
            return;
        BigInt result;
        BigInt x = BigInt(a.value), y = BigInt(b.value);
        bool checked = true;
        switch (op)
        {
            case TokenKind.Plus:
                result = x + y;
                break;
            case TokenKind.Minus:
                result = x - y;
                break;
            case TokenKind.Star:
                result = x * y;
                break;
            case TokenKind.Slash:
            case TokenKind.IntDiv:
                if (a.value == long.min
                        && b.value == -1)
                    issue(binary, integerOverflow);
                checked = false;
                break;
            case TokenKind.Pow:
                if (b.value >= 0 && b.value <= 64)
                {
                    result = 1;
                    foreach (long _; 0 .. b.value)
                        result *= x;
                }
                else
                {
                    if (b.value > 64 && (a.value > 1 || a.value < -1))
                        issue(binary, integerOverflow);
                    checked = false;
                }
                break;
            default:
                checked = false;
                break;
        }
        if (checked && (result < BigInt(long.min) || result > BigInt(long.max)))
            issue(binary, integerOverflow);
    }

    private void checkCall(CallExpr call)
    {
        Identifier identifier = cast(Identifier) call.fn;
        if (identifier is null || identifier.functionRef is null)
            return;
        FnDecl fn = identifier.functionRef;
        if (!call.args.any!((Node arg) => cast(SpreadExpr) arg !is null))
        {
            foreach (size_t i, Node arg; call.args)
                if (i < fn.args.length)
                    contract(arg, fn.args[i].type_expr, call);
                else if (fn.args.length && fn.args[$ - 1].rest)
                    contract(arg, fn.args[$ - 1].type_expr, call);
        }
        dstring builtin = fn.builtinName;
        if (call.args.length == 1 && (builtin == "inteiro" || builtin == "real"
                || builtin == "numero" || builtin == "número"))
            if (StringLit text = cast(StringLit) constant(call.args[0]))
            {
                import core.stdc.stdlib : strtoll, strtod;
                import core.stdc.errno : errno;

                string source = text.value.to!string;
                immutable(char)* start = source.toStringz;
                immutable(char)* end;
                errno = 0;
                bool valid;
                if (builtin == "inteiro")
                {
                    strtoll(start, &end, 10);
                    valid = errno == 0;
                }
                else
                {
                    double result = strtod(start, &end);
                    valid = errno == 0 && isFinite(result);
                }
                if (!valid || end == start || end != start + source.length)
                    issue(call, invalidConversion, builtin.to!string);
            }
    }

    void analyze(Node node)
    {
        if (node is null || node in seen)
            return;
        seen[node] = true;
        if (FnDecl fn = cast(FnDecl) node)
        {
            FnDecl previous = functionNode;
            size_t saved = protectedDepth;
            functionNode = fn;
            protectedDepth = 0;
            scope (exit)
            {
                functionNode = previous;
                protectedDepth = saved;
            }
            foreach (FnArg arg; fn.args)
            {
                analyze(arg.value);
                contract(arg.value, arg.type_expr, fn);
            }
            foreach (Node child; fn.body)
                analyze(child);
            return;
        }
        if (TryStmt attempt = cast(TryStmt) node)
        {
            if (attempt.catches.length)
                protectedDepth++;
            foreach (Node child; attempt.body)
                analyze(child);
            if (attempt.catches.length)
                protectedDepth--;
            foreach (CatchClause c; attempt.catches)
                foreach (Node child; c.body)
                    analyze(child);
            foreach (Node child; attempt.finalBody)
                analyze(child);
            return;
        }
        if (IfStmt branch = cast(IfStmt) node)
        {
            analyze(branch.expr);
            bool truth;
            bool known = branch.expr is null || knownTruth(branch.expr, truth);
            if (branch.expr is null || (known && truth))
            {
                foreach (Node child; branch.body)
                    analyze(child);
            }
            else if (known)
            {
                analyze(branch._else);
            }
            else
            {
                foreach (Node child; branch.body)
                    analyze(child);
                analyze(branch._else);
            }
            return;
        }
        if (ConditionalExpr conditional = cast(ConditionalExpr) node)
        {
            analyze(conditional.condition);
            bool truth;
            if (knownTruth(conditional.condition, truth))
                analyze(truth ? conditional.yes : conditional.no);
            else
            {
                analyze(conditional.yes);
                analyze(conditional.no);
            }
            return;
        }
        if (BinaryExpr binary = cast(BinaryExpr) node)
        {
            analyze(binary.left);
            bool truth;
            bool known = knownTruth(binary.left, truth);
            if ((binary.op == TokenKind.And && known && !truth) || (binary.op == TokenKind.Or
                    && known && truth) || (binary.op == TokenKind.Coalesce && known
                    && constant(binary.left).kind != NodeKind.NullLit))
                return;
            analyze(binary.right);
            checkBinary(binary);
            return;
        }
        if (ForStmt loop = cast(ForStmt) node)
        {
            analyze(loop.init);
            analyze(loop.condition);
            bool truth;
            if (loop.condition is null || !knownTruth(loop.condition, truth) || truth)
            {
                foreach (Node child; loop.body)
                    analyze(child);
                analyze(loop.step);
            }
            return;
        }
        if (EachStmt loop = cast(EachStmt) node)
        {
            analyze(loop.iterable);
            if (ArrayLit values = cast(ArrayLit) loop.iterable)
                foreach (Node value; values.elements)
                    contract(value, loop.bindingType, loop);
            if (MapLit values = cast(MapLit) loop.iterable)
                foreach (size_t i, TypeExpr type; loop.destructuredTypes)
                    foreach (Node value; i == 0 ? values.keys : values.values)
                        contract(value, type, loop);
            ArrayLit literal = cast(ArrayLit) loop.iterable;
            if (literal is null || literal.elements.length)
                foreach (Node child; loop.body)
                    analyze(child);
            return;
        }
        if (WhileStmt loop = cast(WhileStmt) node)
        {
            analyze(loop.expr);
            bool truth;
            if (!knownTruth(loop.expr, truth) || truth)
                foreach (Node child; loop.body)
                    analyze(child);
            return;
        }
        foreach (Node child; childNodes(node))
            analyze(child);
        if (VarDecl variable = cast(VarDecl) node)
        {
            if (!variable.uninitialized)
                contract(variable.value, variable.type_expr, node);
        }
        if (Comprehension comprehension = cast(Comprehension) node)
            if (ArrayLit values = cast(ArrayLit) comprehension.iterable)
                foreach (Node value; values.elements)
                    contract(value, comprehension.bindingType, comprehension);
        if (AssignStmt assignment = cast(AssignStmt) node)
            if (assignment.op == TokenKind.Equals)
                contract(assignment.value, assignment.left.type_expr, node);
        if (ReturnStmt ret = cast(ReturnStmt) node)
            if (functionNode !is null && !ret.collectionReturn)
                contract(ret.val, functionNode.type_expr, node);
        if (CallExpr call = cast(CallExpr) node)
            checkCall(call);
        if (UnaryExpr unary = cast(UnaryExpr) node)
            if (unary.op == TokenKind.BITNot)
                if (Node value = constant(unary.value))
                    if (!cast(IntLit) value)
                        issue(node, invalidOperation, "negação bit a bit exige inteiro");
        if (SliceExpr slice = cast(SliceExpr) node)
            if (IntLit step = cast(IntLit) constant(slice.step))
                if (step.value == 0)
                    issue(node, invalidSlice);
        if (IndexExpr index = cast(IndexExpr) node)
        {
            IntLit idx = cast(IntLit) constant(index.idx);
            long length = -1;
            if (ArrayLit literal = cast(ArrayLit) index.value)
                if (!literal.elements.any!((Node e) => cast(SpreadExpr) e !is null))
                    length = literal.elements.length;
            if (StringLit text = cast(StringLit) constant(index.value))
                length = text.value.length;
            if (length >= 0 && constant(index.idx) !is null && idx is null)
                issue(node, invalidIndex, "esperado inteiro");
            if (idx !is null && length >= 0 && (idx.value >= length || idx.value < -length))
                issue(node, invalidIndex, "fora dos limites do literal");
        }
    }
}
