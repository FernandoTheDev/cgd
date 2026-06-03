module frontend.parser.parser;

import std.stdio;
import std.exception;
import frontend;
import frontend.lexer;
import frontend.parser;

class Parser
{
private:
    Diagnostics err;
    Token[] tokens;
    uint offset;

public:
    ParseType parseType;
    ParseExpr parseExpr;
    ParseStmt parseStmt;
    ParseDecl parseDecl;

    this(Token[] tokens, Diagnostics err)
    {
        this.tokens = tokens;
        this.err = err;
        this.parseType = new ParseType(this);
        this.parseExpr = new ParseExpr(this);
        this.parseStmt = new ParseStmt(this);
        this.parseDecl = new ParseDecl(this);
    }

    Position getPos(Position l, Position r)
    {
        return new Position(l.filename, l.start, r.end);
    }

    bool isAtEnd(uint n = 0)
    {
        return (offset + n) >= tokens.length;
    }

    void checkIsAtEnd(uint n = 0)
    {
        enforce(!isAtEnd(n), "Source out of bounds in parser.");
    }

    Token peek()
    {
        checkIsAtEnd();
        return tokens[offset];
    }

    Token advance()
    {
        checkIsAtEnd();
        return tokens[offset++];
    }

    bool match(TokenKind kind)
    {
        if (peek().kind == kind)
        {
            advance();
            return true;
        }
        return false;
    }

    bool check(TokenKind kind)
    {
        checkIsAtEnd();
        return tokens[offset].kind == kind;
    }

    Token consume(TokenKind kind, string message)
    {
        Token tk = advance();
        if (tk.kind == kind) return tk;
        err.error(tk.pos, message);
        return tk;
    }

    bool isStmt()
    {
        switch (peek().kind)
        {
            case TokenKind.For:
            case TokenKind.If:
            case TokenKind.While:
            case TokenKind.Return:
                return true;
            default:
                return false;
        }
    }

    bool isDecl()
    {
        switch (peek().kind)
        {
            case TokenKind.Var:
            case TokenKind.Const:
            case TokenKind.Fn:
                return true;
            default:
                return false;
        }
    }

    Node parseIntern()
    {
        if (isDecl()) return parseDecl.parse();
        if (isStmt()) return parseStmt.parse();
        return parseExpr.parse();
    }

    Program parse()
    {
        Node[] body;
        while (!isAtEnd())
            body ~= parseIntern();
        return new Program(body);
    }
}
