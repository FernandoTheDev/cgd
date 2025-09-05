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

class Stmt
{
    NodeType kind;
    FTypeInfo type;
    Variant value;
    Loc loc;
    Stmt[] args;
}

class Program : Stmt
{
    Stmt[] body;

    this(Stmt[] body)
    {
        this.kind = NodeType.Program;
        this.body = body;
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
}

class ElifStatement : IfStatement
{
    this(Stmt condition, Stmt[] primary, FTypeInfo type, Variant value, Loc loc, NullStmt secondary = null)
    {
        super(condition, primary, type, value, loc);
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
}

// Adicionar novas classes AST:

class ConstructorDeclaration : Stmt
{
    FunctionArgs args;
    Stmt[] body;
    SymbolInfo[string] context;

    this(FunctionArgs args, Stmt[] body, Loc loc)
    {
        this.kind = NodeType.ConstructorDeclaration;
        this.args = args;
        this.body = body;
        this.loc = loc;
        this.type = createTypeInfo(TypesNative.NULO);
        this.value = null;
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
}

class MemberAssignment : Stmt
{
    Stmt left, index, value;
    this(Stmt left, Stmt value, Loc loc)
    {
        this.kind = NodeType.MemberAssignment;
        this.left = left;
        this.type = left.type; // permite encadeamento
        this.value = value;
        this.loc = loc;
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
