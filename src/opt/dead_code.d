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
    this(Program program, Context context)
    {
        this.program = program;
    }

    private void clean(ref Node[] body)
    {
        Node[] result;
        bool stopped;
        foreach (original; body)
        {
            auto node = original;
            if (stopped && !cast(FnDecl) node && !cast(ClassDecl) node)
            {
                changes++;
                continue;
            }
            if (auto branch = cast(IfStmt) node)
                if (auto condition = cast(BoolLit) branch.expr)
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
            if (auto loop = cast(WhileStmt) node)
                if (auto condition = cast(BoolLit) loop.expr)
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
        if (auto n = cast(Program) node)
            clean(n.body);
        else if (auto n = cast(FnDecl) node)
            clean(n.body);
        else if (auto n = cast(BlockStmt) node)
            clean(n.body);
        else if (auto n = cast(SequenceStmt) node)
            clean(n.body);
        else if (auto n = cast(IfStmt) node)
            clean(n.body);
        else if (auto n = cast(WhileStmt) node)
            clean(n.body);
        else if (auto n = cast(ForStmt) node)
            clean(n.body);
        else if (auto n = cast(DoStmt) node)
            clean(n.body);
        else if (auto n = cast(EachStmt) node)
            clean(n.body);
        else if (auto n = cast(TryStmt) node)
        {
            clean(n.body);
            clean(n.finalBody);
            foreach (ref c; n.catches)
                clean(c.body);
        }
        else if (auto n = cast(SwitchStmt) node)
        {
            clean(n.fallback);
            foreach (ref c; n.cases)
                clean(c.body);
        }
        return node;
    }

    void remove()
    {
        rewrite(program);
    }
}
