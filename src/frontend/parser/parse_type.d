module frontend.parser.parse_type;
import frontend;

mixin template ParseType()
{
    TypeExpr parseType()
    {
        Loc start = this.peek().loc;
        TypeExpr type = this.parsePrimaryType();

        if (this.check(TokenKind.BitOr))
        {
            TypeExpr[] types = [type];
            while (this.match([TokenKind.BitOr]))
                types ~= this.parsePrimaryType();
            return new UnionTypeExpr(types, this.getLoc(start, this.previous().loc));
        }

        if (this.check(TokenKind.LBracket))
            return this.parseArrayType(type);

        return type;
    }

    TypeExpr parsePrimaryType()
    {
        Token token = this.peek();

        switch (token.kind)
        {
        case TokenKind.Identifier:
            Token name = this.advance();
            return new NamedTypeExpr(name.value.get!string, name.loc);

        case TokenKind.LBracket:
            return this.parseArrayType();

        case TokenKind.Star:
            return this.parsePointerType();

            // Função: (int, string): bool
        case TokenKind.LParen:
            return this.parseFunctionType();

        default:
            reportError("Esperado tipo, encontrado: " ~ to!string(token.value),
                token.loc);
            throw new Exception("Tipo inválido");
        }
    }

    // // []int
    ArrayTypeExpr parseArrayType()
    {
        Loc start = this.advance().loc; // consome '['

        // // Tamanho opcional: [10]int
        // Node size = null;
        // if (!this.check(TokenKind.RBracket))
        // {
        //     if (this.check(TokenKind.I32) || this.check(TokenKind.I64))
        //     {
        //         Token sizeToken = this.advance();
        //         size = new IntLit(sizeToken.value.get!int, sizeToken.loc);
        //     }
        // }

        this.consume(TokenKind.RBracket, "Esperado ']' em tipo array");
        TypeExpr elementType = this.parseType();
        return new ArrayTypeExpr(elementType,
            this.getLoc(start, elementType.loc));
    }

    // // int[]
    ArrayTypeExpr parseArrayType(TypeExpr elementType)
    {
        Loc start = this.advance().loc; // consome '['
        this.consume(TokenKind.RBracket, "Esperado ']' em tipo array");
        return new ArrayTypeExpr(elementType,
            this.getLoc(start, elementType.loc));
    }

    // *int
    PointerTypeExpr parsePointerType()
    {
        Loc start = this.advance().loc; // consome '*'
        TypeExpr pointeeType = this.parseType();

        return new PointerTypeExpr(pointeeType,
            this.getLoc(start, pointeeType.loc));
    }

    // // Tipo de função: (int, string): bool
    FunctionTypeExpr parseFunctionType()
    {
        Loc start = this.advance().loc; // consome '('

        TypeExpr[] paramTypes;
        if (!this.check(TokenKind.RParen))
        {
            do
                paramTypes ~= this.parseType();
            while (this.match([TokenKind.Comma]));
        }

        this.consume(TokenKind.RParen, "Esperado ')' em tipo de função");

        TypeExpr returnType = null;
        if (this.match([TokenKind.Colon]))
            returnType = this.parseType();

        Loc loc = returnType ? this.getLoc(start, returnType.loc) : this.getLoc(start, this.previous()
                .loc);

        return new FunctionTypeExpr(paramTypes, returnType, loc);
    }

    // // Tipo opcional: int?
    // OptionalType parseOptionalType(TypeExpr baseType)
    // {
    //     this.advance(); // consome '?'
    //     return new OptionalType(baseType,
    //         this.getLoc(baseType.loc, this.previous().loc));
    // }
}
