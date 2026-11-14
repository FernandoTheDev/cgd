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
        auto current = pending[$ - 1];
        pending.length--;
        if (current.node is null || current.node in seen)
            continue;
        seen[current.node] = true;
        if (current.depth > 512 || seen.length > 500_000)
        {
            diagnostics.error(current.node.pos,
                    "Limite estrutural da AST excedido; divida a expressão ou o módulo.", "E1004");
            return false;
        }
        foreach (child; childNodes(current.node))
            pending ~= Pending(child, current.depth + 1);
    }
    return true;
}
