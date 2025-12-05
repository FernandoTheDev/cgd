module frontend.semantic.semantic1;

import frontend;
import common.reporter;

// ============================================================
// SEMANTIC1 - Primeira Passada
// Objetivo: Coletar todas as declarações top-level
//   - Funções
//   - Classes
//   - Structs
//   - Enums
//   - Variáveis globais
// Não analisa corpos ainda!
// ============================================================

class Semantic1
{
    Context ctx;
    DiagnosticError error;

    this(Context ctx, DiagnosticError error)
    {
        this.ctx = ctx;
        this.error = error;
    }

    pragma(inline, true)
    void reportError(string message, Loc loc, Suggestion[] suggestions = null)
    {
        error.addError(Diagnostic(message, loc, suggestions));
    }

    void analyze(Program program)
    {
        foreach (node; program.body)
            collectDeclaration(node);
    }

    void collectDeclaration(Node node)
    {
        if (auto varDecl = cast(VarDecl) node)
            collectVarDecl(varDecl);
        else if (auto funcDecl = cast(FuncDecl) node)
            collectFunctionDecl(funcDecl);
    }

    void collectVarDecl(VarDecl decl)
    {
        if (ctx.isDefined(decl.id))
        {
            reportError(format("Redefinição de '%s'", decl.id), decl.loc);
            return;
        }

        // Adiciona símbolo temporário (tipo será resolvido no semantic2)
        // Por enquanto, usa tipo "qualquer" ou null
        Type tempType = null;
        if (!ctx.addVariable(decl.id, tempType, decl.isConst, decl.loc))
            reportError(format("Erro ao adicionar variável '%s'", decl.id), decl.loc);
    }

    void collectFunctionDecl(FuncDecl decl)
    {
        // Verifica redefinição
        if (ctx.isDefined(decl.name))
        {
            reportError(format("Redefinição de função '%s'", decl.name), decl.loc);
            return;
        }

        // Tipos dos parâmetros serão resolvidos no semantic2
        // Por enquanto, cria símbolo vazio
        Type[] paramTypes;
        foreach (param; decl.args)
            paramTypes ~= null; // será preenchido depois

        Type returnType = null; // será preenchido depois

        auto funcSym = new FunctionSymbol(
            decl.name,
            paramTypes,
            returnType,
            decl,
            decl.loc
        );

        if (!ctx.addFunction(funcSym))
            reportError(format("Erro ao adicionar função '%s'", decl.name), decl.loc);
    }
}
