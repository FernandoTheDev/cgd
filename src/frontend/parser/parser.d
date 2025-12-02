module frontend.parser.parser;
import frontend, common.reporter;

enum Precedence
{
    LOWEST = 1,
    ASSIGN = 2, // =, +=, -=, |=, &=, <<=, >>=
    EQUALS = 3, // ==, !=
    OR = 4, // ||
    AND = 5, // &&
    BIT_OR = 6, // |
    BIT_XOR = 7, // ^
    BIT_AND = 8, // &
    SUM = 9, // +, -
    MUL = 10, // *, /
    BIT_SHIFT = 11, // <<, >>
    CALL = 12, // funções, index
    HIGHEST = 13,
}

class Parser
{
private:
    Token[] tokens;
    ulong pos = 0; // offset
    DiagnosticError error;

    pragma(inline, true)
    void reportError(string message, Loc loc, Suggestion[] suggestions = null)
    {
        error.addError(Diagnostic(message, loc, suggestions));
    }

    // BinaryExpr parseBinaryExpr(Node left)
    // {
    //     Token op = this.advance();
    //     Node right = this.parseExpression(this.getPrecedence(op.kind));
    //     return new BinaryExpr(left, right, op.value.get!string, this.getLoc(left.loc, right.loc));
    // }

    // void infix(ref Node leftOld)
    // {
    //     switch (this.peek().kind)
    //     {
    //     case TokenKind.Plus:
    //     case TokenKind.Minus:
    //     case TokenKind.Star:
    //     case TokenKind.Slash:

    //     case TokenKind.And:
    //     case TokenKind.Or:

    //     case TokenKind.BitAnd:
    //     case TokenKind.BitOr:
    //     case TokenKind.BitXor:
    //     case TokenKind.BitSHL:
    //     case TokenKind.BitSHR:
    //     case TokenKind.BitSAR:

    //     case TokenKind.PlusEquals:
    //     case TokenKind.MinusEquals:
    //     case TokenKind.StarEquals:
    //     case TokenKind.SlashEquals:
    //     case TokenKind.ModuloEquals:

    //     case TokenKind.BitAndEquals:
    //     case TokenKind.BitOrEquals:
    //     case TokenKind.BitXorEquals:
    //     case TokenKind.BitSHLEquals:
    //     case TokenKind.BitSHREquals:

    //     case TokenKind.EqualsEquals:
    //     case TokenKind.GreaterThan:
    //     case TokenKind.GreaterThanEquals:
    //     case TokenKind.LessThanEquals:
    //     case TokenKind.LessThan:
    //     case TokenKind.NotEquals:
    //     case TokenKind.TildeEquals:
    //         leftOld = parseBinaryExpr(leftOld);
    //         return;
    //     default:
    //         return;
    //     }
    // }

    mixin ParseDecl!();
    mixin ParseExpr!();
    mixin ParseStmt!();
    mixin ParseType!();

    Node parse()
    {
        immutable startPos = this.pos;

        if (this.isDeclaration())
        {
            if (auto node = this.parseDeclaration())
                return node;
            this.pos = startPos;
        }

        if (auto node = this.parseStatement())
            return node;

        this.pos = startPos;

        if (auto node = this.parseExpression())
            return node;

        throw new Exception("Erro ao fazer parsing na posição " ~ to!string(startPos));
    }

    bool isDeclaration()
    {
        Token current = this.peek();
        switch (current.kind)
        {
        case TokenKind.Var:
        case TokenKind.Const:
        case TokenKind.Funcao:
            return true;
        default:
            return false;
        }
    }

    pragma(inline, true);
    bool isAtEnd()
    {
        return this.peek().kind == TokenKind.Eof;
    }

    Variant next()
    {
        if (this.isAtEnd())
            return Variant(false);
        return Variant(this.tokens[this.pos + 1]);
    }

    pragma(inline, true);
    Token peek()
    {
        return this.tokens[this.pos];
    }

    pragma(inline, true);
    Token previous(ulong i = 1)
    {
        return this.tokens[this.pos - i];
    }

    Token advance()
    {
        if (!this.isAtEnd())
            this.pos++;
        return this.previous();
    }

    bool match(TokenKind[] kinds)
    {
        foreach (kind; kinds)
        {
            if (this.check(kind))
            {
                this.advance();
                return true;
            }
        }
        return false;
    }

    bool check(TokenKind kind)
    {
        if (this.isAtEnd())
            return false;
        return this.peek().kind == kind;
    }

    Token consume(TokenKind expected, string message)
    {
        if (this.check(expected))
            return this.advance();
        reportError(format("Erro de parsing: %s", message), this.peek().loc);
        throw new Exception(format("Erro de parsing: %s", message));
    }

    Precedence getPrecedence(TokenKind kind)
    {
        switch (kind)
        {
        case TokenKind.Equals:
        case TokenKind.PlusEquals:
        case TokenKind.MinusEquals:
        case TokenKind.StarEquals:
        case TokenKind.SlashEquals:
        case TokenKind.ModuloEquals:
        case TokenKind.BitAndEquals:
        case TokenKind.BitOrEquals:
        case TokenKind.BitXorEquals:
        case TokenKind.BitSHLEquals:
        case TokenKind.BitSHREquals:
        case TokenKind.TildeEquals:
        case TokenKind.Or:
        case TokenKind.And:
            return Precedence.ASSIGN;

        case TokenKind.EqualsEquals:
        case TokenKind.NotEquals:
        case TokenKind.GreaterThan:
        case TokenKind.LessThan:
        case TokenKind.LessThanEquals:
        case TokenKind.GreaterThanEquals:
            return Precedence.EQUALS;

        case TokenKind.BitOr:
            return Precedence.BIT_OR;
        case TokenKind.BitXor:
            return Precedence.BIT_XOR;
        case TokenKind.BitAnd:
            return Precedence.BIT_AND;

        case TokenKind.Plus:
        case TokenKind.Minus:
        case TokenKind.PlusPlus:
        case TokenKind.MinusMinus:
            return Precedence.SUM;
        case TokenKind.Star:
        case TokenKind.Slash:
        case TokenKind.Modulo:
            return Precedence.MUL;

        case TokenKind.BitSHL:
        case TokenKind.BitSHR:
        case TokenKind.BitSAR:
            return Precedence.BIT_SHIFT;

        case TokenKind.LParen:
        case TokenKind.LBracket:
            return Precedence.CALL;

        default:
            return Precedence.LOWEST;
        }
    }

    pragma(inline, true);
    Precedence peekPrecedence()
    {
        return this.getPrecedence(this.peek().kind);
    }

    pragma(inline, true);
    Loc getLoc(ref Loc start, ref Loc end)
    {
        return Loc(start.filename, start.dir, start.start, start.end);
    }

public:
    this(Token[] tokens = [], DiagnosticError error)
    {
        this.error = error;
        this.tokens = tokens;
    }

    Program parseProgram()
    {
        Program program = new Program([]);
        try
        {
            while (!this.isAtEnd())
                program.body ~= this.parse();
            if (this.tokens.length == 0)
                return program;
        }
        catch (Exception e)
            throw e; // propaga
        return program;
    }
}
