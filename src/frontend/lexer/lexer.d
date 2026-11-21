module frontend.lexer.lexer;

import std.utf : decodeFront, decode;
import std.uni : unicodeAlpha = isAlpha, isMark;
import std.math : isFinite;
import std.exception : enforce;
import std.format;
import std.stdio;
import std.conv;
import std.string : toStringz;
import core.stdc.stdlib : strtod;
import core.stdc.errno : errno;

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
    uint l_offset;
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

    bool isHexDigit(dchar c)
    {
        return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
    }

    bool isDigitForBase(dchar c, uint base)
    {
        if (base == 2)
            return c == '0' || c == '1';
        if (base == 8)
            return c >= '0' && c <= '7';
        if (base == 16)
            return isHexDigit(c);
        return isNumeric(c);
    }

    uint digitValue(dchar c)
    {
        if (c >= '0' && c <= '9')
            return cast(uint)(c - '0');
        if (c >= 'a' && c <= 'f')
            return 10u + cast(uint)(c - 'a');
        if (c >= 'A' && c <= 'F')
            return 10u + cast(uint)(c - 'A');
        return 0u;
    }

    bool isAlphaNumeric(dchar c)
    {
        return isNumeric(c) || isAlpha(c) || isMark(c);
    }

    bool isAtEnd(uint n = 0)
    {
        if (n == 0)
            return source.length == 0;
        size_t idx = 0;
        foreach (uint step; 0 .. n)
        {
            if (idx >= source.length)
                return true;
            decode(source, idx);
        }
        return idx >= source.length;
    }

    void checkIsAtEnd(uint n = 0)
    {
        enforce(!isAtEnd(n), "Source out of bounds in lexer.");
    }

    dchar future(uint n)
    {
        checkIsAtEnd(n);
        size_t idx = 0;
        foreach (uint step; 0 .. n)
            decode(source, idx);
        return decode(source, idx);
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

    private bool hasHexFloatExponentAfterDot()
    {
        // Verifica em source (após o '.' atual) se há dígitos hex/underscores seguidos de 'p'/'P',
        // distinguindo '0x1.fp+3' ou '0x1.p2' de chamada de método como '0xFF.formatar()'.
        size_t idx = 0;
        if (idx >= source.length)
            return false;
        dchar dot = decode(source, idx);
        if (dot != '.')
            return false;
        bool sawHexOrUnderscore = false;
        while (idx < source.length)
        {
            size_t nextIdx = idx;
            dchar c = decode(source, nextIdx);
            if ((c == 'p' || c == 'P') && sawHexOrUnderscore)
                return true;
            if (isHexDigit(c) || c == '_')
            {
                sawHexOrUnderscore = true;
                idx = nextIdx;
                continue;
            }
            return false;
        }
        return false;
    }

    private void consumeTrailingInvalidNumberChars()
    {
        while (!isAtEnd() && (isAlphaNumeric(peek()) || peek() == '_'))
            advance();
    }

    private bool scanDigitsWithSeparators(uint base, ref char[] clean, out size_t digitCount)
    {
        digitCount = 0;
        bool prevUnderscore = false;
        while (!isAtEnd())
        {
            dchar c = peek();
            if (isDigitForBase(c, base))
            {
                advance();
                clean ~= cast(char) c;
                digitCount++;
                prevUnderscore = false;
            }
            else if (c == '_')
            {
                advance();
                if (digitCount == 0 || prevUnderscore)
                {
                    consumeTrailingInvalidNumberChars();
                    return false;
                }
                prevUnderscore = true;
            }
            else
                break;
        }
        if (prevUnderscore)
        {
            consumeTrailingInvalidNumberChars();
            return false;
        }
        return true;
    }

    private bool lexNumberToken(dchar firstChar, uint start, out TokenKind kind, out TokenRaw raw, out bool dotInvalid)
    {
        kind = TokenKind.Int;
        raw = TokenRaw.init;
        dotInvalid = false;

        uint base = 10;
        char[] clean;

        if (firstChar == '0' && !isAtEnd())
        {
            dchar p = peek();
            if (p == 'x' || p == 'X')
            {
                base = 16;
                advance();
            }
            else if (p == 'b' || p == 'B')
            {
                base = 2;
                advance();
            }
            else if (p == 'o' || p == 'O')
            {
                base = 8;
                advance();
            }
        }

        if (base != 10)
        {
            size_t intDigits = 0;
            if (!scanDigitsWithSeparators(base, clean, intDigits) || intDigits == 0)
                return false;

            // Literal hexadecimal de ponto flutuante: 0x<hex>[.<hex>]p[+-]<dec>
            bool isHexFloat = false;
            char[] hexFloatBuf = ['0', 'x'];
            hexFloatBuf ~= clean;

            if (base == 16 && !isAtEnd() && peek() == '.' && hasHexFloatExponentAfterDot())
            {
                isHexFloat = true;
                advance(); // '.'
                hexFloatBuf ~= '.';
                char[] fracClean;
                size_t fracDigits = 0;
                if (!scanDigitsWithSeparators(16, fracClean, fracDigits) || fracDigits == 0)
                    return false;
                hexFloatBuf ~= fracClean;
            }

            if (base == 16 && !isAtEnd() && (peek() == 'p' || peek() == 'P'))
            {
                isHexFloat = true;
                hexFloatBuf ~= cast(char) advance();
                if (!isAtEnd() && (peek() == '+' || peek() == '-'))
                    hexFloatBuf ~= cast(char) advance();
                char[] expClean;
                size_t expDigits = 0;
                if (!scanDigitsWithSeparators(10, expClean, expDigits) || expDigits == 0)
                    return false;
                hexFloatBuf ~= expClean;
            }
            else if (isHexFloat)
            {
                // Tinha ponto fracionário hex mas faltou expoente binário p/P
                consumeTrailingInvalidNumberChars();
                return false;
            }

            if (!isAtEnd() && (isAlphaNumeric(peek()) || peek() == '_'))
            {
                consumeTrailingInvalidNumberChars();
                return false;
            }

            if (isHexFloat)
            {
                kind = TokenKind.Double;
                string cStr = cast(string) hexFloatBuf;
                immutable(char)* cPtr = cStr.toStringz;
                immutable(char)* endPtr = null;
                errno = 0;
                double val = strtod(cPtr, &endPtr);
                if (errno != 0 || !isFinite(val) || endPtr != cPtr + cStr.length)
                    return false;
                raw.d = val;
                return true;
            }

            ulong acc = 0;
            ulong maxLimit = cast(ulong) long.max;
            foreach (char ch; clean)
            {
                uint d = digitValue(ch);
                if (acc > (maxLimit - d) / base)
                    return false;
                acc = acc * base + d;
            }
            raw.i = cast(long) acc;
            return true;
        }

        // Base 10 (decimal inteiro, real ou notação científica)
        clean ~= cast(char) firstChar;
        bool prevUnderscore = false;
        while (!isAtEnd())
        {
            dchar c = peek();
            if (isNumeric(c))
            {
                advance();
                clean ~= cast(char) c;
                prevUnderscore = false;
            }
            else if (c == '_')
            {
                advance();
                if (prevUnderscore)
                {
                    consumeTrailingInvalidNumberChars();
                    return false;
                }
                prevUnderscore = true;
            }
            else
                break;
        }
        if (prevUnderscore)
        {
            consumeTrailingInvalidNumberChars();
            return false;
        }

        bool isDouble = false;
        if (!isAtEnd() && peek() == '.')
        {
            // Se após '.' vem letra (exceto '_' inválido que deve falhar como literal se seguido de dígito),
            // trata-se de acesso a método como 10.formatar().
            if (!isAtEnd(1) && unicodeAlpha(future(1)))
            {
                // Mantém '.' para o próximo token (MemberExpr)
            }
            else if (!isAtEnd(1) && future(1) == '_')
            {
                // 1._0 é separador mal posicionado adjacente ao ponto
                advance();
                consumeTrailingInvalidNumberChars();
                return false;
            }
            else
            {
                isDouble = true;
                advance(); // '.'
                clean ~= '.';
                char[] fracClean;
                size_t fracDigits = 0;
                if (!scanDigitsWithSeparators(10, fracClean, fracDigits))
                    return false;
                clean ~= fracClean;
                if (!isAtEnd() && peek() == '.')
                {
                    if (!isAtEnd(1) && unicodeAlpha(future(1)))
                    {
                        // ex.: 10.5.formatar() -> para antes do segundo '.'
                    }
                    else
                    {
                        dotInvalid = true;
                        while (!isAtEnd() && (isNumeric(peek()) || peek() == '.' || peek() == '_'))
                            advance();
                        return false;
                    }
                }
            }
        }

        // Notação científica: e / E
        if (!isAtEnd() && (peek() == 'e' || peek() == 'E'))
        {
            isDouble = true;
            clean ~= cast(char) advance();
            if (!isAtEnd() && (peek() == '+' || peek() == '-'))
                clean ~= cast(char) advance();
            char[] expClean;
            size_t expDigits = 0;
            if (!scanDigitsWithSeparators(10, expClean, expDigits) || expDigits == 0)
                return false;
            clean ~= expClean;
        }

        if (!isAtEnd() && (isAlphaNumeric(peek()) || peek() == '_'))
        {
            consumeTrailingInvalidNumberChars();
            return false;
        }

        if (isDouble)
        {
            kind = TokenKind.Double;
            string cStr = cast(string) clean;
            immutable(char)* cPtr = cStr.toStringz;
            immutable(char)* endPtr = null;
            errno = 0;
            double val = strtod(cPtr, &endPtr);
            if (errno != 0 || !isFinite(val) || endPtr != cPtr + cStr.length)
                return false;
            raw.d = val;
            return true;
        }

        ulong acc = 0;
        ulong maxLimit = cast(ulong) long.max;
        foreach (char ch; clean)
        {
            uint d = cast(uint)(ch - '0');
            if (acc > (maxLimit - d) / 10u)
                return false;
            acc = acc * 10u + d;
        }
        raw.i = cast(long) acc;
        return true;
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
                TokenKind kind = TokenKind.Int;
                TokenRaw raw;
                bool dotInvalid;
                bool ok = lexNumberToken(ch, start, kind, raw, dotInvalid);

                if (dotInvalid)
                {
                    err.error(getPosition(start, line), "Uso de '.' inválido.");
                    continue;
                }
                if (!ok)
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

                if (tk == "/*")
                {
                    uint start = l_offset;
                    uint startLine = line;
                    advance(); // consome '*'
                    bool closed = false;
                    while (!isAtEnd())
                    {
                        dchar c = advance();
                        if (c == '\n')
                        {
                            line++;
                            l_offset = 0;
                        }
                        else if (c == '*' && !isAtEnd() && peek() == '/')
                        {
                            advance();
                            closed = true;
                            break;
                        }
                    }
                    if (!closed)
                    {
                        err.error(getPosition(start, startLine), "Comentário de bloco não foi fechado.");
                        return tokens;
                    }
                    if (includeComments)
                        pushToken(new Token(TokenKind.Comment, TokenRaw.init, getPosition(start, startLine)));
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
