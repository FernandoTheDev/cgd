module frontend.lexer.lexer;

import std.variant;
import std.stdio;
import std.conv;
import std.array;
import std.string;
import std.ascii : toLower;
import frontend.lexer.token;
import error;

class Lexer
{
private:
    string source;
    string file;
    string dir;
    DiagnosticError error;

    ulong line = 1;
    ulong offset = 0;
    ulong lineOffset = 0;
    ulong start = 1;
    Token[] tokens = [];

    // Estaticos e imutaveis
    static immutable TokenType[string] SINGLE_CHAR_TOKENS = initSingleCharTokens();
    static immutable TokenType[string] MULTI_CHAR_TOKENS = initMultiCharTokens();
    static immutable bool[char] ALPHA_CHARS = initCharSet(
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_áÁãÃâÂàÀéÉêÊíÍóÓõÕôÔúÚçÇ");
    static immutable bool[char] DIGIT_CHARS = initCharSet("0123456789");
    static immutable bool[char] HEX_CHARS = initCharSet("0123456789abcdefABCDEF");
    static immutable bool[char] OCTAL_CHARS = initCharSet("01234567");
    static immutable bool[char] BINARY_CHARS = initCharSet("01");
    static immutable bool[char] WHITESPACE_CHARS = initCharSet(" \t\r");

    static TokenType[string] initSingleCharTokens()
    {
        TokenType[string] m;
        m["+"] = TokenType.PLUS;
        m["-"] = TokenType.MINUS;
        m["*"] = TokenType.ASTERISK;
        m["/"] = TokenType.SLASH;
        m[">"] = TokenType.GREATER_THAN;
        m["<"] = TokenType.LESS_THAN;
        m[","] = TokenType.COMMA;
        m[";"] = TokenType.SEMICOLON;
        m[":"] = TokenType.COLON;
        m["("] = TokenType.LPAREN;
        m[")"] = TokenType.RPAREN;
        m["{"] = TokenType.LBRACE;
        m["}"] = TokenType.RBRACE;
        m["."] = TokenType.DOT;
        m["%"] = TokenType.MODULO;
        m["="] = TokenType.EQUALS;
        m["["] = TokenType.LBRACKET;
        m["]"] = TokenType.RBRACKET;
        m["!"] = TokenType.BANG;
        m["?"] = TokenType.QUESTION;
        m["&"] = TokenType.BIT_AND;
        m["|"] = TokenType.BIT_OR;
        m["^"] = TokenType.BIT_XOR;
        m["~"] = TokenType.BIT_NOT;
        return m;
    }

    static TokenType[string] initMultiCharTokens()
    {
        TokenType[string] m;
        m["++"] = TokenType.INCREMENT;
        m["--"] = TokenType.DECREMENT;
        m["**"] = TokenType.EXPONENTIATION;
        m["%%"] = TokenType.REMAINDER;
        m["=="] = TokenType.EQUALS_EQUALS;
        m[">="] = TokenType.GREATER_THAN_OR_EQUALS;
        m["<="] = TokenType.LESS_THAN_OR_EQUALS;
        m["&&"] = TokenType.AND;
        m["||"] = TokenType.OR;
        m["!="] = TokenType.NOT_EQUALS;
        m[".."] = TokenType.RANGE;
        m["<<"] = TokenType.LEFT_SHIFT;
        m[">>"] = TokenType.RIGHT_SHIFT;
        m["&="] = TokenType.BIT_AND_ASSIGN;
        m["|="] = TokenType.BIT_OR_ASSIGN;
        m["^="] = TokenType.BIT_XOR_ASSIGN;
        m["<<="] = TokenType.LEFT_SHIFT_ASSIGN;
        m[">>="] = TokenType.RIGHT_SHIFT_ASSIGN;
        return m;
    }

    static bool[char] initCharSet(string chars)
    {
        bool[char] set;
        foreach (c; chars)
        {
            set[c] = true;
        }
        return set;
    }

    Loc getLocation(ulong start, ulong end, ulong line = 0)
    {
        ulong currentLine = line == 0 ? this.line : line;
        return Loc(
            this.file,
            currentLine,
            start,
            end,
            this.dir
        );
    }

    void reportError(
        string message,
        Loc loc,
        string suggestion = "",
    )
    {
        error.addError(Diagnostic(message, loc, [
                    error.makeSuggestion(
                    suggestion)
                ]));
        return;
    }

    void reportUnexpectedChar(char ch)
    {
        error.addError(
            Diagnostic(format("Caractere inesperado '%c'", ch),
                this.getLocation(this.start, this.start + 1),
                [
                    error.makeSuggestion(
                    "Remova o caractere e verifique se o erro não persiste mais.",
                    error.getLineText(this.line, this.file).replace(ch, ""),
                    ),
                ])
        );
    }

    Token createToken(TokenType kind, Variant value, ulong skipChars = 1, ulong startAdd = 0)
    {
        auto valueLength = to!string(value).length;
        ulong st = this.start + startAdd;
        Token token = Token(kind, value, this.getLocation(st, cast(ulong) st + valueLength));
        this.tokens ~= token;
        this.offset += skipChars;
        return token;
    }

    void createTokenWithLocation(TokenType kind, Variant value, ulong start, ulong length)
    {
        this.tokens ~= Token(
            kind,
            value,
            this.getLocation(start, start + length)
        );
    }

    TokenType getNumType(long n)
    {

        // i32 range: -2,147,483,648 to 2,147,483,647
        if (n >= -2_147_483_648L && n <= 2_147_483_647L)
        {
            return TokenType.I32;
        }
        // i64 range: fits in long (D's long is 64-bit)
        return TokenType.I64;

    }

    void lexHexadecimal(ulong startPos)
    {
        this.offset += 2; // Skip "0x" or "0X"
        const hexDigits = this.consumeHexDigits();

        if (hexDigits.length == 0)
        {
            this.reportError("Número hexadecimal inválido: dígitos ausentes após '0x'", this.getLocation(startPos, this
                    .offset));
            return;
        }

        auto fullHex = "0x" ~ hexDigits;
        long value = to!long(hexDigits, 16);

        this.createTokenWithLocation(
            getNumType(value),
            Variant(value),
            startPos,
            fullHex.length,
        );
    }

    void lexOctal(ulong startPos)
    {
        this.offset += 2; // Skip "0o" or "0O"
        const octalDigits = this.consumeOctalDigits();

        if (octalDigits.length == 0)
        {
            this.reportError("Número octal inválido: dígitos ausentes após '0o'", this.getLocation(startPos, this
                    .offset));
            return;
        }

        auto fullOctal = "0o" ~ octalDigits;
        long value = to!long(octalDigits, 8);

        this.createTokenWithLocation(
            getNumType(value),
            Variant(value),
            startPos,
            fullOctal.length,
        );
    }

    void lexBinaryWithPrefix(ulong startPos)
    {
        this.offset += 2; // Skip "0b" or "0B"
        const binaryDigits = this.consumeBinaryDigits();

        if (binaryDigits.length == 0)
        {
            this.reportError("Número binário inválido: dígitos ausentes após '0b'", this.getLocation(startPos, this
                    .offset));
            return;
        }

        auto fullBinary = "0b" ~ binaryDigits;
        long value = to!long(binaryDigits, 2);

        this.createTokenWithLocation(
            getNumType(value),
            Variant(value),
            startPos,
            fullBinary.length,
        );
    }

    bool lexString()
    {
        string value = ""; // Buffer
        ulong startLine = this.line;
        ulong startPos = this.start;
        char openingQuote = this.source[this.offset];
        this.offset++; // Skip opening quote

        while (this.offset < this.source.length && this.source[this.offset] != openingQuote)
        {
            char ch = this.source[this.offset];

            if (ch == '\n')
            {
                this.line += 1;
                value ~= ch;
                this.offset++;
                this.lineOffset = this.offset;
                continue;
            }

            // Handle escape sequences
            if (ch == '\\')
            {
                this.offset++;
                if (this.offset >= this.source.length)
                    break;

                value ~= this.getEscapedChar(this.source[this.offset]);
                this.offset++;
            }
            else
            {
                value ~= ch;
                this.offset++;
            }
        }

        // Check for unclosed string
        if (this.offset >= this.source.length || this.source[this.offset] != openingQuote)
        {
            ulong errorStart = startPos;
            ulong errorEnd = this.offset - this.lineOffset;

            Loc loc = this.getLocation(errorStart, errorEnd);
            loc.line = startLine;

            this.reportError(
                "A string não foi fechada",
                loc,
                format("Adicione '%c' ao final da string.", openingQuote)
            );
            return false;
        }

        this.offset++;
        this.createTokenWithLocation(
            TokenType.I8P,
            Variant(value),
            startPos,
            this.offset - startPos - this.lineOffset + startPos
        );
        return true;
    }

    char getEscapedChar(char ch)
    {
        switch (ch)
        {
        case 'n':
            return '\n';
        case 't':
            return '\t';
        case 'r':
            return '\r';
        case '\\':
            return '\\';
        case '\'':
            return '\'';
        case '0':
            return '\0';
        default:
            return ch;
        }
    }

    bool lexComment()
    {
        ulong startPos = this.offset;
        this.offset++; // Skip the first '/'

        if (this.source[this.offset] == '/')
        {
            this.offset++;
            while (this.offset < this.source.length && this.source[this.offset] != '\n')
            {
                this.offset++;
            }
            return true;
        }

        if (this.source[this.offset] == '*')
        {
            // Multiple-line body comment
            this.offset++;

            while (this.offset + 1 < this.source.length)
            {
                if (this.source[this.offset] == '*' &&
                    this.source[this.offset + 1] == '/')
                {
                    this.offset += 2;
                    return true;
                }

                if (this.source[this.offset] == '\n')
                {
                    this.line++;
                    this.lineOffset = this.offset + 1;
                }
                this.offset++;
            }
            // Error
            this.reportError("Corpo do comentário não foi fechado.", this.getLocation(startPos, this
                    .offset));
            return false;
        }

        this.offset--;
        return false;
    }

    void lexIdentifier()
    {
        const ulong startOffset = this.offset;
        while (this.offset < this.source.length)
        {
            char c = this.source[this.offset];
            if (!(c in this.ALPHA_CHARS) && !(
                    c in this.DIGIT_CHARS))
            {
                break;
            }
            this.offset++;
        }

        string identifier = this.source[startOffset .. this.offset];
        TokenType tokenType = TokenType
            .IDENTIFIER;
        if (auto keywordType = identifier in keywords)
        {
            tokenType = *keywordType;
        }

        this.createTokenWithLocation(tokenType, Variant(identifier), startOffset - this.lineOffset, identifier
                .length);
    }

    bool lexSingleCharToken()
    {
        string currentChar = this.source[this.offset .. this.offset + 1];

        if (auto tokenType = currentChar in SINGLE_CHAR_TOKENS)
        {
            this.createToken(*tokenType, Variant(currentChar));
            return true;
        }
        return false;
    }

    bool lexMultiCharToken()
    {
        if (this.offset + 1 >= this.source.length)
            return false;
        string twoChars = this
            .source[this.offset .. this.offset + 2];

        if (auto tokenType = twoChars in MULTI_CHAR_TOKENS)
        {
            this.createToken(*tokenType, Variant(twoChars), 2);
            return true;
        }
        return false;
    }

    string consumeDigits()
    {
        ulong _start = this.offset;
        while (this.offset < this.source.length && this
            .source[this.offset] in this.DIGIT_CHARS)
        {
            this.offset++;
        }
        return this.source[_start .. this.offset];
    }

    string consumeHexDigits()
    {
        ulong _start = this.offset;
        while (this.offset < this.source.length && this
            .source[this.offset] in this.HEX_CHARS)
        {
            this.offset++;
        }
        return this.source[_start .. this.offset];
    }

    string consumeOctalDigits()
    {
        ulong _start = this.offset;
        while (
            this.offset < this.source.length && this
            .source[this.offset] in this.OCTAL_CHARS)
        {
            this.offset++;
        }
        return this.source[_start .. this.offset];
    }

    string consumeBinaryDigits()
    {
        ulong _start = this.offset;
        while (this.offset < this.source.length && this
            .source[this.offset] in this
            .BINARY_CHARS)
        {
            this.offset++;
        }
        return this
            .source[_start .. this.offset];
    }

    void lexNumber()
    {
        ulong startPos = this.offset;

        if (
            this.source[this.offset] == '0' && this.offset + 1 < this
            .source.length
            )
        {
            const prefix = toLower(
                this.source[this.offset + 1]);

            // Hexadecimal (0x or 0X)
            if (prefix == 'x')
            {
                this.lexHexadecimal(startPos);
                return;
            }

            // Octal (0o or 0O)
            if (prefix == 'o')
            {
                this.lexOctal(startPos);
                return;
            }

            // Binary (0b or 0B)
            if (prefix == 'b')
            {
                this.lexBinaryWithPrefix(
                    startPos);
                return;
            }
        }

        string number = this.consumeDigits();

        // Handle range operator (e.g., 123..456)
        if (
            this.source[0 .. this.offset] == "..")
        {
            this.createTokenWithLocation(
                getNumType(to!long(number)),
                Variant(to!long(number)),
                startPos,
                number.length,
            );
            this.createToken(TokenType.RANGE, Variant(
                    ".."), 2);
            return;
        }

        // Handle floating point numbers
        if (this.offset < this.source.length && this
            .source[this.offset] == '.')
        {
            const nextChar = this
                .source[this.offset + 1];
            if (
                nextChar in this
                .DIGIT_CHARS)
            {
                number ~= ".";
                this.offset++;
                number ~= this.consumeDigits();

                TokenType type = TokenType.DOUBLE;

                if (this.source[this.offset] == 'f' && this.source[this.offset] == 'F')
                {
                    type = TokenType.FLOAT;
                    this.offset++;
                }

                this.createTokenWithLocation(
                    type,
                    Variant(number),
                    startPos,
                    number.length,
                );
                return;
            }
        }

        // Handle binary literals with suffix (e.g., 101b)
        if (
            this.offset < this.source.length &&
            toLower(
                this
                .source[this.offset]) == 'b'
            )
        {
            this.offset++;
            long binaryValue = to!long(number, 2);

            this.createTokenWithLocation(
                getNumType(binaryValue),
                Variant(binaryValue),
                startPos,
                number.length + 1
            );
            return;
        }

        this.createTokenWithLocation(
            getNumType(to!long(number)),
            Variant(to!long(number)),
            startPos,
            number.length,
        );
    }

public:
    this(string file, string source, string dir, DiagnosticError e)
    {
        this.file = file;
        this.source = source;
        this.dir = dir;
        this.error = e;
    }

    Token[] tokenize(
        bool ignoreNewLine = false)
    {
        try
        {
            ulong sourceLength = cast(
                ulong) this.source
                .length;

            while (
                this.offset < sourceLength)
            {
                this.start = this.offset - this
                    .lineOffset;
                char c = this
                    .source[this
                        .offset];

                if (c == '\n')
                {
                    if (
                        ignoreNewLine)
                    {
                        this
                            .offset++;
                        continue;
                    }
                    this.line++;
                    this
                        .offset++;
                    this.lineOffset = this
                        .offset;
                    continue;
                }

                if (
                    c in this
                    .WHITESPACE_CHARS)
                {
                    this.offset++;
                    continue;
                }

                if (c == '/' && this.offset + 1 < sourceLength)
                {
                    char nextChar = this
                        .source[this.offset + 1];
                    if (nextChar == '/' || nextChar == '*')
                    {
                        if (
                            !this.lexComment())
                        {
                            if (!this
                                .lexSingleCharToken())
                            {
                                this.reportUnexpectedChar(
                                    c);
                            }
                        }
                        continue;
                    }
                }

                // Handle string literals
                if (c == '"' || c == '\'')
                {
                    if (
                        !this.lexString())
                        return null; // Error
                    continue;
                }

                if (
                    c in this
                    .ALPHA_CHARS)
                {
                    this.lexIdentifier();
                    continue;
                }

                if (
                    c in this
                    .DIGIT_CHARS)
                {
                    this.lexNumber();
                    continue;
                }

                if (
                    this.lexMultiCharToken())
                {
                    continue;
                }

                if (
                    this.lexSingleCharToken())
                {
                    continue;
                }

                this.reportUnexpectedChar(
                    c);
                this.offset++; // skip
                continue;
            }

            this.createToken(TokenType.EOF, Variant(
                    "\0"), 0);
            return this.tokens;
        }
        catch (Exception e)
        {
            // ignore
            throw e;
        }
    }
}

unittest
{
    writeln("Testando Lexer básico...");

    auto error = new DiagnosticError();
    auto lexer = new Lexer("test.delegua", "", ".", error);

    assert(lexer !is null);

    writeln("✓ Teste de criação do Lexer passou!");
}

unittest
{
    writeln("Testando tokenização básica...");

    auto error = new DiagnosticError();
    auto lexer = new Lexer("test.delegua", "var x = 42;", ".", error);
    auto tokens = lexer.tokenize();

    assert(tokens.length >= 6);
    assert(tokens[0].kind == TokenType.VAR);
    assert(tokens[1].kind == TokenType.IDENTIFIER);
    assert(tokens[1].value.get!string == "x");
    assert(tokens[2].kind == TokenType.EQUALS);
    assert(tokens[3].kind == TokenType.INT);
    assert(tokens[3].value.get!long == 42);
    assert(tokens[4].kind == TokenType.SEMICOLON);
    assert(tokens[$ - 1].kind == TokenType.EOF);

    writeln("✓ Teste de tokenização básica passou!");
}

unittest
{
    writeln("Testando tokenização de strings...");

    auto error = new DiagnosticError();
    auto lexer = new Lexer("test.delegua", `"hello world"`, ".", error);
    auto tokens = lexer.tokenize();

    assert(tokens.length == 2);
    assert(tokens[0].kind == TokenType.STRING);
    assert(tokens[0].value.get!string == "hello world");
    assert(tokens[1].kind == TokenType.EOF);

    writeln("✓ Teste de tokenização de strings passou!");
}

unittest
{
    writeln("Testando tokenização de números...");

    auto error = new DiagnosticError();

    // Teste número inteiro
    auto lexer1 = new Lexer("test.delegua", "123", ".", error);
    auto tokens1 = lexer1.tokenize();
    assert(tokens1.length == 2);
    assert(tokens1[0].kind == TokenType.INT);
    assert(tokens1[0].value.get!long == 123);

    // Teste número float - vou verificar primeiro o tipo retornado
    auto lexer2 = new Lexer("test.delegua", "12.34", ".", error);
    auto tokens2 = lexer2.tokenize();
    assert(tokens2.length == 2);
    assert(tokens2[0].kind == TokenType.FLOAT);
    // Como pode ser string ou double, vou verificar se é um valor numérico válido
    // usando conversão segura
    if (tokens2[0].value.type == typeid(string))
    {
        import std.conv : to;

        double val = tokens2[0].value
            .get!string
            .to!double;
        assert(val == 12.34);
    }
    else
    {
        assert(tokens2[0].value.get!double == 12.34);
    }

    writeln("✓ Teste de tokenização de números passou!");
}

unittest
{
    writeln("Testando keywords em português...");

    auto error = new DiagnosticError();
    auto lexer = new Lexer("test.delegua", "se verdadeiro então", ".", error);
    auto tokens = lexer.tokenize();

    assert(tokens.length == 4);
    assert(tokens[0].kind == TokenType.SE);
    assert(tokens[1].kind == TokenType.TRUE);
    assert(tokens[2].kind == TokenType.IDENTIFIER);
    assert(tokens[3].kind == TokenType.EOF);

    writeln("✓ Teste de keywords em português passou!");
}

unittest
{
    writeln("Testando operadores...");

    auto error = new DiagnosticError();
    auto lexer = new Lexer("test.delegua", "+ - * / == != >= <=", ".", error);
    auto tokens = lexer.tokenize();

    assert(tokens.length == 9);
    assert(tokens[0].kind == TokenType.PLUS);
    assert(tokens[1].kind == TokenType.MINUS);
    assert(tokens[2].kind == TokenType.ASTERISK);
    assert(tokens[3].kind == TokenType.SLASH);
    assert(tokens[4].kind == TokenType.EQUALS_EQUALS);
    assert(tokens[5].kind == TokenType.NOT_EQUALS);
    assert(tokens[6].kind == TokenType.GREATER_THAN_OR_EQUALS);
    assert(tokens[7].kind == TokenType.LESS_THAN_OR_EQUALS);
    assert(tokens[8].kind == TokenType.EOF);

    writeln("✓ Teste de operadores passou!");
}
