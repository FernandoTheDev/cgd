module opt.dead_code;

import frontend;
import frontend.flow : terminates;
import middle.rewrite;

/// Elimina apenas regiões comprovadamente não executadas. Declarações permanecem
/// no escopo original, inclusive funções referenciadas antes de sua declaração.
final class CgdDeadCode : AstRewriter
{
    private Program program;
    size_t changes;
    this(Program program)
    {
        this.program = program;
    }

    private void clean(ref Node[] body)
    {
        Node[] result;
        bool stopped;
        foreach (Node original; body)
        {
            Node node = original;
            if (stopped && !cast(FnDecl) node && !cast(ClassDecl) node)
            {
                changes++;
                continue;
            }
            if (IfStmt branch = cast(IfStmt) node)
                if (BoolLit condition = cast(BoolLit) branch.expr)
                {
                    changes++;
                    if (condition.value)
                        node = new BlockStmt(branch.body, branch.pos);
                    else if (branch._else !is null)
                        node = branch._else;
                    else
                        continue;
                }
            // Nunca remove um laço com declaração: o backend mantém os vínculos.
            if (WhileStmt loop = cast(WhileStmt) node)
                if (BoolLit condition = cast(BoolLit) loop.expr)
                    if (!condition.value)
                    {
                        changes++;
                        continue;
                    }
            result ~= node;
            stopped = stopped || terminates(node);
        }
        body = result;
    }

    override protected Node transform(Node node)
    {
        if (Program n = cast(Program) node)
            clean(n.body);
        else if (FnDecl n = cast(FnDecl) node)
            clean(n.body);
        else if (BlockStmt n = cast(BlockStmt) node)
            clean(n.body);
        else if (SequenceStmt n = cast(SequenceStmt) node)
            clean(n.body);
        else if (IfStmt n = cast(IfStmt) node)
            clean(n.body);
        else if (WhileStmt n = cast(WhileStmt) node)
            clean(n.body);
        else if (ForStmt n = cast(ForStmt) node)
            clean(n.body);
        else if (DoStmt n = cast(DoStmt) node)
            clean(n.body);
        else if (EachStmt n = cast(EachStmt) node)
            clean(n.body);
        else if (TryStmt n = cast(TryStmt) node)
        {
            clean(n.body);
            clean(n.finalBody);
            foreach (ref CatchClause c; n.catches)
                clean(c.body);
        }
        else if (SwitchStmt n = cast(SwitchStmt) node)
        {
            clean(n.fallback);
            foreach (ref SwitchCase c; n.cases)
                clean(c.body);
        }
        return node;
    }

    void remove()
    {
        rewrite(program);
    }
}
