module frontend.parser.parser;

import std.exception;
import std.stdio;

import frontend.parser;
import frontend.lexer;
import frontend;

class Parser
{
private:
    Token[] tokens;
    uint offset;

public:
    Diagnostics err;
    
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

    Position getPos(Position l, Position r) => new Position(l.filename, l.start, r.end);

    bool isAtEnd(uint n = 0) => (offset + n) >= tokens.length;

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
        if (check(kind))
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
        switch (peek().kind) with (TokenKind)
        {
            case For:
            case If:
            case While:
            case Return:
                return true;
            default:
                return false;
        }
    }

    bool isDecl()
    {
        switch (peek().kind) with (TokenKind)
        {
            case Var:
            case Const:
            case Fn:
                return true;
            default:
                return false;
        }
    }

    pragma(inline, true)
    bool needSemiColon(NodeKind kind)
    {
        switch (kind) with (NodeKind) 
        {
            case ReturnStmt:
            case CallExpr:
            case VarDecl:
                return true;
            default:
                return false;
        }
    }

    pragma(inline, true)
    void checkSemiColon(NodeKind kind)
    {
        if (!isAtEnd())
            if (needSemiColon(kind))
                bool _ = match(TokenKind.Semicolon);
    }

    Node parseIntern()
    {
        Node node;
        
        if (isDecl())       node = parseDecl.parse();
        else if (isStmt())  node = parseStmt.parse();
        else                node = parseExpr.parse();
        
        checkSemiColon(node.kind);
        return node;
    }

    Program parse()
    {
        Node[] body;
        while (!isAtEnd())
            body ~= parseIntern();
        return new Program(body);
    }
}
