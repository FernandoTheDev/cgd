// resolve os simbolos
module frontend.semantic.sema1;

import std.exception;
import std.format;
import std.stdio;

import frontend.semantic;
import frontend.parser;
import frontend.lexer;
import frontend;
import errors;
import utils;

class Sema1
{
private:
    Context context;
    Diagnostics err;

    void analyze(Node node)
    {
        switch (node.kind)
        {
            case NodeKind.ClassDecl:
                ClassDecl c = cast(ClassDecl) node;
                foreach (dstring name; [
                    "Objeto"d, "Excecao"d, "texto"d, "numero"d, "número"d, "inteiro"d, "real"d,
                    "decimal"d, "longo"d, "logico"d, "lógico"d, "booleano"d, "binario"d,
                    "binário"d, "qualquer"d, "tupla"d, "dicionario"d, "dicionário"d, "vazio"d
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
        // writeln(node.args);
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
    }

public:
    this(Context context, Diagnostics err)
    {
        this.context = context;
        this.err = err;
    }

    void analyze(Program program)
    {
        context.push();
        addStdFunctions();
        context.push();
        foreach (Node node; program.body)
            analyze(node);
    }
}
