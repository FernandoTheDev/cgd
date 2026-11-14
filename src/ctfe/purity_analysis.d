module ctfe.purity_analysis;

import std.algorithm;
import std.format;
import std.stdio;
import std.array;

import frontend.semantic;
import frontend.parser;
import errors;
import ctfe;

final class PurityAnalysis
{
private:
    CTFEContext ctfe;
    CTFECompile compiler;

    Context context;
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
                err.error(fn.pos, "Função com envelope de decorador não aceita avaliação //>puro.");
                return false;
            }
        bool status = nodeAnalysisBlockStmt(fn.body);
        dstring name = fn.fn;
        // writefln("A função é pura: %d -> '%s'", status, name);

        if (status && name !in ctfe.functions)
        {
            // compila a função
            ctfe.functions[name] = VM(VMContext(), compiler.compile(fn), ctfe);
            ctfe.symbols[name] = *(cast(SymbolFn*) context.get(name));
        }

        if (!status)
            err.error(fn.pos, format(
                    "A função '%s' foi marcada como pura mas após uma análise a pureza não foi detectada.", name));

        return status;
    }

    bool nodeAnalysis(Node node)
    {
        final switch (node.kind)
        {
            case NodeKind.TupleLit:
            case NodeKind.SequenceStmt:
            case NodeKind.ConditionalExpr:
            case NodeKind.SpreadExpr:
            case NodeKind.SliceExpr:
            case NodeKind.Comprehension:
            case NodeKind.SwitchStmt:
            case NodeKind.LoopExpr:
            case NodeKind.TypeOfExpr:
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
            case NodeKind.ForStmt:
            case NodeKind.DoStmt:
            case NodeKind.BreakStmt:
            case NodeKind.ContinueStmt:
                err.error(node.pos,
                        "Esse recurso ainda não é suportado na avaliação em tempo de compilação.");
                return false;
            case NodeKind.Identifier:
                if ((cast(Identifier) node).functionRef !is null)
                {
                    err.error(node.pos,
                            "Valor de função ainda não é representável na avaliação em tempo de compilação.");
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

                if (binary.op == TokenKind.And || binary.op == TokenKind.Or
                        || binary.op == TokenKind.Coalesce || binary.op == TokenKind.Pow || binary.op == TokenKind.In)
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
                return nodeAnalysis(var.value);

            case NodeKind.AssignStmt:
                AssignStmt ass = cast(AssignStmt) node;
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

            case NodeKind.ArrayLit:
            case NodeKind.IndexExpr:
            case NodeKind.MemberExpr:

                err.error(node.pos, "Essa expressão não é pura.");
                return false;
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
        Identifier identifier = cast(Identifier) node.fn;
        if (identifier is null || identifier.functionRef is null)
        {
            err.error(node.pos,
                    "Chamada indireta/método ainda não é suportada na avaliação em tempo de compilação.");
            return false;
        }
        dstring name = identifier.value;
        Symbol* sym = context.get(name);
        if (sym is null || !sym.isFn() || (cast(SymbolFn*) sym).node !is identifier.functionRef)
        {
            err.error(node.pos, "Identidade da função não disponível na avaliação em tempo de compilação.");
            return false;
        }
        SymbolFn* symf = cast(SymbolFn*) sym;
        if (symf.node.ctfe_flags & CTFEFlags.Pure)
        {
            bool valid = true;
            foreach (Node arg; node.args)
                if (!nodeAnalysis(arg))
                    valid = false;
            return valid;
        }

        err.error(node.pos, format("A função '%s' não é marcada pura.", name));

        if (!symf.isRuntime)
            err.hint(symf.node.pos, format("A função '%s' foi definida aqui.", name));

        return false;
    }

public:
    this(Context context, Diagnostics err, CTFEContext ctfe)
    {
        this.context = context;
        this.err = err;
        this.compiler = new CTFECompile;
        this.ctfe = ctfe;
    }

    void analysis(Program program)
    {
        FnDecl[] functions = cast(FnDecl[]) program.body.filter!((Node node) => node.kind == NodeKind.FnDecl).array;
        foreach (FnDecl fn; functions)
            analysis(fn);
    }
}
