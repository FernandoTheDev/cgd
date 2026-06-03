module frontend.lexer.lexer;

import std.stdio;
import std.exception : enforce;
import std.conv;
import frontend.lexer.token;
import std.utf : decodeFront, decode;

class Lexer
{
private:
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
        
        "retorne": TokenKind.Return,
        "retorna": TokenKind.Return,
    ];

public:
    this(string source, string filename)
    {
        this.source = source;
        this.filename = filename;
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
                dstring buffer = [ch];
                bool isFloat, isDouble;

                while ((isNumeric(peek()) || peek() == '_' || peek() == '.') && !isAtEnd())
                {
                    if (peek() == '_')
                        continue;
                    if (peek() == '.' && isDouble)
                    {
                        // TODO: melhorar
                        writeln("Error: não é permitido usar '.' em um double.");
                        continue;
                    }
                    if (peek() == '.' && !isDouble)
                        isDouble = true;
                    buffer ~= [advance()];
                }

                isFloat = match('f') || match('F');
                TokenKind kind = TokenKind.Int;
                TokenRaw raw;

                if (isDouble && !isFloat)
                {
                    kind = TokenKind.Double;
                    raw.d = to!double(buffer);
                }
                else if (isFloat)
                {
                    kind = TokenKind.Float;
                    raw.d = to!float(buffer);
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

                while (isAlphaNumeric(peek()) && !isAtEnd())
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
                while (peek() != '"' && !isAtEnd())
                    buffer ~= [advance()];

                if (!match('"'))
                {
                    writeln("String não foi fechada.");
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
                    writefln("Char desconhecido: '%c'", ch);
                    continue;
            }
            
            if (k == TokenKind.Eof)
            {
                writefln("Char desconhecido: '%c'", ch);
                continue;
            }

            tokens ~= new Token(k, TokenRaw.init, getPosition(start, line));
        }
        return tokens;
    }
}
