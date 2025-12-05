module frontend.parser.parse_stmt;
import frontend;

mixin template ParseStmt()
{
    Node parseStatement()
    {
        switch (this.peek().kind)
        {
        case TokenKind.Retorna:
            return parseReturn();
        case TokenKind.Se:
            return parseIfStmt();
        default:
            return null;
        }
    }

    IfStmt parseIfStmt()
    {
        Loc loc = this.advance().loc;
        Node condition = this.parseExpression();
        Node[] body = this.parseBody(true);
        Node else_ = null;

        if (this.peek().kind == TokenKind.Senao)
        {
            Loc elseLoc = this.advance().loc;

            if (this.peek().kind == TokenKind.Se)
            {
                Node ifStmt = this.parseIfStmt();
                else_ = ifStmt;
            }
            else
            {
                Node[] elseBody = this.parseBody(true);
                Node elseStmt = new IfStmt(null, new BlockStmt(elseBody, elseLoc), null, elseLoc);
                else_ = elseStmt;
            }
        }

        return new IfStmt(condition, new BlockStmt(body, loc), else_, loc);

    }

    ReturnStmt parseReturn()
    {
        Loc loc = this.advance().loc;
        Node value = null;
        if (!this.match([TokenKind.SemiColon]))
            value = this.parseExpression();
        return new ReturnStmt(value, loc);
    }

    Node[] parseBody(bool uniqueStmt = false)
    {
        Node[] body_;
        if (!this.check(TokenKind.LBrace) && !uniqueStmt)
        {
            reportError("Esperava-se '{' para iniciar o corpo.", this.peek().loc);
            return body_;
        }
        if (this.check(TokenKind.LBrace))
        {
            this.consume(TokenKind.LBrace, "Era esperado '{' para iniciar o corpo.");
            while (!this.check(TokenKind.RBrace) && !this.isAtEnd())
                body_ ~= this.parse();
            this.consume(TokenKind.RBrace, "Era esperado'}' após o corpo.");
        }
        else
            body_ ~= this.parse();

        return body_;
    }
}
