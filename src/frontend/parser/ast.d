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
    TypeDecl,
    ClassDecl,

    BinaryExpr,
    CallExpr,
    UnaryExpr,
    AssignDecl,
    GroupedExpr,
    IndexExpr,
    MemberExpr,
    TernaryExpr,
    NewExpr,
    ThisExpr,
    FuncExpr,

    BlockStmt,
    IfStmt,
    ForStmt,
    ReturnStmt,
}

abstract class Node
{
    NodeKind kind;
    Variant value;
    TypeExpr type;
    Type resolvedType = Type.init;
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
        println(continuation ~ "├── Tipo resolvido: " ~ (resolvedType is null ? "nulo" : resolvedType.toStr()), ident);
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
        println(continuation ~ "├── Tipo resolvido: " ~ (resolvedType is null ? "nulo" : resolvedType.toStr()), ident);
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
        this.type = new NamedTypeExpr(BaseType.Any, loc);
        this.value = id;
        this.loc = loc;
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        string prefix = isLast ? "└── " : "├── ";
        string continuation = isLast ? "    " : "│   ";

        println(prefix ~ "Identifier: " ~ value.get!string, ident);
        println(continuation ~ "├── Tipo: " ~ type.toStr(), ident);
        println(continuation ~ "└── Tipo resolvido: " ~ (resolvedType is null ? "nulo" : resolvedType.toStr()), ident);
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
        println(continuation ~ "├── Tipo resolvido: " ~ (resolvedType is null ? "nulo" : resolvedType.toStr()), ident);
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
        this.type = new ArrayTypeExpr(new NamedTypeExpr(BaseType.Any, loc), loc);
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        string prefix = isLast ? "└── " : "├── ";
        string continuation = isLast ? "    " : "│   ";

        println(prefix ~ "ArrayLiteral (" ~ to!string(elements.length) ~ " elementos)", ident);
        println(continuation ~ "├── Tipo: " ~ type.toStr(), ident);
        println(continuation ~ "├── Tipo resolvido: " ~ (resolvedType is null ? "nulo" : resolvedType.toStr()), ident);
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

    this(Node operand, TypeExpr type, string op, Loc loc)
    {
        this.kind = NodeKind.UnaryExpr;
        this.operand = operand;
        this.op = op;
        this.type = type;
        this.loc = loc;
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        string prefix = isLast ? "└── " : "├── ";
        string continuation = isLast ? "    " : "│   ";

        println(prefix ~ "UnaryExpr: (" ~ op ~ ")", ident);
        println(continuation ~ "├── Tipo: " ~ type.toStr(), ident);
        println(continuation ~ "├── Tipo resolvido: " ~ (resolvedType is null ? "nulo" : resolvedType.toStr()), ident);
        println(continuation ~ "└── Operando:", ident);

        if (operand !is null)
            operand.print(ident + continuation.length + 4, true);
        else
            println(continuation ~ "    └── (nulo)", ident);
    }
}

class AssignDecl : Node
{
    Node left, right;
    string op;

    this(Node left, Node right, string op, Loc loc)
    {
        this.kind = NodeKind.AssignDecl;
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

        println(prefix ~ "AssignDecl: (" ~ op ~ ")", ident);
        println(continuation ~ "├── Tipo: " ~ type.toStr(), ident);
        println(continuation ~ "├── Tipo resolvido: " ~ (resolvedType is null ? "nulo" : resolvedType.toStr()), ident);
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
        println(continuation ~ "├── Tipo resolvido: " ~ (resolvedType is null ? "nulo" : resolvedType.toStr()), ident);
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
        this.type = new NamedTypeExpr(BaseType.Any, loc);
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        string prefix = isLast ? "└── " : "├── ";
        string continuation = isLast ? "    " : "│   ";

        println(prefix ~ "IndexExpr: [ ... ]", ident);
        println(continuation ~ "├── Tipo: " ~ type.toStr(), ident);
        println(continuation ~ "├── Tipo resolvido: " ~ (resolvedType is null ? "nulo" : resolvedType.toStr()), ident);
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
        this.type = new NamedTypeExpr(BaseType.Void, loc);
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        string prefix = isLast ? "└── " : "├── ";
        string continuation = isLast ? "    " : "│   ";

        println(prefix ~ "MemberExpr: ." ~ member, ident);
        println(continuation ~ "├── Tipo: " ~ type.toStr(), ident);
        println(continuation ~ "├── Tipo resolvido: " ~ (resolvedType is null ? "nulo" : resolvedType.toStr()), ident);
        println(continuation ~ "└── Target:", ident);

        if (target !is null)
            target.print(ident + continuation.length + 4, true);
        else
            println(continuation ~ "    └── (nulo)", ident);
    }
}

class TypeDecl : Node
{
    this(string id, TypeExpr type, Loc loc)
    {
        this.kind = NodeKind.TypeDecl;
        this.type = type;
        this.value = id;
        this.loc = loc;
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        string prefix = isLast ? "└── " : "├── ";
        string continuation = isLast ? "    " : "│   ";

        println(prefix ~ format("TypeDecl: (%s) ", value.get!string), ident);
        println(continuation ~ "└── Tipo: " ~ type.toStr(), ident);
    }
}

struct FuncArgument
{
    string name;
    TypeExpr type;
    Type resolvedType;
    Node value;
    Loc loc;
}

class FuncDecl : Node
{
    string name;
    BlockStmt body;
    FuncArgument[] args;

    this(string name, ref FuncArgument[] args, Node[] body, TypeExpr type, Loc loc)
    {
        this.kind = NodeKind.FuncDecl;
        this.type = type;
        this.body = new BlockStmt(body, loc);
        this.name = name;
        this.args = args;
        this.loc = loc;
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        string prefix = isLast ? "└── " : "├── ";
        string continuation = isLast ? "    " : "│   ";

        println(prefix ~ "FuncDecl: " ~ name, ident);
        println(continuation ~ "├── Tipo: " ~ type.toStr(), ident);
        println(continuation ~ "├── Tipo resolvido: " ~ (resolvedType is null ? "nulo" : resolvedType.toStr()), ident);
        println(continuation ~ "├── Argumentos (" ~ to!string(args.length) ~ "):", ident);

        foreach (long i, FuncArgument arg; args)
        {
            string argPrefix = (i == cast(uint) args.length - 1) ? "└── " : "├── ";
            println(continuation ~ "│   " ~ argPrefix ~ "Argumento: " ~ arg.name, ident);
            println(continuation ~ "│   " ~ (i == cast(uint) args.length - 1 ? "    " : "│   ") ~
                    "├── Tipo: " ~ arg.type.toStr(), ident);
            println(continuation ~ "│   " ~ (i == cast(uint) args.length - 1 ? "    " : "│   ") ~
                    "└── Tem valor padrão: " ~ (arg.value !is null ? "sim" : "não"), ident);
        }

        println(continuation ~ "└── Corpo (" ~ to!string(
                body.statements.length) ~ " nó(s)):", ident);
        foreach (long i, Node node; body.statements)
        {
            if (i == cast(uint)
                body.statements.length - 1)
                node.print(ident + continuation.length + 4, true);
            else
                node.print(ident + continuation.length + 4, false);
        }
    }
}

class BlockStmt : Node
{
    Node[] statements;

    this(Node[] statements, Loc loc)
    {
        this.kind = NodeKind.BlockStmt;
        this.statements = statements;
        this.loc = loc;
        this.type = new NamedTypeExpr(BaseType.Void, loc);
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        string prefix = isLast ? "└── " : "├── ";
        string continuation = isLast ? "    " : "│   ";

        println(prefix ~ "BlockStmt { ... }", ident);
        foreach (long i, Node stmt; statements)
        {
            bool last = (i == cast(uint) statements.length - 1);
            stmt.print(ident + continuation.length + 4, last);
        }
    }
}

class IfStmt : Node
{
    Node condition;
    Node thenBranch;
    Node elseBranch; // Pode ser null

    this(Node condition, Node thenBranch, Node elseBranch, Loc loc)
    {
        this.kind = NodeKind.IfStmt;
        this.condition = condition;
        this.thenBranch = thenBranch;
        this.elseBranch = elseBranch;
        this.loc = loc;
        this.type = new NamedTypeExpr(BaseType.Void, loc);
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        string prefix = isLast ? "└── " : "├── ";
        string continuation = isLast ? "    " : "│   ";

        println(prefix ~ "IfStmt", ident);

        // } senao {
        if (condition is null)
            println(continuation ~ "├── Condição: (vazio)", ident);
        else
        {
            println(continuation ~ "├── Condição:", ident);
            condition.print(ident + continuation.length + 4, false);
        }

        println(continuation ~ "├── Entao:", ident);
        thenBranch.print(ident + continuation.length + 4, elseBranch is null); // Se não tiver else, o then é o ultimo visualmente

        if (elseBranch !is null)
        {
            println(continuation ~ "└── Senão:", ident);
            elseBranch.print(ident + continuation.length + 4, true);
        }
    }
}

class ForStmt : Node
{
    Node init_; // Pode ser VarDecl ou Expr (ou null)
    Node condition; // Pode ser null
    Node increment; // Pode ser Expr (ou null)
    Node body;

    this(Node init, Node condition, Node increment, Node body, Loc loc)
    {
        this.kind = NodeKind.ForStmt;
        this.init_ = init;
        this.condition = condition;
        this.increment = increment;
        this.body = body;
        this.loc = loc;
        this.type = new NamedTypeExpr(BaseType.Void, loc);
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        string prefix = isLast ? "└── " : "├── ";
        string continuation = isLast ? "    " : "│   ";

        println(prefix ~ "ForStmt (C-Style)", ident);

        println(continuation ~ "├── Init:", ident);
        if (init_ !is null)
            init_.print(ident + continuation.length + 4, false);
        else
            println(continuation ~ "│   └── (vazio)", ident);

        println(continuation ~ "├── Condição:", ident);
        if (condition !is null)
            condition.print(ident + continuation.length + 4, false);
        else
            println(continuation ~ "│   └── (vazio/true)", ident);

        println(continuation ~ "├── Incremento:", ident);
        if (increment !is null)
            increment.print(ident + continuation.length + 4, false);
        else
            println(continuation ~ "│   └── (vazio)", ident);

        println(continuation ~ "└── Corpo:", ident);
        body.print(ident + continuation.length + 4, true);
    }
}

class ReturnStmt : Node
{
    Node value; // Pode ser null (return void)

    this(Node value, Loc loc)
    {
        this.kind = NodeKind.ReturnStmt;
        this.value = value;
        this.loc = loc;
        this.type = new NamedTypeExpr(BaseType.Void, loc); // Statement não tem tipo, ou é Bottom
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        string prefix = isLast ? "└── " : "├── ";
        string continuation = isLast ? "    " : "│   ";

        println(prefix ~ "ReturnStmt", ident);
        if (value !is null)
        {
            println(continuation ~ "└── Valor:", ident);
            value.print(ident + continuation.length + 4, true);
        }
        else
            println(continuation ~ "└── (void)", ident);
    }
}

class ClassDecl : Node
{
    string name;
    Node[] members; // VarDecl (propriedades) e FuncDecl (métodos)

    this(string name, Node[] members, Loc loc)
    {
        this.kind = NodeKind.ClassDecl;
        this.name = name;
        this.members = members;
        this.loc = loc;
        this.type = new NamedTypeExpr(BaseType.Void, loc);
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        string prefix = isLast ? "└── " : "├── ";
        string continuation = isLast ? "    " : "│   ";

        println(prefix ~ "ClassDecl: " ~ name, ident);
        println(continuation ~ "└── Membros (" ~ to!string(members.length) ~ "):", ident);

        foreach (long i, Node member; members)
        {
            bool last = (i == cast(uint) members.length - 1);
            member.print(ident + continuation.length + 4, last);
        }
    }
}

class NewExpr : Node
{
    string className;
    Node[] args; // Argumentos para o construtor

    this(string className, Node[] args, Loc loc)
    {
        this.kind = NodeKind.NewExpr;
        this.className = className;
        this.args = args;
        this.loc = loc;
        this.type = new NamedTypeExpr(className, loc); // O tipo é o nome da classe
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        string prefix = isLast ? "└── " : "├── ";
        string continuation = isLast ? "    " : "│   ";

        println(prefix ~ "NewExpr: " ~ className, ident);
        println(continuation ~ "└── Args (" ~ to!string(args.length) ~ "):", ident);
        foreach (long i, Node arg; args)
        {
            bool last = (i == cast(uint) args.length - 1);
            arg.print(ident + continuation.length + 4, last);
        }
    }
}

class ThisExpr : Node
{
    this(Loc loc)
    {
        this.kind = NodeKind.ThisExpr;
        this.loc = loc;
        this.type = new NamedTypeExpr(BaseType.Any, loc); // Resolvido semanticamente depois
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        string prefix = isLast ? "└── " : "├── ";
        println(prefix ~ "ThisExpr", ident);
    }
}

class TernaryExpr : Node
{
    Node condition;
    Node trueExpr;
    Node falseExpr;

    this(Node condition, Node trueExpr, Node falseExpr, Loc loc)
    {
        this.kind = NodeKind.TernaryExpr;
        this.condition = condition;
        this.trueExpr = trueExpr;
        this.falseExpr = falseExpr;
        this.loc = loc;
        this.type = new NamedTypeExpr(BaseType.Any, loc);
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        string prefix = isLast ? "└── " : "├── ";
        string continuation = isLast ? "    " : "│   ";

        println(prefix ~ "TernaryExpr (? :)", ident);

        println(continuation ~ "├── Condição:", ident);
        condition.print(ident + continuation.length + 4, false);

        if (trueExpr !is null)
        {
            println(continuation ~ "├── Caso Verdadeiro:", ident);
            trueExpr.print(ident + continuation.length + 4, false);
        }
        else
            println(continuation ~ "├── Caso Verdadeiro: (nulo)", ident);

        println(continuation ~ "└── Caso Falso:", ident);
        falseExpr.print(ident + continuation.length + 4, true);
    }
}

class FuncExpr : Node
{
    BlockStmt body;
    FuncArgument[] args;

    this(ref FuncArgument[] args, Node[] body, TypeExpr type, Loc loc)
    {
        this.kind = NodeKind.FuncExpr;
        this.type = type;
        this.body = new BlockStmt(body, loc);
        this.args = args;
        this.loc = loc;
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        string prefix = isLast ? "└── " : "├── ";
        string continuation = isLast ? "    " : "│   ";

        println(prefix ~ "FuncExpr: ", ident);
        println(continuation ~ "├── Tipo: " ~ type.toStr(), ident);
        println(continuation ~ "├── Tipo resolvido: " ~ (resolvedType is null ? "nulo" : resolvedType.toStr()), ident);
        println(continuation ~ "├── Argumentos (" ~ to!string(args.length) ~ "):", ident);

        foreach (long i, FuncArgument arg; args)
        {
            string argPrefix = (i == cast(uint) args.length - 1) ? "└── " : "├── ";
            println(continuation ~ "│   " ~ argPrefix ~ "Argumento: " ~ arg.name, ident);
            println(continuation ~ "│   " ~ (i == cast(uint) args.length - 1 ? "    " : "│   ") ~
                    "├── Tipo: " ~ arg.type.toStr(), ident);
            println(continuation ~ "│   " ~ (i == cast(uint) args.length - 1 ? "    " : "│   ") ~
                    "└── Tem valor padrão: " ~ (arg.value !is null ? "sim" : "não"), ident);
        }

        println(continuation ~ "└── Corpo (" ~ to!string(
                body.statements.length) ~ " nó(s)):", ident);
        foreach (long i, Node node; body.statements)
        {
            if (i == cast(uint)
                body.statements.length - 1)
                node.print(ident + continuation.length + 4, true);
            else
                node.print(ident + continuation.length + 4, false);
        }
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
