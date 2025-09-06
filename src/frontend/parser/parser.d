module frontend.parser.parser;

import std.algorithm;
import std.typecons;
import std.format;
import std.stdio;
import std.conv;
import std.variant;
import frontend.lexer.token;
import frontend.values;
import frontend.parser.ftype_info;
import frontend.parser.ast;
import frontend.parser.parse_type;
import error;

enum Precedence
{
    LOWEST = 1,
    ASSIGN = 2,
    TERNARY = 3,
    OR = 4,
    AND = 5,
    BIT_OR = 6,
    BIT_XOR = 7,
    BIT_AND = 8,
    EQUALS = 9,
    COMPARISON = 10,
    BIT_SHIFT = 11,
    SUM = 12,
    PRODUCT = 13,
    EXPONENT = 14,
    PREFIX = 15,
    POSTFIX = 16,
    CALL = 17,
}

class Parser
{
private:
    Token[] tokens;
    ulong pos = 0;
    DiagnosticError error;

    Stmt parsePrefix()
    {
        Token token = this.advance();

        switch (token.kind)
        {
            // Literals
        case TokenType.I8:
            return new IntLiteral(token.value.get!long, createTypeInfo(TypesNative.I8), token.loc);
        case TokenType.I16:
            return new IntLiteral(token.value.get!long, createTypeInfo(TypesNative.I16), token.loc);
        case TokenType.I32:
            return new IntLiteral(token.value.get!long, createTypeInfo(TypesNative.I32), token.loc);
        case TokenType.I64:
            return new IntLiteral(token.value.get!long, createTypeInfo(TypesNative.I64), token.loc);
        case TokenType.FLOAT:
            return new FloatLiteral(to!double(token.value.get!string), createTypeInfo(
                    TypesNative.F32), token.loc);
        case TokenType.DOUBLE:
            return new FloatLiteral(to!double(token.value.get!string), createTypeInfo(
                    TypesNative.F64), token.loc);
        case TokenType.I8P:
            auto literal = new StringLiteral(token.value.get!string, token.loc);
            if (this.peek()
                .kind == TokenType.LBRACKET)
                return this.parseIndexExpr(literal);
            return literal;
        case TokenType.TRUE:
            return new BoolLiteral(true, token.loc);
        case TokenType.FALSE:
            return new BoolLiteral(false, token.loc);
        case TokenType.NULL:
            return new NullLiteral(token.loc);

        case TokenType.LPAREN:
            return this.parseGroupedExpression();

        case TokenType.MINUS:
            Stmt operand = this.parseExpression(Precedence.LOWEST);
            return new UnaryExpr("-", operand, this.makeLoc(token.loc, operand.loc));

        case TokenType.PLUS:
            Stmt operand = this.parseExpression(Precedence.LOWEST);
            return new UnaryExpr("+", operand, this.makeLoc(token.loc, operand.loc));

        case TokenType.BANG:
            Stmt operand = this.parseExpression(Precedence.LOWEST);
            return new UnaryExpr("!", operand, this.makeLoc(token.loc, operand.loc));

        case TokenType.ASTERISK:
        case TokenType.EXPONENTIATION:
            int count = 1;

            if (token.kind == TokenType.EXPONENTIATION)
            {
                count++;
            }

            while (
                this.peek().kind == TokenType.ASTERISK ||
                this.peek()
                .kind == TokenType.EXPONENTIATION
                )
            {
                count++;
                if (this.peek().kind == TokenType.EXPONENTIATION)
                    count++;
                this.advance();
            }

            Stmt operand = this.parseExpression(Precedence.PREFIX);
            for (int i = 0; i < count; i++)
            {
                operand = new UnaryExpr(
                    "*",
                    operand,
                    this.makeLoc(token.loc, operand.loc),
                );
            }

            return operand;

        case TokenType.BIT_AND:
            Stmt operand = this.parseExpression(Precedence.PREFIX);
            return new UnaryExpr("&", operand, this.makeLoc(token.loc, operand.loc));

            // Keywords
        case TokenType.VAR:
            return parseVarDeclaration();
        case TokenType.RETORNA:
            return this.parseReturnStatement();
        case TokenType.FUNCAO:
            return this.parseFnStatement();
        case TokenType.SE:
            return this.parseIfStatement();
        case TokenType.PARA:
            return this.parseForStatement();
        case TokenType.ENQUANTO:
            return this.parseWhileStatement();
        case TokenType.FAZER:
            return this.parseDoWhileStatement();
        case TokenType.ESCOLHA:
            return this.parseSwitchStatement();
        case TokenType.QUEBRAR:
            return this.parseBreakStatement();
        case TokenType.IMPORTAR:
            return this.parseImportStatement();
        case TokenType.CLASSE:
            return this.parseClassDeclaration();
        case TokenType.NOVO:
            return this.parseNewExpression();
        case TokenType.ISTO:
            if (this.peek()
                .kind == TokenType.DOT)
                return this.parseMemberCallExpression(new Identifier(token.value.get!string, token
                        .loc));
            return new ThisExpr(token.loc);

            // Others
        case TokenType.IDENTIFIER:
            if (this.peek()
                .kind == TokenType.LPAREN)
                return this.parseCallExpression();
            if (this.peek().kind == TokenType.EQUALS)
                return this.parseAssignmentDeclaration();
            auto identifier = new Identifier(token.value.get!string, token.loc);
            if (this.peek().kind == TokenType.LBRACKET)
                return this.parseIndexExpr(identifier);
            if (this.peek().kind == TokenType.DOT)
                return this.parseMemberCallExpression(identifier);
            return identifier;

        case TokenType.BIT_NOT:
            Stmt operand = this.parseExpression(Precedence.PREFIX);
            return new UnaryExpr("~", operand, this.makeLoc(token.loc, operand.loc));
        case TokenType.INCREMENT:
            if (this.peek().kind != TokenType.IDENTIFIER)
            {
                error.addError(Diagnostic("Operador '++' prefix requer um identificador válido.", token
                        .loc));
                throw new Exception("Operador '++' prefix requer um identificador válido.");
            }
            Stmt operand = this.parseExpression(Precedence.POSTFIX);
            return new UnaryExpr("++", operand, this.makeLoc(token.loc, operand.loc), false);

        case TokenType.DECREMENT:
            if (this.peek().kind != TokenType.IDENTIFIER)
            {
                error.addError(Diagnostic("Operador '--' prefix requer um identificador válido.", token
                        .loc));
                throw new Exception("Operador '--' prefix requer um identificador válido.");
            }
            Stmt operand = this.parseExpression(Precedence.POSTFIX);
            return new UnaryExpr("--", operand, this.makeLoc(token.loc, operand.loc), false);

        case TokenType.LBRACKET:
            return this.parseArrayLiteral();

        default:
            error.addError(Diagnostic("Nenhuma função de análise de prefixo para isso.", token
                    .loc));
            throw new Exception("No prefix parse function for " ~ to!string(token.kind));
        }
    }

    Stmt parseIndexExpr(Stmt left)
    {
        Loc start = this.consume(TokenType.LBRACKET, "...").loc;
        Stmt index = this.parseExpression(Precedence.LOWEST);
        Loc end = this.consume(TokenType.RBRACKET, "Esperava-se ']' após o acesso ao indice.").loc;
        Stmt indexExpr = new IndexExpr(left, index, this.makeLoc(start, end));
        if (this.peek().kind == TokenType.LBRACKET) // encadeamento
            return this.parseIndexExpr(indexExpr);
        if (this.peek().kind == TokenType.EQUALS) // IndexExprAssignment
        {
            this.match([TokenType.EQUALS]); // consome
            Stmt value = this.parseExpression(Precedence.LOWEST);
            return new IndexExprAssignment(left, index, value, this.makeLoc(start, value.loc));
        }
        return indexExpr;
    }

    Stmt parseArrayLiteral()
    {
        Loc start = this.previous().loc;
        Stmt[] elements;
        Tuple!(bool, FTypeInfo) type = Tuple!(bool, FTypeInfo)(false, createTypeInfo(
                TypesNative.NULO));
        while (this.peek().kind != TokenType.RBRACKET && !this.isAtEnd())
        {
            // primeiro argumento
            elements ~= this.parseExpression(Precedence.LOWEST);
            if (!type[0])
                type = tuple(true, elements[0].type);
            else if (elements[$ - 1].type.baseType != type[1].baseType)
            {
                // Erro
                this.error.addError(Diagnostic(format("O vetor foi declarado com tipo '%s'.", cast(
                        string) type[1]
                        .baseType), start));
                throw new Exception(format("O vetor foi declarado com tipo '%s'.", cast(string) type[1]
                        .baseType));
            }
            this.match([TokenType.COMMA]);
        }
        Loc end = this.consume(TokenType.RBRACKET, "Esperado ']' após a declaração do vetor.")
            .loc;
        type[1].isArray = true;
        return new ArrayLiteral(elements, type[1], this.makeLoc(start, end));
    }

    Stmt parseNewExpression()
    {
        Loc start = this.previous().loc;
        Token classNameToken = this.consume(TokenType.IDENTIFIER, "Esperado nome da classe após 'novo'.");
        Identifier className = new Identifier(classNameToken.value.get!string, classNameToken.loc);

        this.consume(TokenType.LPAREN, "Esperado '(' após nome da classe.");
        Stmt[] args = [];

        if (!this.check(TokenType.RPAREN))
        {
            do
            {
                args ~= this.parseExpression(Precedence.LOWEST);
            }
            while (this.match([TokenType.COMMA]));
        }

        Loc end = this.consume(TokenType.RPAREN, "Esperado ')' após argumentos do construtor.")
            .loc;

        return new NewExpr(className, args, this.makeLoc(start, end));
    }

    Stmt parseClassDeclaration()
    {
        Loc start = this.previous().loc;
        Token name = this.consume(TokenType.IDENTIFIER, "Esperado um identificador para o nome da classe.");
        this.consume(TokenType.LBRACE, "Esperado '{' após o nome da classe.");

        auto classBlockResult = this.parseClassBlock();
        ClassProperty[] properties = classBlockResult[1];
        ClassMethodDeclaration[] methods = classBlockResult[0];

        // Encontrar construtor e destrutor
        ConstructorDeclaration constructor = null;
        DestructorDeclaration destructor = null;

        foreach (method; methods)
        {
            if (method.kind == NodeType.ConstructorDeclaration)
            {
                constructor = cast(ConstructorDeclaration) method;
            }
            else if (method.kind == NodeType.DestructorDeclaration)
            {
                destructor = cast(DestructorDeclaration) method;
            }
        }

        this.consume(TokenType.RBRACE, "Esperado '}' após a classe.");

        ClassDeclaration classDecl = new ClassDeclaration(properties, methods, this.makeLoc(start, this.previous()
                .loc));
        classDecl.id = new Identifier(name.value.get!string, name.loc);
        classDecl.construct = constructor;
        classDecl.destruct = destructor;

        return classDecl;
    }

    // Implementação completa de parseClassBlock:
    Tuple!(ClassMethodDeclaration[], ClassProperty[]) parseClassBlock()
    {
        ClassMethodDeclaration[] methods;
        ClassProperty[] properties;

        while (this.peek().kind != TokenType.RBRACE && !this.isAtEnd())
        {
            ClassVisibility visibility = ClassVisibility.PUBLIC; // público por padrão

            // Verificar visibilidade
            if (this.check(TokenType.PUBLICO))
            {
                this.advance();
                visibility = ClassVisibility.PUBLIC;
            }
            else if (this.check(TokenType.PRIVADO))
            {
                this.advance();
                visibility = ClassVisibility.PRIVATE;
            }

            if (this.check(TokenType.CONSTRUTOR))
            {
                ConstructorDeclaration cons = this.parseConstructor(visibility);
                methods ~= new ClassMethodDeclaration(
                    cons.id,
                    cons.args,
                    cons.body,
                    cons.type,
                    cons.visibility,
                    cons.loc
                );
            }
            else if (this.check(TokenType.DESTRUTOR))
            {
                // TODO: corrigir isso
                methods ~= cast(ClassMethodDeclaration) this.parseDestructor(visibility);
            }
            else if (this.check(TokenType.IDENTIFIER))
            {
                // Pode ser propriedade ou método
                ulong savedPos = this.pos;
                Token identifier = this.advance();

                if (this.check(TokenType.COLON))
                {
                    // É uma propriedade
                    this.pos = savedPos; // Volta para o identificador
                    properties ~= this.parseClassProperty(visibility);
                }
                else if (this.check(TokenType.LPAREN))
                {
                    // É um método
                    this.pos = savedPos; // Volta para o identificador
                    methods ~= this.parseClassMethod(visibility);
                }
                else
                {
                    error.addError(Diagnostic(
                            "Esperado ':' para propriedade ou '(' para método após identificador na classe.", this
                            .peek().loc));
                    throw new Exception(
                        "Esperado ':' para propriedade ou '(' para método após identificador na classe.");
                }
            }
            else
            {
                error.addError(Diagnostic(
                        "Esperado identificador, 'construtor', 'destrutor', 'publico' ou 'privado' dentro da classe.",
                        this.peek().loc));
                throw new Exception(
                    "Esperado identificador, 'construtor', 'destrutor', 'publico' ou 'privado' dentro da classe.");
            }
        }

        return tuple(methods, properties);
    }

    // Implementar parseConstructor:
    ConstructorDeclaration parseConstructor(ClassVisibility visibility)
    {
        Loc start = this.advance().loc; // consome 'construtor'
        FunctionArgs args = this.parseFnArguments();

        this.consume(TokenType.LBRACE, "Esperado '{' após argumentos do construtor.");
        Stmt[] body;

        while (!this.check(TokenType.RBRACE) && !this.isAtEnd())
        {
            body ~= this.parseExpression(Precedence.LOWEST);
        }

        Loc end = this.consume(TokenType.RBRACE, "Esperado '}' após corpo do construtor.").loc;

        ConstructorDeclaration constructor = new ConstructorDeclaration(args, body, this.makeLoc(start, end));

        return constructor;
    }

    // Implementar parseDestructor:
    Stmt parseDestructor(ClassVisibility visibility)
    {
        Loc start = this.advance().loc; // consome 'destrutor'
        this.consume(TokenType.LPAREN, "Esperado '(' após 'destrutor'.");
        this.consume(TokenType.RPAREN, "Esperado ')' após '(' do destrutor.");

        this.consume(TokenType.LBRACE, "Esperado '{' após parênteses do destrutor.");
        Stmt[] body;

        while (!this.check(TokenType.RBRACE) && !this.isAtEnd())
        {
            body ~= this.parseExpression(Precedence.LOWEST);
        }

        Loc end = this.consume(TokenType.RBRACE, "Esperado '}' após corpo do destrutor.").loc;

        DestructorDeclaration destructor = new DestructorDeclaration(body, this.makeLoc(start, end));

        return destructor;
    }

    // Implementar parseClassProperty:
    ClassProperty parseClassProperty(ClassVisibility visibility)
    {
        Token nameToken = this.consume(TokenType.IDENTIFIER, "Esperado identificador para nome da propriedade.");
        Identifier name = new Identifier(nameToken.value.get!string, nameToken.loc);

        this.consume(TokenType.COLON, "Esperado ':' após nome da propriedade.");

        // Parse do tipo
        Token[] typeTokens;
        while (this.peek().kind != TokenType.EQUALS &&
            this.peek()
            .kind != TokenType.SEMICOLON &&
            !this.isAtEnd())
        {
            typeTokens ~= this.advance();
        }

        FTypeInfo type = new ParseType(typeTokens).parse();
        Stmt defaultValue = null;

        // Verificar se há valor padrão
        if (this.match([TokenType.EQUALS]))
        {
            defaultValue = this.parseExpression(Precedence.LOWEST);
        }

        this.match([TokenType.SEMICOLON]); // Semicolon opcional

        return ClassProperty(name, type, visibility, defaultValue);
    }

    // Implementar parseClassMethod:
    ClassMethodDeclaration parseClassMethod(ClassVisibility visibility)
    {
        Token nameToken = this.consume(TokenType.IDENTIFIER, "Esperado identificador para nome do método.");
        Identifier name = new Identifier(nameToken.value.get!string, nameToken.loc);

        FunctionArgs args = this.parseFnArguments();
        FTypeInfo returnType = createTypeInfo(TypesNative.NULO);

        if (this.match([TokenType.COLON]))
        {
            Token[] fnTokens;
            while (this.peek().kind != TokenType.LBRACE)
            {
                fnTokens ~= this.advance();
            }
            returnType = new ParseType(fnTokens).parse();
            returnType.className = fnTokens[0].value.get!string;
        }

        this.consume(TokenType.LBRACE, "Esperado '{' antes do corpo do método.");
        Stmt[] body;

        while (!this.check(TokenType.RBRACE) && !this.isAtEnd())
        {
            body ~= this.parseExpression(Precedence.LOWEST);
        }

        Token end = this.consume(TokenType.RBRACE, "Esperado '}' após corpo do método.");

        return new ClassMethodDeclaration(name, args, body, returnType, visibility,
            this.makeLoc(nameToken.loc, end.loc));
    }

    Stmt parseImportStatement()
    {
        // importar "lib"
        // importar { ids, ... } de "lib"
        // importar "lib" como x
        // importar { ids, ... } de "lib" como x
        Loc start = this.previous().loc;
        Identifier[] targets;
        string _alias;
        string from; // lib|file.delegua

        if (this.match([TokenType.LBRACE]))
        {
            while (this.peek().kind != TokenType.RBRACE && !this.isAtEnd())
            {
                Token target = this.consume(TokenType.IDENTIFIER, "Esperado um identificador.");
                targets ~= new Identifier(target.value.get!string, target.loc);
                this.match([TokenType.COMMA]);
            }
            this.consume(TokenType.RBRACE, "Esperado '}' após os alvos da importação.");
        }

        this.match([TokenType.DE]);
        Token _from = this.consume(TokenType.I8P, "Esperado uma string para a importação."); // TODO: melhorar esse cu
        from = _from.value.get!string;

        if (this.match([TokenType.COMO]))
        {
            Token __alias = this.consume(TokenType.IDENTIFIER, "Esperado um identificador para o nome do apelido."); // TODO: melhorar esse cu
            _alias = __alias.value.get!string;
        }

        return new ImportStatement(from, _alias, targets, start);
    }

    Stmt parseSwitchStatement()
    {
        Loc start = this.previous().loc;

        // this.consume(TokenType.LPAREN, "Esperava-se '(' após 'escolha'.");
        Stmt condition = this.parseExpression(Precedence.LOWEST);
        // this.consume(TokenType.RPAREN, "Esperava-se ')' após a condição do 'escolha'.");
        this.consume(TokenType.LBRACE, "Esperava-se '{' após a condição do 'escolha'.");

        CaseStatement[] cases;
        DefaultStatement defaultCase = null;

        while (!this.check(TokenType.RBRACE) && !this.isAtEnd())
        {
            if (this.match([TokenType.CASO]))
            {
                cases ~= this.parseCaseStatement();
            }
            else if (this.match([TokenType.PADRAO]))
            {
                if (defaultCase !is null)
                {
                    error.addError(Diagnostic(
                            "Apenas um caso 'padrão' é permitido por 'escolha'.", start));
                    throw new Exception("Apenas um caso 'padrão' é permitido por 'escolha'.");
                }
                defaultCase = this.parseDefaultStatement();
            }
            else
            {
                error.addError(Diagnostic(
                        "Esperava-se 'caso' ou 'padrão' dentro de 'escolha'.", this.peek().loc));
                throw new Exception("Esperava-se 'caso' ou 'padrão' dentro de 'escolha'.");
            }
        }

        Loc end = this.consume(TokenType.RBRACE, "Esperava-se '}' após o corpo do 'escolha'.").loc;

        return new SwitchStatement(condition, cases, defaultCase, this.makeLoc(start, end));
    }

    CaseStatement parseCaseStatement()
    {
        Loc start = this.previous().loc;

        Stmt value = this.parseExpression(Precedence.LOWEST);
        this.consume(TokenType.COLON, "Esperava-se ':' após o valor do 'caso'.");

        Stmt[] body;
        while (!this.check(TokenType.CASO) && !this.check(TokenType.PADRAO) &&
            !this.check(TokenType.RBRACE) && !this.isAtEnd())
        {
            body ~= this.parseExpression(Precedence.LOWEST);
        }

        return new CaseStatement(value, body, start);
    }

    DefaultStatement parseDefaultStatement()
    {
        Loc start = this.previous().loc;

        this.consume(TokenType.COLON, "Esperava-se ':' após 'padrão'.");

        Stmt[] body;
        while (!this.check(TokenType.CASO) && !this.check(TokenType.PADRAO) &&
            !this.check(TokenType.RBRACE) && !this.isAtEnd())
        {
            body ~= this.parseExpression(Precedence.LOWEST);
        }

        return new DefaultStatement(body, start);
    }

    Stmt parseBreakStatement()
    {
        Loc start = this.previous().loc;
        return new BreakStatement(start);
    }

    Stmt parseMemberCallExpression(Stmt object)
    {
        while (this.check(TokenType.DOT))
        {
            this.advance();

            Token memberToken = this.consume(TokenType.IDENTIFIER,
                "Esperava-se um identificador após '.'.");
            Identifier member = new Identifier(memberToken.value.get!string, memberToken.loc);

            Stmt[] args = [];
            bool isMethodCall = false;

            // Verifica se é uma chamada de método (tem parênteses)
            if (this.check(TokenType.LPAREN))
            {
                this.advance();
                isMethodCall = true;

                if (!this.check(TokenType.RPAREN))
                {
                    do
                    {
                        args ~= this.parseExpression(Precedence.LOWEST);
                    }
                    while (this.match([TokenType.COMMA]));
                }

                this.consume(TokenType.RPAREN, "Esperava-se ')' após os argumentos do método.");
            }

            if (this.peek().kind == TokenType.EQUALS && !isMethodCall)
            {
                this.match([TokenType.EQUALS]);
                Stmt value = this.parseExpression(Precedence.LOWEST);
                return new MemberAssignment(object, member, value, value.loc);
            }

            Loc loc = this.makeLoc(object.loc, this.previous().loc);
            object = new MemberCallExpr(object, member, args, isMethodCall, loc);
        }

        return object;
    }

    Stmt parseAssignmentDeclaration()
    {
        Token id = this.previous();
        this.consume(TokenType.EQUALS, "Esperava-se '=' após o identificador.");
        Stmt expr = this.parseExpression(Precedence.LOWEST);
        return new AssignmentDeclaration(new Identifier(id.value.get!string, id.loc), expr, expr.type, id
                .loc);
    }

    Stmt parseDoWhileStatement()
    {
        Loc start = this.previous().loc;

        this.consume(TokenType.LBRACE, "Esperava-se '{' após 'fazer'.");
        Stmt[] body;

        while (!this.check(TokenType.RBRACE) && !this.isAtEnd())
        {
            body ~= this.parseExpression(Precedence.LOWEST);
        }

        Loc end = this.consume(
            TokenType.RBRACE,
            "Esperava-se '}' após o corpo do 'enquanto'.",
        ).loc;

        this.consume(TokenType.ENQUANTO, "Esperava-se 'enquanto' após o corpo do 'fazer'.");
        Stmt cond = this.parseExpression(Precedence.LOWEST);

        return new DoWhileStatement(cond, body, this.makeLoc(start, end));
    }

    Stmt parseWhileStatement()
    {
        Loc start = this.previous().loc;
        Stmt cond = this.parseExpression(Precedence.LOWEST);
        Stmt[] body;

        if (this.peek().kind != TokenType.LBRACE)
        {
            body ~= this.parseExpression(Precedence.LOWEST);
            return new WhileStatement(cond, body, start);
        }

        this.consume(TokenType.LBRACE, "Esperava-se '{' após a condição do 'enquanto'.");

        while (!this.check(TokenType.RBRACE) && !this.isAtEnd())
        {
            body ~= this.parseExpression(Precedence.LOWEST);
        }

        Loc end = this.consume(
            TokenType.RBRACE,
            "Esperava-se '}' após o corpo do 'enquanto'.",
        ).loc;

        return new WhileStatement(cond, body, this.makeLoc(start, end));
    }

    Stmt parseForStatement()
    {
        Loc start = this.previous().loc;
        Stmt _init = this.parseExpression(Precedence.LOWEST);

        if (_init.kind != NodeType.VariableDeclaration && _init.kind != NodeType
            .AssignmentDeclaration)
        {
            error.addError(Diagnostic(
                    "É esperado uma declaração ou redeclaração de variavel no inicio do 'para'.", _init
                    .loc));
            throw new Exception(
                "É esperado uma declaração ou redeclaração de variavel no inicio do 'para'.");
        }
        this.consume(TokenType.SEMICOLON, "Esperava-se ';' antes da condição do 'para'.");
        Stmt cond = this.parseExpression(Precedence.LOWEST);

        this.consume(TokenType.SEMICOLON, "Esperava-se ';' após a condição do 'para'.");
        Stmt expr = this.parseExpression(Precedence.LOWEST);
        Stmt[] body;

        if (this.peek().kind != TokenType.LBRACE)
        {
            body ~= this.parseExpression(Precedence.LOWEST);
            return new ForStatement(_init, cond, expr, body, start);
        }

        this.consume(TokenType.LBRACE, "Esperava-se '{' após a expressão do 'para'.");

        while (!this.check(TokenType.RBRACE) && !this.isAtEnd())
        {
            body ~= this.parseExpression(Precedence.LOWEST);
        }

        Loc end = this.consume(
            TokenType.RBRACE,
            "Esperava-se '}' após o bloco do 'para'.",
        ).loc;

        return new ForStatement(_init, cond, expr, body, this.makeLoc(start, end));
    }

    Stmt parseElseStatement()
    {
        Token start = this.previous();
        Stmt[] body = [];
        Stmt returnStmt = null;
        Loc end;
        bool unique = false;

        if (this.peek().kind != TokenType.LBRACE)
        {
            body ~= this.parseExpression(Precedence.LOWEST);
            end = body[0].loc;
            unique = true;
        }

        if (!unique)
        {
            this.consume(TokenType.LBRACE, "Esperava-se '{' após o 'senão'.");

            while (!this.check(TokenType.RBRACE) && !this.isAtEnd())
            {
                if (this.peek().kind == TokenType.RETORNA)
                {
                    returnStmt = this.parseExpression(Precedence.LOWEST);
                    body ~= returnStmt;
                    break;
                }
                body ~= this.parseExpression(Precedence.LOWEST);
            }
            end = this.consume(TokenType.RBRACE, "Esperava-se '}' após o corpo da condição.")
                .loc;
        }

        FTypeInfo type = returnStmt is null ? createTypeInfo(TypesNative.NULO) : returnStmt
            .type;
        Variant value = type.baseType == TypesNative.NULO ? Variant("void") : Variant(
            returnStmt.value);

        return new ElseStatement(body, type, value, this.makeLoc(start.loc, end));
    }

    Stmt parseIfStatement(bool miaKhalifa = true)
    {
        Token start = this.previous();
        Stmt condition = this.parseExpression(Precedence.LOWEST);
        Stmt[] body = [];
        Stmt returnStmt = null;
        NullStmt bodySecond = null;
        Loc end;
        bool unique = false;

        if (this.peek().kind != TokenType.LBRACE)
        {
            body ~= this.parseExpression(Precedence.LOWEST);
            end = body[0].loc;
            unique = true;
        }

        if (!unique)
        {
            this.consume(TokenType.LBRACE, "Esperava-se '{' após a condição.");

            while (!this.check(TokenType.RBRACE) && !this.isAtEnd())
            {
                if (this.peek().kind == TokenType.RETORNA)
                {
                    returnStmt = this.parseExpression(Precedence.LOWEST);
                    body ~= returnStmt;
                    break;
                }
                body ~= this.parseExpression(Precedence.LOWEST);
            }
            end = this.consume(TokenType.RBRACE, "Esperava-se '}' após o corpo da condição.")
                .loc;
        }

        if (this.match([TokenType.SENAO]))
        {
            if (this.match([TokenType.SE]))
            {
                bodySecond = this.parseIfStatement(false);
            }
            else
            {
                bodySecond = this.parseElseStatement();
            }
        }

        FTypeInfo type = returnStmt is null ? createTypeInfo(TypesNative.NULO) : returnStmt
            .type;
        Variant value = type.baseType == TypesNative.NULO ? Variant("void") : Variant(
            returnStmt.value);

        return new IfStatement(condition, body, type, value, this.makeLoc(start.loc, end), bodySecond);
    }

    Stmt parseFnStatement()
    {
        Token start = this.previous();
        Token id = this.consume(TokenType.IDENTIFIER, "Esperava-se um identificador para o nome da função.");
        FunctionArgs args = this.parseFnArguments();
        FTypeInfo returnType = createTypeInfo(TypesNative.NULO);

        if (this.match([TokenType.COLON]))
        {
            Token[] fnTokens;
            while (this.peek().kind != TokenType.LBRACE && this.peek().kind != TokenType.BIT_OR)
            {
                // caiu em loop
                if (fnTokens.length > 3)
                {
                    this.error.addError(Diagnostic("Tipo desconhecido.", fnTokens[0].loc));
                    throw new Exception("Tipo desconhecido.");
                }
                fnTokens ~= this.advance();
            }
            returnType = new ParseType(fnTokens).parse();
        }

        Stmt[] body;

        if (this.match([TokenType.BIT_OR]))
        {
            body ~= this.parseExpression(Precedence.LOWEST);
            if (body[0].kind != NodeType.ReturnStatement)
            {
                // ERRRO
                this.error.addError(Diagnostic("Essa sintaxe só está disponivel para retornos unicos.", body[0]
                        .loc));
                throw new Exception("Essa sintaxe só está disponivel para retornos unicos.");
            }
            Loc end = body[0].loc;
            return new FunctionDeclaration(new Identifier(id.value.get!string, id.loc), args, body, returnType, this
                    .makeLoc(
                        start.loc, end));
        }

        this.consume(TokenType.LBRACE, "Expect '{' before function body.");

        while (!this.check(TokenType.RBRACE) && !this.isAtEnd())
        {
            body ~= this.parseExpression(Precedence.LOWEST);
        }

        Token end = this.consume(
            TokenType.RBRACE,
            "Expect '}' after function body.",
        );

        return new FunctionDeclaration(new Identifier(id.value.get!string, id.loc), args, body, returnType, this
                .makeLoc(
                    start.loc, end.loc));
    }

    FunctionArgs parseFnArguments()
    {
        FunctionArgs args;
        this.consume(TokenType.LPAREN, "Esperava-se '(' após o nome da função.");
        while (this.peek().kind != TokenType.RPAREN)
        {
            Token argToken = this.consume(TokenType.IDENTIFIER,
                "Esperava-se um identificador para o nome do argumento.");
            Identifier argId = new Identifier(argToken.value.get!string, argToken.loc);
            FTypeInfo argType;
            NullStmt def = null;

            this.consume(TokenType.COLON, "Esperava-se ':' após o nome do argumento para tipagem.");

            // Parse the type of argument
            Token[] argTokens;
            while (this.peek().kind != TokenType.EQUALS && this.peek()
                .kind != TokenType.COMMA && this.peek().kind != TokenType.RPAREN)
            {
                argTokens ~= this.advance();
            }

            argType = new ParseType(argTokens).parse();
            if (this.match([TokenType.EQUALS]))
            {
                def = this.parseExpression(Precedence.LOWEST);
            }

            args ~= new FunctionArg(argId, argType, def);

            if (this.peek().kind == TokenType.COMMA)
            {
                this.advance(); // skip ','
            }
            else if (this.peek().kind != TokenType.RPAREN)
            {
                error.addError(Diagnostic(
                        "Esperava-se ',' ou ')' após o(s) argumento(s).", this.peek()
                        .loc));
                throw new Exception("Esperava-se ',' ou ')' após o(s) argumento(s).");
            }
        }
        this.consume(TokenType.RPAREN, "Esperava-se ')' após o(s) argumento(s).");
        return args;
    }

    Stmt parseReturnStatement()
    {
        Stmt expr = new NullLiteral(this.previous().loc);
        expr.type.baseType = TypesNative.NULO;
        if (!this.match([TokenType.SEMICOLON]))
            expr = this.parseExpression(Precedence.LOWEST);
        return new ReturnStatement(expr, this.previous().loc);
    }

    Stmt parseCallExpression()
    {
        Token calle = this.previous();
        this.advance(); // skip '('
        Stmt[] args = [];
        while (this.peek().kind != TokenType.RPAREN && !this.isAtEnd())
        {
            args ~= this.parseExpression(Precedence.LOWEST);
            this.match([TokenType.COMMA]);
        }
        this.consume(TokenType.RPAREN, "Esperava-se ')' após os argumentos.");
        return new CallExpr(new Identifier(calle.value.get!string, calle.loc), args, calle.loc);
    }

    Stmt parseVarDeclaration()
    {
        Token firstIdToken = this.consume(TokenType.IDENTIFIER, "Esperava-se um ID para o nome da variavel.");
        Identifier[] ids = [
            new Identifier(firstIdToken.value.get!string, firstIdToken.loc)
        ];
        bool isMultiple = false;

        if (this.match([TokenType.COMMA]))
        {
            isMultiple = true;

            while (this.peek().kind != TokenType.EQUALS &&
                this.peek()
                .kind != TokenType.COLON &&
                this.peek()
                .kind != TokenType.SEMICOLON &&
                !this.isAtEnd())
            {
                Token idToken = this.consume(TokenType.IDENTIFIER, "Esperava-se um identificador após a ','.");
                ids ~= new Identifier(idToken.value.get!string, idToken.loc);

                if (!this.match([TokenType.COMMA]))
                {
                    break;
                }
            }
        }

        FTypeInfo declaredType = createTypeInfo(TypesNative.NULO);
        if (this.match([TokenType.COLON]))
        {
            Token[] typeTokens;
            while (this.peek().kind != TokenType.EQUALS &&
                this.peek()
                .kind != TokenType.SEMICOLON &&
                !this.isAtEnd())
            {
                typeTokens ~= this.advance();
            }

            if (typeTokens.length > 0)
            {
                declaredType = new ParseType(typeTokens).parse();
            }
        }

        if (this.match([TokenType.SEMICOLON]))
        {
            if (declaredType.baseType == TypesNative.NULO)
            {
                error.addError(Diagnostic(
                        "Tipo deve ser especificado para variáveis não inicializadas.", firstIdToken
                        .loc));
                throw new Exception(
                    "Tipo deve ser especificado para variáveis não inicializadas.");
            }

            if (isMultiple)
            {
                return VariableDeclarationFactory.createMultipleUninitialized(
                    ids,
                    declaredType,
                    true,
                    firstIdToken.loc
                );
            }
            else
            {
                return VariableDeclarationFactory.createUninitialized(
                    ids[0],
                    declaredType,
                    true,
                    firstIdToken.loc
                );
            }
        }

        this.consume(TokenType.EQUALS, "Esperava-se '=' após a declaração da variavel.");

        if (isMultiple)
        {
            Stmt[] values;
            do
            {
                values ~= this.parseExpression(Precedence.LOWEST);
            }
            while (this.match([TokenType.COMMA]));

            if (ids.length != values.length)
            {
                error.addError(Diagnostic(
                        format(
                        "Número de identificadores (%d) não corresponde ao número de valores (%d).",
                        ids.length,
                        values.length
                    ), firstIdToken
                        .loc));
                throw new Exception(format(
                        "Número de identificadores (%d) não corresponde ao número de valores (%d).",
                        ids.length,
                        values.length
                ));
            }

            return VariableDeclarationFactory.createMultipleInitialized(
                ids,
                values,
                declaredType,
                true,
                firstIdToken.loc
            );
        }
        else
        {
            Stmt value = this.parseExpression(Precedence.LOWEST);
            FTypeInfo finalType = declaredType.baseType != TypesNative.NULO ? declaredType
                : value.type;

            return VariableDeclarationFactory.createInitialized(
                ids[0],
                value,
                finalType,
                true,
                firstIdToken.loc
            );
        }
    }

    bool isVariableDeclaration(Stmt stmt)
    {
        return stmt.kind == NodeType.VariableDeclaration ||
            stmt.kind == NodeType.UninitializedVariableDeclaration ||
            stmt.kind == NodeType.MultipleVariableDeclaration;
    }

    Identifier[] extractIdentifiers(Stmt stmt)
    {
        switch (stmt.kind)
        {
        case NodeType.VariableDeclaration:
            auto varDecl = cast(VariableDeclaration) stmt;
            return [varDecl.id];

        case NodeType.UninitializedVariableDeclaration:
            auto uninitDecl = cast(UninitializedVariableDeclaration) stmt;
            return [uninitDecl.id];

        case NodeType.MultipleVariableDeclaration:
            auto multiDecl = cast(MultipleVariableDeclaration) stmt;
            return multiDecl.getIdentifiers();

        default:
            return [];
        }
    }

    Stmt parseCastExpression()
    {
        Loc startLoc = this.previous().loc;
        ulong savedPos = this.pos - 1;

        Token[] typeTokens;
        ulong nestingLevel = 0;
        bool foundClosingParen = false;
        bool hasOperators = false;

        while (!this.isAtEnd())
        {
            if (this.check(TokenType.LPAREN))
            {
                nestingLevel++;
            }
            else if (this.check(TokenType.RPAREN))
            {
                if (nestingLevel == 0)
                {
                    foundClosingParen = true;
                    break;
                }
                nestingLevel--;
            }
            else if (
                this.check(TokenType.PLUS) ||
                this.check(TokenType.MINUS) ||
                this.check(TokenType.SLASH) ||
                this.check(TokenType.MODULO) ||
                this.check(TokenType.REMAINDER) ||
                this.check(TokenType.EXPONENTIATION) ||
                this.check(TokenType.EQUALS_EQUALS) ||
                this.check(TokenType.NOT_EQUALS) ||
                this.check(TokenType.GREATER_THAN) ||
                this.check(TokenType.LESS_THAN)
                )
            {
                hasOperators = true;
                break;
            }

            typeTokens ~= this.advance();
        }

        if (!foundClosingParen || hasOperators)
        {
            this.pos = savedPos;
            this.advance(); // Consome o LPAREN
            Stmt expr = this.parseExpression(Precedence.LOWEST);
            this.consume(TokenType.RPAREN, "Expect ')' after expression.");
            return expr;
        }

        this.consume(TokenType.RPAREN, "Expect ')' after type cast.");

        bool nextTokenIsValidCastTarget =
            this.peek().kind == TokenType.IDENTIFIER ||
            this.peek()
            .kind == TokenType.I32 ||
            this.peek().kind == TokenType.FLOAT ||
            this.peek().kind == TokenType.I8P ||
            this.peek()
            .kind == TokenType.ASTERISK ||
            this.peek().kind == TokenType.LPAREN;

        if (!nextTokenIsValidCastTarget)
        {
            this.pos = savedPos;
            this.advance(); // Consome o LPAREN
            Stmt expr = this.parseExpression(Precedence.LOWEST);
            this.consume(TokenType.RPAREN, "Expect ')' after expression.");
            return expr;
        }

        if (!this.isValidTypeSequence(typeTokens))
        {
            this.pos = savedPos;
            this.advance(); // Consome o LPAREN
            Stmt expr = this.parseExpression(Precedence.LOWEST);
            this.consume(TokenType.RPAREN, "Expect ')' after expression.");
            return expr;
        }

        try
        {
            FTypeInfo castType = new ParseType(typeTokens).parse();
            Stmt expr = this.parseExpression(Precedence.PREFIX);
            return new CastExpr(castType, expr, this.makeLoc(startLoc, expr.loc));
        }
        catch (Exception e)
        {
            this.pos = savedPos;
            this.advance(); // Consome o LPAREN
            Stmt expr = this.parseExpression(Precedence.LOWEST);
            this.consume(TokenType.RPAREN, "Expect ')' after expression.");
            return expr;
        }
    }

    bool isValidTypeSequence(ref Token[] tokens)
    {
        if (tokens.length == 0)
            return false;

        if (tokens.length == 1)
        {
            return tokens[0].kind == TokenType.IDENTIFIER ||
                tokens[0].kind == TokenType.I32 ||
                tokens[0].kind == TokenType.FLOAT ||
                tokens[0].kind == TokenType.I8P;
        }

        ulong position = 0;
        return parseTypeHelper(tokens, position) && position == tokens.length;
    }

    bool parseTypeHelper(ref Token[] tokens, ref ulong pos)
    {
        if (pos >= tokens.length)
            return false;

        if (tokens[pos].kind != TokenType.IDENTIFIER)
            return false;

        pos++;

        while (pos < tokens.length && tokens[pos].kind == TokenType.ASTERISK)
        {
            pos++;
        }

        while (pos + 1 < tokens.length &&
            tokens[pos].kind == TokenType.LBRACKET &&
            tokens[pos + 1].kind == TokenType.RBRACKET)
        {
            pos += 2;
        }

        return true;
    }

    Stmt parseGroupedExpression()
    {
        Stmt expr = this.parseExpression(Precedence.LOWEST);
        this.consume(TokenType.RPAREN, "Expect ')' after expression.");
        return expr;
    }

    Stmt parseBinaryInfix(Stmt left)
    {
        this.advance();
        Token operatorToken = this.previous();

        Precedence precedence = this.getPrecedence(operatorToken.kind);
        Stmt right = this.parseExpression(precedence);
        FTypeInfo type = this.inferType(left, right);

        BinaryExpr node = new BinaryExpr(left, right, operatorToken.value.get!string, this.makeLoc(left.loc, right
                .loc));
        node.type = type;
        return node;
    }

    void infix(ref Stmt leftOld)
    {
        switch (this.peek().kind)
        {
        case TokenType.PLUS:
        case TokenType.MINUS:
        case TokenType.SLASH:
        case TokenType.ASTERISK:
        case TokenType.EXPONENTIATION:
        case TokenType.MODULO:
        case TokenType.REMAINDER:
        case TokenType.EQUALS_EQUALS:
        case TokenType.NOT_EQUALS:
        case TokenType.GREATER_THAN:
        case TokenType.LESS_THAN:
        case TokenType.GREATER_THAN_OR_EQUALS:
        case TokenType.LESS_THAN_OR_EQUALS:
        case TokenType.AND:
        case TokenType.OR:
        case TokenType.BIT_AND:
        case TokenType.BIT_OR:
        case TokenType.BIT_XOR:
        case TokenType.LEFT_SHIFT:
        case TokenType.RIGHT_SHIFT:
        case TokenType.BIT_AND_ASSIGN:
        case TokenType.BIT_OR_ASSIGN:
        case TokenType.BIT_XOR_ASSIGN:
        case TokenType.LEFT_SHIFT_ASSIGN:
        case TokenType.RIGHT_SHIFT_ASSIGN:
            leftOld = this.parseBinaryInfix(leftOld);
            return;
        case TokenType.INCREMENT:
        case TokenType.DECREMENT:
            Token operatorToken = this.advance();
            leftOld = new UnaryExpr(
                operatorToken.value.get!string,
                leftOld,
                this.makeLoc(leftOld.loc, operatorToken.loc),
                true
            );
            return;
        case TokenType.DOT: // suporte para member call
            leftOld = this.parseMemberCallExpression(leftOld);
            return;
        default:
            return;
        }
    }

    Stmt parseExpression(Precedence precedence)
    {
        Stmt left = this.parsePrefix();

        while (!this.isAtEnd() && precedence < this.peekPrecedence())
        {
            ulong oldPos = this.pos;
            this.infix(left);

            if (this.pos == oldPos)
            {
                break;
            }
        }

        return left;
    }

    Stmt parseStmt()
    {
        Stmt stmt = this.parseExpression(Precedence.LOWEST);
        this.match([TokenType.SEMICOLON]);
        return stmt;
    }

public:
    this(Token[] tokens = [], DiagnosticError e)
    {
        this.error = e;
        this.tokens = tokens;
    }

    Program parse()
    {
        Program program = new Program([]);
        program.type = createTypeInfo(TypesNative.NULO);
        program.value = null;

        try
        {
            while (!this.isAtEnd())
            {
                program.body ~= this.parseStmt();
            }

            if (this.tokens.length == 0)
            {
                return program;
            }

            program.loc = this.makeLoc(this.tokens[0].loc, this
                    .tokens[$ - 1].loc);
        }
        catch (Exception e)
        {
            throw e;
        }

        return program;
    }

    // Helpers
private:
    bool isAtEnd()
    {
        return this.peek().kind == TokenType.EOF;
    }

    Variant next()
    {
        if (this.isAtEnd())
            return Variant(false);
        return Variant(this.tokens[this.pos + 1]);
    }

    Token peek()
    {
        return this.tokens[this.pos];
    }

    Token previous(ulong i = 1)
    {
        return this.tokens[this.pos - i];
    }

    Token advance()
    {
        if (!this.isAtEnd())
            this.pos++;
        return this.previous();
    }

    bool match(TokenType[] kinds)
    {
        foreach (kind; kinds)
        {
            if (this.check(kind))
            {
                this.advance();
                return true;
            }
        }
        return false;
    }

    bool check(TokenType kind)
    {
        if (this.isAtEnd())
            return false;
        return this.peek().kind == kind;
    }

    Token consume(TokenType expected, string message)
    {
        if (this.check(expected))
            return this.advance();
        error.addError(Diagnostic(message, this.peek().loc));
        throw new Exception(format(`Erro de parsing: %s`, message));
    }

    Precedence getPrecedence(TokenType kind)
    {
        switch (kind)
        {
        case TokenType.EQUALS:
            return Precedence.ASSIGN;
        case TokenType.QUESTION:
            return Precedence.TERNARY;
        case TokenType.OR:
            return Precedence.OR;
        case TokenType.AND:
            return Precedence.AND;
        case TokenType.EQUALS_EQUALS:
        case TokenType.NOT_EQUALS:
            return Precedence.EQUALS;
        case TokenType.LESS_THAN:
        case TokenType.GREATER_THAN:
        case TokenType.LESS_THAN_OR_EQUALS:
        case TokenType.GREATER_THAN_OR_EQUALS:
            return Precedence.COMPARISON;
        case TokenType.PLUS:
        case TokenType.MINUS:
            return Precedence.SUM;
        case TokenType.SLASH:
        case TokenType.ASTERISK:
        case TokenType.MODULO:
        case TokenType.REMAINDER:
            return Precedence.PRODUCT;
        case TokenType.EXPONENTIATION:
            return Precedence.EXPONENT;
        case TokenType.LPAREN:
        case TokenType.DOT:
            return Precedence.CALL;

        case TokenType.BIT_OR:
            return Precedence.BIT_OR;
        case TokenType.BIT_XOR:
            return Precedence.BIT_XOR;
        case TokenType.BIT_AND:
            return Precedence.BIT_AND;
        case TokenType.LEFT_SHIFT:
        case TokenType.RIGHT_SHIFT:
            return Precedence.BIT_SHIFT;
        case TokenType.BIT_AND_ASSIGN:
        case TokenType.BIT_OR_ASSIGN:
        case TokenType.BIT_XOR_ASSIGN:
        case TokenType.LEFT_SHIFT_ASSIGN:
        case TokenType.RIGHT_SHIFT_ASSIGN:
            return Precedence.ASSIGN;
        case TokenType.INCREMENT:
        case TokenType.DECREMENT:
            return Precedence.POSTFIX;
        default:
            return Precedence.LOWEST;
        }
    }

    Precedence peekPrecedence()
    {
        return this.getPrecedence(this.peek().kind);
    }

    FTypeInfo inferType(Stmt left, Stmt right)
    {
        if (left.type.baseType == "string" || right.type.baseType == "string")
        {
            return createTypeInfo(TypesNative.I8P);
        }

        if (left.type.baseType == "float" || right.type.baseType == "float")
        {
            return createTypeInfo(TypesNative.F32);
        }
        return createTypeInfo(TypesNative.I32);
    }

    Loc makeLoc(ref Loc start, ref Loc end)
    {
        return Loc(start.file, start.line, start.start, end.end, start.dir);
    }
}
