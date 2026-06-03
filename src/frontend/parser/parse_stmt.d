module frontend.parser.parse_stmt;

import frontend;
import frontend.lexer;
import frontend.parser;

class ParseStmt
{
private:
    Parser p;

public:
    this(Parser p)
    {
        this.p = p;
    }

    Node parseIfStmt(Position pos)
    {
        IfStmt _else = null;
        Node[] body;
        Node expr = p.parseExpr.parse();
        if (p.check(TokenKind.LBrace))
        {
            while (!p.check(TokenKind.RBrace))
                body ~= p.parseIntern();
            p.consume(TokenKind.RBrace, "Esperado '}' após o 'se'.");
        }
        else
            body ~= p.parseIntern();

        return new IfStmt(expr, body, _else, pos);
    }

    Node parseReturnStmt(Position pos)
    {
        return new ReturnStmt(p.parseExpr.parse(), pos);
    }

    Node parse()
    {
        Token tk = p.advance();
        switch (tk.kind)
        {
        case TokenKind.If:
            return parseIfStmt(tk.pos);

        case TokenKind.Return:
            return parseReturnStmt(tk.pos);

        default:
            return null;
        }
    }
}
