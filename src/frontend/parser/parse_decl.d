module frontend.parser.parse_decl;
import frontend;

mixin template ParseDecl()
{
    Node parseDeclaration()
    {
        switch (this.peek().kind)
        {
        case TokenKind.Var:
        case TokenKind.Const:
            return this.parseVarDecl();

        default:
            reportError("Declaração não reconhecida", this.peek().loc);
            return null;
        }
    }

    VarDecl parseVarDecl()
    {
        bool isConst = this.advance().kind == TokenKind.Const;
        Token id = this.consume(TokenKind.Identifier, "Esperado um identificador para o nome da variavel.");
        TypeExpr type;
        Node value = null;

        if (this.match([TokenKind.Colon]))
            type = this.parseType();

        if (!this.check(TokenKind.SemiColon))
        {
            this.consume(TokenKind.Equals, "Esperado '=' após a declaração da variavel.");
            value = this.parseExpression();
            if (type is null)
                type = value.type;
        }
        else
        {
            if (type is null)
                type = new NamedTypeExpr(BaseType.Any, Loc.init);
            this.advance();
        }

        return new VarDecl(id.value.get!string, type, value, isConst, id.loc);
    }
}
