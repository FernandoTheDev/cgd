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
        foreach (ref Decorator decorator; node.decorators)
            rewriteBody(decorator.values);
        if (Program n = cast(Program) node)
            rewriteBody(n.body);
        else if (ModuleUnit n = cast(ModuleUnit) node)
            n.program = cast(Program) rewrite(n.program);
        else if (ImportExpr n = cast(ImportExpr) node)
        {
            n.path = rewrite(n.path);
            rewrite(n.target);
        }
        else if (ClassDecl n = cast(ClassDecl) node)
        {
            foreach (FnDecl method; n.methods)
                rewrite(method);
            foreach (ref ClassField field; n.fields)
                foreach (ref Decorator decorator; field.decorators)
                    rewriteBody(decorator.values);
        }
        else if (FnDecl n = cast(FnDecl) node)
        {
            foreach (FnArg arg; n.args)
                arg.value = rewrite(arg.value);
            rewriteBody(n.body);
        }
        else if (FunctionExpr n = cast(FunctionExpr) node)
            rewrite(n.declaration);
        else if (VarDecl n = cast(VarDecl) node)
            n.value = rewrite(n.value);
        else if (BinaryExpr n = cast(BinaryExpr) node)
        {
            n.left = rewrite(n.left);
            n.right = rewrite(n.right);
        }
        else if (UnaryExpr n = cast(UnaryExpr) node)
            n.value = rewrite(n.value);
        else if (CallExpr n = cast(CallExpr) node)
        {
            n.fn = rewrite(n.fn);
            rewriteBody(n.args);
        }
        else if (ReturnStmt n = cast(ReturnStmt) node)
            n.val = rewrite(n.val);
        else if (IfStmt n = cast(IfStmt) node)
        {
            n.expr = rewrite(n.expr);
            rewriteBody(n.body);
            n._else = cast(IfStmt) rewrite(n._else);
        }
        else if (BlockStmt n = cast(BlockStmt) node)
            rewriteBody(n.body);
        else if (SequenceStmt n = cast(SequenceStmt) node)
            rewriteBody(n.body);
        else if (WhileStmt n = cast(WhileStmt) node)
        {
            n.expr = rewrite(n.expr);
            rewriteBody(n.body);
        }
        else if (ForStmt n = cast(ForStmt) node)
        {
            n.init = rewrite(n.init);
            n.condition = rewrite(n.condition);
            n.step = rewrite(n.step);
            rewriteBody(n.body);
        }
        else if (DoStmt n = cast(DoStmt) node)
        {
            n.condition = rewrite(n.condition);
            rewriteBody(n.body);
        }
        else if (EachStmt n = cast(EachStmt) node)
        {
            n.iterable = rewrite(n.iterable);
            rewriteBody(n.body);
        }
        else if (ArrayLit n = cast(ArrayLit) node)
            rewriteBody(n.elements);
        else if (MapLit n = cast(MapLit) node)
        {
            rewriteBody(n.keys);
            rewriteBody(n.values);
        }
        else if (IndexExpr n = cast(IndexExpr) node)
        {
            n.value = rewrite(n.value);
            n.idx = rewrite(n.idx);
        }
        else if (MemberExpr n = cast(MemberExpr) node)
            n.left = rewrite(n.left); // right é nome, não expressão.
        else if (AssignStmt n = cast(AssignStmt) node)
        {
            rewriteLvalue(n.left);
            n.value = rewrite(n.value);
        }
        else if (TypeOfExpr n = cast(TypeOfExpr) node)
            n.value = rewrite(n.value);
        else if (ThrowStmt n = cast(ThrowStmt) node)
            n.value = rewrite(n.value);
        else if (TryStmt n = cast(TryStmt) node)
        {
            rewriteBody(n.body);
            rewriteBody(n.finalBody);
            foreach (ref CatchClause c; n.catches)
                rewriteBody(c.body);
        }
        else if (ConditionalExpr n = cast(ConditionalExpr) node)
        {
            n.condition = rewrite(n.condition);
            n.yes = rewrite(n.yes);
            n.no = rewrite(n.no);
        }
        else if (SliceExpr n = cast(SliceExpr) node)
        {
            n.value = rewrite(n.value);
            n.start = rewrite(n.start);
            n.end = rewrite(n.end);
            n.step = rewrite(n.step);
        }
        else if (SpreadExpr n = cast(SpreadExpr) node)
            n.value = rewrite(n.value);
        else if (Comprehension n = cast(Comprehension) node)
        {
            n.value = rewrite(n.value);
            n.iterable = rewrite(n.iterable);
            n.condition = rewrite(n.condition);
        }
        else if (LoopExpr n = cast(LoopExpr) node)
            n.loop = rewrite(n.loop);
        else if (SwitchStmt n = cast(SwitchStmt) node)
        {
            n.value = rewrite(n.value);
            rewriteBody(n.fallback);
            foreach (ref SwitchCase c; n.cases)
            {
                rewriteBody(c.values);
                rewriteBody(c.body);
            }
        }
        return transform(node);
    }

    private void rewriteLvalue(Node node)
    {
        if (IndexExpr n = cast(IndexExpr) node)
        {
            n.value = rewrite(n.value);
            n.idx = rewrite(n.idx);
        }
        else if (MemberExpr n = cast(MemberExpr) node)
            n.left = rewrite(n.left);
    }

    final void rewriteBody(ref Node[] body)
    {
        foreach (ref Node child; body)
            child = rewrite(child);
    }

    protected Node transform(Node node)
    {
        return node;
    }
}
