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
            case LParen:
                TypeExpr[] elements;
                do
                {
                    elements ~= parse();
                }
                while (p.match(TokenKind.Comma));
                p.consume(TokenKind.RParen, "Esperado ')' após tipos da tupla.");
                return new TypeExprTuple(elements, tk.pos);
            case Null:
                return new TypeExprNamed("nulo", tk.pos);
            case Fn:
                return new TypeExprNamed("funcao", tk.pos);
            case Identifier:
                return new TypeExprNamed(tk.value.s, tk.pos);

            default:
                p.err.error(tk.pos, "Tipo inválido.");
                return TypeExpr.init;
        }
    }

    TypeExpr parse()
    {
        TypeExpr type = parsePrimary();
        while (p.match(TokenKind.LBracket))
        {
            type = new TypeExprArray(type, type.pos);
            p.consume(TokenKind.RBracket, "Esperado ']' após o tipo.");
        }
        return type;
    }
}
