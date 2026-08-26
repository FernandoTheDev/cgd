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
            err.error(fn.pos, 
                format("A função '%s' foi marcada como pura mas após uma análise a pureza não foi detectada.", name));

        return status;
    }

    bool nodeAnalysis(Node node)
    {
        final switch (node.kind)
        {
            case NodeKind.Identifier:
            
            case NodeKind.NaN:
            case NodeKind.StringLit:
            case NodeKind.IntLit:
            case NodeKind.DoubleLit:
            case NodeKind.BoolLit:
            case NodeKind.TypeOfExpr:
            case NodeKind.Program:
                return true;

            case NodeKind.BinaryExpr:
                BinaryExpr binary = cast(BinaryExpr) node;
                return (nodeAnalysis(binary.left) == true) && (nodeAnalysis(binary.right) == true);
            
            case NodeKind.UnaryExpr:
                UnaryExpr un = cast(UnaryExpr) node;
                return nodeAnalysis(un.value);

            case NodeKind.FnDecl:
                return nodeAnalysisBlockStmt((cast(FnDecl) node).body);

            case NodeKind.VarDecl:
                VarDecl var = cast(VarDecl) node;
                return nodeAnalysis(var.value);

            case NodeKind.AssignStmt:
                AssignStmt ass = cast(AssignStmt) node;
                return (nodeAnalysis(ass.left) == true) && (nodeAnalysis(ass.value) == true);

            case NodeKind.BlockStmt:
                return nodeAnalysisBlockStmt(cast(BlockStmt) node);

            case NodeKind.ReturnStmt:
                return nodeAnalysis((cast(ReturnStmt) node).val);
            
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
        bool expr = nodeAnalysis(node.expr);
        if (!expr) return false;
        return nodeAnalysisBlockStmt(node.body);
    }

    bool nodeAnalysisIfStmt(IfStmt node)
    {
        bool expr = nodeAnalysis(node.expr);
        if (!expr) return false;

        if (!nodeAnalysisBlockStmt(node.body))
            return false;

        // TODO: else

        return true;
    }

    bool nodeAnalysisBlockStmt(BlockStmt node) => nodeAnalysisBlockStmt(node.body);

    bool nodeAnalysisBlockStmt(Node[] body)
    {
        bool ret = true;
        foreach (Node child; body)
            if (!nodeAnalysis(child) && ret) ret = false;
        return ret;
    }

    bool nodeAnalysisCallExpr(CallExpr node)
    {
        dstring name = (cast(Identifier) node.fn).value;
        Symbol* sym = context.get(name);

        if (sym is null || !sym.isFn())
        {
            err.error(node.pos, format("A função '%s' não foi encontrada.", name));
            return false;
        }

        SymbolFn* symf = cast(SymbolFn*) sym;
        if (symf.node.ctfe_flags & CTFEFlags.Pure)
            return true;

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
        FnDecl[] functions = cast(FnDecl[]) program.body.filter!(node => node.kind == NodeKind.FnDecl).array;
        foreach (FnDecl fn; functions)
            analysis(fn);
    }
}
