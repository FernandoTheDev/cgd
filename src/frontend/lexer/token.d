module frontend.lexer.token;

import std.variant;
import std.stdio;

// Token type
enum TokenType
{
    // Keywords
    VAR, // var
    FALSE, // false
    TRUE, // true
    SUSTAR, // sustar
    DO, // faça/faca
    CASO, // caso
    SENAO, // senão/senao
    CONTINUE, // continue
    PARA, // para
    ESCOLHA, // escolha
    ENQUANTO, // enquanto
    FAZER, // fazer
    PADRAO, // padrão/padrao
    SE, // se
    FALHAR, // falhar
    TENTE, // tente
    FINALMENTE, // finalmente
    INSTANCEOF, // instanceof
    NOVO, // novo
    PEGUE, // pegue
    RETORNA, // retorna/retorne
    VAZIO, // vazio
    DEBUGGER, // debugger
    FUNCAO, // função/funcao
    ISTO, // isto
    COM, // com
    EXCLUIR, // excluir
    EM, // em
    COMO, // como
    DE, // de
    QUEBRAR, // quebrar (para switch)
    IMPORTAR, // impotar
    CLASSE, // classe
    PRIVADO, // privado
    PUBLICO, // publico
    PROTEGIDO, // protegido
    CONSTRUTOR, // construtor
    DESTRUTOR, // destrutor

    // Future Reserved Words
    ENUM, // enum
    EXTENDE, // estende
    SUPER, // super
    CONST, // const
    EXPORTAR, // exportar

    IDENTIFIER, // x

    // TYPES
    NULL, // null
    I1, // i1 type
    I8P, // i8 type / "string literals"
    I8, // i8 type
    I16, // i16 type
    I32, // i32 type  
    I64, // i64 type
    I128, // i128 type
    // Floating point types
    HALF, // half type
    FLOAT, // float type / 10.1
    DOUBLE, // double type
    FP128, // fp128 type
    X86_FP80, // x86_fp80 type
    PPC_FP128, // ppc_fp128 type
    // Special types
    VOID, // void type
    LABEL, // label type
    METADATA, // metadata type
    TOKEN, // token type

    // Symbols
    EQUALS, // =
    PLUS, // +
    INCREMENT, // ++
    MINUS, // -
    DECREMENT, // --
    SLASH, // /
    ASTERISK, // *
    EXPONENTIATION, // **
    MODULO, // %
    REMAINDER, // %%
    EQUALS_EQUALS, // ==
    NOT_EQUALS, // !=
    GREATER_THAN, // >
    LESS_THAN, // <
    GREATER_THAN_OR_EQUALS, // >=
    LESS_THAN_OR_EQUALS, // <=
    AND, // &&
    OR, // ||
    COMMA, // ,
    COLON, // :
    SEMICOLON, // ;
    DOT, // .
    LPAREN, // (
    RPAREN, // )
    LBRACE, // {
    RBRACE, // }
    LBRACKET, // [
    RBRACKET, // ]
    NOT, // ]
    RANGE, // ..
    BANG, // !
    QUESTION, // ?

    // Operadores bitwise básicos
    BIT_AND, // &
    BIT_OR, // |
    BIT_XOR, // ^
    BIT_NOT, // ~
    LEFT_SHIFT, // <<
    RIGHT_SHIFT, // >>

    // Operadores bitwise compostos (assignment)
    BIT_AND_ASSIGN, // &=
    BIT_OR_ASSIGN, // |=
    BIT_XOR_ASSIGN, // ^=
    LEFT_SHIFT_ASSIGN, // <<=
    RIGHT_SHIFT_ASSIGN, // >>=

    EOF, // EndOfFile
}

// Loc from Token
struct Loc
{
    string file;
    ulong line;
    ulong start;
    ulong end;
    string dir;
}

// Token
struct Token
{
    TokenType kind;
    Variant value;
    Loc loc;

    this(TokenType kind, Variant value, Loc loc)
    {
        this.kind = kind;
        this.value = value;
        this.loc = loc;
    }

    void print()
    {
        import std.stdio : writeln;
        import std.format : format;

        writeln(format("Token Kind: %s", this.kind));
        writeln(format("Token value: %s", this.value));
        writeln(format("Token loc: %s", this.loc.line));
        writeln("---------------------------------------------\n");
    }
}

TokenType[string] keywords;

shared static this()
{
    keywords["var"] = TokenType.VAR;

    keywords["false"] = TokenType.FALSE;
    keywords["falso"] = TokenType.FALSE;
    keywords["verdadeiro"] = TokenType.TRUE;

    keywords["sustar"] = TokenType.SUSTAR;
    keywords["faca"] = TokenType.DO;
    keywords["faça"] = TokenType.DO;
    keywords["caso"] = TokenType.CASO;
    keywords["quebrar"] = TokenType.QUEBRAR;
    keywords["senao"] = TokenType.SENAO;
    keywords["senão"] = TokenType.SENAO;
    keywords["continue"] = TokenType.CONTINUE;
    keywords["para"] = TokenType.PARA;
    keywords["escolha"] = TokenType.ESCOLHA;
    keywords["enquanto"] = TokenType.ENQUANTO;
    keywords["fazer"] = TokenType.FAZER;
    keywords["padrao"] = TokenType.PADRAO;
    keywords["padrão"] = TokenType.PADRAO;
    keywords["se"] = TokenType.SE;
    keywords["falhar"] = TokenType.FALHAR;
    keywords["tente"] = TokenType.TENTE;
    keywords["finalmente"] = TokenType.FINALMENTE;
    keywords["instanceof"] = TokenType.INSTANCEOF;
    keywords["novo"] = TokenType.NOVO;
    keywords["pegue"] = TokenType.PEGUE;
    keywords["retorna"] = TokenType.RETORNA;
    keywords["retorne"] = TokenType.RETORNA;
    keywords["debugger"] = TokenType.DEBUGGER;
    keywords["funcao"] = TokenType.FUNCAO;
    keywords["função"] = TokenType.FUNCAO;
    keywords["isto"] = TokenType.ISTO;
    keywords["com"] = TokenType.COM;
    keywords["excluir"] = TokenType.EXCLUIR;
    keywords["em"] = TokenType.EM;
    keywords["como"] = TokenType.COMO;
    keywords["de"] = TokenType.DE;
    keywords["importar"] = TokenType.IMPORTAR;
    keywords["classe"] = TokenType.CLASSE;
    keywords["publico"] = TokenType.PUBLICO;
    keywords["público"] = TokenType.PUBLICO;
    keywords["privado"] = TokenType.PRIVADO;
    keywords["protegido"] = TokenType.PROTEGIDO;
    keywords["construtor"] = TokenType.CONSTRUTOR;
    keywords["destrutor"] = TokenType.DESTRUTOR;

    // Future Reserved Words
    keywords["enum"] = TokenType.ENUM;
    keywords["estende"] = TokenType.EXTENDE;
    keywords["super"] = TokenType.SUPER;
    keywords["const"] = TokenType.CONST;
    keywords["exportar"] = TokenType.EXPORTAR;
}

bool isTypeToken(Token token)
{
    import std.conv : to;

    if (token.kind != TokenType.IDENTIFIER)
        return false;

    static immutable bool[string] typeKeywords = [
        "null": true,
        "i1": true, // 1-bit integer (boolean)
        "i8p": true, // string
        "i8": true, // 8-bit integer (byte)
        "i16": true, // 16-bit integer
        "i32": true, // 32-bit integer
        "i64": true, // 64-bit integer
        "i128": true, // 128-bit integer

        // Floating point types
        "half": true, // 16-bit floating point
        "float": true, // 32-bit floating point
        "double": true, // 64-bit floating point
        "fp128": true, // 128-bit floating point
        "x86_fp80": true, // x86 80-bit floating point
        "ppc_fp128": true, // PowerPC 128-bit floating point

        // Other basic types
        "void": true, // void type
        "label": true, // label type
        "metadata": true, // metadata type
        "token": true, // token type
    ];

    try
    {
        string tokenValue = token.value.get!string;
        return (tokenValue in typeKeywords) !is null;
    }
    catch (Exception e)
    {
        return false;
    }
}

bool isComplexTypeToken(Token token)
{
    switch (token.kind)
    {
    case TokenType.ASTERISK:
    case TokenType.LBRACKET:
    case TokenType.RBRACKET:
        return true;
    default:
        return false;
    }
}

unittest
{
    writeln("Testando Token...");

    auto loc = Loc("test.d", 1, 1, 5, ".");
    auto token = Token(TokenType.IDENTIFIER, Variant("teste"), loc);
    assert(token.kind == TokenType.IDENTIFIER);
    assert(token.value.get!string == "teste");
    assert(token.loc.line == 1);
    assert(token.loc.file == "test.d");

    auto tokenVar = Token(TokenType.VAR, Variant("var"), loc);
    assert(tokenVar.kind == TokenType.VAR);

    writeln("✓ Testes de Token passaram!");
}

unittest
{
    writeln("Testando isTypeToken...");

    auto loc = Loc("test.d", 1, 1, 5, ".");

    auto intToken = Token(TokenType.IDENTIFIER, Variant("int"), loc);
    assert(isTypeToken(intToken) == true);

    auto floatToken = Token(TokenType.IDENTIFIER, Variant("float"), loc);
    assert(isTypeToken(floatToken) == true);

    auto stringToken = Token(TokenType.IDENTIFIER, Variant("string"), loc);
    assert(isTypeToken(stringToken) == true);

    auto boolToken = Token(TokenType.IDENTIFIER, Variant("bool"), loc);
    assert(isTypeToken(boolToken) == true);

    auto voidToken = Token(TokenType.IDENTIFIER, Variant("void"), loc);
    assert(isTypeToken(voidToken) == true);

    auto vazioToken = Token(TokenType.IDENTIFIER, Variant("vazio"), loc);
    assert(isTypeToken(vazioToken) == true);

    auto invalidToken = Token(TokenType.IDENTIFIER, Variant("qualquercoisa"), loc);
    assert(isTypeToken(invalidToken) == false);

    auto nonIdToken = Token(TokenType.PLUS, Variant("+"), loc);
    assert(isTypeToken(nonIdToken) == false);

    writeln("✓ Testes de isTypeToken passaram!");
}

unittest
{
    writeln("Testando isComplexTypeToken...");

    auto loc = Loc("test.d", 1, 1, 5, ".");

    auto asteriskToken = Token(TokenType.ASTERISK, Variant("*"), loc);
    assert(isComplexTypeToken(asteriskToken) == true);

    auto lbracketToken = Token(TokenType.LBRACKET, Variant("["), loc);
    assert(isComplexTypeToken(lbracketToken) == true);

    auto rbracketToken = Token(TokenType.RBRACKET, Variant("]"), loc);
    assert(isComplexTypeToken(rbracketToken) == true);

    auto plusToken = Token(TokenType.PLUS, Variant("+"), loc);
    assert(isComplexTypeToken(plusToken) == false);

    auto identifierToken = Token(TokenType.IDENTIFIER, Variant("teste"), loc);
    assert(isComplexTypeToken(identifierToken) == false);

    writeln("✓ Testes de isComplexTypeToken passaram!");
}

unittest
{
    writeln("Testando keywords...");

    assert("var" in keywords);
    assert("se" in keywords);
    assert("enquanto" in keywords);
    assert("para" in keywords);
    assert("funcao" in keywords);
    assert("função" in keywords);
    assert("classe" in keywords);
    assert("verdadeiro" in keywords);
    assert("falso" in keywords);

    assert(keywords["var"] == TokenType.VAR);
    assert(keywords["se"] == TokenType.SE);
    assert(keywords["enquanto"] == TokenType.ENQUANTO);
    assert(keywords["para"] == TokenType.PARA);
    assert(keywords["funcao"] == TokenType.FUNCAO);
    assert(keywords["função"] == TokenType.FUNCAO);
    assert(keywords["classe"] == TokenType.CLASSE);
    assert(keywords["verdadeiro"] == TokenType.TRUE);
    assert(keywords["falso"] == TokenType.FALSE);

    writeln("✓ Testes de keywords passaram!");
}
