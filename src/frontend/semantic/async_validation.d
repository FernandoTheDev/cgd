module frontend.semantic.async_validation;
import frontend;
import ctfe.ctfe_flags;

/// Limites temporários são diagnósticos compartilhados CLI/LSP, não fallback C.
void validateAsyncFeatures(Program program, Diagnostics diagnostics)
{
    bool[Node] seen;
    void inspect(Node node, bool asynchronous, bool valueUsed = false)
    {
        if (node is null || node in seen)
            return;
        seen[node] = true;
        if (ImportExpr imported = cast(ImportExpr) node)
        {
            inspect(imported.path, asynchronous, true);
            inspect(imported.target, false);
            return;
        }
        if (FnDecl declaration = cast(FnDecl) node)
        {
            if (declaration.isAsync)
            {
                if (declaration.accessor || declaration.foreignSymbol.length || declaration.decoratorEnvelope
                        || declaration.fn == "construtor" || declaration.fn == "destrutor")
                    diagnostics.errorCode(node.pos, asyncContext);
                if (declaration.ctfe_flags & CTFEFlags.Pure)
                    diagnostics.errorCode(node.pos, asyncPure);
            }
            foreach (FnArg argument; declaration.args)
                inspect(argument.value, false, true);
            foreach (Node child; declaration.body)
                inspect(child, declaration.isAsync);
            return;
        }
        if (valueUsed && cast(AwaitExpr) node && node.type_sema !is null && node.type_sema.toStr() == "vazio")
            diagnostics.errorCode(node.pos, asyncVoid);
        if (asynchronous)
        {
            switch (node.kind)
            {
                case NodeKind.ClassDecl:
                    diagnostics.errorCode(node.pos, asyncUnsupported, node.kind);
                    break;
                default:
                    break;
            }
        }
        if (SwitchStmt selection = cast(SwitchStmt) node)
        {
            inspect(selection.value, asynchronous, true);
            foreach (SwitchCase branch; selection.cases)
            {
                foreach (Node value; branch.values)
                    inspect(value, asynchronous, true);
                foreach (Node statement; branch.body)
                    inspect(statement, asynchronous);
            }
            foreach (Node statement; selection.fallback)
                inspect(statement, asynchronous);
            return;
        }
        foreach (Node child; childNodes(node))
        {
            bool used = true;
            if (cast(Program) node || cast(BlockStmt) node || cast(SequenceStmt) node
                    || cast(TryStmt) node || cast(ReturnStmt) node)
                used = false;
            if (IfStmt condition = cast(IfStmt) node)
                used = child is condition.expr;
            if (WhileStmt loop = cast(WhileStmt) node)
                used = child is loop.expr;
            if (ForStmt loop = cast(ForStmt) node)
                used = child is loop.condition;
            if (EachStmt loop = cast(EachStmt) node)
                used = child is loop.iterable;
            if (DoStmt loop = cast(DoStmt) node)
                used = child is loop.condition;
            inspect(child, asynchronous, used);
        }
    }

    inspect(program, false);
}
