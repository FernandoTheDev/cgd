module frontend.semantic.context;

import std.exception : enforce;
import std.algorithm;

import frontend.semantic;
import frontend.parser.ast : VarDecl;

class Scope
{
private:
    Symbol[dstring] symbols;

public:
    Symbol* get(dstring name)
    {
        return name in symbols;
    }

    bool set(dstring name, Symbol sym)
    {
        if (name in symbols)
            return false;
        symbols[name] = sym;
        return true;
    }

    dstring[] names() const
    {
        return symbols.keys;
    }

    void remove(dstring name)
    {
        symbols.remove(name);
    }
}

class Context
{
private:
    public Scope[] scopes;
    size_t[] functionBoundaries;

    size_t levenshtein(dstring a, dstring b)
    {
        // Duas linhas em vez de uma matriz por candidato: memória O(min(n,m)).
        if (a.length > b.length)
        {
            dstring temp = a;
            a = b;
            b = temp;
        }
        size_t[] previous = new size_t[a.length + 1];
        size_t[] current = new size_t[a.length + 1];
        foreach (size_t i; 0 .. previous.length)
            previous[i] = i;
        foreach (size_t j; 1 .. b.length + 1)
        {
            current[0] = j;
            foreach (size_t i; 1 .. a.length + 1)
                current[i] = min(current[i - 1] + 1, previous[i] + 1, previous[i - 1] + (a[i - 1] == b[j - 1] ? 0 : 1));
            size_t[] temp = previous;
            previous = current;
            current = temp;
        }
        return previous[a.length];
    }

public:
    size_t cursor;

    void push()
    {
        scopes ~= new Scope;
        cursor = cast(size_t) scopes.length - 1;
    }

    void pop()
    {
        enforce(scopes.length > 0, "pop em escopo vazio.");
        scopes.length--;
        cursor = cast(size_t) scopes.length - 1;
    }

    void pushFunction()
    {
        functionBoundaries ~= scopes.length;
        push();
    }

    void popFunction()
    {
        functionBoundaries.length--;
        pop();
    }

    void enter()
    {
        enforce(cursor + 1 < scopes.length, "enter: sem escopo filho.");
        cursor++;
    }

    void leave()
    {
        enforce(cursor > 0, "leave: já no topo.");
        cursor--;
    }

    Symbol* get(dstring name)
    {
        size_t limit = functionBoundaries.length > 0 ? functionBoundaries[$ - 1] : 0;

        foreach_reverse (size_t i, Scope sc; scopes[0 .. cursor + 1])
        {
            if (i < limit)
                break;
            if (Symbol* sym = sc.get(name))
                return sym;
        }
        // Funções globais não precisam capturar o ambiente externo.
        foreach_reverse (Scope sc; scopes[0 .. limit])
            if (Symbol* sym = sc.get(name))
                return sym.isFn() ? sym : null;
        return null;
    }

    /// Só os membros escalares são reutilizados; nunca captura o mapa do enum.
    VarDecl enumDeclaration(dstring name)
    {
        foreach_reverse (Scope scopeEntry; scopes[0 .. cursor + 1])
            if (Symbol* symbol = scopeEntry.get(name))
                return symbol.isVar() && (cast(SymbolVar)*symbol).node.isEnum ? (cast(SymbolVar)*symbol).node : null;
        return null;
    }

    bool requiresCapture(dstring name)
    {
        if (!functionBoundaries.length)
            return false;
        size_t limit = functionBoundaries[$ - 1];
        foreach_reverse (Scope sc; scopes[0 .. limit])
            if (Symbol* sym = sc.get(name))
                return !sym.isFn();
        return false;
    }

    Symbol* getLocal(dstring name)
    {
        return scopes[cursor].get(name);
    }

    bool set(dstring name, Symbol sym)
    {
        enforce(scopes.length > 0, "nenhum escopo ativo.");
        return scopes[cursor].set(name, sym);
    }

    dstring suggest(dstring name, size_t maxDistance = size_t.max)
    {
        size_t limit = functionBoundaries.length > 0 ? functionBoundaries[$ - 1] : 0;

        if (maxDistance == size_t.max)
            maxDistance = max(3, name.length / 3);

        if (name.length > 128)
            return null;
        dstring melhor;
        size_t menorDist = size_t.max;

        foreach_reverse (size_t i, Scope sc; scopes[0 .. cursor + 1])
        {
            if (i < limit)
                break;

            foreach (dstring candidato; sc.names())
            {
                if (candidato.length > 128 || candidato == name)
                    continue; // não sugere ele mesmo

                size_t d = levenshtein(name, candidato);
                if (d < menorDist || (d == menorDist && candidato < melhor))
                {
                    menorDist = d;
                    melhor = candidato;
                }
            }
        }

        return menorDist <= maxDistance ? melhor : null;
    }

    void remove(dstring name)
    {
        enforce(scopes.length > 0, "nenhum escopo ativo.");
        return scopes[cursor].remove(name);
    }
}
