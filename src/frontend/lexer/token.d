module frontend.lexer.token;

import std.format;

enum TokenKind : ubyte
{
    // ctfe
    Pure,

    // keywords
    Var,
    Const,
    Fn,
    Return,
    If,
    Else,
    While,
    For,
    Type,
    Of,

    // literals
    Identifier,
    Int,
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
    LBracket,
    RBracket,

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
    dstring s;

    pragma(inline, true)
    static TokenRaw _i(long n)
    {
        return TokenRaw(i: n);
    }

    pragma(inline, true)
    static TokenRaw _d(double n)
    {
        return TokenRaw(d: n);
    }

    pragma(inline, true)
    static TokenRaw _s(dstring n)
    {
        return TokenRaw(s: n);
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
        return format("{ %s:%d:%d }", filename, start.line, start.offset);
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
