module frontend.semantic.context;

import std.exception : enforce;

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
}

class Context
{
private:
    public Scope[] scopes;
    size_t[] functionBoundaries;

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
}
