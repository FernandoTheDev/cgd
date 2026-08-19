module frontend.parser.parse_decl;

import frontend.parser;
import frontend.lexer;
import frontend;

class ParseDecl
{
private:
    Parser p;

public:
    this(Parser p)
    {
        this.p = p;
    }

    Node parseVarDecl(bool isConst)
    {
        Token name = p.consume(TokenKind.Identifier, "Esperado um identificador pro nome da variavel.");
        
        TypeExpr texpr = null;
        if (p.match(TokenKind.Colon))
            texpr = p.parseType.parse();
        
        p.consume(TokenKind.Equals, "Esperado '=' após a variavel.");
        Node value = p.parseExpr.parse();

        return new VarDecl(name.value.s, value, isConst, texpr, name.pos);
    }

    Node parseFnDecl()
    {
        Token name = p.consume(TokenKind.Identifier, "Esperado um identificador pro nome da função.");
        TypeExpr retType = new TypeExprNamed("qualquer", name.pos);

        p.consume(TokenKind.LParen, "Esperado '(' após o nome função.");
        FnArg[] args;
        while (!p.check(TokenKind.RParen))
        {
            Token argName = p.consume(TokenKind.Identifier, "Esperado um nome pro argumento.");
            TypeExpr type = new TypeExprNamed("qualquer", argName.pos);
            if (p.match(TokenKind.Colon))
                type = p.parseType.parse();
            Node val = null;
            if (p.match(TokenKind.Equals))
                val = p.parseExpr.parse();
            if (!p.check(TokenKind.RParen))
                p.consume(TokenKind.Comma, "Esperado ',' após o argumento.");
            args ~= new FnArg(argName.value.s, type, val, argName.pos);
        }
        p.consume(TokenKind.RParen, "Esperado ')' após os argumentos.");

        if (p.match(TokenKind.Colon))
            retType = p.parseType.parse();

        p.consume(TokenKind.LBrace, "Esperado '{' pro corpo da função.");
        Node[] body;
        while (!p.check(TokenKind.RBrace))
            body ~= p.parseIntern();
        p.consume(TokenKind.RBrace, "Esperado '}' após o corpo da função.");

        return new FnDecl(name.value.s, args, retType, body, name.pos);
    }

    Node parse()
    {
        Token tk = p.advance();
        switch (tk.kind)
        {
            case TokenKind.Var:
            case TokenKind.Const:
                return parseVarDecl(tk.kind == TokenKind.Const);

            case TokenKind.Fn:
                return parseFnDecl();
                
            default:
                return new Identifier("null", tk.pos);
        }
    }
}
