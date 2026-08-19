module frontend.parser.parse_type;

import std.exception;

import frontend.parser;
import frontend.lexer;
import frontend;

class ParseType
{
private:
    Parser p;
    
public:
    this(Parser p)
    {
        this.p = p;
    }

    TypeExpr parsePrimary()
    {
        Token tk = p.advance();
        switch (tk.kind) with (TokenKind)
        {
            case Identifier:
                return new TypeExprNamed(tk.value.s, tk.pos);

            default:
                p.err.error(tk.pos, "Tipo inválido.");
                return TypeExpr.init;
        }
    }

    TypeExpr parse() => parsePrimary();
}
