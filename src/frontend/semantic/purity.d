module frontend.semantic.purity;

import std.algorithm;
import std.format;
import std.array;

import frontend.parser;
import errors;
import ctfe.ctfe_flags;

final class PureFunctionAnalysis
{
private:
    FnDecl[] validFunctions;
    bool[Object] locals;
    bool[Node] visited;
    Diagnostics err;

    bool analysis(FnDecl fn)
    {
        // analise de pureza em funções marcadas apenas
        // no futuro poderá haver a expansão
        if (!(fn.ctfe_flags & CTFEFlags.Pure))
            return false;

        foreach (Decorator d; fn.decorators)
            if (d.envelope !is null)
            {
                err.error(fn.pos, "Função com envelope de decorador não aceita avaliação @puro / //>puro.");
                return false;
            }
        bool allowedTarget = !fn.isMethod || (fn.isStatic && !fn.isAbstract && !fn.accessor
                && !fn.foreignSymbol.length && (fn.ownerClass is null || !fn.ownerClass.isForeign));
        if (!allowedTarget)
        {
            err.error(fn.pos, "Apenas funções livres e métodos estáticos gerenciados aceitam @puro.");
            return false;
        }
        locals = null;
        foreach (FnArg arg; fn.args)
            locals[arg] = true;
        collectLocals(fn.body);
        bool status = nodeAnalysisBlockStmt(fn.body);
        dstring name = fn.fn;
        if (status)
            validFunctions ~= fn;

        if (!status)
            err.error(fn.pos, format(
                    "A função '%s' foi marcada como pura mas após uma análise a pureza não foi detectada.", name));

        return status;
    }

    private bool isPureConstLiteral(Node node)
    {
        if (node is null)
            return false;
        if (cast(IntLit) node || cast(DoubleLit) node || cast(BoolLit) node || cast(StringLit) node)
            return true;
        if (ArrayLit arr = cast(ArrayLit) node)
        {
            foreach (Node el; arr.elements)
                if (!isPureConstLiteral(el))
                    return false;
            return true;
        }
        return false;
    }

    bool nodeAnalysis(Node node)
    {
        if (node is null)
            return true;
        final switch (node.kind)
        {
            case NodeKind.TupleLit:
            case NodeKind.SequenceStmt:
            case NodeKind.SpreadExpr:
            case NodeKind.SliceExpr:
            case NodeKind.Comprehension:
            case NodeKind.LoopExpr:
            case NodeKind.TypeOfExpr:
            case NodeKind.AwaitExpr:
            case NodeKind.RoutineExpr:
            case NodeKind.ModuleUnit:
            case NodeKind.ImportExpr:
            case NodeKind.TryStmt:
            case NodeKind.ThrowStmt:
            case NodeKind.ClassDecl:
            case NodeKind.SuperExpr:
            case NodeKind.FunctionExpr:
            case NodeKind.MapLit:
            case NodeKind.EachStmt:
            case NodeKind.NullLit:
                err.error(node.pos, "Esse recurso ainda não é suportado na avaliação em tempo de compilação.");
                return false;
            case NodeKind.ConditionalExpr:
                ConditionalExpr cond = cast(ConditionalExpr) node;
                return nodeAnalysis(cond.condition) && nodeAnalysis(cond.yes) && nodeAnalysis(cond.no);
            case NodeKind.ForStmt:
                ForStmt f = cast(ForStmt) node;
                return nodeAnalysis(f.init) && nodeAnalysis(f.condition) && nodeAnalysis(f.step)
                    && nodeAnalysisBlockStmt(f.body);
            case NodeKind.DoStmt:
                DoStmt d = cast(DoStmt) node;
                return nodeAnalysisBlockStmt(d.body) && nodeAnalysis(d.condition);
            case NodeKind.BreakStmt:
            case NodeKind.ContinueStmt:
                return true;
            case NodeKind.SwitchStmt:
                SwitchStmt sw = cast(SwitchStmt) node;
                if (!nodeAnalysis(sw.value))
                    return false;
                foreach (SwitchCase c; sw.cases)
                {
                    foreach (Node v; c.values)
                        if (!nodeAnalysis(v))
                            return false;
                    if (!nodeAnalysisBlockStmt(c.body))
                        return false;
                }
                return nodeAnalysisBlockStmt(sw.fallback);
            case NodeKind.Identifier:
                Identifier identifier = cast(Identifier) node;
                if (identifier.variableRef !is null && identifier.variableRef.isEnum)
                {
                    err.error(node.pos, "CTFE aceita membros escalares do enum, não o namespace como valor.");
                    return false;
                }
                if (identifier.functionRef !is null)
                {
                    err.error(node.pos,
                            "Valor de função ainda não é representável na avaliação em tempo de compilação.");
                    return false;
                }
                if (identifier.variableRef !is null && identifier.variableRef !in locals)
                {
                    if (identifier.variableRef.isConst && !identifier.variableRef.uninitialized
                            && isPureConstLiteral(identifier.variableRef.value))
                        return true;
                    err.errorCode(node.pos, impureState, identifier.value);
                    return false;
                }
                if (identifier.parameterRef !is null && identifier.parameterRef !in locals)
                {
                    err.errorCode(node.pos, impureState, identifier.value);
                    return false;
                }
                return true;

            case NodeKind.NaN:
            case NodeKind.StringLit:
            case NodeKind.IntLit:
            case NodeKind.DoubleLit:
            case NodeKind.BoolLit:
            case NodeKind.Program:
                return true;

            case NodeKind.BinaryExpr:
                BinaryExpr binary = cast(BinaryExpr) node;
                import frontend.lexer : TokenKind;

                if (binary.op == TokenKind.Coalesce || binary.op == TokenKind.In)
                {
                    err.error(node.pos, "Operador ainda não suportado na avaliação em tempo de compilação.");
                    return false;
                }
                return (nodeAnalysis(binary.left) == true) && (nodeAnalysis(binary.right) == true);

            case NodeKind.UnaryExpr:
                UnaryExpr un = cast(UnaryExpr) node;
                return nodeAnalysis(un.value);

            case NodeKind.FnDecl:
                err.error(node.pos,
                        "Função local ainda não é suportada na avaliação em tempo de compilação.");
                return false;

            case NodeKind.VarDecl:
                VarDecl var = cast(VarDecl) node;
                return var.isEnum || nodeAnalysis(var.value);

            case NodeKind.AssignStmt:
                AssignStmt ass = cast(AssignStmt) node;
                if (Identifier leftId = cast(Identifier) ass.left)
                {
                    if (leftId.variableRef !is null && leftId.variableRef !in locals)
                    {
                        err.errorCode(ass.left.pos, impureState, leftId.value);
                        return false;
                    }
                }
                else
                {
                    err.error(ass.left.pos, "Atribuição de índice ou membro não é suportada em função pura.");
                    return false;
                }
                return (nodeAnalysis(ass.left) == true) && (nodeAnalysis(ass.value) == true);

            case NodeKind.BlockStmt:
                return nodeAnalysisBlockStmt(cast(BlockStmt) node);

            case NodeKind.ReturnStmt:
                Node value = (cast(ReturnStmt) node).val;
                if (value is null)
                {
                    err.error(node.pos, "Retorno sem valor ainda não é suportado em funções puras.");
                    return false;
                }
                return nodeAnalysis(value);

            case NodeKind.CallExpr:
                return nodeAnalysisCallExpr(cast(CallExpr) node);

            case NodeKind.IfStmt:
                return nodeAnalysisIfStmt(cast(IfStmt) node);

            case NodeKind.WhileStmt:
                return nodeAnalysisWhileStmt(cast(WhileStmt) node);

            case NodeKind.MemberExpr:
                if ((cast(MemberExpr) node).enumValue !is null)
                    return true;
                err.error(node.pos, "Essa expressão não é pura.");
                return false;
            case NodeKind.ArrayLit:
                ArrayLit arr = cast(ArrayLit) node;
                foreach (Node el; arr.elements)
                    if (!nodeAnalysis(el))
                        return false;
                return true;
            case NodeKind.IndexExpr:
                IndexExpr idx = cast(IndexExpr) node;
                return nodeAnalysis(idx.value) && nodeAnalysis(idx.idx);
        }
    }

    bool nodeAnalysisWhileStmt(WhileStmt node)
    {
        bool expr = node.expr is null || nodeAnalysis(node.expr);
        if (!expr)
            return false;
        return nodeAnalysisBlockStmt(node.body);
    }

    bool nodeAnalysisIfStmt(IfStmt node)
    {
        bool expr = node.expr is null || nodeAnalysis(node.expr);
        if (!expr)
            return false;

        if (!nodeAnalysisBlockStmt(node.body))
            return false;

        return node._else is null || nodeAnalysisIfStmt(node._else);
    }

    bool nodeAnalysisBlockStmt(BlockStmt node) => nodeAnalysisBlockStmt(node.body);

    bool nodeAnalysisBlockStmt(Node[] body)
    {
        bool ret = true;
        foreach (Node child; body)
            if (!nodeAnalysis(child) && ret)
                ret = false;
        return ret;
    }

    bool nodeAnalysisCallExpr(CallExpr node)
    {
        import ctfe.evaluation : pureCallTarget;

        FnDecl target = pureCallTarget(node);
        if (target is null)
        {
            err.error(node.pos, "Chamada indireta ou método de instância ainda não é suportado na avaliação em tempo de compilação.");
            return false;
        }
        dstring name = target.fn;
        if (target.ctfe_flags & CTFEFlags.Pure)
        {
            bool valid = true;
            foreach (Node arg; node.args)
                if (!nodeAnalysis(arg))
                    valid = false;
            return valid;
        }

        err.error(node.pos, format("A função '%s' não é marcada pura.", name));

        if (target.pos !is null)
            err.hint(target.pos, format("A função '%s' foi definida aqui.", name));

        return false;
    }

    void collectLocals(Node[] body)
    {
        foreach (Node node; body)
        {
            if (node is null || cast(FnDecl) node || cast(ClassDecl) node)
                continue;
            if (VarDecl variable = cast(VarDecl) node)
                locals[variable] = true;
            collectLocals(childNodes(node));
        }
    }

    void visit(Node node)
    {
        if (node is null || node in visited)
            return;
        visited[node] = true;
        if (FnDecl fn = cast(FnDecl) node)
        {
            analysis(fn);
        }
        foreach (Node child; childNodes(node))
            visit(child);
    }

public:
    this(Diagnostics diagnostics)
    {
        err = diagnostics;
    }

    FnDecl[] analyze(Program program)
    {
        visit(program);
        return validFunctions;
    }
}
