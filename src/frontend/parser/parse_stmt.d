module frontend.parser.parse_stmt;

import frontend.parser;
import frontend.lexer;
import frontend;

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
        Node expr = isElse ? null : p.parseExpr.parse();

        // cobre casos de else if
        if (p.match(TokenKind.If))
            expr = p.parseExpr.parse();

        Node[] body = p.parseBody(true);

        if (!p.isAtEnd() && p.check(TokenKind.Else))
            _else = cast(IfStmt) parseIfStmt(p.advance().pos, true);

        return new IfStmt(expr, body, _else, pos);
    }

    Node parseReturnStmt(Position pos)
    {
        return new ReturnStmt(p.parseExpr.parse(), pos);
    }

    Node parseWhileStmt(Position pos)
    {
        Node expr = p.parseExpr.parse();
        Node[] body = p.parseBody(true);
        return new WhileStmt(expr, body, p.getPos(pos, expr.pos));
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

            case TokenKind.While:
                return parseWhileStmt(tk.pos);

            default:
                return new Identifier("null", tk.pos);
        }
    }
}
