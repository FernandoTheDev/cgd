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
        if (kind == TokenKind.Identifier && tk.kind <= TokenKind.Of && tk.value.s.length)
        {
            import std.format : format;

            err.errorCode(tk.pos, expectedToken,
                    format("%s ('%s' é uma palavra reservada em Delégua).", message, tk.value.s));
            throw new ParseException;
        }
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
            {
                if (cursor >= tokens.length)
                    return false;
                if (tokens[cursor].kind == TokenKind.Arrow)
                    return true;
                if (tokens[cursor].kind == TokenKind.Colon)
                {
                    // Só é arrow com tipo de retorno `(args): Ret => ...` se houver `=>` após o tipo.
                    size_t scan = cursor + 1;
                    size_t typeDepth = 0;
                    while (scan < tokens.length)
                    {
                        TokenKind tk = tokens[scan].kind;
                        if (tk == TokenKind.Arrow && typeDepth == 0)
                            return true;
                        if (tk == TokenKind.LThan || tk == TokenKind.LParen || tk == TokenKind.LBracket)
                            typeDepth++;
                        else if ((tk == TokenKind.GThan || tk == TokenKind.RParen || tk == TokenKind.RBracket)
                                && typeDepth > 0)
                            typeDepth--;
                        else if (typeDepth == 0 && (tk == TokenKind.Semicolon || tk == TokenKind.LBrace
                                || tk == TokenKind.RBrace || tk == TokenKind.Equals
                                || tk == TokenKind.Question || tk == TokenKind.Comma))
                            return false;
                        scan++;
                    }
                }
                return false;
            }
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
                    // Suporta tanto argumentos nomeados (`chave = expr`) quanto posicionais (`expr`),
                    // ex.: `@quando(Compilacao.sistemaOperacional() == "linux")`, `@operador("+")`.
                    bool isNamedArg = (check(TokenKind.Identifier) || peek().kind <= TokenKind.Of)
                        && checkNext(TokenKind.Equals);
                    if (isNamedArg)
                    {
                        Token key = consumeName("Esperado nome do argumento do decorador.");
                        consume(TokenKind.Equals, "Esperado '=' após argumento do decorador.");
                        d.keys ~= key.value.s;
                        d.values ~= parseExpr.parse();
                    }
                    else
                    {
                        d.keys ~= ""d;
                        d.values ~= parseExpr.parse();
                    }
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
            node.decorators = decorators ~ node.decorators;
            foreach (Decorator d; decorators)
            {
                if (d.name == "puro")
                {
                    if (d.keys.length)
                        err.error(node.pos, "O decorador @puro não aceita argumentos.");
                    if (FnDecl fn = cast(FnDecl) node)
                        fn.ctfe_flags |= CTFEFlags.Pure;
                    else
                        err.error(node.pos, "O decorador @puro exige uma função ou método estático.");
                }
                else if (d.name == "nativo")
                {
                    if (d.keys.length)
                        err.error(node.pos, "O decorador @nativo não aceita argumentos.");
                    if (FnDecl fn = cast(FnDecl) node)
                        fn.isNative = true;
                    else
                        err.errorCode(node.pos, nativeInvalidTarget, "exige uma função ou método");
                }
                else if (d.name == "pilha" || d.name == "valor")
                {
                    if (d.keys.length)
                        err.error(node.pos, "O decorador @" ~ (d.name == "valor" ? "valor" : "pilha")
                                ~ " não aceita argumentos.");
                    if (ClassDecl cls = cast(ClassDecl) node)
                        cls.isValueType = true;
                    else
                        err.error(node.pos, "O decorador @" ~ (d.name == "valor" ? "valor" : "pilha")
                                ~ " exige uma declaração de classe.");
                }
                else if (d.name == "gpu")
                {
                    if (d.keys.length)
                        err.error(node.pos, "O decorador @gpu não aceita argumentos.");
                    if (FnDecl fn = cast(FnDecl) node)
                        fn.isGpu = true;
                    else
                        err.errorCode(node.pos, gpuUnsupportedFeature, "o decorador @gpu exige uma função");
                }
            }
            return node;
        }
        if (check(TokenKind.Import) && !checkNext(TokenKind.LParen))
            return parseImportStmt();
        if (isDecl())
            node = parseDecl.parse();
        else if (isStmt())
            node = parseStmt.parse();
        else
            node = parseExpr.parseStatement();

        checkSemiColon(node.kind);
        return node;
    }

    private Node parseImportStmt()
    {
        Token tk = advance();
        dstring[] segments;
        Token first = consume(TokenKind.Identifier, "Esperado nome de módulo após 'importar'.");
        segments ~= first.value.s;
        while (match(TokenKind.Dot))
        {
            Token seg = consumeName("Esperado segmento de módulo após '.'.");
            segments ~= seg.value.s;
        }
        dstring aliasName;
        if (!isAtEnd() && check(TokenKind.Identifier) && peek().value.s == "como")
        {
            advance();
            Token aliasTk = consume(TokenKind.Identifier, "Esperado alias após 'como'.");
            aliasName = aliasTk.value.s;
        }
        match(TokenKind.Semicolon);
        ImportExpr imported = new ImportExpr(null, tk.pos);
        imported.modulePath = segments;
        imported.aliasName = aliasName;
        imported.isStatementImport = true;
        return imported;
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
        dstring[] modulePath;
        Position modulePos;
        while (match(TokenKind.Semicolon))
        {
        }
        if (!isAtEnd() && check(TokenKind.Identifier)
                && (peek().value.s == "modulo" || peek().value.s == "módulo")
                && checkNext(TokenKind.Identifier))
        {
            Token modTk = advance();
            modulePos = modTk.pos;
            Token first = consume(TokenKind.Identifier, "Esperado nome do módulo.");
            modulePath ~= first.value.s;
            while (match(TokenKind.Dot))
            {
                Token seg = consumeName("Esperado segmento do módulo após '.'.");
                modulePath ~= seg.value.s;
            }
            match(TokenKind.Semicolon);
        }
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
        Program program = new Program(body);
        program.modulePath = modulePath;
        program.modulePos = modulePos;
        return program;
    }
}
