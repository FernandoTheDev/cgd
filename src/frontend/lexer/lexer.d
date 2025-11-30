module frontend.lexer.lexer;

import std.stdio, std.conv, std.variant, std.ascii, std.format, std.exception, frontend
    .lexer.token, common.reporter;

class Lexer
{
private:
    string source = "";
    string filename = "";
    string dir = ".";
    long offset = 0;
    long line = 1;
    long column = 1;
    Token[] tokens = [];
    DiagnosticError error;

    TokenKind[string] keywords;
    TokenKind[string] symbols;

    // Otimizações
    string[256] charToStr;
    string[string] internedStrings;
    bool[256] isIdentStart;
    bool[256] isIdentCont;

    string intern(string s)
    {
        if (auto cached = s in internedStrings)
            return *cached;
        internedStrings[s] = s;
        return s;
    }

    pragma(inline, true)
    void setCharToStrAndAsIdent()
    {
        foreach (i; 0 .. 256)
            charToStr[i] = [cast(char) i];

        foreach (c; 'a' .. 'z' + 1)
        {
            isIdentStart[c] = true;
            isIdentCont[c] = true;
        }
        foreach (c; 'A' .. 'Z' + 1)
        {
            isIdentStart[c] = true;
            isIdentCont[c] = true;
        }
        isIdentStart['_'] = true;
        isIdentCont['_'] = true;
        foreach (c; '0' .. '9' + 1)
            isIdentCont[c] = true;
    }

    pragma(inline, true)
    void setKeywords()
    {
        keywords["var"] = TokenKind.Var;
        keywords["funcao"] = TokenKind.Funcao;
    }

    pragma(inline, true)
    void setSymbols()
    {
        // Agrupadores
        symbols["("] = TokenKind.LParen;
        symbols[")"] = TokenKind.RParen;
        symbols["{"] = TokenKind.LBrace;
        symbols["}"] = TokenKind.RBrace;
        symbols["["] = TokenKind.LBracket;
        symbols["]"] = TokenKind.RBracket;

        // Operadores aritméticos básicos
        symbols["+"] = TokenKind.Plus;
        symbols["-"] = TokenKind.Minus;
        symbols["*"] = TokenKind.Star;
        symbols["/"] = TokenKind.Slash;
        symbols["%"] = TokenKind.Modulo;

        // Operadores de comparação
        symbols[">"] = TokenKind.GreaterThan;
        symbols["<"] = TokenKind.LessThan;
        symbols["!"] = TokenKind.Bang;
        symbols[">="] = TokenKind.GreaterThanEquals;
        symbols["<="] = TokenKind.LessThanEquals;
        symbols["=="] = TokenKind.EqualsEquals;
        symbols["!="] = TokenKind.NotEquals;

        // Pontuação
        symbols["."] = TokenKind.Dot;
        symbols[":"] = TokenKind.Colon;
        symbols[","] = TokenKind.Comma;
        symbols[";"] = TokenKind.SemiColon;
        symbols["="] = TokenKind.Equals;

        // Operadores bitwise
        symbols["&"] = TokenKind.BitAnd;
        symbols["|"] = TokenKind.BitOr;
        symbols["^"] = TokenKind.BitXor;
        symbols["~"] = TokenKind.BitNot;
        symbols["<<"] = TokenKind.BitSHL;
        symbols[">>"] = TokenKind.BitSHR;
        symbols[">>>"] = TokenKind.BitSAR;

        // Operadores lógicos
        symbols["||"] = TokenKind.Or;
        symbols["&&"] = TokenKind.And;

        // Operadores de incremento/decremento
        symbols["++"] = TokenKind.PlusPlus;
        symbols["--"] = TokenKind.MinusMinus;

        // Operadores de atribuição composta
        symbols["+="] = TokenKind.PlusEquals;
        symbols["-="] = TokenKind.MinusEquals;
        symbols["/="] = TokenKind.SlashEquals;
        symbols["*="] = TokenKind.StarEquals;
        symbols["%="] = TokenKind.ModuloEquals;
        symbols["&="] = TokenKind.BitAndEquals;
        symbols["|="] = TokenKind.BitOrEquals;
        symbols["^="] = TokenKind.BitXorEquals;
        symbols["~="] = TokenKind.TildeEquals;
        symbols[">>="] = TokenKind.BitSHREquals;
        symbols["<<="] = TokenKind.BitSHLEquals;
    }

    bool lexSymbol(char c)
    {
        string ch = charToStr[c];

        // Tenta operadores de 3, 2 e 1 caractere(s)
        foreach (len; [3, 2, 1])
        {
            if (offset + len - 1 < source.length)
            {
                string op = source[offset .. offset + len];
                if (op in symbols)
                {
                    createToken(symbols[op], Variant(op), len);
                    return true;
                }
            }
        }

        return false;
    }

    pragma(inline, true)
    Loc createLoc(ulong startCol, ulong endCol, long line_ = -1)
    {
        long actualLine = (line_ == -1) ? line : line_;
        return Loc(
            filename,
            dir,
            LocLine(startCol - 1, actualLine),
            LocLine(endCol - 1, line)
        );
    }

    pragma(inline, true)
    void createToken(TokenKind kind, Variant value, ulong len)
    {
        tokens ~= Token(kind, value, createLoc(column - len, column - 1));
    }

    pragma(inline, true)
    void reportError(string message, long startCol, long startLine = -1, Suggestion[] suggestions = null)
    {
        error.addError(Diagnostic(message, createLoc(startCol, column - 1, startLine), suggestions));
    }

    void advance(int count = 1)
    {
        for (int i; i < count; i++)
        {
            if (offset < source.length)
            {
                if (source[offset] == '\n')
                {
                    line++;
                    column = 1;
                }
                else
                    column++;
                offset++;
            }
        }
    }

    pragma(inline, true)
    char peek(int lookahead = 0)
    {
        long pos = offset + lookahead;
        return (pos < source.length) ? source[pos] : '\0';
    }

    void lexIdentifier()
    {
        long startOffset = offset;
        long startCol = column;

        while (offset < source.length && (isIdentCont[peek()] || peek() == '_'))
            advance();

        string id = source[startOffset .. offset];
        TokenKind kind = (id in keywords) ? keywords[id] : TokenKind.Identifier;
        tokens ~= Token(kind, Variant(intern(id)), createLoc(startCol, column - 1));
    }

    void lexNumber()
    {
        long startOffset = offset;
        long startCol = column;
        string n;
        bool isDouble = false;

        // Números decimais normais
        while (offset < source.length && (isDigit(peek()) || peek() == '_'))
        {
            if (peek() != '_')
                n ~= charToStr[peek()];
            advance();
        }

        // Verifica ponto decimal
        if (offset < source.length && peek() == '.' && offset + 1 < source.length && isDigit(
                source[offset + 1]))
        {
            n ~= ".";
            advance();
            isDouble = true;
            long offsetSave = offset;

            while (offset < source.length && isDigit(peek()))
                advance();
            n ~= source[offsetSave .. offset];
        }

        // Números hexadecimais
        if (n.length == 1 && n[0] == '0' && offset < source.length && (peek() == 'x' || peek() == 'X'))
        {
            n ~= "x";
            advance();
            long offsetSave = offset;

            while (offset < source.length && isHexDigit(peek()))
                advance();

            n ~= source[offsetSave .. offset];
            auto hexOnly = n[2 .. $];

            if (hexOnly.length == 0)
            {
                reportError("Número hexadecimal vazio", startCol);
                tokens ~= Token(TokenKind.I64, Variant(intern("0")), createLoc(startCol, column - 1));
                return;
            }

            tokens ~= Token(TokenKind.I64, Variant(intern(to!string(parse!long(hexOnly, 16)))),
                createLoc(startCol, column - 1));
            return;
        }

        // Determina o tipo do token baseado no sufixo ou se é double
        TokenKind kind;
        if (offset < source.length)
        {
            char suffix = peek();
            switch (suffix)
            {
            case 'F', 'f':
                advance();
                kind = TokenKind.F32;
                break;
            case 'D', 'd':
                advance();
                kind = TokenKind.F64;
                break;
            case 'L':
                advance();
                kind = TokenKind.F128;
                break;
            default:
                kind = isDouble ? TokenKind.F64 : TokenKind.I64;
            }
        }
        else
        {
            kind = isDouble ? TokenKind.F64 : TokenKind.I64;
        }

        tokens ~= Token(kind, Variant(intern(n)), createLoc(startCol, column - 1));
    }

    void lexString()
    {
        long startLine = line;
        long startCol = column;
        advance(); // Consome '"'
        string buff;

        while (offset < source.length && peek() != '"')
        {
            char pk = peek();

            if (pk == '\\')
            {
                processEscapeSequence(buff, startCol, startLine);
            }
            else if (pk == '\n')
            {
                buff ~= '\n';
                advance();
            }
            else
            {
                buff ~= pk;
                advance();
            }
        }

        if (offset < source.length && peek() == '"')
        {
            advance();
        }
        else
        {
            reportError("Texto não terminado", startCol, startLine,
                [error.makeSuggestion("Adicione um '\"' ao fim do texto.")]);
        }

        tokens ~= Token(TokenKind.String, Variant(buff), createLoc(startCol, column - 1, startLine));
    }

    void processEscapeSequence(ref string buff, long startCol, long startLine)
    {
        advance(); // Consome '\'

        if (offset >= source.length)
        {
            reportError("Sequência de escape incompleta no final do arquivo", startCol, startLine);
            return;
        }

        char escaped = peek();

        switch (escaped)
        {
        case 'n':
            buff ~= '\n';
            break;
        case 't':
            buff ~= '\t';
            break;
        case 'r':
            buff ~= '\r';
            break;
        case '\\':
            buff ~= '\\';
            break;
        case '"':
            buff ~= '"';
            break;
        case '0':
            buff ~= '\0';
            break;
        case 'b':
            buff ~= '\b';
            break;
        case 'f':
            buff ~= '\f';
            break;
        case 'v':
            buff ~= '\v';
            break;
        case '\'':
            buff ~= '\'';
            break;
        case 'x':
            processHexEscape(buff, 2, startCol, startLine);
            return;
        case 'u':
            processUnicodeEscape(buff, startCol, startLine);
            return;
        default:
            reportError(format("Sequência de escape desconhecida \\%s", escaped), startCol, startLine);
            buff ~= escaped;
            break;
        }
        advance();
    }

    void processHexEscape(ref string buff, int digits, long startCol, long startLine)
    {
        advance(); // Consome 'x'
        if (offset + digits - 1 < source.length)
        {
            string hexStr = source[offset .. offset + digits];
            try
            {
                int hexValue = parse!int(hexStr, 16);
                buff ~= cast(char) hexValue;
                advance(digits - 1);
            }
            catch (Exception e)
            {
                reportError(format("Sequência hexadecimal inválida \\x%s", hexStr), startCol, startLine);
                buff ~= 'x';
            }
        }
        else
        {
            reportError("Sequência hexadecimal incompleta", startCol, startLine);
            buff ~= 'x';
        }
    }

    void processUnicodeEscape(ref string buff, long startCol, long startLine)
    {
        advance(); // Consome 'u'
        if (offset + 3 < source.length)
        {
            string hexStr = source[offset .. offset + 4];
            try
            {
                int unicodeValue = parse!int(hexStr, 16);
                import std.utf : encode;

                char[4] utf8Buf;
                long len = encode(utf8Buf, cast(dchar) unicodeValue);
                buff ~= utf8Buf[0 .. len];
                advance(3);
            }
            catch (Exception e)
            {
                reportError(format("Sequência de escape unicode inválida \\u%s", hexStr), startCol, startLine);
                buff ~= 'u';
            }
        }
        else
        {
            reportError("Escape unicode incompleto", startCol, startLine);
            buff ~= 'u';
        }
    }

public:
    this(string filename = "", string source = "", string dir = ".", DiagnosticError error = null)
    {
        this.filename = filename;
        this.source = source;
        this.dir = dir;
        this.error = error;
        setKeywords();
        setSymbols();
        setCharToStrAndAsIdent();
    }

    Token[] tokenize()
    {
        while (offset < source.length)
        {
            char ch = source[offset];

            // Pula quebras de linha
            if (ch == '\n')
            {
                advance();
                continue;
            }

            // Pula espaços em branco
            if (isWhite(ch))
            {
                advance();
                continue;
            }

            // Comentários
            if ((ch == '/' && offset + 1 < source.length && source[offset + 1] == '/') || ch == '#')
            {
                while (offset < source.length && peek() != '\n')
                    advance();
                continue;
            }

            // Identificadores e palavras-chave
            if (isIdentStart[ch])
            {
                lexIdentifier();
                continue;
            }

            // Números
            if (isDigit(ch))
            {
                lexNumber();
                continue;
            }

            // Strings
            if (ch == '"')
            {
                lexString();
                continue;
            }

            // Símbolos e operadores
            if (lexSymbol(ch))
            {
                // Determina o tamanho do operador encontrado
                int opLen = 1;
                foreach (len; [3, 2])
                {
                    if (offset + len - 1 < source.length)
                    {
                        string op = source[offset .. offset + len];
                        if (op in symbols)
                        {
                            opLen = len;
                            break;
                        }
                    }
                }
                advance(opLen);
                continue;
            }

            // Caractere inválido
            reportError(format("Caractere inválido '%c'", ch), column, -1, [
                    error.makeSuggestion("Remova o caractere.")
                ]);
            advance();
        }

        tokens ~= Token(TokenKind.Eof, Variant(null), createLoc(column, column));
        return tokens;
    }
}
