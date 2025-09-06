module frontend.parser.ast;

import std.stdio;
import frontend.lexer.token : Loc;
import frontend.values;
import frontend.lexer.token;
import middle.semantic_symbol_info;
import frontend.parser.ftype_info;
import frontend.parser.ast_utils;
import std.variant : Variant, Algebraic;
import std.typecons;

alias NullStmt = Nullable!Stmt;

enum NodeType
{
    Program,
    Identifier,

    VariableDeclaration,
    UninitializedVariableDeclaration,
    MultipleVariableDeclaration,
    MultipleUninitializedVariableDeclaration,
    ReturnStatement,
    FunctionDeclaration,
    AssignmentDeclaration,
    ClassDeclaration,
    ConstructorDeclaration,
    DestructorDeclaration,

    IfStatement,
    ElseStatement,
    ForStatement,
    WhileStatement,
    DoWhileStatement,
    SwitchStatement,
    CaseStatement,
    DefaultStatement,
    BreakStatement,
    ImportStatement,

    IntLiteral,
    FloatLiteral,
    StringLiteral,
    NullLiteral,
    BoolLiteral,
    ArrayLiteral,

    DereferenceExpr,
    AddressOfExpr,
    UnaryExpr,
    CallExpr,
    CastExpr,
    BinaryExpr,
    MemberCallExpr,
    NewExpr,
    ThisExpr,
    IndexExpr,

    IndexExprAssignment,
    MemberAssignment,
}

string repeat(string s, int times)
{
    string result;
    foreach (_; 0 .. times)
        result ~= s;
    return result;
}

class Stmt
{
    NodeType kind;
    FTypeInfo type;
    Variant value;
    Loc loc;
    Stmt[] args;

    void print(int indent = 0)
    {
        string spaces = " ".repeat(indent);
        writefln("%s└── Stmt [%s]", spaces, kind);
        if (args.length > 0)
        {
            writefln("%s    ├── args:", spaces);
            foreach (arg; args)
            {
                arg.print(indent + 8);
            }
        }
    }
}

class Program : Stmt
{
    Stmt[] body;

    this(Stmt[] body)
    {
        this.kind = NodeType.Program;
        this.body = body;
    }

    override void print(int indent = 0)
    {
        string spaces = " ".repeat(indent);
        writefln("%s└── Program", spaces);
        if (body.length > 0)
        {
            writefln("%s    ├── body (%d statements):", spaces, body.length);
            foreach (i, stmt; body)
            {
                if (i == body.length - 1)
                    writefln("%s        └──", spaces);
                else
                    writefln("%s        ├──", spaces);
                stmt.print(indent + 12);
            }
        }
    }
}

class BinaryExpr : Stmt
{
    Stmt left, right;
    string op;

    this(Stmt left, Stmt right, string op, Loc loc)
    {
        this.kind = NodeType.BinaryExpr;
        this.left = left;
        this.right = right;
        this.op = op;
        this.loc = loc;
    }

    override void print(int indent = 0)
    {
        string spaces = " ".repeat(indent);
        writefln("%s└── BinaryExpr [%s]", spaces, op);
        writefln("%s    ├── left:", spaces);
        left.print(indent + 8);
        writefln("%s    └── right:", spaces);
        right.print(indent + 8);
    }
}

class IntLiteral : Stmt
{
    this(long value, FTypeInfo type, Loc loc)
    {
        this.kind = NodeType.IntLiteral;
        this.type = type;
        this.value = value;
        this.loc = loc;
    }

    override void print(int indent = 0)
    {
        string spaces = " ".repeat(indent);
        writefln("%s└── IntLiteral: %d", spaces, value.get!long);
    }
}

class NullLiteral : Stmt
{
    this(Loc loc)
    {
        this.kind = NodeType.NullLiteral;
        this.type = createTypeInfo(TypesNative.NULO);
        this.value = null;
        this.loc = loc;
    }

    override void print(int indent = 0)
    {
        string spaces = " ".repeat(indent);
        writefln("%s└── NullLiteral: null", spaces);
    }
}

class BoolLiteral : Stmt
{
    this(bool value, Loc loc)
    {
        this.kind = NodeType.BoolLiteral;
        this.type = createTypeInfo(TypesNative.I1);
        this.value = value;
        this.loc = loc;
    }

    override void print(int indent = 0)
    {
        string spaces = " ".repeat(indent);
        writefln("%s└── BoolLiteral: %s", spaces, value.get!bool ? "true" : "false");
    }
}

class FloatLiteral : Stmt
{
    this(double value, FTypeInfo type, Loc loc)
    {
        this.kind = NodeType.FloatLiteral;
        this.type = type;
        this.value = value;
        this.loc = loc;
    }

    override void print(int indent = 0)
    {
        string spaces = " ".repeat(indent);
        writefln("%s└── FloatLiteral: %.2f", spaces, value.get!double);
    }
}

class StringLiteral : Stmt
{
    this(string value, Loc loc)
    {
        this.kind = NodeType.StringLiteral;
        this.type = createTypeInfo(TypesNative.I8P);
        this.value = value;
        this.loc = loc;
    }

    override void print(int indent = 0)
    {
        string spaces = " ".repeat(indent);
        writefln("%s└── StringLiteral: \"%s\"", spaces, value.get!string);
    }
}

class ArrayLiteral : Stmt
{
    Stmt[] elements;
    this(Stmt[] elements, FTypeInfo type, Loc loc)
    {
        this.kind = NodeType.ArrayLiteral;
        this.type = type;
        this.elements = elements;
        this.value = null;
        this.loc = loc;
    }

    override void print(int indent = 0)
    {
        string spaces = " ".repeat(indent);
        writefln("%s└── ArrayLiteral [%d elements]", spaces, elements.length);
        if (elements.length > 0)
        {
            writefln("%s    └── elements:", spaces);
            foreach (i, element; elements)
            {
                if (i == elements.length - 1)
                    writefln("%s        └──", spaces);
                else
                    writefln("%s        ├──", spaces);
                element.print(indent + 12);
            }
        }
    }
}

class CastExpr : Stmt
{
    Stmt expr;

    this(FTypeInfo type, Stmt expr, Loc loc)
    {
        this.kind = NodeType.CastExpr;
        this.type = type;
        this.expr = expr;
        this.value = null;
        this.loc = loc;
    }

    override void print(int indent = 0)
    {
        string spaces = " ".repeat(indent);
        writefln("%s└── CastExpr", spaces);
        writefln("%s    └── expr:", spaces);
        expr.print(indent + 8);
    }
}

class Identifier : Stmt
{
    this(string id, Loc loc)
    {
        this.kind = NodeType.Identifier;
        this.type = createTypeInfo(TypesNative.POINTER);
        this.value = id;
        this.loc = loc;
    }

    override void print(int indent = 0)
    {
        string spaces = " ".repeat(indent);
        writefln("%s└── Identifier: %s", spaces, value.get!string);
    }
}

class UninitializedVariableDeclaration : Stmt
{
    Identifier id;
    bool mut;

    this(Identifier id, FTypeInfo type, bool mut, Loc loc)
    {
        this.kind = NodeType.UninitializedVariableDeclaration;
        this.id = id;
        this.type = type;
        this.mut = mut;
        this.loc = loc;
        this.value = null;
    }

    override void print(int indent = 0)
    {
        string spaces = " ".repeat(indent);
        writefln("%s└── UninitializedVariableDeclaration [mut: %s]", spaces, mut ? "true"
                : "false");
        writefln("%s    └── id:", spaces);
        id.print(indent + 8);
    }
}

struct VariablePair
{
    Identifier id;
    Stmt value;
    FTypeInfo type;
    bool mut;

    this(Identifier id, Stmt value, FTypeInfo type, bool mut)
    {
        this.id = id;
        this.value = value;
        this.type = type;
        this.mut = mut;
    }

    void print(int indent = 0)
    {
        string spaces = " ".repeat(indent);
        writefln("%s└── VariablePair [mut: %s]", spaces, mut ? "true" : "false");
        writefln("%s    ├── id:", spaces);
        id.print(indent + 8);
        writefln("%s    └── value:", spaces);
        value.print(indent + 8);
    }
}

class MultipleVariableDeclaration : Stmt
{
    VariablePair[] declarations;
    FTypeInfo commonType;

    this(VariablePair[] declarations, FTypeInfo commonType, Loc loc)
    {
        this.kind = NodeType.MultipleVariableDeclaration;
        this.declarations = declarations;
        this.commonType = commonType;
        this.loc = loc;
        this.type = createTypeInfo(TypesNative.NULO);
        this.value = null;
    }

    override void print(int indent = 0)
    {
        string spaces = " ".repeat(indent);
        writefln("%s└── MultipleVariableDeclaration [%d declarations]", spaces, declarations
                .length);
        if (declarations.length > 0)
        {
            writefln("%s    └── declarations:", spaces);
            foreach (i, decl; declarations)
            {
                if (i == declarations.length - 1)
                    writefln("%s        └──", spaces);
                else
                    writefln("%s        ├──", spaces);
                decl.print(indent + 12);
            }
        }
    }

    Identifier[] getIdentifiers()
    {
        Identifier[] ids;
        foreach (decl; declarations)
        {
            ids ~= decl.id;
        }
        return ids;
    }

    Stmt[] getValues()
    {
        Stmt[] values;
        foreach (decl; declarations)
        {
            values ~= decl.value;
        }
        return values;
    }

    FTypeInfo[] getTypes()
    {
        FTypeInfo[] types;
        foreach (decl; declarations)
        {
            types ~= decl.type;
        }
        return types;
    }
}

class MultipleUninitializedVariableDeclaration : Stmt
{
    Identifier[] ids;
    FTypeInfo commonType;
    bool mut;

    this(Identifier[] ids, FTypeInfo commonType, bool mut, Loc loc)
    {
        this.kind = NodeType.MultipleUninitializedVariableDeclaration;
        this.ids = ids;
        this.commonType = commonType;
        this.mut = mut;
        this.loc = loc;
        this.type = commonType;
        this.value = null;
    }

    override void print(int indent = 0)
    {
        string spaces = " ".repeat(indent);
        writefln("%s└── MultipleUninitializedVariableDeclaration [mut: %s, %d ids]", spaces, mut ? "true"
                : "false", ids.length);
        if (ids.length > 0)
        {
            writefln("%s    └── ids:", spaces);
            foreach (i, id; ids)
            {
                if (i == ids.length - 1)
                    writefln("%s        └──", spaces);
                else
                    writefln("%s        ├──", spaces);
                id.print(indent + 12);
            }
        }
    }
}

class VariableDeclaration : Stmt
{
    Identifier id;
    bool mut;

    this(Identifier id, Stmt value, FTypeInfo type, bool mut, Loc loc)
    {
        this.kind = NodeType.VariableDeclaration;
        this.id = id;
        this.value = value;
        this.type = type;
        this.mut = mut;
        this.loc = loc;
    }

    override void print(int indent = 0)
    {
        string spaces = " ".repeat(indent);
        writefln("%s└── VariableDeclaration [mut: %s]", spaces, mut ? "true" : "false");
        writefln("%s    ├── id:", spaces);
        id.print(indent + 8);
        if (value.hasValue())
        {
            writefln("%s    └── value:", spaces);
            value.get!Stmt.print(indent + 8);
        }
    }

    bool isInitialized()
    {
        return this.value.hasValue();
    }
}

class VariableDeclarationFactory
{
    static VariableDeclaration createInitialized(Identifier id, Stmt value, FTypeInfo type, bool mut, Loc loc)
    {
        return new VariableDeclaration(id, value, type, mut, loc);
    }

    static UninitializedVariableDeclaration createUninitialized(Identifier id, FTypeInfo type, bool mut, Loc loc)
    {
        return new UninitializedVariableDeclaration(id, type, mut, loc);
    }

    static MultipleVariableDeclaration createMultipleInitialized(
        Identifier[] ids,
        Stmt[] values,
        FTypeInfo commonType,
        bool mut,
        Loc loc
    )
    {
        if (ids.length != values.length)
        {
            throw new Exception(
                "Número de identificadores deve corresponder ao número de valores");
        }

        VariablePair[] pairs;
        foreach (i; 0 .. ids.length)
        {
            FTypeInfo finalType = commonType.baseType != TypesNative.NULO ? commonType
                : values[i].type;
            pairs ~= VariablePair(ids[i], values[i], finalType, mut);
        }

        return new MultipleVariableDeclaration(pairs, commonType, loc);
    }

    static MultipleUninitializedVariableDeclaration createMultipleUninitialized(
        Identifier[] ids,
        FTypeInfo commonType,
        bool mut,
        Loc loc
    )
    {
        if (commonType.baseType == TypesNative.NULO)
        {
            throw new Exception(
                "Tipo deve ser especificado para declarações múltiplas não inicializadas");
        }

        return new MultipleUninitializedVariableDeclaration(ids, commonType, mut, loc);
    }
}

class CallExpr : Stmt
{
    Identifier calle;
    Stmt[] args;

    this(Identifier calle, Stmt[] args, Loc loc)
    {
        this.kind = NodeType.CallExpr;
        this.calle = calle;
        this.loc = loc;
        this.args = args;
        this.type = createTypeInfo(TypesNative.NULO);
    }

    override void print(int indent = 0)
    {
        string spaces = " ".repeat(indent);
        writefln("%s└── CallExpr", spaces);
        writefln("%s    ├── calle:", spaces);
        calle.print(indent + 8);
        if (args.length > 0)
        {
            writefln("%s    └── args [%d]:", spaces, args.length);
            foreach (i, arg; args)
            {
                if (i == args.length - 1)
                    writefln("%s        └──", spaces);
                else
                    writefln("%s        ├──", spaces);
                arg.print(indent + 12);
            }
        }
    }
}

class IfStatement : Stmt
{
    Stmt condition;
    Stmt[] primary;
    NullStmt secondary;

    this(Stmt condition, Stmt[] primary, FTypeInfo type, Variant value, Loc loc, NullStmt secondary = null)
    {
        this.kind = NodeType.IfStatement;
        this.condition = condition;
        this.primary = primary;
        this.secondary = secondary;
        this.value = value;
        this.loc = loc;
        this.type = type;
    }

    override void print(int indent = 0)
    {
        string spaces = " ".repeat(indent);
        writefln("%s└── IfStatement", spaces);
        writefln("%s    ├── condition:", spaces);
        condition.print(indent + 8);
        writefln("%s    ├── primary [%d statements]:", spaces, primary.length);
        foreach (i, stmt; primary)
        {
            if (i == primary.length - 1 && secondary.isNull())
                writefln("%s        └──", spaces);
            else
                writefln("%s        ├──", spaces);
            stmt.print(indent + 12);
        }
        if (!secondary.isNull())
        {
            writefln("%s    └── secondary:", spaces);
            secondary.get().print(indent + 8);
        }
    }
}

class ElifStatement : IfStatement
{
    this(Stmt condition, Stmt[] primary, FTypeInfo type, Variant value, Loc loc, NullStmt secondary = null)
    {
        super(condition, primary, type, value, loc);
    }

    override void print(int indent = 0)
    {
        string spaces = " ".repeat(indent);
        writefln("%s└── ElifStatement", spaces);
        writefln("%s    ├── condition:", spaces);
        condition.print(indent + 8);
        writefln("%s    ├── primary [%d statements]:", spaces, primary.length);
        foreach (i, stmt; primary)
        {
            if (i == primary.length - 1 && secondary.isNull())
                writefln("%s        └──", spaces);
            else
                writefln("%s        ├──", spaces);
            stmt.print(indent + 12);
        }
        if (!secondary.isNull())
        {
            writefln("%s    └── secondary:", spaces);
            secondary.get().print(indent + 8);
        }
    }
}

class ElseStatement : Stmt
{
    Stmt[] primary;

    this(Stmt[] primary, FTypeInfo type, Variant value, Loc loc)
    {
        this.kind = NodeType.ElseStatement;
        this.primary = primary;
        this.value = value;
        this.loc = loc;
        this.type = type;
    }

    override void print(int indent = 0)
    {
        string spaces = " ".repeat(indent);
        writefln("%s└── ElseStatement [%d statements]", spaces, primary.length);
        if (primary.length > 0)
        {
            writefln("%s    └── primary:", spaces);
            foreach (i, stmt; primary)
            {
                if (i == primary.length - 1)
                    writefln("%s        └──", spaces);
                else
                    writefln("%s        ├──", spaces);
                stmt.print(indent + 12);
            }
        }
    }
}

class UnaryExpr : Stmt
{
    string op; // "-", "!", "&", "*"
    Stmt operand;
    bool postFix;

    this(string op, Stmt operand, Loc loc, bool postFix = false)
    {
        this.kind = NodeType.UnaryExpr;
        this.op = op;
        this.postFix = postFix;
        this.operand = operand;
        this.value = null;
        this.type = createTypeInfo(TypesNative.NULO);
        this.loc = loc;
    }

    override void print(int indent = 0)
    {
        string spaces = " ".repeat(indent);
        writefln("%s└── UnaryExpr [%s] (postfix: %s)", spaces, op, postFix ? "true" : "false");
        writefln("%s    └── operand:", spaces);
        operand.print(indent + 8);
    }
}

class DereferenceExpr : Stmt
{
    Stmt operand;

    this(Stmt operand, Loc loc)
    {
        this.kind = NodeType.DereferenceExpr;
        this.operand = operand;
        this.value = null;
        this.type = createTypeInfo(TypesNative.NULO);
        this.loc = loc;
    }

    override void print(int indent = 0)
    {
        string spaces = " ".repeat(indent);
        writefln("%s└── DereferenceExpr", spaces);
        writefln("%s    └── operand:", spaces);
        operand.print(indent + 8);
    }
}

class AddressOfExpr : Stmt
{
    Stmt operand;

    this(Stmt operand, Loc loc)
    {
        this.kind = NodeType.AddressOfExpr;
        this.operand = operand;
        this.value = null;
        this.type = createTypeInfo(TypesNative.NULO);
        this.loc = loc;
    }

    override void print(int indent = 0)
    {
        string spaces = " ".repeat(indent);
        writefln("%s└── AddressOfExpr", spaces);
        writefln("%s    └── operand:", spaces);
        operand.print(indent + 8);
    }
}

// FunctionDeclaration

class FunctionArg
{
    Identifier id;
    FTypeInfo type;
    Nullable!Stmt def; // Default, like: function fernando(x: int = 10) {}

    this(Identifier id, FTypeInfo type, Nullable!Stmt def = null)
    {
        this.id = id;
        this.type = type;
        this.def = def;
    }

    void print(int indent = 0)
    {
        string spaces = " ".repeat(indent);
        writefln("%s└── FunctionArg", spaces);
        writefln("%s    ├── id:", spaces);
        id.print(indent + 8);
        if (!def.isNull())
        {
            writefln("%s    └── default:", spaces);
            if (def.get() !is null)
                def.get().print(indent + 8);
        }
    }
}

alias FunctionArgs = FunctionArg[];

class FunctionDeclaration : Stmt
{
    Identifier id;
    FunctionArgs args;
    Stmt[] body;
    SymbolInfo[string] context;

    this(Identifier id, FunctionArgs args, Stmt[] body, FTypeInfo type, Loc loc)
    {
        this.id = id;
        this.args = args;
        this.kind = NodeType.FunctionDeclaration;
        this.body = body;
        this.loc = loc;
        this.type = type;
        this.value = null;
    }

    override void print(int indent = 0)
    {
        string spaces = " ".repeat(indent);
        writefln("%s└── FunctionDeclaration", spaces);
        writefln("%s    ├── id:", spaces);
        id.print(indent + 8);
        if (args.length > 0)
        {
            writefln("%s    ├── args [%d]:", spaces, args.length);
            foreach (i, arg; args)
            {
                if (i == args.length - 1)
                    writefln("%s        └──", spaces);
                else
                    writefln("%s        ├──", spaces);
                arg.print(indent + 12);
            }
        }
        writefln("%s    └── body [%d statements]:", spaces, body.length);
        foreach (i, stmt; body)
        {
            if (i == body.length - 1)
                writefln("%s        └──", spaces);
            else
                writefln("%s        ├──", spaces);
            stmt.print(indent + 12);
        }
    }
}

class ReturnStatement : Stmt
{
    Stmt expr;

    this(Stmt expr, Loc loc)
    {
        this.kind = NodeType.ReturnStatement;
        this.expr = expr;
        this.value = null;
        this.loc = loc;
        this.type = createTypeInfo(TypesNative.NULO);
    }

    override void print(int indent = 0)
    {
        string spaces = " ".repeat(indent);
        writefln("%s└── ReturnStatement", spaces);
        if (expr !is null)
        {
            writefln("%s    └── expr:", spaces);
            expr.print(indent + 8);
        }
    }
}

class ForStatement : Stmt
{
    // varDecl, cond, expr, body
    // for var i = 10; cond; expr {}
    // for i = 10; cond; expr {}
    Stmt _init;
    Stmt cond;
    Stmt expr;
    Stmt[] body;

    this(Stmt _init, Stmt cond, Stmt expr, Stmt[] body, Loc loc)
    {
        this.kind = NodeType.ForStatement;
        this.value = null;
        this._init = _init;
        this.cond = cond;
        this.expr = expr;
        this.body = body;
        this.loc = loc;
        this.type = createTypeInfo(TypesNative.NULO);
    }

    override void print(int indent = 0)
    {
        string spaces = " ".repeat(indent);
        writefln("%s└── ForStatement", spaces);
        writefln("%s    ├── init:", spaces);
        if (_init !is null)
            _init.print(indent + 8);
        writefln("%s    ├── condition:", spaces);
        if (cond !is null)
            cond.print(indent + 8);
        writefln("%s    ├── expr:", spaces);
        if (expr !is null)
            expr.print(indent + 8);
        writefln("%s    └── body [%d statements]:", spaces, body.length);
        foreach (i, stmt; body)
        {
            if (i == body.length - 1)
                writefln("%s        └──", spaces);
            else
                writefln("%s        ├──", spaces);
            stmt.print(indent + 12);
        }
    }
}

class WhileStatement : Stmt
{
    // while cond body
    Stmt cond;
    Stmt[] body;

    this(Stmt cond, Stmt[] body, Loc loc)
    {
        this.kind = NodeType.WhileStatement;
        this.value = null;
        this.cond = cond;
        this.body = body;
        this.loc = loc;
        this.type = createTypeInfo(TypesNative.NULO);
    }

    override void print(int indent = 0)
    {
        string spaces = " ".repeat(indent);
        writefln("%s└── WhileStatement", spaces);
        writefln("%s    ├── condition:", spaces);
        cond.print(indent + 8);
        writefln("%s    └── body [%d statements]:", spaces, body.length);
        foreach (i, stmt; body)
        {
            if (i == body.length - 1)
                writefln("%s        └──", spaces);
            else
                writefln("%s        ├──", spaces);
            stmt.print(indent + 12);
        }
    }
}

class DoWhileStatement : Stmt
{
    // while cond body
    Stmt cond;
    Stmt[] body;

    this(Stmt cond, Stmt[] body, Loc loc)
    {
        this.kind = NodeType.DoWhileStatement;
        this.value = null;
        this.cond = cond;
        this.body = body;
        this.loc = loc;
        this.type = createTypeInfo(TypesNative.NULO);
    }

    override void print(int indent = 0)
    {
        string spaces = " ".repeat(indent);
        writefln("%s└── DoWhileStatement", spaces);
        writefln("%s    ├── body [%d statements]:", spaces, body.length);
        foreach (i, stmt; body)
        {
            if (i == body.length - 1)
                writefln("%s        └──", spaces);
            else
                writefln("%s        ├──", spaces);
            stmt.print(indent + 12);
        }
        writefln("%s    └── condition:", spaces);
        cond.print(indent + 8);
    }
}

class AssignmentDeclaration : Stmt
{
    Identifier id;

    this(Identifier id, Stmt value, FTypeInfo type, Loc loc)
    {
        this.kind = NodeType.AssignmentDeclaration;
        this.id = id;
        this.value = value;
        this.type = type;
        this.loc = loc;
    }

    override void print(int indent = 0)
    {
        string spaces = " ".repeat(indent);
        writefln("%s└── AssignmentDeclaration", spaces);
        writefln("%s    ├── id:", spaces);
        id.print(indent + 8);
        writefln("%s    └── value:", spaces);
        value.get!Stmt.print(indent + 8);
    }
}

class MemberCallExpr : Stmt
{
    Stmt object; // A expressão à esquerda do ponto ("String".tamanho) -> "String"
    Identifier member; // O membro sendo chamado
    Stmt[] args; // Argumentos se for uma chamada de método
    bool isMethodCall; // true se for x.method(), false se for x.property

    this(Stmt object, Identifier member, Stmt[] args, bool isMethodCall, Loc loc)
    {
        this.kind = NodeType.MemberCallExpr;
        this.object = object;
        this.member = member;
        this.args = args;
        this.isMethodCall = isMethodCall;
        this.loc = loc;
        this.type = createTypeInfo(TypesNative.NULO);
        this.value = null;
    }

    override void print(int indent = 0)
    {
        string spaces = " ".repeat(indent);
        writefln("%s└── MemberCallExpr [%s]", spaces, isMethodCall ? "method" : "property");
        writefln("%s    ├── object:", spaces);
        object.print(indent + 8);
        writefln("%s    ├── member:", spaces);
        member.print(indent + 8);
        if (args.length > 0)
        {
            writefln("%s    └── args [%d]:", spaces, args.length);
            foreach (i, arg; args)
            {
                if (i == args.length - 1)
                    writefln("%s        └──", spaces);
                else
                    writefln("%s        ├──", spaces);
                arg.print(indent + 12);
            }
        }
    }
}

class SwitchStatement : Stmt
{
    Stmt condition;
    CaseStatement[] cases;
    DefaultStatement defaultCase;

    this(Stmt condition, CaseStatement[] cases, DefaultStatement defaultCase, Loc loc)
    {
        this.kind = NodeType.SwitchStatement;
        this.condition = condition;
        this.cases = cases;
        this.defaultCase = defaultCase;
        this.loc = loc;
        this.type = createTypeInfo(TypesNative.NULO);
        this.value = null;
    }

    override void print(int indent = 0)
    {
        string spaces = " ".repeat(indent);
        writefln("%s└── SwitchStatement", spaces);
        writefln("%s    ├── condition:", spaces);
        condition.print(indent + 8);
        if (cases.length > 0)
        {
            writefln("%s    ├── cases [%d]:", spaces, cases.length);
            foreach (i, caseStmt; cases)
            {
                if (i == cases.length - 1 && defaultCase is null)
                    writefln("%s        └──", spaces);
                else
                    writefln("%s        ├──", spaces);
                caseStmt.print(indent + 12);
            }
        }
        if (defaultCase !is null)
        {
            writefln("%s    └── default:", spaces);
            defaultCase.print(indent + 8);
        }
    }
}

class CaseStatement : Stmt
{
    Stmt value; // Valor do caso
    Stmt[] body; // Corpo do caso

    this(Stmt value, Stmt[] body, Loc loc)
    {
        this.kind = NodeType.CaseStatement;
        this.value = value;
        this.body = body;
        this.loc = loc;
        this.type = createTypeInfo(TypesNative.NULO);
    }

    override void print(int indent = 0)
    {
        string spaces = " ".repeat(indent);
        writefln("%s└── CaseStatement", spaces);
        writefln("%s    ├── value:", spaces);
        value.print(indent + 8);
        writefln("%s    └── body [%d statements]:", spaces, body.length);
        foreach (i, stmt; body)
        {
            if (i == body.length - 1)
                writefln("%s        └──", spaces);
            else
                writefln("%s        ├──", spaces);
            stmt.print(indent + 12);
        }
    }
}

class DefaultStatement : Stmt
{
    Stmt[] body; // Corpo do caso padrão

    this(Stmt[] body, Loc loc)
    {
        this.kind = NodeType.DefaultStatement;
        this.body = body;
        this.loc = loc;
        this.type = createTypeInfo(TypesNative.NULO);
        this.value = null;
    }

    override void print(int indent = 0)
    {
        string spaces = " ".repeat(indent);
        writefln("%s└── DefaultStatement [%d statements]", spaces, body.length);
        if (body.length > 0)
        {
            writefln("%s    └── body:", spaces);
            foreach (i, stmt; body)
            {
                if (i == body.length - 1)
                    writefln("%s        └──", spaces);
                else
                    writefln("%s        ├──", spaces);
                stmt.print(indent + 12);
            }
        }
    }
}

class BreakStatement : Stmt
{
    this(Loc loc)
    {
        this.kind = NodeType.BreakStatement;
        this.loc = loc;
        this.type = createTypeInfo(TypesNative.NULO);
        this.value = null;
    }

    override void print(int indent = 0)
    {
        string spaces = " ".repeat(indent);
        writefln("%s└── BreakStatement", spaces);
    }
}

enum ClassVisibility : string
{
    PRIVATE = "private",
    PUBLIC = "public",
}

// a: inteiro = 10
struct ClassProperty
{
    Identifier name;
    FTypeInfo type;
    ClassVisibility visibility;
    Stmt defaultValue;

    void print(int indent = 0)
    {
        string spaces = " ".repeat(indent);
        writefln("%s└── ClassProperty [%s]", spaces, visibility);
        writefln("%s    ├── name:", spaces);
        name.print(indent + 8);
        if (defaultValue !is null)
        {
            writefln("%s    └── defaultValue:", spaces);
            defaultValue.print(indent + 8);
        }
    }
}

// a() {}
class ClassMethodDeclaration : Stmt
{
    Identifier id;
    FunctionArgs args;
    Stmt[] body;
    SymbolInfo[string] context; // compartilha com a classe
    ClassVisibility visibility;

    this(Identifier id, FunctionArgs args, Stmt[] body, FTypeInfo type, ClassVisibility visibility, Loc loc)
    {
        this.id = id;
        this.args = args;
        this.kind = NodeType.FunctionDeclaration;
        this.body = body;
        this.loc = loc;
        this.type = type;
        this.visibility = visibility;
        this.value = null;
    }

    override void print(int indent = 0)
    {
        string spaces = " ".repeat(indent);
        writefln("%s└── ClassMethodDeclaration [%s]", spaces, visibility);
        writefln("%s    ├── id:", spaces);
        id.print(indent + 8);
        if (args.length > 0)
        {
            writefln("%s    ├── args [%d]:", spaces, args.length);
            foreach (i, arg; args)
            {
                if (i == args.length - 1)
                    writefln("%s        └──", spaces);
                else
                    writefln("%s        ├──", spaces);
                arg.print(indent + 12);
            }
        }
        writefln("%s    └── body [%d statements]:", spaces, body.length);
        foreach (i, stmt; body)
        {
            if (i == body.length - 1)
                writefln("%s        └──", spaces);
            else
                writefln("%s        ├──", spaces);
            stmt.print(indent + 12);
        }
    }
}

class ClassDeclaration : Stmt
{
    Identifier id;
    ClassProperty[] properties;
    ClassMethodDeclaration[] methods;
    ConstructorDeclaration construct; // método construtor
    DestructorDeclaration destruct; // método destrutor
    SymbolInfo[string] context; // salva o contexto global

    this(ClassProperty[] p, ClassMethodDeclaration[] m, Loc loc)
    {
        this.kind = NodeType.ClassDeclaration;
        this.properties = p;
        this.methods = m;
        this.value = null;
        this.type = createTypeInfo(TypesNative.NULO);
        this.loc = loc;
    }

    override void print(int indent = 0)
    {
        string spaces = " ".repeat(indent);
        writefln("%s└── ClassDeclaration", spaces);
        if (id !is null)
        {
            writefln("%s    ├── id:", spaces);
            id.print(indent + 8);
        }
        if (properties.length > 0)
        {
            writefln("%s    ├── properties [%d]:", spaces, properties.length);
            foreach (i, prop; properties)
            {
                if (i == properties.length - 1 && methods.length == 0 && construct is null && destruct is null)
                    writefln("%s        └──", spaces);
                else
                    writefln("%s        ├──", spaces);
                prop.print(indent + 12);
            }
        }
        if (methods.length > 0)
        {
            writefln("%s    ├── methods [%d]:", spaces, methods.length);
            foreach (i, method; methods)
            {
                if (i == methods.length - 1 && construct is null && destruct is null)
                    writefln("%s        └──", spaces);
                else
                    writefln("%s        ├──", spaces);
                method.print(indent + 12);
            }
        }
        if (construct !is null)
        {
            writefln("%s    ├── constructor:", spaces);
            construct.print(indent + 8);
        }
        if (destruct !is null)
        {
            writefln("%s    └── destructor:", spaces);
            destruct.print(indent + 8);
        }
    }
}

// Adicionar novas classes AST:

class ConstructorDeclaration : Stmt
{
    Identifier id;
    FunctionArgs args;
    Stmt[] body;
    SymbolInfo[string] context;
    ClassVisibility visibility;

    this(FunctionArgs args, Stmt[] body, Loc loc)
    {
        this.id = new Identifier("_", loc);
        this.visibility = ClassVisibility.PUBLIC;
        this.kind = NodeType.ConstructorDeclaration;
        this.args = args;
        this.body = body;
        this.loc = loc;
        this.type = createTypeInfo(TypesNative.NULO);
        this.value = null;
    }

    override void print(int indent = 0)
    {
        string spaces = " ".repeat(indent);
        writefln("%s└── ConstructorDeclaration [%s]", spaces, visibility);
        if (args.length > 0)
        {
            writefln("%s    ├── args [%d]:", spaces, args.length);
            foreach (i, arg; args)
            {
                if (i == args.length - 1)
                    writefln("%s        └──", spaces);
                else
                    writefln("%s        ├──", spaces);
                arg.print(indent + 12);
            }
        }
        writefln("%s    └── body [%d statements]:", spaces, body.length);
        foreach (i, stmt; body)
        {
            if (i == body.length - 1)
                writefln("%s        └──", spaces);
            else
                writefln("%s        ├──", spaces);
            stmt.print(indent + 12);
        }
    }
}

class DestructorDeclaration : Stmt
{
    Stmt[] body;
    SymbolInfo[string] context;

    this(Stmt[] body, Loc loc)
    {
        this.kind = NodeType.DestructorDeclaration;
        this.body = body;
        this.loc = loc;
        this.type = createTypeInfo(TypesNative.NULO);
        this.value = null;
    }

    override void print(int indent = 0)
    {
        string spaces = " ".repeat(indent);
        writefln("%s└── DestructorDeclaration [%d statements]", spaces, body.length);
        if (body.length > 0)
        {
            writefln("%s    └── body:", spaces);
            foreach (i, stmt; body)
            {
                if (i == body.length - 1)
                    writefln("%s        └──", spaces);
                else
                    writefln("%s        ├──", spaces);
                stmt.print(indent + 12);
            }
        }
    }
}

class NewExpr : Stmt
{
    Identifier className;
    Stmt[] args;

    this(Identifier className, Stmt[] args, Loc loc)
    {
        this.kind = NodeType.NewExpr;
        this.className = className;
        this.args = args;
        this.loc = loc;
        this.type = createTypeInfo(TypesNative.NULO); // Será definido durante análise semântica
        this.value = null;
    }

    override void print(int indent = 0)
    {
        string spaces = " ".repeat(indent);
        writefln("%s└── NewExpr", spaces);
        writefln("%s    ├── className:", spaces);
        className.print(indent + 8);
        if (args.length > 0)
        {
            writefln("%s    └── args [%d]:", spaces, args.length);
            foreach (i, arg; args)
            {
                if (i == args.length - 1)
                    writefln("%s        └──", spaces);
                else
                    writefln("%s        ├──", spaces);
                arg.print(indent + 12);
            }
        }
    }
}

class ThisExpr : Stmt
{
    this(Loc loc)
    {
        this.kind = NodeType.ThisExpr;
        this.loc = loc;
        this.type = createTypeInfo(TypesNative.NULO); // Será definido durante análise semântica
        this.value = null;
    }

    override void print(int indent = 0)
    {
        string spaces = " ".repeat(indent);
        writefln("%s└── ThisExpr", spaces);
    }
}

// importar "lib"
// importar { ids, ... } de "lib"
// importar "lib" como x
// importar { ids, ... } de "lib" como x
class ImportStatement : Stmt
{
    Identifier[] targets;
    string from; // lib|file.delegua
    string _alias;

    this(string from, string _alias = "", Identifier[] targets = [], Loc loc)
    {
        this.kind = NodeType.ImportStatement;
        this.value = null;
        this.from = from;
        this._alias = _alias;
        this.targets = targets;
        this.loc = loc;
        this.type = createTypeInfo(TypesNative.NULO);
    }

    override void print(int indent = 0)
    {
        string spaces = " ".repeat(indent);
        writefln("%s└── ImportStatement", spaces);
        writefln("%s    ├── from: \"%s\"", spaces, from);
        if (_alias != "")
        {
            writefln("%s    ├── alias: \"%s\"", spaces, _alias);
        }
        if (targets.length > 0)
        {
            writefln("%s    └── targets [%d]:", spaces, targets.length);
            foreach (i, target; targets)
            {
                if (i == targets.length - 1)
                    writefln("%s        └──", spaces);
                else
                    writefln("%s        ├──", spaces);
                target.print(indent + 12);
            }
        }
    }
}

class IndexExpr : Stmt
{
    Stmt left, index;
    this(Stmt left, Stmt index, Loc loc)
    {
        this.kind = NodeType.IndexExpr;
        this.left = left;
        this.index = index;
        this.type = left.type; // permite encadeamento
        this.value = null;
        this.loc = loc;
    }

    override void print(int indent = 0)
    {
        string spaces = " ".repeat(indent);
        writefln("%s└── IndexExpr", spaces);
        writefln("%s    ├── left:", spaces);
        left.print(indent + 8);
        writefln("%s    └── index:", spaces);
        index.print(indent + 8);
    }
}

class IndexExprAssignment : Stmt
{
    Stmt left, index, value;
    this(Stmt left, Stmt index, Stmt value, Loc loc)
    {
        this.kind = NodeType.IndexExprAssignment;
        this.left = left;
        this.index = index;
        this.type = left.type; // permite encadeamento
        this.value = value;
        this.loc = loc;
    }

    override void print(int indent = 0)
    {
        string spaces = " ".repeat(indent);
        writefln("%s└── IndexExprAssignment", spaces);
        writefln("%s    ├── left:", spaces);
        left.print(indent + 8);
        writefln("%s    ├── index:", spaces);
        index.print(indent + 8);
        writefln("%s    └── value:", spaces);
        value.print(indent + 8);
    }
}

// x.o = v
class MemberAssignment : Stmt
{
    Stmt left, value;
    Identifier member;
    this(Stmt left, Identifier member, Stmt value, Loc loc)
    {
        this.kind = NodeType.MemberAssignment;
        this.left = left;
        this.member = member;
        this.type = left.type; // permite encadeamento
        this.value = value;
        this.loc = loc;
    }

    override void print(int indent = 0)
    {
        string spaces = " ".repeat(indent);
        writefln("%s└── MemberAssignment", spaces);
        writefln("%s    ├── left:", spaces);
        left.print(indent + 8);
        writefln("%s    └── value:", spaces);
        value.print(indent + 8);
    }
}

unittest
{
    writeln("Testando criação de AST nodes...");

    auto loc = Loc("test.d", 1, 1, 5, ".");
    auto intLit = new IntLiteral(42, loc);
    assert(intLit.kind == NodeType.IntLiteral);
    assert(intLit.value.get!long == 42);
    assert(intLit.loc.line == 1);
    assert(intLit.loc.file == "test.d");

    writeln("✓ Teste de IntLiteral passou!");
}

unittest
{
    writeln("Testando criação de BinaryExpr...");

    auto loc = Loc("test.d", 1, 1, 5, ".");
    auto left = new IntLiteral(10, loc);
    auto right = new IntLiteral(20, loc);
    auto binExpr = new BinaryExpr(left, right, "+", loc);

    assert(binExpr.kind == NodeType.BinaryExpr);
    assert(binExpr.left == left);
    assert(binExpr.right == right);
    assert(binExpr.op == "+");
    assert(binExpr.loc.line == 1);

    writeln("✓ Teste de BinaryExpr passou!");
}

unittest
{
    writeln("Testando criação de Identifier...");

    auto loc = Loc("test.d", 1, 1, 5, ".");
    auto ident = new Identifier("variavel", loc);

    assert(ident.kind == NodeType.Identifier);
    assert(ident.value.get!string == "variavel");
    assert(ident.loc.line == 1);
    assert(ident.loc.start == 1);

    writeln("✓ Teste de Identifier passou!");
}

unittest
{
    writeln("Testando criação de Program...");

    auto loc = Loc("test.d", 1, 1, 5, ".");
    auto stmt1 = new IntLiteral(1, loc);
    auto stmt2 = new IntLiteral(2, loc);
    Stmt[] stmts = [stmt1, stmt2];

    auto program = new Program(stmts);

    assert(program.kind == NodeType.Program);
    assert(program.body.length == 2);
    assert(program.body[0] == stmt1);
    assert(program.body[1] == stmt2);

    writeln("✓ Teste de Program passou!");
}

unittest
{
    writeln("Testando criação de StringLiteral...");

    auto loc = Loc("test.d", 2, 1, 5, ".");
    auto strLit = new StringLiteral("hello", loc);

    assert(strLit.kind == NodeType.StringLiteral);
    assert(strLit.value.get!string == "hello");
    assert(strLit.loc.line == 2);
    assert(strLit.loc.start == 1);

    writeln("✓ Teste de StringLiteral passou!");
}

unittest
{
    writeln("Testando criação de BoolLiteral...");

    auto loc = Loc("test.d", 1, 1, 5, ".");
    auto boolLit = new BoolLiteral(true, loc);

    assert(boolLit.kind == NodeType.BoolLiteral);
    assert(boolLit.value.get!bool == true);

    auto boolLit2 = new BoolLiteral(false, loc);
    assert(boolLit2.value.get!bool == false);

    writeln("✓ Teste de BoolLiteral passou!");
}
