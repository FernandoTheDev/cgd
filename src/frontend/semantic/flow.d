module frontend.semantic.flow;

import frontend;

/// Conservador: laços podem não executar; finalmente e capturas são analisados
/// separadamente. Retornos de laços-coletores não encerram a função.
bool terminates(Node node)
{
    if (node is null)
        return false;
    if (ReturnStmt ret = cast(ReturnStmt) node)
        return !ret.collectionReturn;
    if (cast(ThrowStmt) node)
        return true;
    if (cast(LoopControl) node)
        return true;
    if (BlockStmt block = cast(BlockStmt) node)
        return terminates(block.body);
    if (SequenceStmt sequence = cast(SequenceStmt) node)
        return terminates(sequence.body);
    if (TryStmt attempt = cast(TryStmt) node)
    {
        if (terminates(attempt.finalBody))
            return true;
        if (!terminates(attempt.body))
            return false;
        foreach (CatchClause handler; attempt.catches)
            if (!terminates(handler.body))
                return false;
        return true;
    }
    if (IfStmt condition = cast(IfStmt) node)
        return condition.expr is null ? terminates(condition.body) : terminates(condition.body)
            && condition._else !is null && terminates(condition._else);
    return false;
}

bool terminates(Node[] body)
{
    foreach (Node node; body)
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
        if (Program n = cast(Program) node)
            inspect(n.body);
        else if (FnDecl n = cast(FnDecl) node)
        {
            inspect(n.body);
            if (TypeExprNamed type = cast(TypeExprNamed) n.type_expr)
                if (type.name != "qualquer" && type.name != "vazio" && !n.classFactory
                        && !n.isAbstract && !n.foreignSymbol.length && !terminates(n.body))
                    diagnostics.warningCode(n.pos, implicitReturn);
        }
        else if (BlockStmt n = cast(BlockStmt) node)
            inspect(n.body);
        else if (SequenceStmt n = cast(SequenceStmt) node)
            inspect(n.body);
        else if (IfStmt n = cast(IfStmt) node)
            inspect(n.body);
        else if (WhileStmt n = cast(WhileStmt) node)
            inspect(n.body);
        else if (ForStmt n = cast(ForStmt) node)
            inspect(n.body);
        else if (DoStmt n = cast(DoStmt) node)
            inspect(n.body);
        else if (EachStmt n = cast(EachStmt) node)
            inspect(n.body);
        else if (TryStmt n = cast(TryStmt) node)
        {
            inspect(n.body);
            inspect(n.finalBody);
            foreach (CatchClause c; n.catches)
                inspect(c.body);
        }
        else if (SwitchStmt n = cast(SwitchStmt) node)
        {
            inspect(n.fallback);
            foreach (SwitchCase c; n.cases)
                inspect(c.body);
        }
        foreach (Node child; childNodes(node))
            analyze(child);
    }

    private void inspect(Node[] body)
    {
        bool stopped, warned;
        foreach (Node node; body)
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
