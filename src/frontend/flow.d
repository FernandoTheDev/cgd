module frontend.flow;

import frontend;

/// Conservador: laços podem não executar; finalmente e capturas são analisados
/// separadamente. Retornos de laços-coletores não encerram a função.
bool terminates(Node node)
{
    if (node is null)
        return false;
    if (auto ret = cast(ReturnStmt) node)
        return !ret.collectionReturn;
    if (cast(ThrowStmt) node)
        return true;
    if (cast(LoopControl) node)
        return true;
    if (auto block = cast(BlockStmt) node)
        return terminates(block.body);
    if (auto sequence = cast(SequenceStmt) node)
        return terminates(sequence.body);
    if (auto condition = cast(IfStmt) node)
        return condition.expr is null ? terminates(condition.body) : terminates(condition.body)
            && condition._else !is null && terminates(condition._else);
    return false;
}

bool terminates(Node[] body)
{
    foreach (node; body)
        if (terminates(node))
            return true;
    return false;
}

/// Avisos independentes das otimizações. Não elimina código antes da semântica.
class FlowAnalysis
{
    private Diagnostics diagnostics;
    private bool[Node] seen;
    this(Diagnostics diagnostics)
    {
        this.diagnostics = diagnostics;
    }

    void analyze(Node node)
    {
        if (node is null || node in seen)
            return;
        seen[node] = true;
        if (auto n = cast(Program) node)
            inspect(n.body);
        else if (auto n = cast(FnDecl) node)
        {
            inspect(n.body);
            if (auto type = cast(TypeExprNamed) n.type_expr)
                if (type.name != "qualquer" && type.name != "vazio" && !n.classFactory && !terminates(n.body))
                    diagnostics.warningCode(n.pos, implicitReturn);
        }
        else if (auto n = cast(BlockStmt) node)
            inspect(n.body);
        else if (auto n = cast(SequenceStmt) node)
            inspect(n.body);
        else if (auto n = cast(IfStmt) node)
            inspect(n.body);
        else if (auto n = cast(WhileStmt) node)
            inspect(n.body);
        else if (auto n = cast(ForStmt) node)
            inspect(n.body);
        else if (auto n = cast(DoStmt) node)
            inspect(n.body);
        else if (auto n = cast(EachStmt) node)
            inspect(n.body);
        else if (auto n = cast(TryStmt) node)
        {
            inspect(n.body);
            inspect(n.finalBody);
            foreach (c; n.catches)
                inspect(c.body);
        }
        else if (auto n = cast(SwitchStmt) node)
        {
            inspect(n.fallback);
            foreach (c; n.cases)
                inspect(c.body);
        }
        foreach (child; childNodes(node))
            analyze(child);
    }

    private void inspect(Node[] body)
    {
        bool stopped, warned;
        foreach (node; body)
        {
            if (node is null)
                continue;
            if (stopped && !warned && !cast(FnDecl) node && !cast(ClassDecl) node)
            {
                diagnostics.warningCode(node.pos, unreachable);
                warned = true;
            }
            stopped = stopped || terminates(node);
        }
    }
}
