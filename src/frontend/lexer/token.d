module frontend.lexer.token;

import std.variant, std.stdio, std.conv;

enum TokenKind
{
    Var,
    Const,
    Funcao,
    Tipo,
    Retorna,
    Se,
    Senao,

    Verdadeiro,
    Falso,
    Nulo,

    Identifier, // identificador
    I32,
    I64,
    F32,
    F64,
    String, // "FernandoDev"
    Bool,
    Void,

    LParen, // (
    RParen, // )
    LBrace, // {
    RBrace, // }
    LBracket, // [
    RBracket, // ]
    Plus, // +
    PlusPlus, // ++
    Minus, // -
    MinusMinus, // --
    Star, // *
    Slash, // /
    Comma, // ,
    Colon, // :
    SemiColon, // ;
    Equals, // =
    Dot, // .
    Bang, // !
    Question, // ?
    Modulo, // %

    GreaterThan, // >
    GreaterThanEquals, // >=
    LessThan, // <
    LessThanEquals, // <=
    Or, // ||
    And, // &&
    EqualsEquals, // ==
    NotEquals, // ==

    BitAnd, // &
    BitOr, // |
    BitXor, // ^
    BitNot, // ~
    BitSHL, // <<
    BitSHR, // >>
    BitSAR, // >>>

    BitAndEquals, // &=
    BitOrEquals, // |=
    BitXorEquals, // ^=
    BitSHLEquals, // <<=
    BitSHREquals, // >>=

    PlusEquals, // +=
    MinusEquals, // -=
    StarEquals, // *=
    SlashEquals, // /=
    ModuloEquals, // %=
    TildeEquals, // ~=

    Eof // EndOfFile (FimDoArquivo)
}

struct Token
{
    TokenKind kind;
    Variant value;
    Loc loc;

    void print()
    {
        writeln("Tipo: ", kind);
        writeln("Valor: ", to!string(value));
        writeln("Localização: ", loc, "\n");
    }
}

struct LocLine
{
    ulong offset;
    ulong line;
}

struct Loc
{
    string filename; // nome do arquivo
    string dir; // diretório do arquivo
    LocLine start;
    LocLine end;
}
