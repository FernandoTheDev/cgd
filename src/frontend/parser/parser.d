module frontend.parser.parser;

import std.exception;
import std.stdio;

import frontend.parser;
import frontend.lexer;
import ctfe.ctfe_flags : CTFEFlags;
import frontend;

class ParseException : Exception
{
    this()
    {
        super("Erro sintático recuperável.");
    }
}

class Parser
{
private:
    Token[] tokens;
    uint offset;

public:
    bool recoverIncomplete;
    ubyte flags;
    size_t nesting;

    void enterSyntax()
    {
        if (nesting >= 256)
        {
            err.errorCode(isAtEnd() ? null : peek().pos, syntaxDepth);
            throw new ParseException;
        }
        nesting++;
    }

    void leaveSyntax()
    {
        nesting--;
    }

    size_t sequenceId;
    dstring hiddenName()
    {
        import std.conv : to;

        return "#seq_"d ~ (sequenceId++).to!dstring;
    }

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
            Position pos = tokens.length ? tokens[$ - 1].pos : null;
            err.errorCode(pos, unexpectedEnd);
            throw new ParseException;
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

    bool checkNext(TokenKind kind, uint distance = 1)
    {
        return !isAtEnd(distance) && tokens[offset + distance].kind == kind;
    }

    bool check(TokenKind kind)
    {
        return !isAtEnd() && tokens[offset].kind == kind;
    }

    Token consume(TokenKind kind, string message)
    {
        if (recoverIncomplete && isAtEnd() && (kind == TokenKind.RBrace || kind == TokenKind.RParen
                || kind == TokenKind.RBracket))
        {
            Position pos = tokens.length ? tokens[$ - 1].pos : null;
            err.errorCode(pos, unexpectedEnd);
            return new Token(kind, TokenRaw.init, pos);
        }
        Token tk = advance();
        if (tk.kind == kind)
            return tk;
        err.errorCode(tk.pos, expectedToken, message);
        throw new ParseException;
    }

    void consumeTypeClose()
    {
        if (check(TokenKind.BITSR) || check(TokenKind.GEquals))
        {
            Token token = peek();
            tokens[offset] = new Token(token.kind == TokenKind.BITSR ? TokenKind.GThan
                    : TokenKind.Equals, TokenRaw.init, token.pos);
            return;
        }
        consume(TokenKind.GThan, "Esperado '>' após resultado de Promessa.");
    }

    Token consumeName(string message)
    {
        Token token = advance();
        if ((token.kind == TokenKind.Identifier || token.kind <= TokenKind.Of) && token.value.s.length)
            return new Token(TokenKind.Identifier, token.value, token.pos);
        err.error(token.pos, message, "E1001");
        throw new ParseException;
    }

    Token consumeMemberName(Position receiver)
    {
        if (recoverIncomplete && (isAtEnd() || check(TokenKind.RBrace) || check(TokenKind.RParen)
                || check(TokenKind.Semicolon)))
        {
            Position position = new Position(receiver.filename, receiver.end, receiver.end);
            err.errorCode(position, expectedToken, "Esperado nome de membro após '.'.");
            return new Token(TokenKind.Identifier, TokenRaw._s("#incompleto"), position);
        }
        return consumeName("Esperado nome de membro após '.'.");
    }

    bool isStmt()
    {
        switch (peek().kind) with (TokenKind)
        {
            case Switch:
            case Assert:
            case Try:
            case Fail:
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

    bool arrowParametersAhead()
    {
        size_t cursor = offset;
        size_t depth = 1;
        while (cursor < tokens.length)
        {
            TokenKind kind = tokens[cursor++].kind;
            if (kind == TokenKind.LParen)
                depth++;
            if (kind == TokenKind.RParen && --depth == 0)
                return cursor < tokens.length && (tokens[cursor].kind == TokenKind.Arrow
                        || tokens[cursor].kind == TokenKind.Colon);
        }
        return false;
    }

    bool isDecl()
    {
        switch (peek().kind) with (TokenKind)
        {
            case Class:
            case Interface:
            case Enum:
            case Var:
            case Const:
            case Fn:
            case Async:
                return true;
            default:
                return false;
        }
    }

    pragma(inline, true) bool needSemiColon(NodeKind kind)
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

    pragma(inline, true) void checkSemiColon(NodeKind kind)
    {
        if (!isAtEnd())
            if (needSemiColon(kind))
                bool _ = match(TokenKind.Semicolon);
    }

    Decorator[] parseDecorators()
    {
        Decorator[] result;
        while (match(TokenKind.At))
        {
            Token name = consumeName("Esperado nome do decorador.");
            Decorator d;
            d.name = name.value.s;
            if (match(TokenKind.LParen))
            {
                while (!isAtEnd() && !check(TokenKind.RParen))
                {
                    Token key = consumeName("Esperado nome do argumento do decorador.");
                    consume(TokenKind.Equals, "Esperado '=' após argumento do decorador.");
                    d.keys ~= key.value.s;
                    d.values ~= parseExpr.parse();
                    if (!check(TokenKind.RParen))
                        consume(TokenKind.Comma, "Esperado ',' após argumento.");
                }
                consume(TokenKind.RParen, "Esperado ')' após decorador.");
            }
            result ~= d;
        }
        return result;
    }

    Node parseIntern()
    {
        enterSyntax();
        scope (exit)
            leaveSyntax();
        Node node;

        if (match(TokenKind.Semicolon))
            return new NaN(tokens[offset - 1].pos);

        if (check(TokenKind.At))
        {
            Decorator[] decorators = parseDecorators();
            node = parseIntern();
            node.decorators = decorators;
            foreach (Decorator d; decorators)
                if (d.name == "puro")
                {
                    if (d.keys.length)
                        err.error(node.pos, "O decorador @puro não aceita argumentos.");
                    if (FnDecl fn = cast(FnDecl) node)
                        fn.ctfe_flags |= CTFEFlags.Pure;
                    else
                        err.error(node.pos, "O decorador @puro exige uma função ou método estático.");
                }
            return node;
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
                uint before = offset;
                try
                {
                    Node node = parseIntern();
                    if (node.kind != NodeKind.NaN)
                        body ~= node;
                }
                catch (ParseException)
                    synchronize(before, true);
            }

            consume(TokenKind.RBrace, "Esperado '}'");
        }

        return
        body;
    }

    ubyte getAndResetFlags()
    {
        ubyte tmp = flags;
        flags = 0;
        return tmp;
    }

    pragma(inline, true) void resetFlags()
    {
        flags = 0;
    }

    private void synchronize(uint before, bool inBody)
    {
        resetFlags();
        if (offset == before && !isAtEnd())
            advance();
        while (!isAtEnd())
        {
            if (inBody && check(TokenKind.RBrace))
                return;
            if (match(TokenKind.Semicolon))
                return;
            if (isDecl() || isStmt() || check(TokenKind.At))
                return;
            advance();
        }
    }

    Program parse()
    {
        Node[] body;
        while (!isAtEnd())
        {
            uint before = offset;
            try
            {
                Node node = parseIntern();
                if (node.kind == NodeKind.NaN)
                    continue;
                body ~= node;
            }
            catch (ParseException)
                synchronize(before, false);
            resetFlags();
        }
        return new Program(body);
    }
}
