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
        Node value;
        if (!p.isAtEnd() && !p.check(TokenKind.RBrace) && !p.check(TokenKind.Semicolon) && p.peek()
                .pos.start.line == pos.end.line)
            value = p.parseExpr.parse();
        return new ReturnStmt(value, pos);
    }

    Node parseWhileStmt(Position pos)
    {
        Node expr = p.parseExpr.parse();
        Node[] body = p.parseBody(true);
        return new WhileStmt(expr, body, p.getPos(pos, expr.pos));
    }

    Node parseFor(Position pos)
    {
        if (p.match(TokenKind.Each))
        {
            dstring[] names;
            TypeExpr[] memberTypes;
            Token name;
            if (p.match(TokenKind.LBrace))
            {
                do
                {
                    names ~= p.consume(TokenKind.Identifier, "Esperado nome após para cada.").value.s;
                    memberTypes ~= p.match(TokenKind.Colon) ? p.parseType.parse() : null;
                }
                while (p.match(TokenKind.Comma));
                p.consume(TokenKind.RBrace, "Esperado '}' após nomes.");
                if (names.length != 2)
                    p.err.error(pos, "Desestruturação de iteração exige chave e valor.");
                name = new Token(TokenKind.Identifier, TokenRaw._s(p.hiddenName()), pos);
            }
            else
                name = p.consume(TokenKind.Identifier, "Esperado nome após para cada.");
            TypeExpr bindingType = p.match(TokenKind.Colon) ? p.parseType.parse() : null;
            if (!p.match(TokenKind.Of))
                p.consume(TokenKind.In, "Esperado 'de' ou 'em' após variável de iteração.");
            Node iterable = p.parseExpr.parse();
            EachStmt loop = new EachStmt(name.value.s, iterable, p.parseBody(true), pos);
            loop.bindingType = bindingType;
            loop.destructured = names;
            loop.destructuredTypes = memberTypes;
            return loop;
        }
        bool paren = p.match(TokenKind.LParen);
        Node init, condition, step;
        if (!p.check(TokenKind.Semicolon))
            init = p.isDecl() ? p.parseDecl.parse() : p.parseExpr.parse();
        p.consume(TokenKind.Semicolon, "Esperado ';' após inicializador do para.");
        if (!p.check(TokenKind.Semicolon))
            condition = p.parseExpr.parse();
        p.consume(TokenKind.Semicolon, "Esperado ';' após condição do para.");
        if (!(paren ? p.check(TokenKind.RParen) : p.check(TokenKind.LBrace)))
            step = p.parseExpr.parse();
        if (paren)
            p.consume(TokenKind.RParen, "Esperado ')' após para.");
        return new ForStmt(init, condition, step, p.parseBody(true), pos);
    }

    Node parseSwitch(Position pos)
    {
        SwitchStmt node = new SwitchStmt(p.parseExpr.parse(), pos);
        p.consume(TokenKind.LBrace, "Esperado '{' após escolha.");
        while (!p.isAtEnd() && !p.check(TokenKind.RBrace))
        {
            SwitchCase c;
            bool fallback = false;
            if (p.match(TokenKind.Default))
            {
                fallback = true;
                p.consume(TokenKind.Colon, "Esperado ':' após padrão.");
            }
            else
                do
                {
                    p.consume(TokenKind.Case, "Esperado caso ou padrão.");
                    c.values ~= p.parseExpr.parse();
                    p.consume(TokenKind.Colon, "Esperado ':' após caso.");
                }
            while (p.check(TokenKind.Case));
            while (!p.isAtEnd() && !p.check(TokenKind.Case) && !p.check(TokenKind.Default)
                    && !p.check(TokenKind.RBrace))
                c.body ~= p.parseIntern();
            if (fallback)
                node.fallback = c.body;
            else
                node.cases ~= c;
        }
        p.consume(TokenKind.RBrace, "Esperado '}' após escolha.");
        return node;
    }

    Node parseTry(Position pos)
    {
        Node[] body = p.parseBody();
        CatchClause[] catches;
        Node[] finalBody;
        while (p.match(TokenKind.Catch))
        {
            CatchClause c;
            c.pos = pos;
            if (p.match(TokenKind.LParen))
            {
                c.name = p.consume(TokenKind.Identifier, "Esperado nome da exceção.").value.s;
                if (p.match(TokenKind.Colon))
                    c.type = p.parseType.parse();
                p.consume(TokenKind.RParen, "Esperado ')' após exceção.");
            }
            c.body = p.parseBody();
            catches ~= c;
        }
        bool hasFinally = p.match(TokenKind.Finally);
        if (hasFinally)
            finalBody = p.parseBody();
        if (!catches.length && !hasFinally)
            p.err.error(pos, "Tente exige pegue ou finalmente.");
        TryStmt result = new TryStmt(body, catches, finalBody, pos);
        result.hasFinally = hasFinally;
        return result;
    }

    Node parse()
    {
        Token tk = p.advance();
        switch (tk.kind)
        {
            case TokenKind.Switch:
                return parseSwitch(tk.pos);
            case TokenKind.Assert:
                Identifier id = new Identifier("assercao", tk.pos);
                if (p.match(TokenKind.LParen))
                    return p.parseExpr.parseCallExpr(id);
                return new CallExpr(id, [p.parseExpr.parse()], tk.pos);
            case TokenKind.Try:
                return parseTry(tk.pos);
            case TokenKind.Fail:
                return new ThrowStmt(p.parseExpr.parse(), tk.pos);
            case TokenKind.For:
                return parseFor(tk.pos);
            case TokenKind.Break:
                return new LoopControl(true, tk.pos);
            case TokenKind.Continue:
                return new LoopControl(false, tk.pos);
            case TokenKind.Do:
                Node[] body = p.parseBody();
                p.consume(TokenKind.While, "Esperado 'enquanto' após fazer.");
                return new DoStmt(p.parseExpr.parse(), body, tk.pos);
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
