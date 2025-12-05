module frontend.semantic.semantic3;

import frontend;
import common.reporter;

class Semantic3
{
    Context ctx;
    TypeChecker checker;
    DiagnosticError error;
    FunctionAnalyzer funcAnalyzer;

    this(Context ctx, DiagnosticError error)
    {
        this.ctx = ctx;
        this.error = error;
        this.checker = new TypeChecker(ctx, error);
        this.funcAnalyzer = new FunctionAnalyzer(ctx, this.checker, this.error, this);
        this.checker.funcAnalyzer = this.funcAnalyzer;
    }

    void analyze(Program program)
    {
        foreach (node; program.body)
            analyzeDeclaration(node);
    }

    void analyzeDeclaration(Node node)
    {
        if (auto varDecl = cast(VarDecl) node)
            analyzeVarDecl(varDecl);
        else if (auto funcDecl = cast(FuncDecl) node)
            this.funcAnalyzer.analyzeFunction(funcDecl);
        else if (auto assign = cast(AssignDecl) node)
            analyzeAssignDecl(assign);
        else if (auto _if = cast(IfStmt) node)
            analyzeIfStmt(_if);
        else if (auto call = cast(CallExpr) node)
            checker.checkExpression(call);
        // else if (auto classDecl = cast(ClassDecl) node)
        //     analyzeClassDecl(classDecl);
    }

    void analyzeAssignDecl(AssignDecl decl)
    {
        if (decl.left.kind == NodeKind.Identifier)
        {
            Identifier iden = cast(Identifier) decl.left;
            string id = iden.value.get!string;
            VarSymbol sym = ctx.lookupVariable(id);
            Type initType = checker.checkExpression(decl.right);
            if (decl.resolvedType !is null)
            {
                if (!sym.type.isCompatibleWith(initType))
                {
                    error.addError(Diagnostic(
                            format("Tipo incompatível: esperado '%s', obteve '%s'",
                            sym.type.toStr(), initType.toStr()),
                            decl.right.loc
                    ));
                }
                if (sym !is null)
                    decl.resolvedType = initType;
            }
        }
    }

    void analyzeVarDecl(VarDecl decl)
    {
        // Analisa inicializador
        Node init_ = decl.value.get!Node;
        VarSymbol sym = ctx.lookupVariable(decl.id);
        if (init_ !is null)
        {
            Type initType = checker.checkExpression(init_);
            if (decl.resolvedType !is null)
            {
                import std.stdio;

                if (!decl.resolvedType.isCompatibleWith(initType))
                {
                    error.addError(Diagnostic(
                            format("Tipo incompatível: esperado '%s', obteve '%s'",
                            decl.resolvedType.toStr(), initType.toStr()),
                            init_.loc
                    ));
                }
                if (sym !is null)
                {
                    sym.type = initType;
                    decl.resolvedType = initType;
                }
            }
            else
            {
                // Inferência de tipo
                decl.resolvedType = initType;
                if (sym !is null)
                    sym.type = initType;
            }
        }
        else if (decl.resolvedType is null)
        {
            error.addError(Diagnostic(
                    format("Variável '%s' precisa de tipo ou inicializador", decl.id),
                    decl.loc
            ));
        }
    }

    void analyzeFunctionDecl(FuncDecl decl)
    {
        FunctionSymbol funcSym = ctx.lookupFunction(decl.name);
        if (funcSym is null)
            return;

        // Entra no escopo da função
        ctx.enterFunction(funcSym);
        decl.resolvedType = funcSym.returnType;

        // Adiciona parâmetros ao escopo
        foreach (param; decl.args)
            if (!ctx.addVariable(param.name, param.resolvedType, false, decl.loc))
            {
                error.addError(Diagnostic(
                        format("Parâmetro '%s' duplicado", param.name),
                        decl.loc
                ));
            }

        // Analisa corpo
        if (decl.body.statements.length >= 0)
        {
            analyzeBlockStmt(decl.body);
            if (!decl.resolvedType.isVoid())
            {
                if (!hasReturn(decl.body))
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

    // // ========================================
    // // ANALISA CLASSE
    // // ========================================

    // void analyzeClassDecl(ClassDecl decl)
    // {
    //     // Analisa métodos
    //     foreach (member; decl.members)
    //     {
    //         if (auto method = cast(FunctionDecl) member)
    //         {
    //             analyzeFunctionDecl(method);
    //         }
    //         else if (auto field = cast(VarDecl) member)
    //         {
    //             // Valida inicializador de campo se houver
    //             if (field.init !is null)
    //             {
    //                 analyzeVarDecl(field);
    //             }
    //         }
    //     }
    // }

    void analyzeBlockStmt(BlockStmt stmt)
    {
        ctx.enterScope("block");

        foreach (node; stmt.statements)
            analyzeStatement(node);

        ctx.exitScope();
    }

    void analyzeStatement(Node stmt)
    {
        if (auto varDecl = cast(VarDecl) stmt)
            analyzeVarDecl(varDecl);
        else if (auto ifStmt = cast(IfStmt) stmt)
            analyzeIfStmt(ifStmt);
        // else if (auto whileStmt = cast(WhileStmt) stmt)
        //     analyzeWhileStmt(whileStmt);
        // else if (auto forStmt = cast(ForStmt) stmt)
        //     analyzeForStmt(forStmt);
        else if (auto returnStmt = cast(ReturnStmt) stmt)
            analyzeReturnStmt(returnStmt);
        // else if (auto breakStmt = cast(BreakStmt) stmt)
        //     analyzeBreakStmt(breakStmt);
        // else if (auto continueStmt = cast(ContinueStmt) stmt)
        //     analyzeContinueStmt(continueStmt);
        else if (auto blockStmt = cast(BlockStmt) stmt)
            analyzeBlockStmt(blockStmt);
    }

    void analyzeIfStmt(IfStmt stmt)
    {
        // Verifica condição
        if (stmt.condition !is null)
        {
            Type condType = checker.checkExpression(stmt.condition);
            stmt.condition.resolvedType = condType;

            if (!condType.isCompatibleWith(new PrimitiveType(BaseType.Bool)))
            {
                error.addError(Diagnostic(
                        format("Condição do 'if' deve ser lógica, obteve '%s'",
                        condType.toStr()),
                        stmt.condition.loc
                ));
            }
        }

        // Analisa branches
        if (stmt.thenBranch !is null)
            analyzeStatement(stmt.thenBranch);
        if (stmt.elseBranch !is null)
            analyzeStatement(stmt.elseBranch);
    }

    // void analyzeWhileStmt(WhileStmt stmt)
    // {
    //     // Verifica condição
    //     Type condType = checker.checkExpression(stmt.condition);
    //     if (!condType.isCompatibleWith(new PrimitiveType(BaseType.Bool)))
    //     {
    //         error.addError(Diagnostic(
    //                 format("Condição do 'while' deve ser lógica, obteve '%s'",
    //                 condType.toStr()),
    //                 stmt.condition.loc
    //         ));
    //     }

    //     // Analisa corpo
    //     ctx.enterLoop();
    //     analyzeStatement(stmt.body);
    //     ctx.exitLoop();
    // }

    // void analyzeForStmt(ForStmt stmt)
    // {
    //     ctx.enterScope("for");

    //     // Analisa inicializador
    //     if (stmt.init !is null)
    //         analyzeStatement(stmt.init);

    //     // Analisa condição
    //     if (stmt.condition !is null)
    //     {
    //         Type condType = checker.checkExpression(stmt.condition);
    //         if (!condType.isCompatibleWith(new PrimitiveType(BaseType.Bool)))
    //         {
    //             error.addError(Diagnostic(
    //                     "Condição do 'for' deve ser lógica",
    //                     stmt.condition.loc
    //             ));
    //         }
    //     }

    //     // Analisa incremento
    //     if (stmt.increment !is null)
    //         checker.checkExpression(stmt.increment);

    //     // Analisa corpo
    //     ctx.enterLoop();
    //     analyzeStatement(stmt.body);
    //     ctx.exitLoop();

    //     ctx.exitScope();
    // }

    void analyzeReturnStmt(ReturnStmt stmt)
    {
        if (!ctx.isInFunction())
        {
            error.addError(Diagnostic(
                    "'retorne' fora de função",
                    stmt.loc
            ));
            return;
        }

        Type returnType = stmt.value ?
            checker.checkExpression(stmt.value) : VoidType.instance();
        Type expectedType = ctx.currentFunction.returnType;

        if (!expectedType.isCompatibleWith(returnType))
        {
            error.addError(Diagnostic(
                    format("Tipo de retorno incompatível: esperado '%s', obteve '%s'",
                    expectedType.toStr(), returnType.toStr()),
                    stmt.loc
            ));
        }
    }

    // void analyzeBreakStmt(BreakStmt stmt)
    // {
    //     if (!ctx.isInLoop())
    //     {
    //         error.addError(Diagnostic(
    //                 "'pare' fora de loop",
    //                 stmt.loc,
    //                 [
    //                     Suggestion("'pare' só pode ser usado dentro de 'enquanto' ou 'para'")
    //                 ]
    //         ));
    //     }
    // }

    // void analyzeContinueStmt(ContinueStmt stmt)
    // {
    //     if (!ctx.isInLoop())
    //     {
    //         error.addError(Diagnostic(
    //                 "'continue' fora de loop",
    //                 stmt.loc,
    //                 [
    //                     Suggestion("'continue' só pode ser usado dentro de 'enquanto' ou 'para'")
    //                 ]
    //         ));
    //     }
    // }

    bool hasReturn(BlockStmt block)
    {
        foreach (stmt; block.statements)
        {
            if (cast(ReturnStmt) stmt)
                return true;

            // Verifica em if/else
            if (auto ifStmt = cast(IfStmt) stmt)
            {
                if (ifStmt.elseBranch !is null)
                {
                    bool thenHas = false, elseHas = false;

                    if (auto thenBlock = cast(BlockStmt) ifStmt.thenBranch)
                        thenHas = hasReturn(thenBlock);

                    if (auto elseBlock = cast(BlockStmt) ifStmt.elseBranch)
                        elseHas = hasReturn(elseBlock);

                    if (thenHas && elseHas)
                        return true;
                }
            }
        }
        return false;
    }
}
