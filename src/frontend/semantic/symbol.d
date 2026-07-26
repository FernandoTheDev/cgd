module frontend.semantic.symbol;

import frontend.parser.ast;

enum SymbolKind : ubyte {
    Var,
    Fn,
    Param,
}

abstract class Symbol {
    SymbolKind kind;
}

class SymbolVar : Symbol {
    VarDecl node;
    this (VarDecl node)
    {
        this.kind = SymbolKind.Var;
        this.node = node;
    }
}

class SymbolFn : Symbol {
    FnDecl node;
    bool isRuntime;
    this (FnDecl node, bool isRuntime = false)
    {
        this.kind = SymbolKind.Fn;
        this.node = node;
        this.isRuntime = isRuntime;
    }
}

class SymbolParam : Symbol {
    FnArg node;
    this (FnArg node)
    {
        this.kind = SymbolKind.Param;
        this.node = node;
    }
}
