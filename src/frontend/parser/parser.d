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
    ubyte flags;
    size_t sequenceId;
    dstring hiddenName() { import std.conv : to; return "#seq_"d ~ (sequenceId++).to!dstring; }
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
        if (isAtEnd(n))
        {
            auto pos = tokens.length ? tokens[$ - 1].pos : null;
            err.error(pos, "Fim inesperado do arquivo; verifique delimitadores e expressões incompletas.");
            throw new Exception("Fim inesperado do arquivo.");
        }
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

    bool checkNext(TokenKind kind,uint distance=1)
    { return !isAtEnd(distance) && tokens[offset+distance].kind==kind; }

    bool check(TokenKind kind)
    {
        return !isAtEnd() && tokens[offset].kind == kind;
    }

    Token consume(TokenKind kind, string message)
    {
        Token tk = advance();
        if (tk.kind == kind) return tk;
        err.error(tk.pos, message);
        return tk;
    }

    Token consumeName(string message)
    {
        auto token=advance();
        if((token.kind==TokenKind.Identifier || token.kind<=TokenKind.Of) && token.value.s.length)
            return new Token(TokenKind.Identifier,token.value,token.pos);
        err.error(token.pos,message);
        return new Token(TokenKind.Identifier,TokenRaw._s("#invalid"),token.pos);
    }

    bool isStmt()
    {
        switch (peek().kind) with (TokenKind)
        {
            case Switch: case Assert:
            case Try: case Fail:
            case For:
            case Do:
            case Break:
            case Continue:
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
            case Class:
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

    Decorator[] parseDecorators()
    {
        Decorator[] result;
        while(match(TokenKind.At))
        {
            auto name=consumeName("Esperado nome do decorador.");Decorator d;d.name=name.value.s;
            if(match(TokenKind.LParen))
            {
                while(!isAtEnd()&&!check(TokenKind.RParen))
                {
                    auto key=consumeName("Esperado nome do argumento do decorador.");
                    consume(TokenKind.Equals,"Esperado '=' após argumento do decorador.");
                    d.keys ~= key.value.s;d.values ~= parseExpr.parse();
                    if(!check(TokenKind.RParen))consume(TokenKind.Comma,"Esperado ',' após argumento.");
                }
                consume(TokenKind.RParen,"Esperado ')' após decorador.");
            }
            result ~= d;
        }
        return result;
    }

    Node parseIntern()
    {
        Node node;

        if (match(TokenKind.Semicolon)) return new NaN(tokens[offset - 1].pos);

        if(check(TokenKind.At))
        {
            auto decorators=parseDecorators();node=parseIntern();node.decorators=decorators;return node;
        }
        if (isDecl())
            node = parseDecl.parse();
        else if (isStmt())
            node = parseStmt.parse();
        else
            node = parseExpr.parseStatement();

        checkSemiColon(node.kind);
        return node;
    }

    Node[] parseBody(bool simpleStatemet = false)
    {
        Node[] body;

        if (simpleStatemet && !check(TokenKind.LBrace))
            body ~= parseIntern();
        else
        {
            consume(TokenKind.LBrace, "Esperado '{'");

            while (!isAtEnd() && !check(TokenKind.RBrace))
            {
                Node node = parseIntern();
                if (node.kind == NodeKind.NaN) continue; // ignora
                body ~= node;
            }

            consume(TokenKind.RBrace, "Esperado '}'");
        }

        return body;
    }

    ubyte getAndResetFlags()
    {
        ubyte tmp = flags;
        flags = 0;
        return tmp;
    }

    pragma(inline, true)
    void resetFlags()
    {
        flags = 0;
    }

    Program parse()
    {
        Node[] body;
        while (!isAtEnd())
        {
            Node node = parseIntern();
            if (node.kind == NodeKind.NaN) continue; // ignora
            body ~= node;
            resetFlags();
        }
        return new Program(body);
    }
}
