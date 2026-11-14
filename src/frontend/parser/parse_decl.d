module frontend.parser.parse_decl;

import std.stdio;

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
        if (p.match(TokenKind.LBrace))
        {
            Token[] names;
            do
            {
                names ~= p.consume(TokenKind.Identifier, "Esperado nome na desestruturação.");
            }
            while (p.match(TokenKind.Comma));
            p.consume(TokenKind.RBrace, "Esperado '}' após nomes.");
            p.consume(TokenKind.Equals, "Esperado '=' após desestruturação.");
            auto value = p.parseExpr.parse();
            auto temp = p.hiddenName();
            Node[] body = [new VarDecl(temp, value, true, null, value.pos)];
            foreach (name; names)
                body ~= new VarDecl(name.value.s, new MemberExpr(new Identifier(temp, value.pos),
                        new Identifier(name.value.s, name.pos), name.pos), isConst, null, name.pos);
            return new SequenceStmt(body, value.pos);
        }
        Token[] names;
        TypeExpr[] types;
        do
        {
            auto name = p.consume(TokenKind.Identifier, "Esperado nome de variável.");
            names ~= name;
            types ~= p.match(TokenKind.Colon) ? p.parseType.parse() : null;
        }
        while (p.match(TokenKind.Comma));
        Node[] values;
        bool initialized = p.match(TokenKind.Equals);
        if (initialized)
            do
        {
            values ~= p.parseExpr.parse();
        }
        while (p.match(TokenKind.Comma));
            else
        {
            foreach (name; names)
                values ~= new NullLit(name.pos);
            if (isConst)
                p.err.error(names[0].pos, "Uma constante exige inicializador.");
        }
        if (names.length != values.length)
        {
            p.err.error(names[0].pos, "Quantidade de variáveis e valores incompatível.");
            return new NaN(names[0].pos);
        }
        if (names.length == 1)
        {
            auto variable = new VarDecl(names[0].value.s, values[0], isConst, types[0], names[0].pos);
            variable.uninitialized = !initialized;
            return variable;
        }
        Node[] body;
        dstring[] temps;
        foreach (value; values)
        {
            auto name = p.hiddenName();
            temps ~= name;
            body ~= new VarDecl(name, value, true, null, value.pos);
        }
        foreach (i, name; names)
        {
            auto variable = new VarDecl(name.value.s, new Identifier(temps[i], name.pos), isConst, types[i], name.pos);
            variable.uninitialized = !initialized;
            body ~= variable;
        }
        return new SequenceStmt(body, names[0].pos);
    }

    Node parseFnDecl(Token name = null)
    {
        if (name is null)
            name = p.consume(TokenKind.Identifier, "Esperado um identificador pro nome da função.");
        TypeExpr retType = new TypeExprNamed("qualquer", name.pos);

        p.consume(TokenKind.LParen, "Esperado '(' após o nome função.");
        FnArg[] args;
        bool optionalSeen;
        while (!p.check(TokenKind.RParen))
        {
            bool rest = p.match(TokenKind.Spread) || p.match(TokenKind.Star);
            Token argName = p.consume(TokenKind.Identifier, "Esperado um nome pro argumento.");
            TypeExpr type = new TypeExprNamed("qualquer", argName.pos);

            if (p.match(TokenKind.Colon))
                type = p.parseType.parse();

            Node val = null;

            if (p.match(TokenKind.Equals))
                val = p.parseExpr.parse();

            if (val !is null)
                optionalSeen = true;
            else if (optionalSeen)
                p.err.error(argName.pos, "Parâmetro obrigatório após parâmetro opcional.");
            if (!p.check(TokenKind.RParen))
                p.consume(TokenKind.Comma, "Esperado ',' após o argumento.");

            auto arg = new FnArg(argName.value.s, type, val, argName.pos);
            arg.rest = rest;
            args ~= arg;
            if (rest && !p.check(TokenKind.RParen))
                p.err.error(argName.pos, "Parâmetro de espalhamento deve ser o último.");
            if (rest && val !is null)
                p.err.error(argName.pos, "Parâmetro de espalhamento não aceita valor padrão.");
            // writeln(args[$ - 1]);
        }

        p.consume(TokenKind.RParen, "Esperado ')' após os argumentos.");

        if (p.match(TokenKind.Colon))
            retType = p.parseType.parse();

        // p.consume(TokenKind.LBrace, "Esperado '{' pro corpo da função.");
        Node[] body = p.parseBody();
        // p.consume(TokenKind.RBrace, "Esperado '}' após o corpo da função.");

        return new FnDecl(name.value.s, args, retType, body, p.getAndResetFlags(), name.pos);
    }

    ClassDecl parseClass()
    {
        if (p.check(TokenKind.Identifier) && p.peek().value.s == "estrangeira")
        {
            auto unsafeToken = p.advance();
            p.err.warning(unsafeToken.pos,
                    "Classe estrangeira/FFI detectada: execução nativa arbitrária desabilitada.");
            p.err.error(unsafeToken.pos, "FFI não é suportada neste compilador por segurança.");
        }
        auto name = p.consume(TokenKind.Identifier, "Esperado nome da classe.");
        dstring parent;
        if (p.match(TokenKind.Extends))
            parent = p.consume(TokenKind.Identifier, "Esperado nome da superclasse.").value.s;
        auto node = new ClassDecl(name.value.s, parent, name.pos);
        p.consume(TokenKind.LBrace, "Esperado '{' na classe.");
        parseClassMembers(node, 0);
        return node;
    }

    void parseClassMembers(ClassDecl node, int access)
    {
        while (!p.isAtEnd() && !p.check(TokenKind.RBrace))
        {
            if (p.match(TokenKind.Semicolon))
                continue;
            if (p.check(TokenKind.Private) || p.check(TokenKind.Protected) || p.check(TokenKind.Public))
            {
                auto kind = p.advance().kind;
                int visibility = kind == TokenKind.Private ? 1 : kind == TokenKind.Protected ? 2 : 0;
                p.consume(TokenKind.LBrace, "Esperado bloco de visibilidade.");
                parseClassMembers(node, visibility);
                continue;
            }
            auto decorators = p.parseDecorators();
            auto name = p.consumeName("Esperado propriedade ou método.");
            if (p.match(TokenKind.Colon))
            {
                auto type = p.parseType.parse();
                ClassField field = ClassField(name.value.s, type, access, name.pos);
                if (p.match(TokenKind.LBrace))
                {
                    field.customAccess = true;
                    while (!p.isAtEnd() && !p.check(TokenKind.RBrace))
                    {
                        auto token = p.consume(TokenKind.Identifier, "Esperado obter ou definir.");
                        bool getter = token.value.s == "obter";
                        if (!getter && token.value.s != "definir")
                            p.err.error(token.pos, "Acessor desconhecido.");
                        if (getter)
                            field.readable = true;
                        else
                            field.writable = true;
                        if (p.check(TokenKind.LParen))
                        {
                            auto method = cast(FnDecl) parseFnDecl(token);
                            method.isMethod = true;
                            method.ownerClass = node;
                            method.accessor = true;
                            method.fn = (getter ? "#get_"d : "#set_"d) ~ name.value.s;
                            if (method.args.length != (getter ? 0 : 1))
                                p.err.error(token.pos, "Aridade inválida do acessor.");
                            if (getter)
                            {
                                method.type_expr = type;
                                field.getter = method;
                            }
                            else
                                field.setter = method;
                            node.methods ~= method;
                        }
                        else
                            p.consume(TokenKind.Semicolon, "Esperado ';' após acessor automático.");
                    }
                    p.consume(TokenKind.RBrace, "Esperado '}' após acessores.");
                }
                field.decorators = decorators;
                node.fields ~= field;
                p.match(TokenKind.Semicolon);
            }
            else
            {
                auto method = cast(FnDecl) parseFnDecl(name);
                method.isMethod = true;
                method.ownerClass = node;
                method.access = access;
                method.decorators = decorators;
                node.methods ~= method;
            }
        }
        p.consume(TokenKind.RBrace, "Esperado '}' após classe/bloco de visibilidade.");
    }

    Node parse()
    {
        Token tk = p.advance();
        switch (tk.kind)
        {
            case TokenKind.Var:
            case TokenKind.Const:
                return parseVarDecl(tk.kind == TokenKind.Const);

            case TokenKind.Class:
                return parseClass();
            case TokenKind.Fn:
                bool envelope = p.match(TokenKind.Of);
                if (envelope)
                {
                    auto marker = p.consumeName("Esperado decorador após função de.");
                    if (marker.value.s != "decorador")
                        p.err.error(marker.pos, "Esperado decorador.");
                }
                auto fn = cast(FnDecl) parseFnDecl();
                fn.decoratorEnvelope = envelope;
                return fn;

            default:
                return new Identifier("null", tk.pos);
        }
    }
}
