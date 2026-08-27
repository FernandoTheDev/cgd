module frontend.parser.ast;

import std.conv : to;
import std.stdio;

import frontend.lexer.token : Position, PosLine, TokenKind;
import frontend.type_sema;
import frontend.type_expr;
import ctfe.ctfe_flags;

enum NodeKind : ubyte
{
    // OK
    Program,
    NaN, // Not a Node
    
    Identifier,
    StringLit,
    IntLit,
    DoubleLit,
    BoolLit,
    ArrayLit,
    
    BinaryExpr,
    UnaryExpr,
    CallExpr,
    TypeOfExpr,
    IndexExpr,
    MemberExpr,
    
    FnDecl,
    VarDecl,

    AssignStmt,
    ReturnStmt,
    IfStmt,
    BlockStmt,
    WhileStmt,

    // TODO
    // ForStmt,
}

abstract class Node
{
    NodeKind kind;
    Position pos;
    TypeExpr type_expr;
    TypeSema type_sema;

    this(NodeKind kind, Position pos = Position.init)
    {
        this.kind = kind;
        this.pos = pos;
    }

    void print(uint indent = 0);
}

class Program : Node
{
    Node[] body;

    this(Node[] body)
    {
        super(NodeKind.Program);
        this.body = body;
    }

    override void print(uint indent = 0)
    {
        writeln("Program");
        foreach (i, node; body)
        {
            bool isLast = (i == cast(size_t) body.length - 1);
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
        super(NodeKind.VarDecl, pos);
        this.name = name;
        this.value = value;
        this.isConst = isConst;
        this.type_expr = texpr;
    }

    override void print(uint indent = 0)
    {
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
        super(NodeKind.IntLit, pos);
        value = val;
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
        super(NodeKind.DoubleLit, pos);
        value = val;
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
        super(NodeKind.StringLit, pos);
        value = val;
        this.type_expr = new TypeExprNamed(TypeSemaBase.String, pos);
    }

    override void print(uint indent = 0)
    {
        writefln(`StringLit("%s")`, value);
    }
}

class BoolLit : Node
{
    bool value;

    this(bool val, Position pos)
    {
        super(NodeKind.BoolLit, pos);
        this.kind = NodeKind.BoolLit;
        value = val;
        this.type_expr = new TypeExprNamed(TypeSemaBase.Bool, pos);
    }

    override void print(uint indent = 0)
    {
        writefln("BoolLit(%d)", value);
    }
}

class Identifier : Node
{
    dstring value;

    this(dstring val, Position pos)
    {
        super(NodeKind.Identifier, pos);
        value = val;
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
        super(NodeKind.BinaryExpr, pos);
        left = l;
        right = r;
        op = o;
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
    bool post;

    this(Node val, TokenKind o, bool post, Position pos)
    {
        super(NodeKind.UnaryExpr, pos);
        this.value = val;
        this.op = o;
        this.post = post;
    }

    override void print(uint indent = 0)
    {
        writef("UnaryExpr(%s) : post -> %d", tokenKindStr(op), post);
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
        super(NodeKind.CallExpr, pos);
        this.fn = fn;
        this.args = args;
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

    this(TypeSema type, Position pos)
    {
        this.type_sema = type;
        this.pos = pos;
    }
}

class FnDecl : Node
{
    dstring fn;
    FnArg[] args;
    Node[] body;
    ubyte ctfe_flags;

    this(dstring fn, FnArg[] args, TypeExpr type, Node[] body, ubyte ctfe_flags, Position pos)
    {
        super(NodeKind.FnDecl, pos);
        this.fn = fn;
        this.args = args;
        this.type_expr = type;
        this.body = body;
        this.ctfe_flags = ctfe_flags;
    }


    this(dstring fn, FnArg[] args, TypeSema type, Node[] body, ubyte ctfe_flags, Position pos)
    {
        super(NodeKind.FnDecl, pos);
        this.fn = fn;
        this.args = args;
        this.type_sema = type;
        this.body = body;
        this.ctfe_flags = ctfe_flags;
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
            if (arg.type_expr !is null) writef(" : %s", arg.type_expr.toStr());
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
        super(NodeKind.ReturnStmt, pos);
        this.val = val;
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
        super(NodeKind.IfStmt, pos);
        this.expr = expr;
        this.body = body;
        this._else = _else;
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
        super(NodeKind.TypeOfExpr, pos);
        value = val;
    }

    override void print(uint indent = 0)
    {
        writeln("TypeOfExpr",);
        if (type_sema !is null) writef(" : %s", type_sema.toStr());
        writeln();
        printIndent(indent, true);
        value.print(indent + 1);
    }
}

class AssignStmt : Node
{
    Node left, value;
    TokenKind op;

    this(Node left, Node val, TokenKind op, Position pos)
    {
        super(NodeKind.AssignStmt, pos);
        this.left = left;
        this.value = val;
    }

    override void print(uint indent = 0)
    {
        writeln("AssignStmt(%s):", tokenKindStr(op));
        printIndent(indent, true);
        left.print(indent + 1);
        printIndent(indent, true);
        value.print(indent + 1);
    }
}

class NaN : Node
{
    this(Position pos)
    {
        super(NodeKind.NaN, pos);
    }

    override void print(uint indent = 0)
    {
        writeln("NaN");
    }
}

class BlockStmt : Node
{
    Node[] body;

    this(Node[] body, Position pos)
    {
        super(NodeKind.BlockStmt, pos);
        this.body = body;
    }

    override void print(uint indent = 0)
    {
        writefln("BlockStmt");
        foreach (i, node; body)
        {
            bool isLast = (i == cast(size_t) body.length - 1);
            printIndent(indent, isLast);
            node.print(indent + 1);
        }
    }
}

class ArrayLit : Node
{
    Node[] elements;

    this(Node[] elements, Position pos)
    {
        super(NodeKind.ArrayLit, pos);
        this.elements = elements;
        this.type_expr = new TypeExprArray(new TypeExprNamed(TypeSemaBase.Any, pos), pos);
    }

    override void print(uint indent = 0)
    {
        writefln("ArrayLit");
    }
}

class IndexExpr : Node
{
    Node value, idx;

    this(Node value, Node idx, Position pos)
    {
        super(NodeKind.IndexExpr, pos);
        this.value = value;
        this.idx = idx;
        this.type_expr = new TypeExprNamed(TypeSemaBase.Any, pos);
    }

    override void print(uint indent = 0)
    {
        writefln("IndexExpr");
    }
}

class WhileStmt : Node
{
    Node expr;
    Node[] body;

    this(Node expr, Node[] body, Position pos)
    {
        super(NodeKind.WhileStmt, pos);
        this.body = body;
        this.expr = expr;
    }

    override void print(uint indent = 0)
    {
        writefln("WhileStmt");
        printIndent(indent);
        expr.print(indent);
        foreach (i, node; body)
        {
            bool isLast = (i == cast(size_t) body.length - 1);
            printIndent(indent, isLast);
            node.print(indent + 1);
        }
    }
}

class MemberExpr : Node
{
    Node left, right;

    this(Node left, Node right, Position pos)
    {
        super(NodeKind.MemberExpr, pos);
        this.left = left;
        this.right = right;
    }

    override void print(uint indent = 0)
    {
        writefln("MemberExpr");
        printIndent(indent);
        left.print(indent);
        printIndent(indent);
        right.print(indent);
    }
}

private void printIndent(uint indent, bool isLast = false)
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
