module middle.rewrite;

import frontend.parser.ast;

/// Reescrita pós-ordem dos slots da AST; referências de resolução não são arestas.
/// Cada módulo/função compartilhado é visitado uma única vez por execução.
class AstRewriter
{
    private bool[Node] visited;

    final Node rewrite(Node node)
    {
        if (node is null || node in visited)
            return node;
        visited[node] = true;
        foreach (ref decorator; node.decorators)
            rewriteBody(decorator.values);
        if (auto n = cast(Program) node)
            rewriteBody(n.body);
        else if (auto n = cast(ModuleUnit) node)
            n.program = cast(Program) rewrite(n.program);
        else if (auto n = cast(ImportExpr) node)
        {
            n.path = rewrite(n.path);
            rewrite(n.target);
        }
        else if (auto n = cast(ClassDecl) node)
        {
            foreach (method; n.methods)
                rewrite(method);
            foreach (ref field; n.fields)
                foreach (ref decorator; field.decorators)
                    rewriteBody(decorator.values);
        }
        else if (auto n = cast(FnDecl) node)
        {
            foreach (arg; n.args)
                arg.value = rewrite(arg.value);
            rewriteBody(n.body);
        }
        else if (auto n = cast(FunctionExpr) node)
            rewrite(n.declaration);
        else if (auto n = cast(VarDecl) node)
            n.value = rewrite(n.value);
        else if (auto n = cast(BinaryExpr) node)
        {
            n.left = rewrite(n.left);
            n.right = rewrite(n.right);
        }
        else if (auto n = cast(UnaryExpr) node)
            n.value = rewrite(n.value);
        else if (auto n = cast(CallExpr) node)
        {
            n.fn = rewrite(n.fn);
            rewriteBody(n.args);
        }
        else if (auto n = cast(ReturnStmt) node)
            n.val = rewrite(n.val);
        else if (auto n = cast(IfStmt) node)
        {
            n.expr = rewrite(n.expr);
            rewriteBody(n.body);
            n._else = cast(IfStmt) rewrite(n._else);
        }
        else if (auto n = cast(BlockStmt) node)
            rewriteBody(n.body);
        else if (auto n = cast(SequenceStmt) node)
            rewriteBody(n.body);
        else if (auto n = cast(WhileStmt) node)
        {
            n.expr = rewrite(n.expr);
            rewriteBody(n.body);
        }
        else if (auto n = cast(ForStmt) node)
        {
            n.init = rewrite(n.init);
            n.condition = rewrite(n.condition);
            n.step = rewrite(n.step);
            rewriteBody(n.body);
        }
        else if (auto n = cast(DoStmt) node)
        {
            n.condition = rewrite(n.condition);
            rewriteBody(n.body);
        }
        else if (auto n = cast(EachStmt) node)
        {
            n.iterable = rewrite(n.iterable);
            rewriteBody(n.body);
        }
        else if (auto n = cast(ArrayLit) node)
            rewriteBody(n.elements);
        else if (auto n = cast(MapLit) node)
        {
            rewriteBody(n.keys);
            rewriteBody(n.values);
        }
        else if (auto n = cast(IndexExpr) node)
        {
            n.value = rewrite(n.value);
            n.idx = rewrite(n.idx);
        }
        else if (auto n = cast(MemberExpr) node)
            n.left = rewrite(n.left); // right é nome, não expressão.
        else if (auto n = cast(AssignStmt) node)
        {
            rewriteLvalue(n.left);
            n.value = rewrite(n.value);
        }
        else if (auto n = cast(TypeOfExpr) node)
            n.value = rewrite(n.value);
        else if (auto n = cast(ThrowStmt) node)
            n.value = rewrite(n.value);
        else if (auto n = cast(TryStmt) node)
        {
            rewriteBody(n.body);
            rewriteBody(n.finalBody);
            foreach (ref c; n.catches)
                rewriteBody(c.body);
        }
        else if (auto n = cast(ConditionalExpr) node)
        {
            n.condition = rewrite(n.condition);
            n.yes = rewrite(n.yes);
            n.no = rewrite(n.no);
        }
        else if (auto n = cast(SliceExpr) node)
        {
            n.value = rewrite(n.value);
            n.start = rewrite(n.start);
            n.end = rewrite(n.end);
            n.step = rewrite(n.step);
        }
        else if (auto n = cast(SpreadExpr) node)
            n.value = rewrite(n.value);
        else if (auto n = cast(Comprehension) node)
        {
            n.value = rewrite(n.value);
            n.iterable = rewrite(n.iterable);
            n.condition = rewrite(n.condition);
        }
        else if (auto n = cast(LoopExpr) node)
            n.loop = rewrite(n.loop);
        else if (auto n = cast(SwitchStmt) node)
        {
            n.value = rewrite(n.value);
            rewriteBody(n.fallback);
            foreach (ref c; n.cases)
            {
                rewriteBody(c.values);
                rewriteBody(c.body);
            }
        }
        return transform(node);
    }

    private void rewriteLvalue(Node node)
    {
        if (auto n = cast(IndexExpr) node)
        {
            n.value = rewrite(n.value);
            n.idx = rewrite(n.idx);
        }
        else if (auto n = cast(MemberExpr) node)
            n.left = rewrite(n.left);
    }

    final void rewriteBody(ref Node[] body)
    {
        foreach (ref child; body)
            child = rewrite(child);
    }

    protected Node transform(Node node)
    {
        return node;
    }
}
