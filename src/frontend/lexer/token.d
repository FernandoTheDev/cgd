module frontend.lexer.token;

import std.format;

enum TokenKind : ubyte
{
    // keywords
    Var,
    Const,
    Fn,
    Return,
    If,
    Else,
    While,
    For,

    // literals
    Identifier,
    Int,
    Float,
    Double,
    True,
    False,
    Null,
    String,

    // symbols
    LParen,
    RParen,
    LBrace,
    RBrace,

    Star,
    Slash,
    Modulo,
    Plus,
    Minus,
    LThan,
    GThan,
    LEquals,
    GEquals,

    Equals,
    EEquals,

    Colon,
    Semicolon,
    Comma,
    Dot,

    // eof
    Eof,
}

union TokenRaw
{
    long i;
    double d;
    float f;
    dstring s;

    pragma(inline, true)
    static TokenRaw _i(long n)
    {
        TokenRaw _;
        _.i = n;
        return _;
    }

    pragma(inline, true)
    static TokenRaw _d(double n)
    {
        TokenRaw _;
        _.d = n;
        return _;
    }

    pragma(inline, true)
    static TokenRaw _f(float n)
    {
        TokenRaw _;
        _.f = n;
        return _;
    }

    pragma(inline, true)
    static TokenRaw _s(dstring n)
    {
        TokenRaw _;
        _.s = n;
        return _;
    }
}

class PosLine
{
    uint offset;
    uint line;

    this(uint o, uint l)
    {
        offset = o;
        line = l;
    }
}

class Position
{
    string filename;
    PosLine start, end;

    this (string f, PosLine s, PosLine e)
    {
        filename = f;
        start = s;
        end = e;
    }

    string toStr()
    {
        return format("{ %s: %d:%d %d:%d }", filename, start.offset, start.line, end.offset, end.line);
    }
}

class Token
{
    TokenKind kind;
    TokenRaw value;
    Position pos;

    this (TokenKind k, TokenRaw r, Position p)
    {
        kind = k;
        value = r;
        pos = p;
    }

    pragma(inline, true)
    void print()
    {
        import std.stdio : writeln;

        writeln("[TOKEN]\n    kind = ", kind, "\n    value = ", value, "\n    pos = ", pos.toStr());
    }
}
