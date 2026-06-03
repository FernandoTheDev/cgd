module frontend.parser.parse_type;

import std.exception;

import frontend;
import frontend.parser;
import frontend.lexer;

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
        switch (tk.kind)
        {
            case TokenKind.Identifier:
                return new TypeExprNamed(tk.value.s, tk.pos);
            default:
                enforce(false, "Tipo invalido.");
                return null;
        }
    }

    TypeExpr parse()
    {
        TypeExpr primary = parsePrimary();
        return primary;
    }
}
