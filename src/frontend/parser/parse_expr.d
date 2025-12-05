module frontend.parser.parse_expr;
import frontend;

mixin template ParseExpr()
{
    Node parseExpression(Precedence precedence = Precedence.LOWEST)
    {
        Node left = this.parsePrefix();

        if (left is null)
            return null;

        while (!this.isAtEnd() && precedence < this.peekPrecedence())
        {
            ulong oldPos = this.pos;
            this.infix(left);
            if (this.pos == oldPos)
                break;
        }

        return left;
    }

    Node parsePrefix()
    {
        Token token = this.advance();

        switch (token.kind)
        {
        case TokenKind.I32:
            return new IntLit(to!int(token.value.get!string), token.loc);

        case TokenKind.I64:
            return new LongLit(to!long(token.value.get!string), token.loc);

        case TokenKind.F32:
            return new FloatLit(to!float(token.value.get!string), token.loc);

        case TokenKind.F64:
            return new DoubleLit(to!double(token.value.get!string), token.loc);

        case TokenKind.String:
            return new StringLit(token.value.get!string, token.loc);

        case TokenKind.Verdadeiro:
            return new BoolLit(true, token.loc);

        case TokenKind.Falso:
            return new BoolLit(false, token.loc);

        case TokenKind.Nulo:
            return new NullLit(token.loc);

        case TokenKind.Identifier:
            return this.parseIdentifierExpr(token);

        case TokenKind.LParen:
            return this.parseGroupedExpr();

        case TokenKind.LBracket:
            return this.parseArrayLiteral();

        case TokenKind.Bang:
        case TokenKind.Minus:
        case TokenKind.Plus:
        case TokenKind.Star:
        case TokenKind.BitAnd:
            return this.parseUnaryExpr(token);

        case TokenKind.PlusPlus:
        case TokenKind.MinusMinus:
            return this.parsePrefixIncDec(token);

        case TokenKind.Funcao:
            return this.parseFuncExpr();

        default:
            reportError("Token desconhecido em expressão: " ~ to!string(token.value), token.loc);
            return null;
        }
    }

    FuncExpr parseFuncExpr()
    {
        Loc loc = this.peek().loc;
        FuncArgument[] arguments;
        TypeExpr[] params;
        TypeExpr funcType = new NamedTypeExpr(BaseType.Void, loc);

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
        funcType = new FunctionTypeExpr(params, funcType, loc);
        return new FuncExpr(arguments, body, funcType, loc);
    }

    TernaryExpr parseTernary(Node left)
    {
        this.advance(); // pula o ?
        Node trueExpr = null;
        Node falseExpr = null;
        // elvis?
        // verdadeiro ?: "tome"
        if (this.match([TokenKind.Colon]))
            falseExpr = this.parseExpression();
        else
        {
            // verdadeiro ? trueExpr : falseExpr
            trueExpr = this.parseExpression();
            this.consume(TokenKind.Colon, "Esperado ':' após o ternario verdadeiro.");
            falseExpr = this.parseExpression();
        }
        return new TernaryExpr(left, trueExpr, falseExpr, this.getLoc(left.loc, falseExpr.loc));
    }

    BinaryExpr parseBinaryExpr(Node left)
    {
        Token op = this.advance();
        Node right = this.parseExpression(this.getPrecedence(op.kind));

        if (right is null)
        {
            reportError("Esperado expressão após operador '" ~ op.value.get!string ~ "'", op.loc);
            return null;
        }

        return new BinaryExpr(left, right, op.value.get!string,
            this.getLoc(left.loc, right.loc));
    }

    AssignDecl parseAssignDecl(Node left)
    {
        // Valida que o lado esquerdo pode receber atribuição
        if (!this.isValidAssignTarget(left))
        {
            reportError("Lado esquerdo inválido para atribuição", left.loc);
            return null;
        }

        Token op = this.advance();
        Node right = this.parseExpression(Precedence.ASSIGN);

        if (right is null)
        {
            reportError("Esperado expressão após '" ~ op.value.get!string ~ "'", op.loc);
            return null;
        }

        return new AssignDecl(left, right, op.value.get!string,
            this.getLoc(left.loc, right.loc));
    }

    UnaryExpr parseUnaryExpr(Token op)
    {
        Loc start = op.loc;
        Node operand = this.parseExpression(Precedence.HIGHEST);

        if (operand is null)
        {
            reportError("Esperado expressão após operador '" ~ op.value.get!string ~ "'", op.loc);
            return null;
        }

        TypeExpr type = operand.type;
        string ope = op.value.get!string;
        if (ope == "&")
            type = new PointerTypeExpr(type, type.loc);

        return new UnaryExpr(operand, type, ope, this.getLoc(start, operand.loc));
    }

    Identifier parseIdentifierExpr(Token name)
    {
        return new Identifier(name.value.get!string, name.loc);
    }

    Node parseGroupedExpr()
    {
        Loc start = this.previous().loc;
        Node expr = this.parseExpression(Precedence.LOWEST);

        if (expr is null)
        {
            reportError("Esperado expressão dentro dos parênteses", start);
            return null;
        }

        this.consume(TokenKind.RParen, "Esperado ')' após expressão");
        return expr;
    }

    ArrayLit parseArrayLiteral()
    {
        Loc start = this.previous().loc;
        Node[] elements;

        if (!this.check(TokenKind.RBracket))
        {
            do
            {
                Node elem = this.parseExpression(Precedence.LOWEST);
                if (elem is null)
                {
                    reportError("Expressão inválida em literal de array", this.peek().loc);
                    // Tenta recuperar pulando até vírgula ou colchete
                    while (!this.isAtEnd() && !this.check(TokenKind.Comma) && !this.check(
                            TokenKind.RBracket))
                        this.advance();
                    if (this.check(TokenKind.Comma))
                        continue;
                    break;
                }
                elements ~= elem;
            }
            while (this.match([TokenKind.Comma]));
        }

        Loc end = this.consume(TokenKind.RBracket, "Esperado ']' após elementos do array").loc;
        return new ArrayLit(elements, this.getLoc(start, end));
    }

    CallExpr parseCallExpr(Node callee)
    {
        Loc start = this.advance().loc; // consome '('
        Node[] args;

        // Extrai o nome da função se for um Identifier
        string funcName = "";
        if (auto id = cast(Identifier) callee)
            funcName = id.value.get!string;

        if (!this.check(TokenKind.RParen))
        {
            do
            {
                Node arg = this.parseExpression(Precedence.LOWEST);
                if (arg is null)
                {
                    reportError("Argumento inválido em chamada de função", this.peek().loc);
                    // Tenta recuperar
                    while (!this.isAtEnd() && !this.check(TokenKind.Comma) && !this.check(
                            TokenKind.RParen))
                        this.advance();
                    if (this.check(TokenKind.Comma))
                        continue;
                    break;
                }
                args ~= arg;
            }
            while (this.match([TokenKind.Comma]));
        }

        this.consume(TokenKind.RParen, "Esperado ')' após argumentos");
        return new CallExpr(funcName, args, this.getLoc(callee.loc, this.previous().loc));
    }

    IndexExpr parseIndexExpr(Node target)
    {
        this.advance(); // consome '['
        Node index = this.parseExpression(Precedence.LOWEST);

        if (index is null)
        {
            reportError("Esperado expressão de índice", this.previous().loc);
            return null;
        }

        this.consume(TokenKind.RBracket, "Esperado ']' após índice");
        return new IndexExpr(target, index, this.getLoc(target.loc, this.previous().loc));
    }

    MemberExpr parseMemberExpr(Node target)
    {
        this.advance(); // consome '.'
        Token member = this.consume(TokenKind.Identifier, "Esperado nome do membro após '.'");

        if (member.kind != TokenKind.Identifier)
            return null;

        return new MemberExpr(target, member.value.get!string,
            this.getLoc(target.loc, member.loc));
    }

    UnaryExpr parsePrefixIncDec(Token op)
    {
        Loc start = op.loc;
        Node operand = this.parseExpression(Precedence.HIGHEST);

        if (operand is null)
        {
            reportError("Esperado expressão após '" ~ op.value.get!string ~ "'", op.loc);
            return null;
        }

        // Valida que o operando pode ser incrementado/decrementado
        if (!this.isValidIncDecTarget(operand))
        {
            reportError("Operando inválido para " ~ op.value.get!string, operand.loc);
            return null;
        }

        return new UnaryExpr(operand, operand.type, op.value.get!string ~ "_prefix",
            this.getLoc(start, operand.loc));
    }

    UnaryExpr parsePostfixIncDec(Node operand)
    {
        // Valida que o operando pode ser incrementado/decrementado
        if (!this.isValidIncDecTarget(operand))
        {
            reportError("Operando inválido para incremento/decremento", operand.loc);
            return null;
        }

        Token op = this.advance();
        return new UnaryExpr(operand, operand.type, op.value.get!string ~ "_postfix",
            this.getLoc(operand.loc, op.loc));
    }

    // Funções auxiliares de validação
    private bool isValidAssignTarget(Node node)
    {
        // Só identifiers, índices e membros podem receber atribuição
        return cast(Identifier) node !is null
            || cast(IndexExpr) node !is null
            || cast(MemberExpr) node !is null;
    }

    private bool isValidIncDecTarget(Node node)
    {
        // Mesma regra que atribuição
        return this.isValidAssignTarget(node);
    }

    void infix(ref Node left)
    {
        switch (this.peek().kind)
        {
            // Operadores binários aritméticos
        case TokenKind.Plus:
        case TokenKind.Minus:
        case TokenKind.Star:
        case TokenKind.Slash:
        case TokenKind.Modulo:

            // Operadores lógicos
        case TokenKind.And:
        case TokenKind.Or:

            // Operadores bitwise
        case TokenKind.BitAnd:
        case TokenKind.BitOr:
        case TokenKind.BitXor:
        case TokenKind.BitSHL:
        case TokenKind.BitSHR:
        case TokenKind.BitSAR:

            // Operadores de comparação
        case TokenKind.EqualsEquals:
        case TokenKind.NotEquals:
        case TokenKind.GreaterThan:
        case TokenKind.GreaterThanEquals:
        case TokenKind.LessThan:
        case TokenKind.LessThanEquals:
        case TokenKind.TildeEquals:
            left = this.parseBinaryExpr(left);
            return;

            // Operadores de atribuição
        case TokenKind.Equals:
        case TokenKind.PlusEquals:
        case TokenKind.MinusEquals:
        case TokenKind.StarEquals:
        case TokenKind.SlashEquals:
        case TokenKind.ModuloEquals:
        case TokenKind.BitAndEquals:
        case TokenKind.BitOrEquals:
        case TokenKind.BitXorEquals:
        case TokenKind.BitSHLEquals:
        case TokenKind.BitSHREquals:
            left = this.parseAssignDecl(left);
            return;

            // Chamada de função
        case TokenKind.LParen:
            left = this.parseCallExpr(left);
            return;

            // Acesso a índice/subscript
        case TokenKind.LBracket:
            left = this.parseIndexExpr(left);
            return;

            // Acesso a membro
        case TokenKind.Dot:
            left = this.parseMemberExpr(left);
            return;

        case TokenKind.Question:
            left = this.parseTernary(left);
            return;

            // Pós-incremento/decremento
        case TokenKind.PlusPlus:
        case TokenKind.MinusMinus:
            left = this.parsePostfixIncDec(left);
            return;

        default:
            return;
        }
    }
}
