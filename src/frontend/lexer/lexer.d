module frontend.lexer.lexer;

import std.utf : decodeFront, decode;
import std.uni : unicodeAlpha = isAlpha, isMark;
import std.math : isFinite;
import std.exception : enforce;
import std.format;
import std.stdio;
import std.conv;

import frontend.lexer.token;
import frontend.lexer.keywords;
import errors;

class Lexer
{
    public bool includeComments;
private:
    Diagnostics err;
    Token[] tokens;
    string source, filename;
    uint offset, l_offset;
    uint line = 1;

    static immutable TokenKind[dstring] symbols = [
        "=>": TokenKind.Arrow, "@": TokenKind.At, "?": TokenKind.Question, "**": TokenKind.Pow,
        "\\": TokenKind.IntDiv, "?:": TokenKind.Coalesce, "<-": TokenKind.Equals,
        "+=": TokenKind.PlusAssign, "-=": TokenKind.MinusAssign, "*=": TokenKind.MulAssign,
        "/=": TokenKind.DivAssign, "%=": TokenKind.ModAssign, "+": TokenKind.Plus,
        "++": TokenKind.PPlus, "-": TokenKind.Minus, "--": TokenKind.MMinus,
        "/": TokenKind.Slash, "*": TokenKind.Star, "%": TokenKind.Modulo, "=": TokenKind.Equals,
        "==": TokenKind.EEquals, "!=": TokenKind.NEquals, "(": TokenKind.LParen,
        ")": TokenKind.RParen, "{": TokenKind.LBrace, "}": TokenKind.RBrace,
        "[": TokenKind.LBracket, "]": TokenKind.RBracket, ":": TokenKind.Colon,
        ";": TokenKind.Semicolon, "!": TokenKind.Bang, ",": TokenKind.Comma, ".": TokenKind.Dot,
        "<": TokenKind.LThan, "<=": TokenKind.LEquals, ">": TokenKind.GThan,
        ">=": TokenKind.GEquals, "&": TokenKind.BITAnd, "|": TokenKind.BITOr,
        "~": TokenKind.BITNot, "^": TokenKind.BITXor, "<<": TokenKind.BITSL, ">>": TokenKind.BITSR,
    ];

    static immutable TokenKind[dstring] ctfeKeywords = ["puro": TokenKind.Pure,];

public:
    this(string source, string filename, Diagnostics err)
    {
        this.source = source;
        this.filename = filename;
        this.err = err;
        err.registerSource(filename, source);
    }

    bool isAlpha(dchar c)
    {
        return c == '_' || unicodeAlpha(c);
    }

    bool isNumeric(dchar c)
    {
        return c >= '0' && c <= '9';
    }

    bool isAlphaNumeric(dchar c)
    {
        return isNumeric(c) || isAlpha(c) || isMark(c);
    }

    bool isAtEnd(uint n = 0)
    {
        return (offset + n) >= source.length;
    }

    void checkIsAtEnd(uint n = 0)
    {
        enforce(!isAtEnd(n), "Source out of bounds in lexer.");
    }

    dchar future(uint n)
    {
        checkIsAtEnd(n);
        return source[offset + n];
    }

    dchar advance()
    {
        checkIsAtEnd();
        l_offset++;
        return decodeFront(source);
    }

    dchar peek()
    {
        checkIsAtEnd();
        size_t i; // não remover
        return decode(source, i);
    }

    bool match(dchar ch)
    {
        if (isAtEnd())
            return false;
        if (peek() == ch)
        {
            advance();
            return true;
        }
        return false;
    }

    dstring lexNumer(dchar ch, uint start, out bool isDouble, out bool dotInvalid)
    {
        dstring buffer = [ch];
        while (!isAtEnd() && (isNumeric(peek()) || peek() == '.'))
        {
            if (peek() == '.' && !isAtEnd(1) && isAlpha(future(1)))
                break;
            if (peek() == '.' && isDouble)
            {
                dotInvalid = true;
                advance();
                continue;
            }
            if (peek() == '.' && !isDouble)
                isDouble = true;
            buffer ~= [advance()];
        }
        return buffer;
    }

    Position getPosition(uint s, uint l) => new Position(filename, new PosLine(s, l), new PosLine(l_offset + 1, line));

    pragma(inline, true) void pushToken(Token tk)
    {
        tokens ~= tk;
    }

    dstring lexId(dchar ch)
    {
        if (!isAlpha(ch))
            return "";

        dstring buffer = [ch];
        while (!isAtEnd() && isAlphaNumeric(peek()))
            buffer ~= [advance()];

        return buffer;
    }

    Token[] tokenizer()
    {
        // Valida antes de decodificar; bytes inválidos nunca viram exceção interna.
        import std.utf : validate, UTFException;

        try
            validate(source);
        catch (UTFException)
        {
            err.errorCode(new Position(filename, new PosLine(1, 1), new PosLine(1, 1)), invalidUTF8);
            return [];
        }
        while (!isAtEnd())
        {
            dchar ch = advance();

            if (ch == '\r' || ch == ' ' || ch == '\t')
                continue;

            if (ch == '\n')
            {
                line++;
                l_offset = 0;
                continue;
            }

            if (isNumeric(ch))
            {
                uint start = l_offset;
                bool isDouble;
                bool dotInvalid;
                dstring buffer = lexNumer(ch, start, isDouble, dotInvalid);

                if (dotInvalid)
                {
                    err.error(getPosition(start, line), "Uso de '.' inválido.");
                    continue;
                }

                TokenKind kind = TokenKind.Int;
                TokenRaw raw;

                try
                {
                    if (isDouble)
                    {
                        kind = TokenKind.Double;
                        raw.d = to!double(buffer);
                        if (!isFinite(raw.d))
                        {
                            err.errorCode(getPosition(start, line), invalidNumericLiteral);
                            continue;
                        }
                    }
                    else
                        raw.i = to!long(buffer);
                }
                catch (ConvException)
                {
                    err.errorCode(getPosition(start, line), invalidNumericLiteral);
                    continue;
                }

                pushToken(new Token(kind, raw, getPosition(start, line)));
                continue;
            }

            if (isAlpha(ch))
            {
                uint start = l_offset;
                dstring buffer = lexId(ch);

                TokenKind kind = TokenKind.Identifier;
                if (immutable TokenKind* k = buffer in keywords)
                    kind = *k;

                pushToken(new Token(kind, TokenRaw._s(buffer), getPosition(start, line)));
                continue;
            }

            if (ch == '"' || ch == '\'')
            {
                uint start = l_offset;
                uint l = line;
                dstring buffer;
                size_t[] escapedInterpolation;

                dchar quote = ch;
                while (!isAtEnd() && peek() != quote)
                {
                    if (peek() == '\n')
                    {
                        line++;
                        l_offset = 0;
                    }
                    dchar c = advance();
                    if (c == '$' && !isAtEnd() && peek() == '{')
                    {
                        buffer ~= "${";
                        advance();
                        uint nesting = 1;
                        dchar innerQuote = 0;
                        bool escaped;
                        while (!isAtEnd() && nesting)
                        {
                            dchar x = advance();
                            buffer ~= x;
                            if (x == '\n')
                            {
                                line++;
                                l_offset = 0;
                            }
                            if (innerQuote)
                            {
                                if (escaped)
                                    escaped = false;
                                else if (x == '\\')
                                    escaped = true;
                                else if (x == innerQuote)
                                    innerQuote = 0;
                            }
                            else if (x == '\'' || x == '"')
                                innerQuote = x;
                            else if (x == '{')
                                nesting++;
                            else if (x == '}')
                                nesting--;
                        }
                        if (nesting)
                            err.error(getPosition(start, l), "Interpolação não foi fechada.");
                        continue;
                    }
                    if (c == '\\' && !isAtEnd())
                    {
                        c = advance();
                        switch (c)
                        {
                            case 'n':
                                c = '\n';
                                break;
                            case 'r':
                                c = '\r';
                                break;
                            case 't':
                                c = '\t';
                                break;
                            case '0':
                                c = '\0';
                                break;
                            case '$':
                                escapedInterpolation ~= buffer.length;
                                break;
                            case '\\':
                            case '\'':
                            case '"':
                                break;
                            default:
                                err.error(getPosition(start, l), "Escape inválido.");
                                break;
                        }
                    }
                    buffer ~= c;
                }

                if (isAtEnd() || !match(quote))
                {
                    err.error(getPosition(start, l), "String não foi fechada.");
                    return tokens;
                }

                Token token = new Token(TokenKind.String, TokenRaw._s(buffer), getPosition(start, l));
                token.escapedInterpolation = escapedInterpolation;
                pushToken(token);
                continue;
            }

            TokenKind k = TokenKind.Eof;
            uint size;

            if (!isAtEnd(1))
            {
                dstring tk = [ch, peek(), future(1)];

                if (tk == "...")
                {
                    advance();
                    advance();
                    pushToken(new Token(TokenKind.Spread, TokenRaw.init, getPosition(l_offset - 2, line)));
                    continue;
                }
                if (tk == "//>")
                {
                    advance(); // pula o /
                    advance(); // pula o >

                    uint start = l_offset + 1;
                    if (isAtEnd())
                    {
                        err.error(getPosition(start, line), "Esperado qualificador após //>.", "E1001");
                        continue;
                    }
                    dstring buffer = lexId(advance());
                    Position pos = getPosition(start, line);

                    if (immutable TokenKind* kind = buffer in ctfeKeywords)
                    {
                        pushToken(new Token(*kind, TokenRaw.init, pos));
                        continue;
                    }

                    err.error(pos, format("Não foi possível detectar o qualificador '%s'.", buffer));
                    continue;
                }
            }

            if (!isAtEnd())
            {
                dstring tk = [ch, peek()];

                if (tk == "//")
                {
                    uint start = l_offset;
                    while (!isAtEnd() && peek() != '\n')
                        advance();
                    if (includeComments)
                        pushToken(new Token(TokenKind.Comment, TokenRaw.init, getPosition(start, line)));
                    continue;
                }

                if (immutable TokenKind* kind = tk in symbols)
                {
                    k = *kind;
                    size++;
                    advance();
                    goto end;
                }
            }

            if (immutable TokenKind* kind = [ch] in symbols)
            {
                k = *kind;
                goto end;
            }

            err.error(getPosition(l_offset - size, line), format("Caractere desconhecido '%c'.", ch));
            continue;

        end:
            pushToken(new Token(k, TokenRaw.init, getPosition(l_offset - size, line)));
        }
        return tokens;
    }
}
