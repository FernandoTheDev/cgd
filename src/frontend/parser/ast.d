module frontend.parser.ast;

import frontend;

enum NodeKind
{
    Program,
    Identifier,

    IntLit,
    LongLit,
    FloatLit,
    DoubleLit,
    StringLit,
    BoolLit,
    NullLit,
    ArrayLit,

    FuncDecl,
    VarDecl,

    BinaryExpr,
    CallExpr,
    UnaryExpr,
    AssignExpr,
    GroupedExpr,
    IndexExpr,
    MemberExpr,
}

abstract class Node
{
    NodeKind kind;
    Variant value;
    TypeExpr type;
    Loc loc;
    string nameMangling;

    void print(ulong ident = 0, bool isLast = false);
}

class Program : Node
{
    Node[] body;
    this(Node[] body)
    {
        this.kind = NodeKind.Program;
        this.body = body;
        this.loc = loc;
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        println("├── Programa", ident);
        println("│   └── Corpo (" ~ to!string(body.length) ~ " nó(s)):", ident);
        foreach (long i, Node node; body)
        {
            if (i == cast(uint)
                body.length - 1)
                node.print(ident + 8, true); // ultimo
            else
                node.print(ident + 8, false);
        }
    }
}

class VarDecl : Node
{
    string id;
    bool isConst;
    this(string id, TypeExpr type, Node value, bool isConst, Loc loc)
    {
        this.kind = NodeKind.VarDecl;
        this.id = id;
        this.type = type;
        this.value = value;
        this.isConst = isConst;
        this.loc = loc;
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        string prefix = isLast ? "└── " : "├── ";
        string continuation = isLast ? "    " : "│   ";

        println(prefix ~ "VarDecl: " ~ id, ident);
        println(continuation ~ "├── Tipo: " ~ type.toStr(), ident);
        if (value.get!Node is null)
            println(continuation ~ "└── Valor: nulo", ident);
        else
        {
            println(continuation ~ "└── Valor:", ident);
            value.get!Node.print(ident + continuation.length + 4, true);
        }
    }
}

class DoubleLit : Node
{
    this(double n, Loc loc)
    {
        this.kind = NodeKind.DoubleLit;
        this.type = new NamedTypeExpr(BaseType.Double, loc);
        this.value = n;
        this.loc = loc;
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        string prefix = isLast ? "└── " : "├── ";
        string continuation = isLast ? "    " : "│   ";

        println(prefix ~ "DoubleLit: " ~ to!string(value.get!double), ident);
        println(continuation ~ "└── Tipo: " ~ type.toStr(), ident);
    }
}

class FloatLit : Node
{
    this(float n, Loc loc)
    {
        this.kind = NodeKind.FloatLit;
        this.type = new NamedTypeExpr(BaseType.Float, loc);
        this.value = n;
        this.loc = loc;
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        string prefix = isLast ? "└── " : "├── ";
        string continuation = isLast ? "    " : "│   ";

        println(prefix ~ "FloatLit: " ~ to!string(value.get!float), ident);
        println(continuation ~ "└── Tipo: " ~ type.toStr(), ident);
    }
}

class LongLit : Node
{
    this(long n, Loc loc)
    {
        this.kind = NodeKind.LongLit;
        this.type = new NamedTypeExpr(BaseType.Long, loc);
        this.value = n;
        this.loc = loc;
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        string prefix = isLast ? "└── " : "├── ";
        string continuation = isLast ? "    " : "│   ";

        println(prefix ~ "IntLit: " ~ to!string(value.get!long), ident);
        println(continuation ~ "└── Tipo: " ~ type.toStr(), ident);
    }
}

class IntLit : Node
{
    this(int n, Loc loc)
    {
        this.kind = NodeKind.IntLit;
        this.type = new NamedTypeExpr(BaseType.Int, loc);
        this.value = n;
        this.loc = loc;
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        string prefix = isLast ? "└── " : "├── ";
        string continuation = isLast ? "    " : "│   ";

        println(prefix ~ "IntLit: " ~ to!string(value.get!int), ident);
        println(continuation ~ "└── Tipo: " ~ type.toStr(), ident);
    }
}

class StringLit : Node
{
    this(string n, Loc loc)
    {
        this.kind = NodeKind.StringLit;
        this.type = new NamedTypeExpr(BaseType.String, loc);
        this.value = n;
        this.loc = loc;
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        string prefix = isLast ? "└── " : "├── ";
        string continuation = isLast ? "    " : "│   ";

        println(prefix ~ "StringLit: \"" ~ value.get!string ~ "\"", ident);
        println(continuation ~ "└── Tipo: " ~ type.toStr(), ident);
    }
}

class BoolLit : Node
{
    this(bool n, Loc loc)
    {
        this.kind = NodeKind.BoolLit;
        this.type = new NamedTypeExpr(BaseType.Bool, loc);
        this.value = n;
        this.loc = loc;
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        string prefix = isLast ? "└── " : "├── ";
        string continuation = isLast ? "    " : "│   ";

        println(prefix ~ "BoolLit: " ~ value.get!bool ? "verdadeiro" : "falso", ident);
        println(continuation ~ "└── Tipo: " ~ type.toStr(), ident);
    }
}

class CallExpr : Node
{
    string id;
    Node[] args;
    this(string id, Node[] args, Loc loc)
    {
        this.kind = NodeKind.CallExpr;
        this.id = id;
        this.loc = loc;
        this.type = new NamedTypeExpr(BaseType.Void, loc);
        this.args = args;
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        string prefix = isLast ? "└── " : "├── ";
        string continuation = isLast ? "    " : "│   ";

        println(prefix ~ "CallExpr: " ~ id ~ "()", ident);
        println(continuation ~ "├── Tipo: " ~ type.toStr(), ident);
        println(continuation ~ "└── Argumentos (" ~ to!string(args.length) ~ "):", ident);

        foreach (long i, Node arg; args)
        {
            if (i == cast(uint) args.length - 1)
                arg.print(ident + continuation.length + 4, true);
            else
                arg.print(ident + continuation.length + 4, false);
        }
    }
}

class Identifier : Node
{
    this(string id, Loc loc)
    {
        this.kind = NodeKind.Identifier;
        this.type = new NamedTypeExpr("void", loc);
        this.value = id;
        this.loc = loc;
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        string prefix = isLast ? "└── " : "├── ";
        string continuation = isLast ? "    " : "│   ";

        println(prefix ~ "Identifier: " ~ value.get!string, ident);
        println(continuation ~ "└── Tipo: " ~ type.toStr(), ident);
    }
}

class BinaryExpr : Node
{
    Node left, right;
    string op;
    this(Node left, Node right, string op, Loc loc)
    {
        this.kind = NodeKind.BinaryExpr;
        this.left = left;
        this.type = left.type;
        this.loc = loc;
        this.right = right;
        this.op = op;
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        string prefix = isLast ? "└── " : "├── ";
        string continuation = isLast ? "    " : "│   ";

        println(prefix ~ "BinaryExpr: (" ~ op ~ ")", ident);
        println(continuation ~ "├── Tipo: " ~ type.toStr(), ident);
        println(continuation ~ "├── Esquerda:", ident);

        if (left !is null)
            left.print(ident + continuation.length + 4, false);
        else
            println(continuation ~ "│   └── (nulo)", ident);

        println(continuation ~ "└── Direita:", ident);

        if (right !is null)
            right.print(ident + continuation.length + 4, true);
        else
            println(continuation ~ "    └── (nulo)", ident);
    }
}

class NullLit : Node
{
    this(Loc loc)
    {
        this.kind = NodeKind.NullLit;
        this.type = new NamedTypeExpr("null", loc);
        this.value = null;
        this.loc = loc;
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        string prefix = isLast ? "└── " : "├── ";
        string continuation = isLast ? "    " : "│   ";

        println(prefix ~ "NullLiteral", ident);
        println(continuation ~ "└── Tipo: " ~ type.toStr(), ident);
    }
}

class ArrayLit : Node
{
    Node[] elements;

    this(Node[] elements, Loc loc)
    {
        this.kind = NodeKind.ArrayLit;
        this.elements = elements;
        this.loc = loc;
        this.type = new NamedTypeExpr("array", loc);
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        string prefix = isLast ? "└── " : "├── ";
        string continuation = isLast ? "    " : "│   ";

        println(prefix ~ "ArrayLiteral (" ~ to!string(elements.length) ~ " elementos)", ident);
        println(continuation ~ "├── Tipo: " ~ type.toStr(), ident);
        println(continuation ~ "└── Elementos:", ident);

        foreach (long i, Node elem; elements)
        {
            if (i == cast(uint) elements.length - 1)
                elem.print(ident + continuation.length + 4, true);
            else
                elem.print(ident + continuation.length + 4, false);
        }
    }
}

class UnaryExpr : Node
{
    Node operand;
    string op;

    this(Node operand, string op, Loc loc)
    {
        this.kind = NodeKind.UnaryExpr;
        this.operand = operand;
        this.op = op;
        this.type = operand.type;
        this.loc = loc;
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        string prefix = isLast ? "└── " : "├── ";
        string continuation = isLast ? "    " : "│   ";

        println(prefix ~ "UnaryExpr: (" ~ op ~ ")", ident);
        println(continuation ~ "├── Tipo: " ~ type.toStr(), ident);
        println(continuation ~ "└── Operando:", ident);

        if (operand !is null)
            operand.print(ident + continuation.length + 4, true);
        else
            println(continuation ~ "    └── (nulo)", ident);
    }
}

class AssignExpr : Node
{
    Node left, right;
    string op;

    this(Node left, Node right, string op, Loc loc)
    {
        this.kind = NodeKind.AssignExpr;
        this.left = left;
        this.right = right;
        this.op = op;
        this.type = left.type;
        this.loc = loc;
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        string prefix = isLast ? "└── " : "├── ";
        string continuation = isLast ? "    " : "│   ";

        println(prefix ~ "AssignExpr: (" ~ op ~ ")", ident);
        println(continuation ~ "├── Tipo: " ~ type.toStr(), ident);
        println(continuation ~ "├── Destino:", ident);

        if (left !is null)
            left.print(ident + continuation.length + 4, false);
        else
            println(continuation ~ "│   └── (nulo)", ident);

        println(continuation ~ "└── Valor:", ident);

        if (right !is null)
            right.print(ident + continuation.length + 4, true);
        else
            println(continuation ~ "    └── (nulo)", ident);
    }
}

class GroupedExpr : Node
{
    Node expr;

    this(Node expr, Loc loc)
    {
        this.kind = NodeKind.GroupedExpr;
        this.expr = expr;
        this.type = expr.type;
        this.loc = loc;
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        string prefix = isLast ? "└── " : "├── ";
        string continuation = isLast ? "    " : "│   ";

        println(prefix ~ "GroupedExpr: ( ... )", ident);
        println(continuation ~ "├── Tipo: " ~ type.toStr(), ident);
        println(continuation ~ "└── Expressão:", ident);

        if (expr !is null)
            expr.print(ident + continuation.length + 4, true);
        else
            println(continuation ~ "    └── (nulo)", ident);
    }
}

class IndexExpr : Node
{
    Node target;
    Node index;

    this(Node target, Node index, Loc loc)
    {
        this.kind = NodeKind.IndexExpr;
        this.target = target;
        this.index = index;
        this.loc = loc;
        // Tipo será determinado depois (elemento do array/string)
        this.type = new NamedTypeExpr("unknown", loc);
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        string prefix = isLast ? "└── " : "├── ";
        string continuation = isLast ? "    " : "│   ";

        println(prefix ~ "IndexExpr: [ ... ]", ident);
        println(continuation ~ "├── Tipo: " ~ type.toStr(), ident);
        println(continuation ~ "├── Target:", ident);

        if (target !is null)
            target.print(ident + continuation.length + 4, false);
        else
            println(continuation ~ "│   └── (nulo)", ident);

        println(continuation ~ "└── Índice:", ident);

        if (index !is null)
            index.print(ident + continuation.length + 4, true);
        else
            println(continuation ~ "    └── (nulo)", ident);
    }
}

class MemberExpr : Node
{
    Node target;
    string member;

    this(Node target, string member, Loc loc)
    {
        this.kind = NodeKind.MemberExpr;
        this.target = target;
        this.member = member;
        this.loc = loc;
        // Tipo será determinado depois (tipo do membro)
        this.type = new NamedTypeExpr("unknown", loc);
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        string prefix = isLast ? "└── " : "├── ";
        string continuation = isLast ? "    " : "│   ";

        println(prefix ~ "MemberExpr: ." ~ member, ident);
        println(continuation ~ "├── Tipo: " ~ type.toStr(), ident);
        println(continuation ~ "└── Target:", ident);

        if (target !is null)
            target.print(ident + continuation.length + 4, true);
        else
            println(continuation ~ "    └── (nulo)", ident);
    }
}

private void println(string message, ulong ident = 0)
{
    writeln(" ".replicate(ident), message);
}

private void print(string message, ulong ident = 0)
{
    write(" ".replicate(ident), message);
}
