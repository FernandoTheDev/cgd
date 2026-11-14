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
    TupleLit,
    SequenceStmt,
    ConditionalExpr,
    SliceExpr,
    SpreadExpr,
    Comprehension,
    SwitchStmt,
    LoopExpr,
    NullLit,
    MapLit,
    EachStmt,
    FunctionExpr,
    ClassDecl,
    SuperExpr,
    TryStmt,
    ThrowStmt,
    ImportExpr,
    ModuleUnit,
    ForStmt,
    DoStmt,
    BreakStmt,
    ContinueStmt,
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
    WhileStmt, // TODO
    // ForStmt,
}

struct Decorator
{
    dstring name;
    dstring[] keys;
    Node[] values;
    FnDecl envelope;
}

abstract class Node
{
    Decorator[] decorators;
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
    bool isConst, uninitialized;

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
    VarDecl variableRef;
    FnDecl functionRef;
    ClassDecl classRef;
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
    bool runtimeCall;
    bool builtinCall, intrinsic;
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

class FnArg
{
    bool rest;
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
    dstring linkName;
    dstring builtinName;
    bool analyzed, isMethod, accessor, anonymous, decoratorEnvelope;
    ClassDecl ownerClass, classFactory;
    int access;
    FnArg[] args;
    Node[] body;
    ubyte ctfe_flags;

    this(dstring fn, FnArg[] args, TypeExpr type, Node[] body, ubyte ctfe_flags, Position pos)
    {
        super(NodeKind.FnDecl, pos);
        this.fn = fn;
        import std.conv : to;

        linkName = "#fn_"d ~ (nextFunctionId++).to!dstring;
        this.args = args;
        this.type_expr = type;
        this.body = body;
        this.ctfe_flags = ctfe_flags;
    }

    this(dstring fn, FnArg[] args, TypeSema type, Node[] body, ubyte ctfe_flags, Position pos)
    {
        super(NodeKind.FnDecl, pos);
        this.fn = fn;
        import std.conv : to;

        linkName = "#fn_"d ~ (nextFunctionId++).to!dstring;
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
            if (arg.type_expr !is null)
                writef(" : %s", arg.type_expr.toStr());
            if (arg.type_sema !is null)
                writef(" :> %s", arg.type_sema.toStr());
            writeln();
        }

        // corpo
        foreach (i, node; body)
        {
            bool isLast = (i == cast(size_t)
                    body.length - 1);
            printIndent(indent, isLast);
            node.print(indent + 1);
        }
    }
}

class ReturnStmt : Node
{
    bool collectionReturn;
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
            bool isLast = (i == cast(size_t)
                    body.length - 1) && _else is null;
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
        if (type_sema !is null)
            writef(" : %s", type_sema.toStr());
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
        this.op = op;
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
            bool isLast = (i == cast(size_t)
                    body.length - 1);
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
            bool isLast = (i == cast(size_t)
                    body.length - 1);
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

class NullLit : Node
{
    this(Position pos)
    {
        super(NodeKind.NullLit, pos);
    }

    override void print(uint indent = 0)
    {
        writeln("NullLit");
    }
}

class ForStmt : Node
{
    Node init, condition, step;
    Node[] body;
    this(Node init, Node condition, Node step, Node[] body, Position pos)
    {
        super(NodeKind.ForStmt, pos);
        this.init = init;
        this.condition = condition;
        this.step = step;
        this.body = body;
    }

    override void print(uint indent = 0)
    {
        writeln("ForStmt");
    }
}

class DoStmt : Node
{
    Node condition;
    Node[] body;
    this(Node condition, Node[] body, Position pos)
    {
        super(NodeKind.DoStmt, pos);
        this.condition = condition;
        this.body = body;
    }

    override void print(uint indent = 0)
    {
        writeln("DoStmt");
    }
}

class LoopControl : Node
{
    this(bool isBreak, Position pos)
    {
        super(isBreak ? NodeKind.BreakStmt : NodeKind.ContinueStmt, pos);
    }

    override void print(uint indent = 0)
    {
        writeln(kind);
    }
}

class MapLit : Node
{
    Node[] keys, values;
    this(Node[] keys, Node[] values, Position pos)
    {
        super(NodeKind.MapLit, pos);
        this.keys = keys;
        this.values = values;
    }

    override void print(uint indent = 0)
    {
        writeln("MapLit");
    }
}

class EachStmt : Node
{
    dstring[] destructured;
    dstring name;
    Node iterable;
    Node[] body;
    this(dstring name, Node iterable, Node[] body, Position pos)
    {
        super(NodeKind.EachStmt, pos);
        this.name = name;
        this.iterable = iterable;
        this.body = body;
    }

    override void print(uint indent = 0)
    {
        writeln("EachStmt");
    }
}

private size_t nextFunctionId;
class FunctionExpr : Node
{
    FnDecl declaration;
    this(FnDecl declaration)
    {
        super(NodeKind.FunctionExpr, declaration.pos);
        this.declaration = declaration;
        declaration.anonymous = true;
    }

    override void print(uint indent = 0)
    {
        declaration.print(indent);
    }
}

Node[] childNodes(Node node)
{
    if (node is null)
        return [];
    if (auto n = cast(SequenceStmt) node)
        return n.body;
    if (auto n = cast(ConditionalExpr) node)
        return [n.condition, n.yes, n.no];
    if (auto n = cast(SliceExpr) node)
        return [n.value, n.start, n.end, n.step];
    if (auto n = cast(SpreadExpr) node)
        return [n.value];
    if (auto n = cast(Comprehension) node)
        return [n.value, n.iterable, n.condition];
    if (auto n = cast(LoopExpr) node)
        return [n.loop];
    if (auto n = cast(SwitchStmt) node)
    {
        Node[] nodes = [n.value] ~ n.fallback;
        foreach (c; n.cases)
            nodes ~= c.values ~ c.body;
        return nodes;
    }
    if (auto n = cast(ModuleUnit) node)
        return [n.program];
    if (auto n = cast(ImportExpr) node)
        return n.target is null ? [n.path] : [n.path, cast(Node) n.target];
    if (auto n = cast(TryStmt) node)
    {
        Node[] result = n.body ~ n.finalBody;
        foreach (c; n.catches)
            result ~= c.body;
        return result;
    }
    if (auto n = cast(ThrowStmt) node)
        return [n.value];
    if (auto n = cast(ClassDecl) node)
    {
        Node[] nodes;
        foreach (m; n.methods)
            nodes ~= m;
        return nodes;
    }
    if (auto n = cast(Program) node)
        return n.body;
    if (auto n = cast(FnDecl) node)
    {
        Node[] result = n.body.dup;
        foreach (a; n.args)
            if (a.value !is null)
                result ~= a.value;
        return result;
    }
    if (auto n = cast(FunctionExpr) node)
        return [n.declaration];
    if (auto n = cast(VarDecl) node)
        return [n.value];
    if (auto n = cast(BinaryExpr) node)
        return [n.left, n.right];
    if (auto n = cast(UnaryExpr) node)
        return [n.value];
    if (auto n = cast(CallExpr) node)
        return [n.fn] ~ n.args;
    if (auto n = cast(ReturnStmt) node)
        return [n.val];
    if (auto n = cast(IfStmt) node)
        return [n.expr, cast(Node) n._else] ~ n.body;
    if (auto n = cast(BlockStmt) node)
        return n.body;
    if (auto n = cast(WhileStmt) node)
        return [n.expr] ~ n.body;
    if (auto n = cast(ForStmt) node)
        return [n.init, n.condition, n.step] ~ n.body;
    if (auto n = cast(DoStmt) node)
        return [n.condition] ~ n.body;
    if (auto n = cast(EachStmt) node)
        return [n.iterable] ~ n.body;
    if (auto n = cast(ArrayLit) node)
        return n.elements;
    if (auto n = cast(MapLit) node)
        return n.keys ~ n.values;
    if (auto n = cast(IndexExpr) node)
        return [n.value, n.idx];
    if (auto n = cast(MemberExpr) node)
        return [n.left, n.right];
    if (auto n = cast(AssignStmt) node)
        return [n.left, n.value];
    if (auto n = cast(TypeOfExpr) node)
        return [n.value];
    return [];
}

struct ClassField
{
    dstring name;
    TypeExpr type;
    int access;
    Position pos;
    bool customAccess, readable, writable;
    FnDecl getter, setter;
    Decorator[] decorators;
}

class ClassDecl : Node
{
    dstring name, superName;
    ClassDecl superClass;
    ClassField[] fields;
    FnDecl[] methods;
    FnDecl signature;
    this(dstring name, dstring superName, Position pos)
    {
        super(NodeKind.ClassDecl, pos);
        this.name = name;
        this.superName = superName;
        signature = new FnDecl(name, [], new TypeExprNamed("qualquer", pos), [], 0, pos);
        signature.classFactory = this;
    }

    override void print(uint indent = 0)
    {
        writeln("ClassDecl ", name);
    }
}

class SuperExpr : Node
{
    dstring name;
    ClassDecl owner;
    this(dstring name, Position pos)
    {
        super(NodeKind.SuperExpr, pos);
        this.name = name;
    }

    override void print(uint indent = 0)
    {
        writeln("SuperExpr ", name);
    }
}

struct CatchClause
{
    dstring name;
    TypeExpr type;
    Node[] body;
    Position pos;
}

class TryStmt : Node
{
    Node[] body, finalBody;
    CatchClause[] catches;
    this(Node[] body, CatchClause[] catches, Node[] finalBody, Position pos)
    {
        super(NodeKind.TryStmt, pos);
        this.body = body;
        this.catches = catches;
        this.finalBody = finalBody;
    }

    override void print(uint indent = 0)
    {
        writeln("TryStmt");
    }
}

class ThrowStmt : Node
{
    Node value;
    this(Node value, Position pos)
    {
        super(NodeKind.ThrowStmt, pos);
        this.value = value;
    }

    override void print(uint indent = 0)
    {
        writeln("ThrowStmt");
    }
}

class ModuleUnit : Node
{
    string path;
    Program program;
    dstring linkName;
    bool analyzed, lowered;
    this(string path, Program program, Position pos)
    {
        super(NodeKind.ModuleUnit, pos);
        this.path = path;
        this.program = program;
        linkName = "#mod_"d ~ (nextFunctionId++).to!dstring;
    }

    override void print(uint indent = 0)
    {
        writeln("ModuleUnit ", path);
    }
}

class ImportExpr : Node
{
    Node path;
    ModuleUnit target;
    this(Node path, Position pos)
    {
        super(NodeKind.ImportExpr, pos);
        this.path = path;
    }

    override void print(uint indent = 0)
    {
        writeln("ImportExpr");
    }
}

class ConditionalExpr : Node
{
    Node condition, yes, no;
    this(Node c, Node y, Node n, Position pos)
    {
        super(NodeKind.ConditionalExpr, pos);
        condition = c;
        yes = y;
        no = n;
    }

    override void print(uint indent = 0)
    {
        writeln("ConditionalExpr");
    }
}

class SliceExpr : Node
{
    Node value, start, end, step;
    this(Node v, Node s, Node e, Node p, Position pos)
    {
        super(NodeKind.SliceExpr, pos);
        value = v;
        start = s;
        end = e;
        step = p;
    }

    override void print(uint indent = 0)
    {
        writeln("SliceExpr");
    }
}

class SpreadExpr : Node
{
    Node value;
    this(Node v, Position pos)
    {
        super(NodeKind.SpreadExpr, pos);
        value = v;
    }

    override void print(uint indent = 0)
    {
        writeln("SpreadExpr");
    }
}

class Comprehension : Node
{
    Node value, iterable, condition;
    dstring name;
    this(Node v, Node source, Node cond, dstring name, Position pos)
    {
        super(NodeKind.Comprehension, pos);
        value = v;
        iterable = source;
        condition = cond;
        this.name = name;
    }

    override void print(uint indent = 0)
    {
        writeln("Comprehension");
    }
}

struct SwitchCase
{
    Node[] values, body;
}

class SwitchStmt : Node
{
    Node value;
    SwitchCase[] cases;
    Node[] fallback;
    this(Node v, Position pos)
    {
        super(NodeKind.SwitchStmt, pos);
        value = v;
    }

    override void print(uint indent = 0)
    {
        writeln("SwitchStmt");
    }
}

class LoopExpr : Node
{
    Node loop;
    this(Node loop, Position pos)
    {
        super(NodeKind.LoopExpr, pos);
        this.loop = loop;
    }

    override void print(uint indent = 0)
    {
        writeln("LoopExpr");
    }
}

class SequenceStmt : Node
{
    Node[] body;
    this(Node[] body, Position pos)
    {
        super(NodeKind.SequenceStmt, pos);
        this.body = body;
    }

    override void print(uint indent = 0)
    {
        writeln("SequenceStmt");
    }
}

class TupleLit : ArrayLit
{
    this(Node[] elements, Position pos)
    {
        super(elements, pos);
        kind = NodeKind.TupleLit;
    }
}
