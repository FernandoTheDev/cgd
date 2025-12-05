module frontend.semantic.function_analyzer;

import frontend;
import common.reporter;

class FunctionAnalyzer
{
    Context ctx;
    TypeChecker checker;
    DiagnosticError error;
    Semantic3 sema3;

    this(Context ctx, TypeChecker checker, DiagnosticError error, Semantic3 sema3)
    {
        this.ctx = ctx;
        this.checker = checker;
        this.error = error;
        this.sema3 = sema3;
    }

    void analyzeFunction(FuncDecl decl)
    {
        FunctionSymbol funcSym = ctx.lookupFunction(decl.name);
        if (funcSym is null)
            return;

        ctx.enterFunction(funcSym);

        foreach (param; decl.args)
        {
            if (!ctx.addVariable(param.name, param.resolvedType, false, decl.loc))
            {
                error.addError(Diagnostic(
                        format("Parâmetro '%s' duplicado", param.name),
                        decl.loc
                ));
            }
        }

        if (decl.body !is null && decl.body.statements.length >= 0)
        {
            sema3.analyzeBlockStmt(decl.body);
            // Verifica se função não-void tem return
            if (!decl.resolvedType.isVoid())
            {
                if (!sema3.hasReturn(decl.body))
                {
                    error.addError(Diagnostic(
                            format("Função '%s' precisa retornar '%s'",
                            decl.name, decl.resolvedType.toStr()),
                            decl.loc,
                            [
                                Suggestion("Adicione um 'retorna' no final da função")
                            ]
                    ));
                }
            }
        }

        ctx.exitFunction();
    }

    void analyzeLambda(FuncExpr expr)
    {
        TypeResolver resolver = new TypeResolver(ctx, error);
        expr.resolvedType = resolver.resolve(expr.type);

        auto funcType = cast(FunctionType) expr.resolvedType;
        if (funcType is null)
        {
            error.addError(Diagnostic(
                    "Expressão de função deve ter tipo função",
                    expr.loc
            ));
            return;
        }

        Type[] paramTypes;
        foreach (ref param; expr.args)
        {
            param.resolvedType = resolver.resolve(param.type);
            paramTypes ~= param.resolvedType;
        }

        auto lambdaSym = new FunctionSymbol(
            "<lambda>", // nome temporário
            paramTypes,
            funcType.returnType,
            null, // não tem FuncDecl
            expr.loc
        );

        ctx.enterFunction(lambdaSym);

        foreach (ref param; expr.args)
        {
            if (!ctx.addVariable(param.name, param.resolvedType, false, expr.loc))
            {
                error.addError(Diagnostic(
                        format("Parâmetro '%s' duplicado", param.name),
                        expr.loc
                ));
            }
        }

        if (expr.body !is null && expr.body.statements.length >= 0)
        {
            sema3.analyzeBlockStmt(expr.body);
            if (!funcType.returnType.isVoid())
            {
                if (!sema3.hasReturn(expr.body))
                {
                    error.addError(Diagnostic(
                            "Função anônima precisa retornar um valor",
                            expr.loc
                    ));
                }
            }
        }

        ctx.exitFunction();
    }
}
