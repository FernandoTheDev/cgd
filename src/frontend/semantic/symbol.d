module frontend.semantic.symbol;

import frontend.parser.ast;

enum SymbolKind : ubyte
{
    Var,
    Fn,
    Param,
}

abstract class Symbol
{
    SymbolKind kind;
    long uses;
    bool isVar() => kind == SymbolKind.Var;
    bool isFn() => kind == SymbolKind.Fn;
    bool isParam() => kind == SymbolKind.Param;
}

class SymbolVar : Symbol
{
    VarDecl node;
    bool isConstant, isComptime;
    this(VarDecl node, bool isConstant = false, bool isComptime = false)
    {
        this.kind = SymbolKind.Var;
        this.node = node;
        this.isConstant = isConstant;
        this.isComptime = isComptime;
    }
}

class SymbolFn : Symbol
{
    FnDecl node;
    bool isRuntime;
    this(FnDecl node, bool isRuntime = false)
    {
        this.kind = SymbolKind.Fn;
        this.node = node;
        this.isRuntime = isRuntime;
    }
}

class SymbolParam : Symbol
{
    FnArg node;
    this(FnArg node)
    {
        this.kind = SymbolKind.Param;
        this.node = node;
    }
}
