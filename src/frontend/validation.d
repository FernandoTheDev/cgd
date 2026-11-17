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

    Pending[] pending = [Pending(program, 0)];
    bool[Node] seen;
    while (pending.length)
    {
        Pending current = pending[$ - 1];
        pending.length--;
        if (current.node is null || current.node in seen)
            continue;
        seen[current.node] = true;
        if (current.depth > 512 || seen.length > 500_000)
        {
            diagnostics.errorCode(current.node.pos, astLimit);
            return false;
        }
        foreach (Node child; childNodes(current.node))
            pending ~= Pending(child, current.depth + 1);
    }
    return true;
}
