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
        case TokenKind.Tipo:
            return this.parseTypeDecl();
        case TokenKind.Funcao:
            return this.parseFuncDecl();

        default:
            reportError("Declaração não reconhecida", this.peek().loc);
            return null;
        }
    }

    FuncDecl parseFuncDecl()
    {
        this.advance();
        Token id = this.consume(TokenKind.Identifier, "Esperado um identificador para o nome da função.");
        FuncArgument[] arguments;
        TypeExpr[] params;
        TypeExpr funcType = new NamedTypeExpr(BaseType.Void, id.loc);

        this.consume(TokenKind.LParen, "Esperado '(' após o nome da função.");
        while (!this.check(TokenKind.RParen))
        {
            Token argId = this.consume(TokenKind.Identifier, "Esperado um identificador para o nome do argumento.");
            TypeExpr type = new NamedTypeExpr(BaseType.Any, argId.loc);
            if (this.match([TokenKind.Colon]))
                type = this.parseType();
            params ~= type;
            Node valueDefault = null;
            if (this.match([TokenKind.Equals]))
                valueDefault = this.parseExpression();
            arguments ~= FuncArgument(argId.value.get!string, type, Type.init, valueDefault,
                argId.loc);
            this.match([TokenKind.Comma]);
        }
        this.consume(TokenKind.RParen, "Esperado ')' após os argumentos da função.");

        if (this.match([TokenKind.Colon]))
            funcType = this.parseType();
        Node[] body = parseBody();
        return new FuncDecl(id.value.get!string, arguments, body, new FunctionTypeExpr(params, funcType, id
                .loc), id
                .loc);
    }

    TypeDecl parseTypeDecl()
    {
        this.advance();
        Token id = this.consume(TokenKind.Identifier, "Esperado um identificador para o nome do apelido.");
        this.consume(TokenKind.Equals, "Esperado '=' após a declaração do apelido.");
        TypeExpr type = this.parseType();
        return new TypeDecl(id.value.get!string, type, id.loc);
    }

    VarDecl parseVarDecl()
    {
        bool isConst = this.advance().kind == TokenKind.Const;
        Token id = this.consume(TokenKind.Identifier, "Esperado um identificador para o nome da variavel.");
        TypeExpr type = new NamedTypeExpr(BaseType.Any, Loc.init);
        Node value = null;

        if (this.match([TokenKind.Colon]))
            type = this.parseType();

        if (!this.check(TokenKind.SemiColon))
        {
            this.consume(TokenKind.Equals, "Esperado '=' após a declaração da variavel.");
            value = this.parseExpression();
        }
        else
            this.advance();

        return new VarDecl(id.value.get!string, type, value, isConst, id
                .loc);
    }
}
