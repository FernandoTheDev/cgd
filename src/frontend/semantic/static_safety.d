module frontend.semantic.static_safety;

import frontend;
import frontend.semantic.constants;
import frontend.semantic.members;
import frontend.semantic.native_methods;
import std.bigint : BigInt;
import std.conv : to;
import std.math : isFinite;
import std.string : toStringz;
import std.algorithm : any, canFind, levenshteinDistance;

/// Provas locais, sem interpretar funções nem inferir conteúdos de objetos mutáveis.
/// Falhas em código protegido por pegue são avisos: podem ser intencionais.
class StaticSafety
{
    private Diagnostics diagnostics;
    private bool[Node] seen;
    private Node[Node] constants;
    private bool[Node] evaluating;
    private bool[VarDecl] mutatedVars;
    private ClassDecl[][ClassDecl] subclasses;
    private bool programInfoCollected;
    private size_t protectedDepth;
    private FnDecl functionNode;

    this(Diagnostics diagnostics)
    {
        this.diagnostics = diagnostics;
    }

    private void collectProgramInfo(Node root)
    {
        bool[Node] visited;
        void scan(Node node)
        {
            if (node is null || node in visited)
                return;
            visited[node] = true;
            if (ClassDecl cls = cast(ClassDecl) node)
            {
                if (cls.superClass !is null)
                    subclasses[cls.superClass] ~= cls;
                foreach (ClassDecl iface; cls.interfaces)
                    subclasses[iface] ~= cls;
                foreach (ClassDecl mx; cls.mixins)
                    subclasses[mx] ~= cls;
            }
            if (AssignStmt assign = cast(AssignStmt) node)
            {
                if (Identifier id = cast(Identifier) assign.left)
                    if (id.variableRef !is null)
                        mutatedVars[id.variableRef] = true;
            }
            if (UnaryExpr unary = cast(UnaryExpr) node)
            {
                if (unary.op == TokenKind.PPlus || unary.op == TokenKind.MMinus)
                    if (Identifier id = cast(Identifier) unary.value)
                        if (id.variableRef !is null)
                            mutatedVars[id.variableRef] = true;
            }
            foreach (Node child; childNodes(node))
                scan(child);
        }

        scan(root);
        programInfoCollected = true;
    }

    private bool isExactInstance(Node node, ClassDecl decl, size_t depth = 0)
    {
        if (node is null || decl is null || depth > 16)
            return false;
        if (CallExpr call = cast(CallExpr) node)
        {
            if (Identifier fnId = cast(Identifier) call.fn)
            {
                if (fnId.classRef is decl)
                    return true;
                if (fnId.variableRef !is null && fnId.variableRef.isConst)
                    if (MemberExpr initMember = cast(MemberExpr) fnId.variableRef.value)
                        if (Identifier initRight = cast(Identifier) initMember.right)
                            if (initRight.classRef is decl)
                                return true;
            }
            if (MemberExpr m = cast(MemberExpr) call.fn)
                if (Identifier r = cast(Identifier) m.right)
                    if (r.classRef is decl)
                        return true;
        }
        if (Identifier id = cast(Identifier) node)
            if (id.variableRef !is null && (id.variableRef.isConst
                    || (!id.variableRef.uninitialized && (id.variableRef !in mutatedVars))))
                return isExactInstance(id.variableRef.value, decl, depth + 1);
        return false;
    }

    private string closestName(string target, string[] candidates)
    {
        string best;
        size_t bestDist = 3;
        foreach (string cand; candidates)
        {
            if (cand == target || cand.length == 0 || cand[0] == '#')
                continue;
            size_t dist = levenshteinDistance(target, cand);
            if (dist < bestDist)
            {
                bestDist = dist;
                best = cand;
            }
        }
        return best;
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
                if (declaration !is null && (declaration.isConst || (!declaration.uninitialized
                        && (declaration !in mutatedVars))))
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
                    value = foldBinary(clone);
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

    private void checkMember(MemberExpr member)
    {
        Identifier right = cast(Identifier) member.right;
        if (right is null || right.value == "#incompleto")
            return;
        string memberName = right.value.to!string;
        static immutable string[] commonMethods = [
            "tipo", "paraTexto", "eInstanciaDe", "éInstânciaDe", "respondeA"
        ];
        if (Node knownLeft = constant(member.left))
            if (knownLeft.kind == NodeKind.NullLit && !commonMethods.canFind(memberName))
            {
                issue(member, nullOperation, "acesso a '" ~ memberName ~ "'");
                return;
            }
        // Módulo importado
        ModuleUnit importedModule;
        if (ImportExpr directImport = cast(ImportExpr) member.left)
            importedModule = directImport.target;
        else if (Identifier leftId = cast(Identifier) member.left)
            if (leftId.variableRef !is null)
                if (ImportExpr varImport = cast(ImportExpr) leftId.variableRef.value)
                    importedModule = varImport.target;
        if (importedModule !is null && importedModule.program !is null)
        {
            string[] exports;
            foreach (Node exported; importedModule.program.body)
            {
                if (ClassDecl cls = cast(ClassDecl) exported)
                {
                    if (cls.name == right.value)
                        return;
                    exports ~= cls.name.to!string;
                }
                else if (FnDecl fn = cast(FnDecl) exported)
                {
                    if (fn.fn == right.value)
                        return;
                    exports ~= fn.fn.to!string;
                }
                else if (VarDecl varDecl = cast(VarDecl) exported)
                {
                    if (varDecl.name == right.value)
                        return;
                    exports ~= varDecl.name.to!string;
                }
            }
            if (commonMethods.canFind(memberName))
                return;
            issue(right, unknownMember, memberName, "módulo");
            string hint = closestName(memberName, exports);
            if (hint.length)
                diagnostics.hintCode(right.pos, suggestion, hint);
            return;
        }
        // Classe gerenciada conhecida
        ClassDecl decl;
        bool isClassReceiver = false;
        if (TypeSemaClass clsType = cast(TypeSemaClass) member.left.type_sema)
            decl = clsType.declaration;
        if (Identifier recv = cast(Identifier) member.left)
        {
            if (recv.classRef !is null)
            {
                decl = recv.classRef;
                isClassReceiver = true;
            }
            else if (recv.lexicalClass !is null)
                decl = recv.lexicalClass;
            else if (recv.variableRef !is null && recv.variableRef.isConst)
                if (MemberExpr initMember = cast(MemberExpr) recv.variableRef.value)
                    if (Identifier initRight = cast(Identifier) initMember.right)
                        if (initRight.classRef !is null)
                        {
                            decl = initRight.classRef;
                            isClassReceiver = true;
                        }
        }
        else if (MemberExpr leftMember = cast(MemberExpr) member.left)
            if (Identifier leftRight = cast(Identifier) leftMember.right)
                if (leftRight.classRef !is null)
                {
                    decl = leftRight.classRef;
                    isClassReceiver = true;
                }
        if (decl !is null && !decl.signature.builtinName.length)
        {
            ClassMember found = resolveClassMember(decl, right.value);
            if (found.owner !is null || commonMethods.canFind(memberName))
                return;
            bool allowPolymorphic = !isClassReceiver && !isExactInstance(member.left, decl);
            bool[ClassDecl] seenSub;
            bool foundInSubclass(ClassDecl cur)
            {
                ClassDecl[]* direct = cur in subclasses;
                if (direct is null)
                    return false;
                foreach (ClassDecl sub; *direct)
                {
                    if (sub is null || sub in seenSub)
                        continue;
                    seenSub[sub] = true;
                    if (resolveClassMember(sub, right.value).owner !is null)
                        return true;
                    if (foundInSubclass(sub))
                        return true;
                }
                return false;
            }

            if (allowPolymorphic && foundInSubclass(decl))
                return;
            string[] candidates = commonMethods.dup;
            bool[ClassDecl] visitedCls;
            void gather(ClassDecl cur)
            {
                if (cur is null || cur in visitedCls)
                    return;
                visitedCls[cur] = true;
                foreach (FnDecl m; cur.methods)
                    if (m.fn != "construtor" && m.fn != "destrutor")
                        candidates ~= m.fn.to!string;
                foreach (ClassField f; cur.fields)
                    candidates ~= f.name.to!string;
                foreach (ClassDecl mx; cur.mixins)
                    gather(mx);
                gather(cur.superClass);
            }

            gather(decl);
            if (allowPolymorphic)
                foreach (ClassDecl sub; seenSub.byKey())
                    gather(sub);
            issue(right, unknownMember, memberName, decl.name.to!string);
            string hint = closestName(memberName, candidates);
            if (hint.length)
                diagnostics.hintCode(right.pos, suggestion, hint);
            return;
        }
        // Tipo primitivo, vetor, tupla, Promessa ou Tarefa conhecido
        TypeSema recvType = member.left.type_sema;
        if (recvType is null || recvType.isAny() || cast(TypeSemaClass) recvType)
            return;
        if (TypeSemaBuiltin builtin = cast(TypeSemaBuiltin) recvType)
            if (builtin.base == TypeSemaBase.Map || builtin.base == TypeSemaBase.Any
                    || builtin.base == TypeSemaBase.Function || builtin.base == TypeSemaBase.Void)
                return;
        string[] allowed = builtinMethods(recvType);
        if (TypeSemaBuiltin builtin = cast(TypeSemaBuiltin) recvType)
            if (builtin.base == TypeSemaBase.Tuple)
                allowed ~= [
                "primeiro", "segundo", "terceiro", "quarto", "quinto", "sexto", "setimo",
                "sétimo", "oitavo", "nono", "decimo", "décimo"
        ];
        if (!allowed.canFind(memberName))
        {
            issue(right, unknownMember, memberName, recvType.toStr().to!string);
            string hint = closestName(memberName, allowed);
            if (hint.length)
                diagnostics.hintCode(right.pos, suggestion, hint);
        }
    }

    private TypeExpr arrayElementTypeExpr(Node arrayNode, Position pos)
    {
        if (arrayNode is null)
            return null;
        if (TypeExprArray arrExpr = cast(TypeExprArray) arrayNode.type_expr)
            return arrExpr.base;
        if (Identifier id = cast(Identifier) arrayNode)
        {
            if (id.variableRef !is null)
                if (TypeExprArray varArr = cast(TypeExprArray) id.variableRef.type_expr)
                    return varArr.base;
            if (id.parameterRef !is null)
                if (TypeExprArray paramArr = cast(TypeExprArray) id.parameterRef.type_expr)
                    return paramArr.base;
        }
        if (TypeSemaArray arrSema = cast(TypeSemaArray) arrayNode.type_sema)
            if (TypeSemaBuiltin elemBuiltin = cast(TypeSemaBuiltin) arrSema.base)
                if (elemBuiltin.base != TypeSemaBase.Any)
                    return new TypeExprNamed(elemBuiltin.base, pos);
        return null;
    }

    private void checkCall(CallExpr call)
    {
        if (Node knownFn = constant(call.fn))
        {
            if (knownFn.kind == NodeKind.NullLit)
            {
                issue(call, nullOperation, "chamada de função");
                return;
            }
            issue(call, notCallable, valueType(knownFn));
            return;
        }
        FnDecl fn;
        if (Identifier identifier = cast(Identifier) call.fn)
            fn = identifier.functionRef;
        else if (MemberExpr member = cast(MemberExpr) call.fn)
        {
            if (Identifier right = cast(Identifier) member.right)
            {
                fn = right.functionRef;
                // Verificar contrato de elemento ao chamar vetorTipado.adicionar(x) / empilhar(x)
                if ((right.value == "adicionar" || right.value == "empilhar") && call.args.length == 1)
                {
                    if (TypeExpr elemType = arrayElementTypeExpr(member.left, call.pos))
                        contract(call.args[0], elemType, call);
                }
            }
        }
        if (fn is null)
            return;
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
        if (!programInfoCollected)
            collectProgramInfo(node);
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
        {
            if (assignment.op == TokenKind.Equals)
                contract(assignment.value, assignment.left.type_expr, node);
            if (IndexExpr idxAssign = cast(IndexExpr) assignment.left)
            {
                if (TypeSemaBuiltin targetType = cast(TypeSemaBuiltin) idxAssign.value.type_sema)
                    if (targetType.base == TypeSemaBase.String || targetType.base == TypeSemaBase.Tuple)
                        issue(node, immutableMutation, targetType.toStr().to!string);
                if (assignment.op == TokenKind.Equals)
                    if (TypeExpr elemType = arrayElementTypeExpr(idxAssign.value, node.pos))
                        contract(assignment.value, elemType, node);
            }
        }
        if (MemberExpr member = cast(MemberExpr) node)
            checkMember(member);
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
            if (Node knownVal = constant(index.value))
                if (knownVal.kind == NodeKind.NullLit)
                    issue(node, nullOperation, "indexação");
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
