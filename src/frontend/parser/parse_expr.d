module frontend.parser.parse_expr;

import frontend;
import frontend.lexer;
import frontend.parser;
import std.exception;

enum Precedence : ubyte {
    Low,
    Plus,
    Mul,
    Call,
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

    Node nud()
    {
        Token tk = p.advance();
        switch (tk.kind)
        {
            case TokenKind.String:
                return new StringLit(tk.value.s, tk.pos);

            case TokenKind.Identifier:
                return new Identifier(tk.value.s, tk.pos);
            
            case TokenKind.Int:
                return new IntLit(tk.value.i, tk.pos);
            
            case TokenKind.Double:
                return new DoubleLit(tk.value.d, tk.pos);
            
            case TokenKind.LParen:
                Node node = parse();
                p.consume(TokenKind.RParen, "Esperado um ')' após a expressão.");
                return node;

            case TokenKind.Type:
                p.consume(TokenKind.Of, "Esperado 'de' após o 'tipo'.");
                Node val = parse();
                return new TypeOfExpr(val, p.getPos(tk.pos, val.pos));
            
            default:
                // TODO: melhorar
                tk.print();
                enforce(false, "Expressão inválida.");
                return null;
        }
    }

    Node parseBinaryExpr(TokenKind op, Node left)
    {
        Node right = parse(getPrecedence(op));
        return new BinaryExpr(left, right, op, p.getPos(left.pos, right.pos));
    }

    Node parseCallExpr(Node left)
    {
        Node[] args;
        while (!p.check(TokenKind.RParen))
        {
            args ~= parse();
            if (!p.check(TokenKind.RParen))
                p.consume(TokenKind.Comma, "Esperado ',' após o valor.");
        }
        p.consume(TokenKind.RParen, "Esperado ')' após a chamada da função.");
        return new CallExpr(left, args, left.pos);
    }

    Node led(Node left)
    {
        Token tk = p.advance();
        switch (tk.kind)
        {
            case TokenKind.Plus:
            case TokenKind.Minus:
            case TokenKind.Star:
            case TokenKind.Slash:
            case TokenKind.Modulo:
            case TokenKind.LThan:
            case TokenKind.GThan:
            case TokenKind.EEquals:
            case TokenKind.LEquals:
            case TokenKind.GEquals:
                return parseBinaryExpr(tk.kind, left);
            case TokenKind.LParen:
                return parseCallExpr(left);
            default:
                return left;
        }
    }

    Precedence getPrecedence(TokenKind kind)
    {
        switch (kind)
        {
            case TokenKind.Plus:
            case TokenKind.Minus:
            case TokenKind.LThan:
            case TokenKind.GThan:
            case TokenKind.EEquals:
            case TokenKind.LEquals:
            case TokenKind.GEquals:
                return Precedence.Plus;
            case TokenKind.Star:
            case TokenKind.Slash:
            case TokenKind.Modulo:
                return Precedence.Mul;
            case TokenKind.Dot:
            case TokenKind.LParen:
                return Precedence.Call;
            default:
                return Precedence.Low;
        }
    }

    Node parse(Precedence pre = Precedence.Low)
    {
        Node left = nud();
        while (!p.isAtEnd() && pre < getPrecedence(p.peek().kind))
            left = led(left);
        return left;
    }
}
