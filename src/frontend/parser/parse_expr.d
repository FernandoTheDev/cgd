module frontend.parser.parse_expr;

import std.exception;
import std.stdio;

import frontend.parser;
import frontend.lexer;
import frontend;
import ctfe;

enum Precedence : ubyte
{
    Low,
    Assign, // = += -= etc
    Ternary, // ?
    Or, // ||
    And, // &&
    BitOr, // |
    BitXor, // ^
    BitAnd, // &
    Eq, // == != ===
    Cmp, // < > <= >=
    Shift, // << >>
    Plus, // + -
    Mul, // * / %
    Power,
    Unary, // ! ~ - * &
    Call, // () [] .
    High,
}

class ParseExpr
{
private:
    Parser p;

public:
    this(Parser p)
    {
        this.p = p;
    }

    Node parseArrow(Token start, bool parenthesized)
    {
        FnArg[] arguments;
        TypeExpr result = new TypeExprNamed("qualquer", start.pos);
        if (parenthesized)
        {
            bool optionalSeen;
            while (!p.check(TokenKind.RParen))
            {
                Token name = p.consume(TokenKind.Identifier, "Esperado parâmetro de arrow function.");
                TypeExpr type = p.match(TokenKind.Colon) ? p.parseType.parse() : new TypeExprNamed("qualquer", name.pos);
                Node defaultValue = p.match(TokenKind.Equals) ? parse(Precedence.Assign) : null;
                if (defaultValue !is null)
                    optionalSeen = true;
                else if (optionalSeen)
                    p.err.error(name.pos, "Parâmetro obrigatório após opcional.");
                arguments ~= new FnArg(name.value.s, type, defaultValue, name.pos);
                if (!p.check(TokenKind.RParen))
                    p.consume(TokenKind.Comma, "Esperado ','.");
            }
            p.consume(TokenKind.RParen, "Esperado ')'.");
            if (p.match(TokenKind.Colon))
                result = p.parseType.parse();
            p.consume(TokenKind.Arrow, "Esperado '=>'.");
        }
        else
            arguments ~= new FnArg(start.value.s, new TypeExprNamed("qualquer", start.pos), null, start.pos);
        Node[] body = p.check(TokenKind.LBrace) ? p.parseBody() : [
            cast(Node) new ReturnStmt(parse(), start.pos)
        ];
        return new FunctionExpr(new FnDecl("anonima", arguments, result, body, 0, start.pos));
    }

    Node parseText(Token tk)
    {
        import std.algorithm : canFind;
        import std.conv : to;

        dstring text = tk.value.s;
        size_t start = 0, i = 0;
        Node result;
        while (i + 1 < text.length)
        {
            if (text[i] != '$' || text[i + 1] != '{' || tk.escapedInterpolation.canFind(i))
            {
                i++;
                continue;
            }
            StringLit literal = new StringLit(text[start .. i], tk.pos);
            result = result is null ? literal : new BinaryExpr(result, literal, TokenKind.Plus, tk.pos);
            size_t begin = i + 2;
            i = begin;
            uint nesting = 1;
            dchar quote = 0;
            bool escaped;
            while (i < text.length && nesting)
            {
                immutable(dchar) c = text[i++];
                if (quote)
                {
                    if (escaped)
                        escaped = false;
                    else if (c == '\\')
                        escaped = true;
                    else if (c == quote)
                        quote = 0;
                }
                else if (c == '\'' || c == '"')
                    quote = c;
                else if (c == '{')
                    nesting++;
                else if (c == '}')
                    nesting--;
            }
            if (nesting)
            {
                p.err.error(tk.pos, "Interpolação não foi fechada.");
                return new StringLit(text, tk.pos);
            }
            Token[] tokens = new Lexer(text[begin .. i - 1].to!string, tk.pos.filename, p.err).tokenizer();
            foreach (Token token; tokens)
                token.pos = tk.pos;
            Parser parser = new Parser(tokens, p.err);
            parser.nesting = p.nesting;
            Node value = parser.parseExpr.parse();
            if (!parser.isAtEnd())
                p.err.error(tk.pos, "Conteúdo inesperado na interpolação.");
            CallExpr converted = new CallExpr(new Identifier("delegua_para_texto", tk.pos), [value], tk.pos);
            converted.intrinsic = true;
            converted.runtimeCall = true;
            result = new BinaryExpr(result, converted, TokenKind.Plus, tk.pos);
            start = i;
        }
        StringLit tail = new StringLit(text[start .. $], tk.pos);
        return result is null ? tail : new BinaryExpr(result, tail, TokenKind.Plus, tk.pos);
    }

    Node nud()
    {
        Token tk = p.advance();
        switch (tk.kind)
        {
            case TokenKind.LBrace:
                Node[] keys, values;
                while (!p.isAtEnd() && !p.check(TokenKind.RBrace))
                {
                    if (p.match(TokenKind.Spread))
                    {
                        keys ~= null;
                        values ~= new SpreadExpr(parse(), tk.pos);
                    }
                    else
                    {
                        if (p.checkNext(TokenKind.Colon) && (p.peek().kind == TokenKind.Identifier
                                || p.peek().kind <= TokenKind.Of) && p.peek().value.s.length)
                        {
                            Token name = p.advance();
                            keys ~= new StringLit(name.value.s, name.pos);
                        }
                        else
                            keys ~= parse();
                        p.consume(TokenKind.Colon, "Esperado ':' após chave do dicionário.");
                        values ~= parse();
                    }
                    if (!p.check(TokenKind.RBrace))
                        p.consume(TokenKind.Comma, "Esperado ',' após entrada do dicionário.");
                }
                Position end = p.consume(TokenKind.RBrace, "Esperado '}' após dicionário.").pos;
                return new MapLit(keys, values, p.getPos(tk.pos, end));
            case TokenKind.Assert:
                return new Identifier("assercao", tk.pos);
            case TokenKind.Spread:
                return new SpreadExpr(parse(Precedence.Assign), tk.pos);
            case TokenKind.While:
                return new LoopExpr(p.parseStmt.parseWhileStmt(tk.pos), tk.pos);
            case TokenKind.For:
                return new LoopExpr(p.parseStmt.parseFor(tk.pos), tk.pos);
            case TokenKind.Do:
                Node[] body = p.parseBody();
                p.consume(TokenKind.While, "Esperado enquanto após fazer.");
                return new LoopExpr(new DoStmt(parse(), body, tk.pos), tk.pos);
            case TokenKind.Import:
                p.consume(TokenKind.LParen, "Esperado '(' após importar.");
                Node path = parse();
                p.consume(TokenKind.RParen, "Esperado ')' após caminho do módulo.");
                return new ImportExpr(path, tk.pos);
            case TokenKind.Fail:
                return new Identifier("falhar", tk.pos);
            case TokenKind.This:
                return new Identifier("isto", tk.pos);
            case TokenKind.Super:
                dstring name = "construtor";
                if (p.match(TokenKind.Dot))
                    name = p.consumeMemberName(tk.pos).value.s;
                return new SuperExpr(name, tk.pos);
            case TokenKind.Fn:
                Token name = new Token(TokenKind.Identifier, TokenRaw._s("anonima"), tk.pos);
                return new FunctionExpr(cast(FnDecl) p.parseDecl.parseFnDecl(name));
            case TokenKind.Null:
                return new NullLit(tk.pos);

            case TokenKind.String:
                return parseText(tk);

            case TokenKind.Identifier:
                if (p.match(TokenKind.Arrow))
                    return parseArrow(tk, false);
                return new Identifier(tk.value.s, tk.pos);

            case TokenKind.Int:
                return new IntLit(tk.value.i, tk.pos);

            case TokenKind.Double:
                return new DoubleLit(tk.value.d, tk.pos);

            case TokenKind.True:
            case TokenKind.False:
                return new BoolLit(tk.kind == TokenKind.True, tk.pos);

            case TokenKind.LParen:
                if (p.arrowParametersAhead())
                    return parseArrow(tk, true);
                Node node = parse();
                if (p.match(TokenKind.Comma))
                {
                    Node[] values = [node];
                    do
                    {
                        values ~= parse();
                    }
                    while (p.match(TokenKind.Comma));
                    Position end = p.consume(TokenKind.RParen, "Esperado ')' após tupla.").pos;
                    return new TupleLit(values, p.getPos(tk.pos, end));
                }
                p.consume(TokenKind.RParen, "Esperado um ')' após a expressão.");
                return node;

            case TokenKind.Type:
                p.consume(TokenKind.Of, "Esperado 'de' após o 'tipo'.");
                Node val = parse(Precedence.Unary);
                return new TypeOfExpr(val, p.getPos(tk.pos, val.pos));

            case TokenKind.Pure:
                p.flags |= CTFEFlags.Pure;
                return new NaN(tk.pos);

            case TokenKind.LBracket:
                Node[] values;
                while (!p.isAtEnd() && !p.check(TokenKind.RBracket))
                {
                    values ~= parse();
                    if (values.length == 1 && p.match(TokenKind.For))
                    {
                        p.consume(TokenKind.Each, "Esperado cada na compreensão.");
                        Token name = p.consume(TokenKind.Identifier, "Esperado variável da compreensão.");
                        TypeExpr bindingType = p.match(TokenKind.Colon) ? p.parseType.parse() : null;
                        if (!p.match(TokenKind.In))
                            p.consume(TokenKind.Of, "Esperado em/de na compreensão.");
                        Node iterable = parse();
                        Node condition;
                        if (p.match(TokenKind.If))
                            condition = parse();
                        p.consume(TokenKind.RBracket, "Esperado ']' após compreensão.");
                        Comprehension result = new Comprehension(values[0], iterable, condition, name.value.s, tk.pos);
                        result.bindingType = bindingType;
                        return result;
                    }
                    if (values.length == 1 && values[0].kind == NodeKind.TupleLit && p.check(TokenKind.RBracket))
                    {
                        p.advance();
                        return values[0];
                    }
                    if (!p.check(TokenKind.RBracket))
                        p.consume(TokenKind.Comma, "Esperado ',' após o elemento.");
                }
                Position end = p.consume(TokenKind.RBracket, "Esperado ']' após o vetor.").pos;
                return new ArrayLit(values, p.getPos(tk.pos, end));

            case TokenKind.Plus:
            case TokenKind.PPlus:
            case TokenKind.Minus:
            case TokenKind.MMinus:
            case TokenKind.BITNot:
            case TokenKind.Bang:
                Node expr = parse(Precedence.Unary);
                return new UnaryExpr(expr, tk.kind, false, p.getPos(tk.pos, expr.pos));

            default:
                p.err.error(tk.pos, "Uma expressão é esperada.", "E1001");
                throw new ParseException;
        }
    }

    Node parseBinaryExpr(TokenKind op, Node left)
    {
        Node right = parse(op == TokenKind.Pow ? Precedence.Mul : getPrecedence(op));
        return new BinaryExpr(left, right, op, p.getPos(left.pos, right.pos));
    }

    Node parseCallExpr(Node left)
    {
        Node[] args;
        while (!p.check(TokenKind.RParen))
        {
            if (p.recoverIncomplete && p.isAtEnd())
                break;
            args ~= parse();
            if (p.recoverIncomplete && p.isAtEnd())
                break;
            if (!p.check(TokenKind.RParen))
                p.consume(TokenKind.Comma, "Esperado ',' após o valor.");
        }
        Position end = p.consume(TokenKind.RParen, "Esperado ')' após a chamada da função.").pos;
        return new CallExpr(left, args, p.getPos(left.pos, end));
    }

    Node parseAssignStmt(Node left, TokenKind op)
    {
        Node value = parse();
        return new AssignStmt(left, value, op, p.getPos(left.pos, value.pos));
    }

    Node parseIndexExpr(Node value)
    {
        Node start, end, step;
        if (!p.check(TokenKind.Colon))
            start = parse();
        if (p.match(TokenKind.Colon))
        {
            if (!p.check(TokenKind.Colon) && !p.check(TokenKind.RBracket))
                end = parse();
            if (p.match(TokenKind.Colon) && !p.check(TokenKind.RBracket))
                step = parse();
            Position pos = p.consume(TokenKind.RBracket, "Esperado ']' após fatia.").pos;
            return new SliceExpr(value, start, end, step, p.getPos(value.pos, pos));
        }
        Position pos = p.consume(TokenKind.RBracket, "Esperado ']' após índice.").pos;
        return new IndexExpr(value, start, p.getPos(value.pos, pos));
    }

    Node parseMemberExpr(Node left)
    {
        Token name = p.consumeMemberName(left.pos);
        Node right = new Identifier(name.value.s, name.pos);
        return new MemberExpr(left, right, p.getPos(left.pos, right.pos));
    }

    Node led(Node left)
    {
        Token tk = p.advance();
        switch (tk.kind) with (TokenKind)
        {
            case Question:
                Node yes = parse();
                p.consume(Colon, "Esperado ':' na expressão condicional.");
                Node no = parse(Precedence.Assign);
                return new ConditionalExpr(left, yes, no, p.getPos(left.pos, no.pos));
            case Bang:
                if ((tk.value.s == "não" || tk.value.s == "nao") && p.match(TokenKind.In))
                {
                    Node right = parse(Precedence.Cmp);
                    BinaryExpr membership = new BinaryExpr(left, right, TokenKind.In, p.getPos(left.pos, right.pos));
                    return new UnaryExpr(membership, TokenKind.Bang, false, membership.pos);
                }
                p.err.error(tk.pos, "Operador de negação em posição inválida.");
                return left;
            case And:
            case Or:
            case Coalesce:
            case In:
            case Pow:
            case IntDiv:
            case NEquals:
            case Plus:
            case Minus:
            case Star:
            case Slash:
            case Modulo:
            case LThan:
            case GThan:
            case EEquals:
            case LEquals:
            case GEquals:
            case BITAnd:
            case BITOr:
            case BITXor:
            case BITSL:
            case BITSR:
                return parseBinaryExpr(tk.kind, left);
            case LParen:
                return parseCallExpr(left);
            case Equals:
            case PlusAssign:
            case MinusAssign:
            case MulAssign:
            case DivAssign:
            case ModAssign:
                return parseAssignStmt(left, tk.kind);
            case LBracket:
                return parseIndexExpr(left);
            case Dot:
                return parseMemberExpr(left);
            case PPlus:
            case MMinus:
                return new UnaryExpr(left, tk.kind, true, p.getPos(left.pos, tk.pos));
            default:
                return left;
        }
    }

    Precedence getPrecedence(TokenKind kind)
    {
        switch (kind) with (TokenKind)
        {
            case Equals:
            case PlusAssign:
            case MinusAssign:
            case MulAssign:
            case DivAssign:
            case ModAssign:
                return Precedence.Assign;
            case And:
                return Precedence.And;
            case Or:
                return Precedence.Or;
            case Coalesce:
            case Question:
                return Precedence.Ternary;
            case In:
                return Precedence.Cmp;
            case Pow:
                return Precedence.Power;
            case IntDiv:
                return Precedence.Mul;
            case NEquals:
                return Precedence.Eq;
            case Plus:
            case Minus:
                return Precedence.Plus;
            case EEquals:
                return Precedence.Eq;
            case LThan:
            case GThan:
            case LEquals:
            case GEquals:
                return Precedence.Cmp;
            case Star:
            case Slash:
            case Modulo:
                return Precedence.Mul;
            case BITAnd:
                return Precedence.BitAnd;
            case BITOr:
                return Precedence.BitOr;
            case BITXor:
                return Precedence.BitXor;
            case BITSL:
            case BITSR:
                return Precedence.Shift;
            case BITNot:
            case Bang:
                return Precedence.Unary;
            case Dot:
            case LParen:
            case LBracket:
            case PPlus:
            case MMinus:
                return Precedence.Call;
            default:
                return Precedence.Low;
        }
    }

    Node parseStatement()
    {
        Node first = parse();
        if (!p.match(TokenKind.Comma))
            return first;
        Node[] targets = [first];
        do
        {
            targets ~= parse(Precedence.Assign);
        }
        while (p.match(TokenKind.Comma));
        p.consume(TokenKind.Equals, "Esperado '=' na atribuição múltipla.");
        Node[] values;
        do
        {
            values ~= parse();
        }
        while (p.match(TokenKind.Comma));
        if (values.length != targets.length)
        {
            p.err.error(first.pos, "Quantidade de destinos e valores incompatível.");
            return new NaN(first.pos);
        }
        Node[] body;
        dstring[] temps;
        foreach (Node value; values)
        {
            dstring name = p.hiddenName();
            temps ~= name;
            body ~= new VarDecl(name, value, true, null, value.pos);
        }
        foreach (size_t i, Node target; targets)
            body ~= new AssignStmt(target, new Identifier(temps[i], target.pos), TokenKind.Equals, target.pos);
        return new SequenceStmt(body, first.pos);
    }

    Node parse(Precedence pre = Precedence.Low)
    {
        p.enterSyntax();
        scope (exit)
            p.leaveSyntax();
        Node left = nud();
        while (!p.isAtEnd() && pre < getPrecedence(p.peek().kind))
            left = led(left);
        return left;
    }
}
