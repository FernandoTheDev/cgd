module frontend.parser.ast;

enum NodeKind
{
    Program,

    IntLit,
    FloatLit,
    StringLit,
    BoolLit,

    FuncDecl,
    VarDecl,

    BinaryExpr,
    CallExpr,
}

abstract class Node
{
    NodeKind kind;
    Variant value;
    Type type;
    Loc loc;
    bool publico = false;
    string nameMangling = "main";

    void print(ulong ident = 0, bool isLast = false);
}

class Program : Node
{
    Node[] body;
    this(Node[] body)
    {
        this.kind = NodeKind.Program;
        this.type = Type(Types.Literal, BaseType.Int);
        this.body = body;
        this.loc = loc;
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        println("├── Programa", ident);
        println("│   ├── Tipo: " ~ cast(string) type.baseType, ident);
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

// Declaração de Variavel
class VarDeclaration : Node
{
    string id;
    this(string id, Type type, Node value, Loc loc)
    {
        this.kind = NodeKind.VarDeclaration;
        this.id = id;
        this.type = type;
        this.value = value;
        this.loc = loc;
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        string prefix = isLast ? "└── " : "├── ";
        string continuation = isLast ? "    " : "│   ";

        println(prefix ~ "VarDeclaration: " ~ id, ident);
        println(continuation ~ "├── Tipo: " ~ cast(string) type.baseType, ident);
        println(continuation ~ "└── Valor:", ident);
        value.get!Node.print(ident + continuation.length + 4, true);
    }
}

class VarAssignmentDecl : Node
{
    string id;
    this(string id, Type type, Node value, Loc loc)
    {
        this.kind = NodeKind.VarAssignmentDecl;
        this.id = id;
        this.type = type;
        this.value = value;
        this.loc = loc;
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        string prefix = isLast ? "└── " : "├── ";
        string continuation = isLast ? "    " : "│   ";

        println(prefix ~ "VarAssignmentDecl: " ~ id, ident);
        println(continuation ~ "├── Type: " ~ cast(string) type.baseType, ident);
        println(continuation ~ "└── Value:", ident);
        value.get!Node.print(ident + continuation.length + 4, true);
    }
}

// Literais {{

// literal de um dec (decimal de 64 bits)
class DoubleLiteral : Node
{
    this(double n, Loc loc)
    {
        this.kind = NodeKind.DoubleLiteral;
        this.type = Type(Types.Literal, BaseType.Double);
        this.value = n;
        this.loc = loc;
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        string prefix = isLast ? "└── " : "├── ";
        string continuation = isLast ? "    " : "│   ";

        println(prefix ~ "DoubleLiteral: " ~ to!string(value.get!double), ident);
        println(continuation ~ "└── Tipo: " ~ cast(string) type.baseType, ident);
    }
}

// literal de um int (inteiro)
class IntLiteral : Node
{
    this(long n, Loc loc)
    {
        this.kind = NodeKind.IntLiteral;
        this.type = Type(Types.Literal, BaseType.Int);
        this.value = n;
        this.loc = loc;
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        string prefix = isLast ? "└── " : "├── ";
        string continuation = isLast ? "    " : "│   ";

        println(prefix ~ "IntLiteral: " ~ to!string(value.get!long), ident);
        println(continuation ~ "└── Tipo: " ~ cast(string) type.baseType, ident);
    }
}

// literal de uma string (texto)
class StringLiteral : Node
{
    this(string n, Loc loc)
    {
        this.kind = NodeKind.StringLiteral;
        this.type = Type(Types.Literal, BaseType.String);
        this.value = n;
        this.loc = loc;
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        string prefix = isLast ? "└── " : "├── ";
        string continuation = isLast ? "    " : "│   ";

        println(prefix ~ "StringLiteral: \"" ~ value.get!string ~ "\"", ident);
        println(continuation ~ "└── Tipo: " ~ cast(string) type.baseType, ident);
    }
}

class BoolLiteral : Node
{
    this(bool n, Loc loc)
    {
        this.kind = NodeKind.BoolLiteral;
        this.type = Type(Types.Literal, BaseType.Bool);
        this.value = n;
        this.loc = loc;
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        string prefix = isLast ? "└── " : "├── ";
        string continuation = isLast ? "    " : "│   ";

        println(prefix ~ "BoolLiteral: " ~ value.get!bool ? "verdadeiro" : "falso", ident);
        println(continuation ~ "└── Tipo: " ~ cast(string) type.baseType, ident);
    }
}

class CallExpr : Node
{
    string id;
    Node[] args;
    this(string id, Node[] args, Loc loc)
    {
        this.kind = NodeKind.CallExpr;
        this.type = Type(Types.Undefined, BaseType.Void);
        this.id = id;
        this.loc = loc;
        this.args = args;
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        string prefix = isLast ? "└── " : "├── ";
        string continuation = isLast ? "    " : "│   ";

        println(prefix ~ "CallExpr: " ~ id ~ "()", ident);
        println(continuation ~ "├── Tipo: " ~ cast(string) type.baseType, ident);
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

class BinaryExpr : Node
{
    Node left, right;
    string op;
    this(Node left, Node right, string op, Loc loc)
    {
        this.kind = NodeKind.BinaryExpr;
        this.type = left.type;
        this.left = left;
        this.loc = loc;
        this.right = right;
        this.op = op;
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        string prefix = isLast ? "└── " : "├── ";
        string continuation = isLast ? "    " : "│   ";

        println(prefix ~ "BinaryExpr: (" ~ op ~ ")", ident);
        println(continuation ~ "├── Tipo: " ~ cast(string) type.baseType, ident);
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
