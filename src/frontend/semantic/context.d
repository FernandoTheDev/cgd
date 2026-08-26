module frontend.semantic.context;

import std.exception : enforce;
import std.algorithm;

import frontend.semantic;

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

    auto names() const
    {
        return symbols.byKey();
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
        auto la = a.length, lb = b.length;
        auto dp = new size_t[][](la + 1, lb + 1);

        foreach (i; 0 .. la + 1) dp[i][0] = i;
        foreach (j; 0 .. lb + 1) dp[0][j] = j;

        foreach (i; 1 .. la + 1)
            foreach (j; 1 .. lb + 1)
            {
                size_t custo = a[i - 1] == b[j - 1] ? 0 : 1;
                dp[i][j] = min(
                    dp[i - 1][j] + 1,
                    dp[i][j - 1] + 1,
                    dp[i - 1][j - 1] + custo
                );
            }

        return dp[la][lb];
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
        size_t limit = functionBoundaries.length > 0
            ? functionBoundaries[$ - 1] : 0;

        foreach_reverse (i, sc; scopes[0 .. cursor + 1])
        {
            if (i < limit) break;
            if (auto sym = sc.get(name)) return sym;
        }
        return null;
    }

    bool set(dstring name, Symbol sym)
    {
        enforce(scopes.length > 0, "nenhum escopo ativo.");
        return scopes[cursor].set(name, sym);
    }

    dstring suggest(dstring name, size_t maxDistance = size_t.max)
    {
        size_t limit = functionBoundaries.length > 0
            ? functionBoundaries[$ - 1] : 0;

        if (maxDistance == size_t.max)
            maxDistance = max(3, name.length / 3);

        dstring melhor;
        size_t menorDist = size_t.max;

        foreach_reverse (i, sc; scopes[0 .. cursor + 1])
        {
            if (i < limit) break;

            foreach (candidato; sc.names())
            {
                if (candidato == name) continue; // não sugere ele mesmo

                auto d = levenshtein(name, candidato);
                if (d < menorDist)
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
