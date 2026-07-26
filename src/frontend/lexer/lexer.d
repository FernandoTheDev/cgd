module frontend.lexer.lexer;

import std.utf : decodeFront, decode;
import std.exception : enforce;
import std.format;
import std.stdio;
import std.conv;

import frontend.lexer.token;
import errors;

class Lexer
{
private:
    Diagnostics err;
    Token[] tokens;
    string source, filename;
    uint offset, l_offset;
    uint line = 1;
    immutable TokenKind[dstring] keywords = [
        "var": TokenKind.Var,
        "variavel": TokenKind.Var,
        "variável": TokenKind.Var,

        "const": TokenKind.Const,
        "fixo": TokenKind.Const,
        "constante": TokenKind.Const,

        "funcao": TokenKind.Fn,
        "função": TokenKind.Fn,

        "se": TokenKind.If,
        "senao": TokenKind.Else,
        "senão": TokenKind.Else,

        "enquanto": TokenKind.While,
        "para": TokenKind.For,

        "nulo": TokenKind.Null,
        "verdadeiro": TokenKind.True,
        "falso": TokenKind.False,

        "tipo": TokenKind.Type,
        "de": TokenKind.Of,

        "retorne": TokenKind.Return,
        "retorna": TokenKind.Return,
    ];

public:
    this(string source, string filename, Diagnostics err)
    {
        this.source = source;
        this.filename = filename;
        this.err = err;
    }

    bool isAlpha(dchar c)
    {
        return (c >= 'a' && c <= 'z')
            || (c >= 'A' && c <= 'Z')
            || c == '_' // validação para caracteres especiais
            || (c >= 192 && c <= 214)
            || (c >= 216 && c <= 246)
            || (c >= 248 && c <= 255);
    }

    bool isNumeric(dchar c)
    {
        return c >= '0' && c <= '9';
    }

    bool isAlphaNumeric(dchar c)
    {
        return isNumeric(c) || isAlpha(c);
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
        size_t i;
        return decode(source, i);
    }

    bool match(dchar ch)
    {
        checkIsAtEnd();
        if (peek() == ch)
        {
            advance();
            return true;
        }
        return false;
    }

    dstring lexNumer(dchar ch, uint start, out bool isDouble, out bool dotInvalid, bool d = true)
    {
        dstring buffer = [ch];
        while (!isAtEnd() && (isNumeric(peek()) || peek() == '.'))
        {
            if (!d && peek() == '.')
            {
                err.error(getPosition(start, line), "Sem permissão para numeros flutuantes.");
                continue;
            }
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

    Position getPosition(uint s, uint l)
    {
        return new Position(filename, new PosLine(s, l), new PosLine(l_offset, line));
    }

    Token[] tokenizer()
    {
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

                if (isDouble)
                {
                    kind = TokenKind.Double;
                    raw.d = to!double(buffer);
                }
                else
                    raw.i = to!long(buffer);

                tokens ~= new Token(kind, raw, getPosition(start, line));
                continue;
            }

            if (isAlpha(ch))
            {
                uint start = l_offset;
                dstring buffer = [ch];

                while (!isAtEnd() && isAlphaNumeric(peek()))
                    buffer ~= [advance()];

                TokenKind kind = TokenKind.Identifier;
                if (immutable TokenKind* k = buffer in keywords)
                    kind = *k;

                tokens ~= new Token(kind, TokenRaw._s(buffer), getPosition(start, line));
                continue;
            }

            if (ch == '"')
            {
                uint start = l_offset;
                uint l = line;
                dstring buffer;

                // TODO: validar escapes
                while (!isAtEnd() && peek() != '"')
                {
                    if (peek() == '\n')
                    {
                        line++;
                        l_offset = 0;
                    }
                    buffer ~= [advance()];
                }

                if (isAtEnd() || !match('"'))
                {
                    err.error(getPosition(start, l), "String não foi fechada.");
                    return tokens;
                }

                tokens ~= new Token(TokenKind.String, TokenRaw._s(buffer), getPosition(start, l));
                continue;
            }

            TokenKind k = TokenKind.Eof;
            uint start = l_offset;

            switch (ch)
            {
            case '+':
                k = TokenKind.Plus;
                break;
            case '-':
                k = TokenKind.Minus;
                break;
            case '=':
                k = TokenKind.Equals;
                if (peek() == '=')
                {
                    k = TokenKind.EEquals;
                    advance();
                }
                break;
            case '/':
                k = TokenKind.Slash;
                break;
            case '*':
                k = TokenKind.Star;
                break;
            case '(':
                k = TokenKind.LParen;
                break;
            case ')':
                k = TokenKind.RParen;
                break;
            case '{':
                k = TokenKind.LBrace;
                break;
            case '}':
                k = TokenKind.RBrace;
                break;
            case ':':
                k = TokenKind.Colon;
                break;
            case ';':
                k = TokenKind.Semicolon;
                break;
            case ',':
                k = TokenKind.Comma;
                break;
            case '.':
                k = TokenKind.Dot;
                break;
            case '<':
                k = TokenKind.LThan;
                if (peek() == '=')
                {
                    k = TokenKind.LEquals;
                    advance();
                }
                break;
            case '>':
                k = TokenKind.GThan;
                if (peek() == '=')
                {
                    k = TokenKind.GEquals;
                    advance();
                }
                break;
            default:
                break;
            }

            if (k == TokenKind.Eof)
            {
                err.error(getPosition(start, line), format("Char desconhecido: '%c'", ch));
                continue;
            }

            tokens ~= new Token(k, TokenRaw.init, getPosition(start, line));
        }
        return tokens;
    }
}
