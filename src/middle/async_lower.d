module middle.async_lower;

import middle.async_ir;
import frontend;
import std.conv : to;
import std.algorithm : canFind, any;

/// Identidades resolvidas distinguem sombras; nomes sintéticos nunca colidem.
class AsyncLowering
{
    private AsyncIR ir;
    private size_t[Object] bindings;
    private size_t[dstring] names;
    private size_t[][] breaks, continues;
    private size_t[] breakDepths, continueDepths;
    private AsyncLabel handler;
    private size_t cleanupEmission;
    private struct Cleanup
    {
        Node[] body;
        AsyncLabel outer;
    }

    private Cleanup[] cleanups;
    private struct Collector
    {
        size_t output, depth, loopIndex;
    }

    private Collector[] collectors;

    private size_t slot(TypeExpr type = null, TypeSema semanticType = null)
    {
        if (ir.slots.length >= 100000)
            throw new AsyncLimitException(ir.position);
        size_t index = ir.slots.length;
        dstring name = "#async_"d ~ index.to!dstring;
        ir.slots ~= AsyncSlot(name, ""d, type, semanticType);
        names[name] = index;
        return index;
    }

    private size_t binding(Object identity, TypeExpr type, TypeSema semanticType)
    {
        if (size_t* found = identity in bindings)
            return *found;
        size_t index = slot(type, semanticType);
        bindings[identity] = index;
        if (VarDecl declaration = cast(VarDecl) identity)
            ir.slots[index].sourceName = declaration.name;
        if (FnArg argument = cast(FnArg) identity)
            ir.slots[index].sourceName = argument.name;
        return index;
    }

    private Identifier reference(size_t index, Position position)
    {
        Identifier result = new Identifier(ir.slots[index].name, position);
        result.type_expr = ir.slots[index].type;
        result.type_sema = ir.slots[index].semanticType;
        return result;
    }

    private void uses(Node node, ref size_t[] result)
    {
        if (node is null || cast(FunctionExpr) node || cast(FnDecl) node || cast(ImportExpr) node)
            return;
        if (Identifier identifier = cast(Identifier) node)
        {
            if (size_t* found = identifier.value in names)
                if (!result.canFind(*found))
                    result ~= *found;
            return;
        }
        if (AssignStmt assignment = cast(AssignStmt) node)
        {
            if (!cast(Identifier) assignment.left)
                uses(assignment.left, result);
            uses(assignment.value, result);
            return;
        }
        if (cast(SuperExpr) node && ir.self != size_t.max)
            result ~= ir.self;
        if (MemberExpr member = cast(MemberExpr) node)
        {
            uses(member.left, result);
            return;
        }
        foreach (Node child; childNodes(node))
            uses(child, result);
    }

    private size_t append(AsyncOp op, Node value = null, size_t target = size_t.max)
    {
        if (ir.instructions.length >= 100000)
            throw new AsyncLimitException(ir.position);
        size_t index = ir.instructions.length;
        AsyncInstruction instruction;
        instruction.handler = op == AsyncOp.Jump || op == AsyncOp.Branch || op == AsyncOp.Return ? null : handler;
        instruction.cleanup = cleanupEmission != 0;
        instruction.op = op;
        instruction.value = value;
        instruction.target = target;
        if (op != AsyncOp.Return && op != AsyncOp.Throw)
            instruction.next = index + 1;
        if (op != AsyncOp.Resume)
            uses(value, instruction.uses);
        if (target != size_t.max)
            instruction.definitions ~= target;
        Node modified;
        if (AssignStmt assignment = cast(AssignStmt) value)
            modified = assignment.left;
        if (UnaryExpr unary = cast(UnaryExpr) value)
            if (unary.op == TokenKind.PPlus || unary.op == TokenKind.MMinus)
                modified = unary.value;
        if (Identifier identifier = cast(Identifier) modified)
            if (size_t* found = identifier.value in names)
                instruction.definitions ~= *found;
        ir.instructions ~= instruction;
        return index;
    }

    private Node store(Node value, TypeExpr type = null)
    {
        size_t index = slot(type, value.type_sema);
        append(AsyncOp.Evaluate, value, index);
        return reference(index, value.pos);
    }

    private Node metadata(Node result, Node original)
    {
        result.type_expr = original.type_expr;
        result.type_sema = original.type_sema;
        return result;
    }

    private Node lvalue(Node node)
    {
        if (Identifier identifier = cast(Identifier) node)
        {
            if (identifier.variableRef !is null)
                return reference(binding(identifier.variableRef, identifier.type_expr, identifier.type_sema), node.pos);
            if (identifier.parameterRef !is null)
            {
                if (identifier.value == "isto")
                    return reference(ir.self, node.pos);
                return reference(binding(identifier.parameterRef, identifier.type_expr, identifier.type_sema), node.pos);
            }
            return node;
        }
        if (MemberExpr member = cast(MemberExpr) node)
        {
            if (member.resolvedModule !is null)
                return member;
            return metadata(new MemberExpr(expression(member.left), member.right, node.pos), node);
        }
        if (IndexExpr index = cast(IndexExpr) node)
        {
            Node receiver = expression(index.value);
            Node key = expression(index.idx);
            return metadata(new IndexExpr(receiver, key, node.pos), node);
        }
        throw new Exception("Destino inválido na IR assíncrona.");
    }

    private Node call(dstring name, Node[] args, Position position)
    {
        CallExpr result = new CallExpr(new Identifier(name, position), args, position);
        result.runtimeCall = true;
        return result;
    }

    private Node choose(Node condition, Node yes, Node no, TokenKind kind = TokenKind.If)
    {
        size_t output = slot();
        size_t branch = append(AsyncOp.Branch, condition);
        ir.instructions[branch].condition = kind;
        Node first = expression(yes);
        append(AsyncOp.Evaluate, first, output);
        size_t jump = append(AsyncOp.Jump);
        ir.instructions[branch].alternative = ir.instructions.length;
        Node second = expression(no);
        append(AsyncOp.Evaluate, second, output);
        ir.instructions[jump].next = ir.instructions.length;
        return reference(output, condition.pos);
    }

    private Node expression(Node node)
    {
        if (node is null)
            return new NullLit(null);
        if (AwaitExpr awaited = cast(AwaitExpr) node)
        {
            Node promise = expression(awaited.value);
            append(AsyncOp.Await, promise);
            size_t output = slot(node.type_expr, node.type_sema);
            append(AsyncOp.Resume, node, output);
            return reference(output, node.pos);
        }
        if (RoutineExpr routine = cast(RoutineExpr) node)
        {
            Node callee = cast(Identifier) routine.call.fn ? routine.call.fn : expression(routine.call.fn);
            Node[] arguments;
            foreach (Node argument; routine.call.args)
                arguments ~= expression(argument);
            CallExpr loweredCall = new CallExpr(callee, arguments, routine.call.pos);
            RoutineExpr lowered = new RoutineExpr(loweredCall, routine.pos);
            lowered.target = routine.target;
            lowered.resultType = routine.resultType;
            return store(metadata(lowered, node));
        }
        if (Identifier identifier = cast(Identifier) node)
            return store(metadata(lvalue(identifier), node));
        if (CallExpr invocation = cast(CallExpr) node)
        {
            Node callee = invocation.runtimeCall ? invocation.fn : expression(invocation.fn);
            if (invocation.args.any!((Node argument) => argument.kind == NodeKind.SpreadExpr))
            {
                Node argumentsVector = store(new ArrayLit([], node.pos));
                foreach (Node argument; invocation.args)
                {
                    SpreadExpr spread = cast(SpreadExpr) argument;
                    Node value = expression(spread is null ? argument : spread.value);
                    store(call(spread is null ? "rt_async_push" : "rt_async_expand", [
                        argumentsVector, value
                    ], argument.pos));
                }
                return store(call("delegua_chamar_vetor", [callee, argumentsVector], node.pos));
            }
            Node[] arguments;
            foreach (Node argument; invocation.args)
                arguments ~= expression(argument);
            CallExpr result = new CallExpr(callee, arguments, node.pos);
            result.runtimeCall = invocation.runtimeCall;
            result.intrinsic = invocation.intrinsic;
            return store(metadata(result, node));
        }
        if (AssignStmt assignment = cast(AssignStmt) node)
        {
            Node destination = lvalue(assignment.left);
            Node previous;
            if (assignment.op != TokenKind.Equals)
                previous = store(destination);
            Node value = expression(assignment.value);
            if (previous !is null)
            {
                dstring operation;
                switch (assignment.op)
                {
                    case TokenKind.PlusAssign:
                        operation = "add";
                        break;
                    case TokenKind.MinusAssign:
                        operation = "sub";
                        break;
                    case TokenKind.MulAssign:
                        operation = "mul";
                        break;
                    case TokenKind.DivAssign:
                        operation = "div";
                        break;
                    case TokenKind.ModAssign:
                        operation = "mod";
                        break;
                    default:
                        throw new Exception("Operador de atribuição inválido.");
                }
                value = call("delegua_op_" ~ operation, [previous, value], node.pos);
            }
            return store(metadata(new AssignStmt(destination, value, TokenKind.Equals, node.pos), node));
        }
        if (ConditionalExpr conditional = cast(ConditionalExpr) node)
            return choose(expression(conditional.condition), conditional.yes, conditional.no);
        if (BinaryExpr binary = cast(BinaryExpr) node)
        {
            Node left = expression(binary.left);
            if (binary.op == TokenKind.And)
                return choose(left, binary.right, left);
            if (binary.op == TokenKind.Or)
                return choose(left, left, binary.right);
            if (binary.op == TokenKind.Coalesce)
                return choose(left, binary.right, left, TokenKind.Coalesce);
            throw new Exception("Operador não normalizado na IR assíncrona.");
        }
        if (MemberExpr member = cast(MemberExpr) node)
        {
            if (member.enumValue !is null)
                return expression(member.enumValue);
            if (member.resolvedModule !is null)
                return store(member);
            return store(metadata(new MemberExpr(expression(member.left), member.right, node.pos), node));
        }
        if (IndexExpr index = cast(IndexExpr) node)
            return store(lvalue(index));
        if (UnaryExpr unary = cast(UnaryExpr) node)
        {
            bool modifies = unary.op == TokenKind.PPlus || unary.op == TokenKind.MMinus;
            Node operand = modifies ? lvalue(unary.value) : expression(unary.value);
            return store(metadata(new UnaryExpr(operand, unary.op, unary.post, node.pos), node));
        }
        if (ArrayLit array = cast(ArrayLit) node)
        {
            Node vector = store(new ArrayLit([], node.pos));
            foreach (Node element; array.elements)
            {
                SpreadExpr spread = cast(SpreadExpr) element;
                Node value = expression(spread is null ? element : spread.value);
                store(call(spread is null ? "rt_async_push" : "rt_async_expand", [vector, value], element.pos));
            }
            return node.kind == NodeKind.TupleLit ? store(call("rt_async_tuple", [vector], node.pos)) : vector;
        }
        if (MapLit map = cast(MapLit) node)
        {
            Node result = store(new MapLit([], [], node.pos));
            foreach (size_t i, Node key; map.keys)
            {
                if (key is null)
                {
                    SpreadExpr spread = cast(SpreadExpr) map.values[i];
                    store(call("rt_async_map_expand", [result, expression(spread.value)], node.pos));
                }
                else
                {
                    Node normalizedKey = expression(key);
                    Node value = expression(map.values[i]);
                    store(call("delegua_map_setar", [result, normalizedKey, value], node.pos));
                }
            }
            return result;
        }
        if (Comprehension comprehension = cast(Comprehension) node)
        {
            Node output = store(new ArrayLit([], node.pos));
            size_t variable = syntheticBinding([comprehension.value, comprehension.condition],
                    comprehension.name, comprehension.bindingType, node.pos);
            iteration(comprehension.iterable, variable, [], null, comprehension.value,
                    comprehension.condition, output);
            return output;
        }
        if (LoopExpr loop = cast(LoopExpr) node)
        {
            Node output = store(new ArrayLit([], node.pos));
            collectors ~= Collector(*((cast(Identifier) output).value in names), cleanups.length, continues.length);
            statement(loop.loop);
            collectors.length--;
            return output;
        }
        if (SliceExpr slice = cast(SliceExpr) node)
        {
            Node value = expression(slice.value);
            Node start = expression(slice.start), end = expression(slice.end), step = expression(slice.step);
            return store(metadata(new SliceExpr(value, start, end, step, node.pos), node));
        }
        return store(node);
    }

    private void body(Node[] nodes)
    {
        foreach (Node node; nodes)
            statement(node);
    }

    private void emitCleanups(size_t depth)
    {
        Cleanup[] original = cleanups.dup;
        AsyncLabel previous = handler;
        scope (exit)
        {
            cleanups = original;
            handler = previous;
        }
        while (cleanups.length > depth)
        {
            Cleanup current = cleanups[$ - 1];
            cleanups.length--;
            handler = current.outer;
            cleanupEmission++;
            body(current.body);
            cleanupEmission--;
        }
    }

    private VarDecl findBinding(Node[] nodes, dstring name, Position position)
    {
        foreach (Node node; nodes)
        {
            if (node is null || cast(FnDecl) node || cast(FunctionExpr) node)
                continue;
            if (Identifier identifier = cast(Identifier) node)
                if (identifier.variableRef !is null && identifier.variableRef.name == name
                        && identifier.variableRef.pos is position && identifier.variableRef.value is null)
                    return identifier.variableRef;
            if (VarDecl found = findBinding(childNodes(node), name, position))
                return found;
        }
        return null;
    }

    private size_t syntheticBinding(Node[] nodes, dstring name, TypeExpr type, Position position)
    {
        VarDecl variable = findBinding(nodes, name, position);
        if (variable is null)
            variable = new VarDecl(name, null, false, type, position);
        return binding(variable, type, variable.type_sema);
    }

    private void lowerTry(TryStmt attempt)
    {
        AsyncLabel outer = handler;
        AsyncLabel dispatch = new AsyncLabel;
        AsyncLabel catchFailure = attempt.finalBody.length ? new AsyncLabel : outer;
        size_t depth = cleanups.length;
        cleanups ~= Cleanup(attempt.finalBody, outer);
        handler = dispatch;
        body(attempt.body);
        emitCleanups(depth);
        size_t[] exits = [append(AsyncOp.Jump)];
        dispatch.index = ir.instructions.length;
        handler = catchFailure;
        size_t saved = slot();
        append(AsyncOp.Evaluate, reference(ir.error, attempt.pos), saved);
        foreach (CatchClause clause; attempt.catches)
        {
            Node matches = clause.type is null ? cast(Node) new BoolLit(true,
                    clause.pos) : call("rt_async_error_matches", [
                reference(saved, clause.pos), new StringLit(clause.type.toStr(), clause.pos)
            ], clause.pos);
            size_t branch = append(AsyncOp.Branch, expression(matches));
            if (clause.name.length)
            {
                size_t variable = syntheticBinding(clause.body, clause.name, clause.type, clause.pos);
                append(AsyncOp.Evaluate, reference(saved, clause.pos), variable);
            }
            body(clause.body);
            emitCleanups(depth);
            exits ~= append(AsyncOp.Jump);
            ir.instructions[branch].alternative = ir.instructions.length;
        }
        handler = outer;
        emitCleanups(depth);
        append(AsyncOp.Throw, reference(saved, attempt.pos));
        if (attempt.finalBody.length)
        {
            catchFailure.index = ir.instructions.length;
            size_t failed = slot();
            append(AsyncOp.Evaluate, reference(ir.error, attempt.pos), failed);
            emitCleanups(depth);
            append(AsyncOp.Throw, reference(failed, attempt.pos));
        }
        cleanups.length = depth;
        foreach (size_t exit; exits)
            ir.instructions[exit].next = ir.instructions.length;
        handler = outer;
    }

    private void iteration(Node iterable, size_t variable, Node[] nodes, EachStmt each = null,
            Node element = null, Node condition = null, Node output = null)
    {
        Node source = expression(iterable);
        size_t index = slot();
        append(AsyncOp.Evaluate, new IntLit(0, iterable.pos), index);
        size_t start = ir.instructions.length;
        Node length = store(call("rt_async_length", [source], iterable.pos));
        Node test = store(call("delegua_op_lt", [reference(index, iterable.pos), length], iterable.pos));
        size_t branch = append(AsyncOp.Branch, test);
        Node item = store(call("rt_async_item", [source, reference(index, iterable.pos)], iterable.pos));
        append(AsyncOp.Evaluate, item, variable);
        if (each !is null)
            foreach (size_t i, dstring name; each.destructured)
            {
                TypeExpr type = i < each.destructuredTypes.length ? each.destructuredTypes[i] : null;
                size_t field = syntheticBinding(nodes, name, type, each.pos);
                append(AsyncOp.Evaluate, call("delegua_obter", [
                    reference(variable, each.pos), new IntLit(i, each.pos)
                ], each.pos), field);
            }
        breaks ~= cast(size_t[]) null;
        continues ~= cast(size_t[]) null;
        breakDepths ~= cleanups.length;
        continueDepths ~= cleanups.length;
        size_t skip = size_t.max;
        if (condition !is null)
            skip = append(AsyncOp.Branch, expression(condition));
        if (element is null)
            body(nodes);
        else
            store(call("rt_async_push", [output, expression(element)], element.pos));
        size_t step = ir.instructions.length;
        if (skip != size_t.max)
            ir.instructions[skip].alternative = step;
        append(AsyncOp.Evaluate, call("delegua_op_add", [
            reference(index, iterable.pos), new IntLit(1, iterable.pos)
        ], iterable.pos), index);
        size_t jump = append(AsyncOp.Jump);
        ir.instructions[jump].next = start;
        ir.instructions[branch].alternative = ir.instructions.length;
        foreach (size_t exit; breaks[$ - 1])
            ir.instructions[exit].next = ir.instructions.length;
        foreach (size_t next; continues[$ - 1])
            ir.instructions[next].next = step;
        breaks.length--;
        continues.length--;
        breakDepths.length--;
        continueDepths.length--;
    }

    private void lowerSwitch(SwitchStmt selection)
    {
        Node value = expression(selection.value);
        size_t[] exits;
        breaks ~= cast(size_t[]) null;
        breakDepths ~= cleanups.length;
        foreach (SwitchCase clause; selection.cases)
        {
            size_t[] matches;
            foreach (Node candidate; clause.values)
            {
                Node equal = store(call("delegua_op_eq", [value, expression(candidate)], candidate.pos));
                size_t branch = append(AsyncOp.Branch, equal);
                matches ~= branch;
                ir.instructions[branch].alternative = ir.instructions.length;
                // A correspondência salta os próximos testes, o falso avança.
                ir.instructions[branch].next = size_t.max;
            }
            size_t noMatch = append(AsyncOp.Jump);
            foreach (size_t branch; matches)
                ir.instructions[branch].next = ir.instructions.length;
            body(clause.body);
            exits ~= append(AsyncOp.Jump);
            ir.instructions[noMatch].next = ir.instructions.length;
        }
        body(selection.fallback);
        foreach (size_t exit; exits ~ breaks[$ - 1])
            ir.instructions[exit].next = ir.instructions.length;
        breaks.length--;
        breakDepths.length--;
    }

    private void statement(Node node)
    {
        if (BlockStmt block = cast(BlockStmt) node)
        {
            body(block.body);
            return;
        }
        if (SequenceStmt sequence = cast(SequenceStmt) node)
        {
            body(sequence.body);
            return;
        }
        if (VarDecl declaration = cast(VarDecl) node)
        {
            size_t index = binding(declaration, declaration.type_expr, declaration.type_sema);
            Node value = expression(declaration.value);
            append(AsyncOp.Evaluate, value, index);
            return;
        }
        if (EachStmt each = cast(EachStmt) node)
        {
            size_t variable = syntheticBinding(each.body, each.name, each.bindingType, each.pos);
            iteration(each.iterable, variable, each.body, each);
            return;
        }
        if (SwitchStmt selection = cast(SwitchStmt) node)
        {
            lowerSwitch(selection);
            return;
        }
        if (TryStmt attempt = cast(TryStmt) node)
        {
            lowerTry(attempt);
            return;
        }
        if (ReturnStmt returned = cast(ReturnStmt) node)
        {
            Node value = expression(returned.val);
            if (returned.collectionReturn)
            {
                Collector collector = collectors[$ - 1];
                size_t saved = slot();
                append(AsyncOp.Evaluate, value, saved);
                emitCleanups(collector.depth);
                store(call("rt_async_push", [
                    reference(collector.output, node.pos), reference(saved, node.pos)
                ], node.pos));
                continues[collector.loopIndex] ~= append(AsyncOp.Jump);
                return;
            }
            size_t result = slot();
            append(AsyncOp.CaptureReturn, value, result);
            emitCleanups(0);
            append(AsyncOp.Return, reference(result, node.pos));
            return;
        }
        if (ThrowStmt thrown = cast(ThrowStmt) node)
        {
            append(AsyncOp.Throw, expression(thrown.value));
            return;
        }
        if (IfStmt conditional = cast(IfStmt) node)
        {
            if (conditional.expr is null)
            {
                body(conditional.body);
                return;
            }
            size_t branch = append(AsyncOp.Branch, expression(conditional.expr));
            body(conditional.body);
            size_t jump = append(AsyncOp.Jump);
            ir.instructions[branch].alternative = ir.instructions.length;
            if (conditional._else !is null)
                statement(conditional._else);
            ir.instructions[jump].next = ir.instructions.length;
            return;
        }
        if (cast(WhileStmt) node || cast(ForStmt) node || cast(DoStmt) node)
        {
            Node condition, step;
            Node[] nodes;
            bool post;
            if (WhileStmt loop = cast(WhileStmt) node)
            {
                condition = loop.expr;
                nodes = loop.body;
            }
            if (ForStmt loop = cast(ForStmt) node)
            {
                if (loop.init !is null)
                    statement(loop.init);
                condition = loop.condition;
                step = loop.step;
                nodes = loop.body;
            }
            if (DoStmt loop = cast(DoStmt) node)
            {
                condition = loop.condition;
                nodes = loop.body;
                post = true;
            }
            size_t start = ir.instructions.length;
            size_t branch = size_t.max;
            if (!post)
                branch = append(AsyncOp.Branch, condition is null ? new BoolLit(true, node.pos) : expression(condition));
            breaks ~= cast(size_t[]) null;
            continues ~= cast(size_t[]) null;
            breakDepths ~= cleanups.length;
            continueDepths ~= cleanups.length;
            body(nodes);
            size_t nextIteration = ir.instructions.length;
            if (step !is null)
                statement(step);
            if (post)
                branch = append(AsyncOp.Branch, expression(condition));
            size_t jump = append(AsyncOp.Jump);
            ir.instructions[jump].next = start;
            ir.instructions[branch].alternative = ir.instructions.length;
            foreach (size_t index; breaks[$ - 1])
                ir.instructions[index].next = ir.instructions.length;
            foreach (size_t index; continues[$ - 1])
                ir.instructions[index].next = nextIteration;
            breaks.length--;
            continues.length--;
            breakDepths.length--;
            continueDepths.length--;
            return;
        }
        if (LoopControl control = cast(LoopControl) node)
        {
            emitCleanups(node.kind == NodeKind.BreakStmt ? breakDepths[$ - 1] : continueDepths[$ - 1]);
            size_t jump = append(AsyncOp.Jump);
            if (node.kind == NodeKind.BreakStmt)
                breaks[$ - 1] ~= jump;
            else
                continues[$ - 1] ~= jump;
            return;
        }
        if (cast(FnDecl) node || node.kind == NodeKind.NaN)
            return;
        expression(node);
    }

    AsyncIR lower(FnDecl declaration)
    {
        bindings = null;
        names = null;
        breaks = null;
        continues = null;
        breakDepths = null;
        continueDepths = null;
        handler = null;
        cleanups = null;
        collectors = null;
        cleanupEmission = 0;
        ir = new AsyncIR;
        ir.position = declaration.pos;
        ir.error = slot();
        if (declaration.isMethod && !declaration.isStatic)
            ir.self = slot();
        foreach (FnArg argument; declaration.args)
            ir.parameters ~= binding(argument, argument.rest ? new TypeExprArray(argument.type_expr,
                    argument.pos) : argument.type_expr, argument.type_sema);
        body(declaration.body);
        append(AsyncOp.Return, new NullLit(declaration.pos));
        foreach (ref AsyncInstruction instruction; ir.instructions)
            if (instruction.handler !is null)
                instruction.exceptional = instruction.handler.index;
        if (!ir.verify())
            throw new Exception("IR assíncrona inválida.");
        ir.analyzeLiveness();
        return ir;
    }
}
