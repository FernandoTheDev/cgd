module frontend.parser.ast;

import std.stdio;
import frontend.type_sema;
import frontend.type_expr;
import frontend.lexer.token : Position, PosLine, TokenKind;
import std.conv : to;

enum NodeKind : ubyte
{
    // OK
    Program,
    
    Identifier,
    StringLit,
    IntLit,
    DoubleLit,
    
    BinaryExpr,
    UnaryExpr,
    CallExpr,
    TypeOfExpr,
    
    FnDecl,
    VarDecl,

    ReturnStmt,
    IfStmt,

    // TODO
    ForStmt,
    WhileStmt,
}

abstract class Node
{
    NodeKind kind;
    Position pos;
    TypeExpr type_expr;
    TypeSema type_sema;

    void print(uint indent = 0);
}

class Program : Node
{
    Node[] body;

    this(Node[] body)
    {
        this.kind = NodeKind.Program;
        this.body = body;
    }

    override void print(uint indent = 0)
    {
        writeln("Program");
        foreach (i, node; body)
        {
            bool isLast = (i == cast(size_t)
                body.length - 1);
            printIndent(indent, isLast);
            node.print(indent + 1);
        }
    }
}

class VarDecl : Node
{
    dstring name;
    Node value;
    bool isConst;

    this(dstring name, Node value, bool isConst, TypeExpr texpr, Position pos)
    {
        this.kind = NodeKind.VarDecl;
        this.name = name;
        this.value = value;
        this.isConst = isConst;
        this.type_expr = texpr;
        this.pos = pos;
    }

    override void print(uint indent = 0)
    {
        import std.conv : to;

        writef("VarDecl %s '%s'", isConst ? "const" : "var", name);
        if (type_expr !is null)
            writef(" : %s", type_expr.toStr());
        if (type_sema !is null)
            writef(" :> %s", type_sema.toStr());
        writeln();

        if (value !is null)
        {
            printIndent(indent, true);
            value.print(indent + 1);
        }
    }
}

class IntLit : Node
{
    long value;

    this(long val, Position pos)
    {
        this.kind = NodeKind.IntLit;
        value = val;
        this.pos = pos;
        this.type_expr = new TypeExprNamed(TypeSemaBase.Int, pos);
    }

    override void print(uint indent = 0)
    {
        writefln("IntLit(%d)", value);
    }
}

class DoubleLit : Node
{
    double value;

    this(double val, Position pos)
    {
        this.kind = NodeKind.DoubleLit;
        value = val;
        this.pos = pos;
        this.type_expr = new TypeExprNamed(TypeSemaBase.Double, pos);
    }

    override void print(uint indent = 0)
    {
        writefln("DoubleLit(%g)", value);
    }
}

class StringLit : Node
{
    dstring value;

    this(dstring val, Position pos)
    {
        this.kind = NodeKind.StringLit;
        value = val;
        this.pos = pos;
        this.type_expr = new TypeExprNamed(TypeSemaBase.String, pos);
    }

    override void print(uint indent = 0)
    {
        import std.conv : to;

        writefln(`StringLit("%s")`, value);
    }
}

class Identifier : Node
{
    dstring value;

    this(dstring val, Position pos)
    {
        this.kind = NodeKind.Identifier;
        value = val;
        this.pos = pos;
    }

    override void print(uint indent = 0)
    {
        import std.conv : to;

        writefln("Identifier('%s')", value);
    }
}

class BinaryExpr : Node
{
    Node left, right;
    TokenKind op;

    this(Node l, Node r, TokenKind o, Position pos)
    {
        this.kind = NodeKind.BinaryExpr;
        left = l;
        right = r;
        op = o;
        this.pos = pos;
    }

    override void print(uint indent = 0)
    {
        writef("BinaryExpr(%s)", tokenKindStr(op));
        if (type_sema !is null)
            writef(" : %s", type_sema.toStr());
        writeln();
        printIndent(indent, false);
        left.print(indent + 1);
        printIndent(indent, true);
        right.print(indent + 1);
    }
}

class UnaryExpr : Node
{
    Node value;
    TokenKind op;

    this(Node val, TokenKind o, Position pos)
    {
        this.kind = NodeKind.UnaryExpr;
        value = val;
        op = o;
        this.pos = pos;
    }

    override void print(uint indent = 0)
    {
        writef("UnaryExpr(%s)", tokenKindStr(op));
        if (type_sema !is null)
            writef(" : %s", type_sema.toStr());
        writeln();
        printIndent(indent, true);
        value.print(indent + 1);
    }
}

class CallExpr : Node
{
    Node fn;
    Node[] args;

    this(Node fn, Node[] args, Position pos)
    {
        this.kind = NodeKind.CallExpr;
        this.fn = fn;
        this.args = args;
        this.pos = pos;
    }

    override void print(uint indent = 0)
    {
        writef("CallExpr");
        if (type_sema !is null)
            writef(" : %s", type_sema.toStr());
        writeln();
        printIndent(indent, args.length == 0);
        fn.print(indent + 1);
        foreach (i, arg; args)
        {
            bool isLast = (i == cast(size_t) args.length - 1);
            printIndent(indent, isLast);
            arg.print(indent + 1);
        }
    }
}

class FnArg {
    dstring name;
    TypeExpr type_expr;
    TypeSema type_sema;
    Node value;
    Position pos;

    this(dstring name, TypeExpr type_expr, Node value, Position pos)
    {
        this.name = name;
        this.type_expr = type_expr;
        this.value = value;
        this.pos = pos;
    }
}

class FnDecl : Node
{
    dstring fn;
    FnArg[] args;
    Node[] body;

    this(dstring fn, FnArg[] args, TypeExpr type, Node[] body, Position pos)
    {
        this.kind = NodeKind.FnDecl;
        this.fn = fn;
        this.args = args;
        this.type_expr = type;
        this.body = body;
        this.pos = pos;
    }

    override void print(uint indent = 0)
    {
        writef("FnDecl '%s'", fn);
        if (type_expr !is null)
            writef(" : %s", type_expr.toStr());
        if (type_sema !is null)
            writef(" :> %s", type_sema.toStr());
        writeln();

        // argumentos
        foreach (i, arg; args)
        {
            bool isLastArg = (i == cast(size_t) args.length - 1) && body.length == 0;
            printIndent(indent, isLastArg);
            writef("FnArg '%s'", arg.name);
            if (arg.type_expr !is null)
                writef(" : %s", arg.type_expr.toStr());
            if (arg.type_sema !is null)
                writef(" :> %s", arg.type_sema.toStr());
            writeln();
        }

        // corpo
        foreach (i, node; body)
        {
            bool isLast = (i == cast(size_t) body.length - 1);
            printIndent(indent, isLast);
            node.print(indent + 1);
        }
    }
}

class ReturnStmt : Node
{
    Node val;

    this(Node val, Position pos)
    {
        this.kind = NodeKind.ReturnStmt;
        this.val = val;
        this.pos = pos;
    }

    override void print(uint indent = 0)
    {
        writeln("ReturnStmt");
        if (val !is null)
        {
            printIndent(indent, true);
            val.print(indent + 1);
        }
    }
}

class IfStmt : Node
{
    Node expr; // se a expressão for nula então esse node é de um else puro
    Node[] body;
    IfStmt _else; // pode ser 'else' e 'else if'
    bool opt;

    this(Node expr, Node[] body, IfStmt _else, Position pos)
    {
        this.kind = NodeKind.IfStmt;
        this.expr = expr;
        this.body = body;
        this._else = _else;
        this.pos = pos;
    }

    override void print(uint indent = 0)
    {
        if (expr !is null)
        {
            writeln("IfStmt");
            printIndent(indent, body.length == 0 && _else is null);
            expr.print(indent + 1);
        }
        else
        {
            writeln("ElseStmt");
        }

        foreach (i, node; body)
        {
            bool isLast = (i == cast(size_t) body.length - 1) && _else is null;
            printIndent(indent, isLast);
            node.print(indent + 1);
        }

        if (_else !is null)
        {
            printIndent(indent, true);
            _else.print(indent + 1);
        }
    }
}

class TypeOfExpr : Node
{
    Node value;

    this(Node val, Position pos)
    {
        this.kind = NodeKind.TypeOfExpr;
        value = val;
        this.pos = pos;
    }

    override void print(uint indent = 0)
    {
        writeln("TypeOfExpr",);
        if (type_sema !is null)
            writef(" : %s", type_sema.toStr());
        writeln();
        printIndent(indent, true);
        value.print(indent + 1);
    }
}

private void printIndent(uint indent, bool isLast)
{
    foreach (i; 0 .. indent)
        write("│   ");
    write(isLast ? "└── " : "├── ");
}

private void printIndentContinue(uint indent)
{
    foreach (i; 0 .. indent)
        write("│   ");
}

private string tokenKindStr(TokenKind op)
{
    return op.to!string;
}
