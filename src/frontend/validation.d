module frontend.validation;

import frontend;

/// Limites estruturais antes dos passes recursivos: uma cadeia associativa longa
/// pode ter parsing iterativo, mas ainda produzir uma AST profundamente aninhada.
bool validateStructure(Program program, Diagnostics diagnostics)
{
    struct Pending
    {
        Node node;
        size_t depth;
    }

    struct PendingType
    {
        TypeExpr type;
        size_t depth;
    }

    PendingType[] typePending;
    bool[TypeExpr] seenTypes;
    void addType(TypeExpr type)
    {
        if (type !is null)
            typePending ~= PendingType(type, 0);
    }

    Pending[] pending = [Pending(program, 0)];
    bool[Node] seen;
    while (pending.length)
    {
        Pending current = pending[$ - 1];
        pending.length--;
        if (current.node is null || current.node in seen)
            continue;
        seen[current.node] = true;
        if (current.depth > 512 || seen.length + seenTypes.length > 500_000)
        {
            diagnostics.errorCode(current.node.pos, astLimit);
            return false;
        }
        addType(current.node.type_expr);
        if (FnDecl declaration = cast(FnDecl) current.node)
            foreach (FnArg argument; declaration.args)
                addType(argument.type_expr);
        if (ClassDecl declaration = cast(ClassDecl) current.node)
            foreach (ClassField field; declaration.fields)
                addType(field.type);
        if (TryStmt attempt = cast(TryStmt) current.node)
            foreach (CatchClause handler; attempt.catches)
                addType(handler.type);
        if (EachStmt loop = cast(EachStmt) current.node)
        {
            addType(loop.bindingType);
            foreach (TypeExpr type; loop.destructuredTypes)
                addType(type);
        }
        if (Comprehension comprehension = cast(Comprehension) current.node)
            addType(comprehension.bindingType);
        while (typePending.length)
        {
            PendingType entry = typePending[$ - 1];
            typePending.length--;
            if (entry.type is null || entry.type in seenTypes)
                continue;
            seenTypes[entry.type] = true;
            if (entry.depth > 512 || seenTypes.length + seen.length + seenTypes.length > 500_000)
            {
                diagnostics.errorCode(entry.type.pos, astLimit);
                return false;
            }
            if (TypeExprArray array = cast(TypeExprArray) entry.type)
                typePending ~= PendingType(array.base, entry.depth + 1);
            if (TypeExprPromise promise = cast(TypeExprPromise) entry.type)
                typePending ~= PendingType(promise.result, entry.depth + 1);
            if (TypeExprTask task = cast(TypeExprTask) entry.type)
                typePending ~= PendingType(task.result, entry.depth + 1);
            if (TypeExprTuple tuple = cast(TypeExprTuple) entry.type)
                foreach (TypeExpr type; tuple.types)
                    typePending ~= PendingType(type, entry.depth + 1);
        }
        foreach (Node child; childNodes(current.node))
            pending ~= Pending(child, current.depth + 1);
    }
    return true;
}
