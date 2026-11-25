module frontend.semantic.symbol;

import frontend.parser.ast;
import frontend.lexer.token : Position;

enum SymbolKind : ubyte
{
    Var,
    Fn,
    Param,
    Module,
}

abstract class Symbol
{
    SymbolKind kind;
    long uses;
    bool isVar() => kind == SymbolKind.Var;
    bool isFn() => kind == SymbolKind.Fn;
    bool isParam() => kind == SymbolKind.Param;
    bool isModule() => kind == SymbolKind.Module;
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
        if (isRuntime)
            node.builtinName = node.fn;
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

class SymbolModule : Symbol
{
    dstring name;
    ModuleUnit target;
    Position pos;
    this(dstring name, ModuleUnit target, Position pos)
    {
        this.kind = SymbolKind.Module;
        this.name = name;
        this.target = target;
        this.pos = pos;
    }
}
