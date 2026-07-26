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

    Node parseIfStmt(Position pos, bool isElse = false)
    {
        IfStmt _else = null;
        Node[] body;
        Node expr = isElse ? null : p.parseExpr.parse();

        // cobre casos de else if
        if (p.match(TokenKind.If))
            expr = p.parseExpr.parse();

        if (p.match(TokenKind.LBrace))
        {
            while (!p.check(TokenKind.RBrace))
                body ~= p.parseIntern();
            p.consume(TokenKind.RBrace, "Esperado '}' após o 'se'.");
        }
        else
            body ~= p.parseIntern();

        if (!p.isAtEnd() && p.check(TokenKind.Else))
            _else = cast(IfStmt) parseIfStmt(p.advance().pos, true);

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
