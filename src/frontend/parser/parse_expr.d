module frontend.parser.parse_expr;

import std.exception;
import std.stdio;

import frontend.parser;
import frontend.lexer;
import frontend;
import ctfe;

enum Precedence : ubyte {
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

            case TokenKind.True:
            case TokenKind.False:
                return new BoolLit(tk.kind == TokenKind.True, tk.pos);
            
            case TokenKind.LParen:
                Node node = parse();
                p.consume(TokenKind.RParen, "Esperado um ')' após a expressão.");
                return node;

            case TokenKind.Type:
                p.consume(TokenKind.Of, "Esperado 'de' após o 'tipo'.");
                Node val = parse();
                return new TypeOfExpr(val, p.getPos(tk.pos, val.pos));

            case TokenKind.Pure:
                p.flags |= CTFEFlags.Pure;
                return new NaN(tk.pos);
            
            default:
                p.err.error(tk.pos, "Uma expressão é esperada.");
                return new Identifier("null", tk.pos);
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

    Node parseAssignStmt(Node left, TokenKind op)
    {
        Node value = parse();
        return new AssignStmt(left, value, op, p.getPos(left.pos, value.pos));
    }

    Node led(Node left)
    {
        Token tk = p.advance();
        switch (tk.kind) with (TokenKind)
        {
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
                return parseBinaryExpr(tk.kind, left);
            case LParen:
                return parseCallExpr(left);
            case Equals:
                return parseAssignStmt(left, tk.kind);
            default:
                return left;
        }
    }

    Precedence getPrecedence(TokenKind kind)
    {
        switch (kind) with (TokenKind)
        {
            case Equals:
                return Precedence.Assign;
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
            case Dot:
            case LParen:
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
