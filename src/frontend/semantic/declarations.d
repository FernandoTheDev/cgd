// Declara símbolos e nomes de tipos antes de analisar os corpos.
module frontend.semantic.declarations;

import std.exception;
import std.format;

import frontend.semantic;
import frontend.parser;
import frontend.lexer;
import frontend;
import errors;
import utils;

class DeclarationAnalysis
{
private:
    Context context;
    TypeRegistry registry;
    Diagnostics err;

    void analyze(Node node)
    {
        switch (node.kind)
        {
            case NodeKind.VarDecl:
                VarDecl enumeration = cast(VarDecl) node;
                if (enumeration.isEnum)
                {
                    if (!registry.declareEnum(enumeration.name))
                        err.error(node.pos, "Nome de enum conflita com tipo existente.");
                }
                return;
            case NodeKind.ClassDecl:
                ClassDecl c = cast(ClassDecl) node;
                registry.set(c.name, new TypeSemaClass(c));
                registry.rememberClass(c);
                foreach (dstring name; [
                    "Objeto"d, "Excecao"d, "texto"d, "numero"d, "número"d, "inteiro"d, "real"d,
                    "decimal"d, "longo"d, "logico"d, "lógico"d, "booleano"d, "binario"d, "binário"d,
                    "qualquer"d, "tupla"d, "dicionario"d, "dicionário"d, "vazio"d, "Promessa"d,
                    "ci8"d, "cu8"d, "ci16"d, "cu16"d, "ci32"d, "cu32"d, "ci64"d, "cu64"d,
                    "cchar"d, "cschar"d, "cuchar"d,
                    "cshort"d, "cushort"d, "cint"d, "cuint"d, "clong"d, "culong"d, "csize"d,
                    "cf32"d, "cf64"d, "cfloat"d, "cdouble"d, "cbool"d
                ])
                    if (c.name == name)
                        err.error(c.pos, "Nome de tipo nativo reservado.");
                if (!context.set(c.name, new SymbolFn(c.signature)))
                    err.error(c.pos, "Classe duplicada neste escopo.");
                return;
            case NodeKind.FnDecl:
                return analyzeFnDecl(as!FnDecl(node));
            default:
                return;
        }
    }

    void analyzeFnDecl(FnDecl node)
    {
        dstring name = node.fn;
        if (Symbol* sym = context.getLocal(name))
        {
            err.error(node.pos, format("%s '%s' já existe.", ternary(sym.isFn(), "A função", "O simbolo"), name));
            alreadyDeclaredHere(name, getPosFromSymbol(sym), err);
        }
        context.set(name, new SymbolFn(node));
    }

    void addStdFunctions()
    {
        import frontend.natives : cgdNativeNames, cgdNativeArities, cgdNativeReturns, cgdNativeParameters;

        TypeExpr nativeType(dstring name)
        {
            if (name.length >= 2 && name[$ - 2 .. $] == "[]")
                return new TypeExprArray(new TypeExprNamed(name[0 .. $ - 2], null), null);
            return new TypeExprNamed(name, null);
        }

        foreach (size_t i, immutable(dstring) name; cgdNativeNames)
        {
            FnArg[] args;
            foreach (immutable(dstring) parameter; cgdNativeParameters[i])
            {
                import std.array : split;

                dstring[] parts = parameter.split(":"d);
                args ~= new FnArg(parts[0], nativeType(parts[1]), null, null);
            }
            context.set(name, new SymbolFn(new FnDecl(name, args, nativeType(cgdNativeReturns[i]), [
            ], 0, null), true));
        }
        foreach (dstring name; ["Objeto"d, "Excecao"d])
        {
            ClassDecl c = new ClassDecl(name, "", null);
            c.signature.builtinName = name;
            if (name == "Excecao")
                c.signature.args = [
                new FnArg("mensagem", new TypeExprNamed("texto", null), null, null)
            ];
            context.set(name, new SymbolFn(c.signature));
        }
        ClassDecl promise = new ClassDecl("Promessa", "", null);
        promise.isAbstract = true;
        promise.signature.builtinName = "Promessa";
        foreach (dstring name; [
            "resolvida"d, "rejeitada"d, "todas"d, "corrida"d, "qualquer"d, "todasResolvidas"d
        ])
        {
            bool collection = name != "resolvida" && name != "rejeitada";
            TypeExpr anyType = new TypeExprNamed("qualquer", null);
            TypeExpr result = name == "todas" || name == "todasResolvidas" ? new TypeExprArray(anyType, null) : anyType;
            FnArg argument = new FnArg(collection ? "promessas" : "valor", collection
                    ? new TypeExprArray(anyType, null) : anyType, null, null);
            FnDecl method = new FnDecl(name, [argument], new TypeExprPromise(result, null), [], 0, null);
            method.isMethod = true;
            method.isStatic = true;
            method.ownerClass = promise;
            promise.methods ~= method;
        }
        context.set("Promessa", new SymbolFn(promise.signature));
        ClassDecl compilacao = new ClassDecl("Compilacao", "", null);
        compilacao.isAbstract = true;
        compilacao.signature.builtinName = "Compilacao";
        foreach (dstring[2] spec; [
            ["sistemaOperacional"d, "texto"d],
            ["arquitetura"d, "texto"d],
            ["tamanhoPonteiro"d, "inteiro"d],
            ["abi"d, "texto"d],
            ["compiladorC"d, "texto"d],
            ["modo"d, "texto"d]
        ])
        {
            FnDecl m = new FnDecl(spec[0], [], new TypeExprNamed(spec[1], null), [], 1, null);
            m.isMethod = true;
            m.isStatic = true;
            m.ownerClass = compilacao;
            compilacao.methods ~= m;
        }
        FnDecl temRecurso = new FnDecl("temRecurso",
                [new FnArg("nome", new TypeExprNamed("texto", null), null, null)],
                new TypeExprNamed("logico", null), [], 1, null);
        temRecurso.isMethod = true;
        temRecurso.isStatic = true;
        temRecurso.ownerClass = compilacao;
        compilacao.methods ~= temRecurso;
        context.set("Compilacao", new SymbolFn(compilacao.signature));
        context.set("Compilação", new SymbolFn(compilacao.signature));

        ClassDecl matematica = new ClassDecl("Matematica", "", null);
        matematica.isAbstract = true;
        matematica.signature.builtinName = "Matematica";
        foreach (dstring mname; [
            "raiz"d, "seno"d, "cosseno"d, "tangente"d, "absoluto"d, "piso"d, "teto"d,
            "arredondar"d, "logaritmo"d, "exponencial"d, "arcoSeno"d, "arcoCosseno"d, "arcoTangente"d
        ])
        {
            FnDecl m = new FnDecl(mname,
                    [new FnArg("x", new TypeExprNamed("cf64", null), null, null)],
                    new TypeExprNamed("cf64", null), [], 0, null);
            m.isMethod = true;
            m.isStatic = true;
            m.isNative = true;
            m.ownerClass = matematica;
            matematica.methods ~= m;
        }
        foreach (dstring mname; [
            "potencia"d, "potência"d, "minimo"d, "mínimo"d, "maximo"d, "máximo"d, "arcoTangente2"d
        ])
        {
            FnDecl m = new FnDecl(mname, [
                new FnArg("a", new TypeExprNamed("cf64", null), null, null),
                new FnArg("b", new TypeExprNamed("cf64", null), null, null)
            ], new TypeExprNamed("cf64", null), [], 0, null);
            m.isMethod = true;
            m.isStatic = true;
            m.isNative = true;
            m.ownerClass = matematica;
            matematica.methods ~= m;
        }
        context.set("Matematica", new SymbolFn(matematica.signature, true));
        context.set("Matemática", new SymbolFn(matematica.signature, true));
        FnArg condition = new FnArg("condicao", new TypeExprNamed("qualquer", null), null, null);
        FnArg message = new FnArg("mensagem", new TypeExprNamed("texto", null),
                new StringLit("A asserção falhou.", null), null);
        context.set("assercao", new SymbolFn(new FnDecl("assercao", [condition, message],
                new TypeExprNamed("vazio", null), [], 0, null), true));
        FnArg failure = new FnArg("erro", new TypeExprNamed("qualquer", null), null, null);
        context.set("falhar", new SymbolFn(new FnDecl("falhar", [failure],
                new TypeExprNamed("qualquer", null), [], 0, null), true));
        foreach (dstring name; [
            "tamanho"d, "inteiro"d, "numero"d, "número"d, "real"d, "texto"d, "tupla"d, "clonar"d,
            "decoradores"d
        ])
        {
            FnArg arg = new FnArg("valor", new TypeExprNamed("qualquer", null), null, null);
            dstring result = name == "clonar" || name == "decoradores" ? "qualquer"d : name == "texto"
                ? "texto"d : name == "tupla" ? "tupla"d : name == "real" || name == "numero"
                || name == "número" ? "real"d : "numero"d;
            context.set(name, new SymbolFn(new FnDecl(name, [arg], new TypeExprNamed(result, null), [
            ], 0, null), true));
        }
        foreach (dstring name; ["mapear"d, "filtrar"d, "paraCada"d, "todosEmCondicao"d])
        {
            FnArg a = new FnArg("vetor", new TypeExprNamed("qualquer", null), null, null);
            FnArg b = new FnArg("funcao", new TypeExprNamed("funcao", null), null, null);
            context.set(name, new SymbolFn(new FnDecl(name, [a, b], new TypeExprNamed("qualquer",
                    null), [], 0, null), true));
        }
        FnArg sortable = new FnArg("vetor", new TypeExprNamed("qualquer", null), null, null);
        FnArg comparator = new FnArg("comparador", new TypeExprNamed("qualquer", null), new NullLit(null), null);
        context.set("ordenar", new SymbolFn(new FnDecl("ordenar", [sortable, comparator],
                new TypeExprNamed("qualquer", null), [], 0, null), true));
        FnArg prompt = new FnArg("mensagem", new TypeExprNamed("texto", null), new StringLit("", null), null);
        context.set("leia", new SymbolFn(new FnDecl("leia", [prompt], new TypeExprNamed("texto",
                null), [], 0, null), true));
        context.set("aleatorio", new SymbolFn(new FnDecl("aleatorio", [], new TypeExprNamed("real",
                null), [], 0, null), true));
        FnArg minArg = new FnArg("minimo", new TypeExprNamed("numero", null), null, null);
        FnArg maxArg = new FnArg("maximo", new TypeExprNamed("numero", null), null, null);
        context.set("aleatorioEntre", new SymbolFn(new FnDecl("aleatorioEntre", [minArg, maxArg],
                new TypeExprNamed("numero", null), [], 0, null), true));
        context.set("escreva", new SymbolFn(new FnDecl("escreva", [], new TypeExprNamed("vazio",
                Position.init), [], 0, Position.init), true));
        foreach (dstring ctype; [
            "ci8"d, "cu8"d, "ci16"d, "cu16"d, "ci32"d, "cu32"d, "ci64"d, "cu64"d,
            "cchar"d, "cschar"d, "cuchar"d,
            "cshort"d, "cushort"d, "cint"d, "cuint"d, "clong"d, "culong"d, "csize"d,
            "cf32"d, "cf64"d, "cfloat"d, "cdouble"d, "cbool"d
        ])
        {
            FnArg arg = new FnArg("valor", new TypeExprNamed("qualquer", null), null, null);
            FnDecl castFn = new FnDecl(ctype, [arg], new TypeExprNamed(ctype, null), [], 0, null);
            castFn.builtinName = ctype;
            castFn.isNative = true;
            context.set(ctype, new SymbolFn(castFn, true));
        }
        foreach (dstring cname; [
            "VetorNativo"d, "MapaNativo"d, "FatiaNativa"d, "StringNativa"d, "VisaoTexto"d,
            "ResultadoNativo"d, "OpcionalNativo"d, "MatrizNativa"d
        ])
        {
            ClassDecl cdecl = new ClassDecl(cname, "", null);
            cdecl.signature.builtinName = cname;
            cdecl.signature.isNative = true;
            context.set(cname, new SymbolFn(cdecl.signature, true));
        }
    }

public:
    this(Context context, TypeRegistry registry, Diagnostics err)
    {
        this.context = context;
        this.registry = registry;
        this.err = err;
    }

    private void ensureModuleAnalyzed(ModuleUnit unit)
    {
        if (unit is null || unit.analyzed)
            return;
        unit.analyzed = true;
        Context ctx = new Context;
        TypeRegistry types = new TypeRegistry;
        new DeclarationAnalysis(ctx, types, err).analyze(unit.program);
        if (!err.hasErrors())
            new SemanticAnalyzer(ctx, types, new TypeResolver(types, err), err).analyze(unit.program);
    }

    private void registerTopLevelImport(Node node)
    {
        if (ImportExpr imported = cast(ImportExpr) node)
        {
            if (imported.target is null || !imported.isStatementImport)
                return;
            ensureModuleAnalyzed(imported.target);
            if (imported.aliasName.length)
            {
                registry.registerModuleAlias(imported.aliasName, imported.target);
                if (!context.set(imported.aliasName, new SymbolModule(imported.aliasName, imported.target, imported.pos)))
                    err.error(imported.pos, format("O símbolo '%s' já existe neste escopo.", imported.aliasName));
            }
            else if (imported.modulePath.length)
            {
                registry.registerQualifiedModule(imported.modulePath, imported.target);
                dstring root = imported.modulePath[0];
                Symbol* existing = context.getLocal(root);
                if (existing is null)
                {
                    ModuleUnit direct = imported.modulePath.length == 1 ? imported.target : null;
                    context.set(root, new SymbolModule(root, direct, imported.pos));
                }
                else if (!existing.isModule())
                {
                    err.error(imported.pos, format("O namespace '%s' conflita com símbolo existente.", root));
                }
                else if (imported.modulePath.length == 1)
                {
                    SymbolModule existingMod = cast(SymbolModule)*existing;
                    if (existingMod.target is null)
                        existingMod.target = imported.target;
                }
            }
            return;
        }
        if (VarDecl varDecl = cast(VarDecl) node)
        {
            if (ImportExpr varImport = cast(ImportExpr) varDecl.value)
            {
                if (varImport.target !is null)
                {
                    ensureModuleAnalyzed(varImport.target);
                    registry.registerModuleAlias(varDecl.name, varImport.target);
                }
            }
        }
    }

    void analyze(Program program)
    {
        context.push();
        addStdFunctions();
        context.push();
        foreach (Node node; program.body)
            registerTopLevelImport(node);
        foreach (Node node; program.body)
            analyze(node);
    }
}
