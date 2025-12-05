module frontend.semantic.semantic2;

import frontend;
import common.reporter;

// ============================================================
// SEMANTIC2 - Segunda Passada
// Objetivo: Resolver todos os tipos
//   - Tipos de variáveis globais
//   - Assinaturas de funções (params + return)
//   - Campos de classes/structs
//   - Validar valores default/init
// Ainda não analisa corpos de funções!
// ============================================================

class Semantic2
{
    Context ctx;
    TypeResolver resolver;
    DiagnosticError error;

    this(Context ctx, DiagnosticError error)
    {
        this.ctx = ctx;
        this.error = error;
        this.resolver = new TypeResolver(ctx, error);
    }

    void analyze(Program program)
    {
        foreach (node; program.body)
            resolveDeclaration(node);
    }

    void resolveDeclaration(Node node)
    {
        if (auto varDecl = cast(VarDecl) node)
            resolveVarDecl(varDecl);
        else if (auto funcDecl = cast(FuncDecl) node)
            resolveFunctionDecl(funcDecl);
        else if (auto type = cast(TypeDecl) node)
            resolveTypeDecl(type);
        else if (auto assign = cast(AssignDecl) node)
            resolveAssignDecl(assign);
    }

    void resolveAssignDecl(AssignDecl decl)
    {
        if (decl.left.kind != NodeKind.Identifier) // erro
            return;

        Identifier id = cast(Identifier) decl.left;
        string name = id.value.get!string;
        VarSymbol sym = ctx.lookupVariable(name);

        if (sym is null)
        {
            error.addError(Diagnostic(
                    format("Variavel não encontrada '%s'.", name),
                    decl.loc
            ));
            return;
        }

        if (sym.isConst)
        {
            error.addError(Diagnostic(
                    "Não é possível alterar o valor de uma constante.",
                    decl.loc
            ));
            return;
        }

        decl.resolvedType = sym.type;
        decl.right.resolvedType = resolver.resolve(decl.right.type);
    }

    void resolveTypeDecl(TypeDecl decl)
    {
        string typename = decl.value.get!string;
        if (resolver.registry.typeExists(typename))
        {
            error.addError(Diagnostic(
                    format("O tipo '%s' já existe.", typename),
                    decl.loc
            ));
            return;
        }
        decl.resolvedType = resolver.resolve(decl.type);
        resolver.registry.registerType(typename, decl.resolvedType);
    }

    // void resolveVarDecl(VarDecl decl)
    // {
    //     decl.resolvedType = resolver.resolve(decl.type);
    //     VarSymbol sym = ctx.lookupVariable(decl.id);
    //     if (sym !is null && decl.resolvedType !is null)
    //         sym.type = decl.resolvedType;
    // }

    void resolveVarDecl(VarDecl decl)
    {
        // Se tem anotação de tipo, resolve
        if (decl.type !is null)
            decl.resolvedType = resolver.resolve(decl.type);
        // Se não tem anotação mas tem inicializador, deixa null para inferir depois
        else if (decl.value.get!Node !is null)
            decl.resolvedType = null; // será inferido no Semantic3
        // Se não tem nem tipo nem inicializador, erro
        else
        {
            error.addError(Diagnostic(
                    format("Variável '%s' precisa de tipo ou inicializador", decl.id),
                    decl.loc
            ));
            decl.resolvedType = new PrimitiveType(BaseType.Any);
            return;
        }

        VarSymbol sym = ctx.lookupVariable(decl.id);
        if (sym !is null && decl.resolvedType !is null)
            sym.type = decl.resolvedType;
    }

    void resolveFunctionDecl(FuncDecl decl)
    {
        FunctionSymbol funcSym = ctx.lookupFunction(decl.name);
        if (funcSym is null)
        {
            error.addError(Diagnostic(
                    format("Função '%s' não encontrada no contexto", decl.name),
                    decl.loc
            ));
            return;
        }

        Type[] paramTypes;
        foreach (i, ref param; decl.args)
        {
            Type paramType = null;
            paramType = resolver.resolve(param.type);
            paramTypes ~= paramType;
            param.resolvedType = paramType;
        }

        decl.resolvedType = resolver.resolve(decl.type);
        funcSym.paramTypes = paramTypes;
        funcSym.returnType = decl.resolvedType;
    }
}
