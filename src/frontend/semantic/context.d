module frontend.semantic.context;

import frontend;

enum SymbolKind
{
    Variable,
    Function,
    Class,
    Lambda,
}

abstract class Symbol
{
    string name;
    SymbolKind kind;
    Loc loc;
    Type type;

    this(string name, SymbolKind kind, Type type, Loc loc)
    {
        this.name = name;
        this.kind = kind;
        this.type = type;
        this.loc = loc;
    }
}

class VarSymbol : Symbol
{
    bool isConst;
    bool isGlobal;

    this(string name, Type type, bool isConst, bool isGlobal, Loc loc)
    {
        super(name, SymbolKind.Variable, type, loc);
        this.isConst = isConst;
        this.isGlobal = isGlobal;
    }
}

class FunctionSymbol : Symbol
{
    Type[] paramTypes;
    Type returnType;
    FuncDecl declaration;
    bool isExternal; // importada de outro módulo

    this(string name, Type[] paramTypes, Type returnType,
        FuncDecl declaration, Loc loc)
    {
        super(name, SymbolKind.Function, returnType, loc);
        this.paramTypes = paramTypes;
        this.returnType = returnType;
        this.declaration = declaration;
        this.isExternal = false;
    }
}

class ClassSymbol : Symbol
{
    Scope memberScope; // Escopo contendo métodos e atributos da classe

    this(string name, Scope memberScope, Type type, Loc loc)
    {
        super(name, SymbolKind.Class, type, loc);
        this.memberScope = memberScope;
    }

    // Busca um membro (propriedade ou método) nesta classe
    Symbol lookupMember(string name)
    {
        if (memberScope is null)
            return null;
        return memberScope.lookupLocal(name); // Busca apenas nos membros diretos
    }
}

class Scope
{
    Scope parent;
    Symbol[string] symbols;
    string name; // para debug

    this(Scope parent, string name = "")
    {
        this.parent = parent;
        this.name = name;
    }

    bool define(Symbol symbol)
    {
        if (symbol.name in symbols)
            return false;

        symbols[symbol.name] = symbol;
        return true;
    }

    Symbol lookupLocal(string name)
    {
        return symbols.get(name, null);
    }

    Symbol lookup(string name)
    {
        Symbol sym = lookupLocal(name);
        if (sym !is null)
            return sym;

        if (parent !is null)
            return parent.lookup(name);

        return null;
    }

    bool isDefined(string name)
    {
        return lookup(name) !is null;
    }
}

class Context
{
    Scope currentScope;
    Scope globalScope;
    FunctionSymbol currentFunction; // função sendo analisada
    bool[] isLambda; // flag pra marcar execução de lambda
    int loopDepth; // para validar break/continue   

    this()
    {
        this.globalScope = new Scope(null, "global");
        this.currentScope = globalScope;
        this.currentFunction = null;
        this.loopDepth = 0;
    }

    void enterScope(string name = "")
    {
        currentScope = new Scope(currentScope, name);
    }

    void exitScope()
    {
        if (currentScope.parent is null)
            throw new Exception("Tentativa de sair do escopo global");
        currentScope = currentScope.parent;
    }

    void enterFunction(FunctionSymbol func)
    {
        currentFunction = func;
        enterScope(format("func:%s", func.name));
    }

    void exitFunction()
    {
        currentFunction = null;
        exitScope();
    }

    void enterLoop()
    {
        loopDepth++;
        enterScope("loop");
    }

    void exitLoop()
    {
        loopDepth--;
        exitScope();
    }

    bool isInLoop()
    {
        return loopDepth > 0;
    }

    bool isInFunction()
    {
        return currentFunction !is null;
    }

    bool isInLambda()
    {
        return isLambda.length > 0;
    }

    bool addSymbol(Symbol symbol)
    {
        return currentScope.define(symbol);
    }

    bool addVariable(string name, Type type, bool isConst, Loc loc)
    {
        auto sym = new VarSymbol(name, type, isConst,
            currentScope == globalScope, loc);
        return addSymbol(sym);
    }

    bool addFunction(FunctionSymbol func)
    {
        // Funções sempre vão no escopo global (ou do módulo)
        return globalScope.define(func);
    }

    Symbol lookup(string name)
    {
        return currentScope.lookup(name);
    }

    Symbol lookupLocal(string name)
    {
        return currentScope.lookupLocal(name);
    }

    VarSymbol lookupVariable(string name)
    {
        Symbol sym = lookup(name);
        return cast(VarSymbol) sym;
    }

    FunctionSymbol lookupFunction(string name)
    {
        Symbol sym = globalScope.lookup(name);
        return cast(FunctionSymbol) sym;
    }

    bool canAssign(string varName)
    {
        VarSymbol var = lookupVariable(varName);
        if (var is null)
            return false;
        return !var.isConst;
    }

    bool isDefined(string name)
    {
        return currentScope.isDefined(name);
    }

    void dump()
    {

        writeln("=== CONTEXT DUMP ===");
        dumpScope(globalScope, 0);
    }

    void dumpScope(Scope scope_, int indent)
    {
        string prefix = " ".replicate(indent * 2);
        writefln("%sScope: %s", prefix, scope_.name);
        Type type;

        foreach (name, sym; scope_.symbols)
        {
            if (sym.kind == SymbolKind.Function)
                type = (cast(FunctionSymbol) sym).returnType;
            else
                type = sym.type;
            writefln("%s  - %s: %s (%s)",
                prefix, name, sym.kind,
                type !is null ? type.toStr() : "no-type");
        }
    }
}
