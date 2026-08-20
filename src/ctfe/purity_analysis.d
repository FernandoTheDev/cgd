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
        
        bool status = bodyAnlysis(fn.body);
        dstring name = fn.fn;
        // writefln("A função é pura: %d -> '%s'", status, name);
        
        if (status && name !in ctfe.functions)
            // compila a função
            ctfe.functions[name] = VM(VMContext(), compiler.compile(fn));
        
        if (!status)
            err.error(fn.pos, 
                format("A função '%s' foi marcada como pura mas após uma análise a pureza não foi detectada.", name));

        return status;
    }

    bool bodyAnlysis(Node[] body)
    {
        foreach (Node node; body)
            if (!nodeAnalysis(node)) 
                return false;
        return true;
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

            case NodeKind.BinaryExpr:
            case NodeKind.UnaryExpr:
            case NodeKind.FnDecl:
            case NodeKind.VarDecl:
            case NodeKind.AssignStmt:
            
            case NodeKind.Program:
                return true;

            case NodeKind.ReturnStmt:
                return nodeAnalysis((cast(ReturnStmt) node).val);

            case NodeKind.IfStmt:
            case NodeKind.CallExpr:
                err.error(node.pos, "Essa expressão não é pura.");
                return false;
        }
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
