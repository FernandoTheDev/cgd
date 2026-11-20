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
                if (tk.value.s == "Promessa")
                {
                    p.consume(TokenKind.LThan, "Promessa exige um tipo de resultado: Promessa<T>.");
                    TypeExpr result = parse();
                    p.consumeTypeClose();
                    return new TypeExprPromise(result, tk.pos);
                }
                if (tk.value.s == "Tarefa")
                {
                    p.consume(TokenKind.LThan, "Tarefa exige um tipo de resultado: Tarefa<T>.");
                    TypeExpr result = parse();
                    p.consumeTypeClose();
                    return new TypeExprTask(result, tk.pos);
                }
                return new TypeExprNamed(tk.value.s, tk.pos);

            default:
                p.err.error(tk.pos, "Tipo inválido.");
                return TypeExpr.init;
        }
    }

    TypeExpr parse()
    {
        p.enterSyntax();
        scope (exit)
            p.leaveSyntax();
        TypeExpr type = parsePrimary();
        while (p.match(TokenKind.LBracket))
        {
            type = new TypeExprArray(type, type.pos);
            p.consume(TokenKind.RBracket, "Esperado ']' após o tipo.");
        }
        return type;
    }
}
