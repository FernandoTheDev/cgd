module frontend.parser.parse_decl;

import std.stdio;

import frontend.parser;
import frontend.lexer;
import frontend;
import ctfe.ctfe_flags : CTFEFlags;

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
            TypeExpr[] memberTypes;
            do
            {
                names ~= p.consume(TokenKind.Identifier, "Esperado nome na desestruturação.");
                memberTypes ~= p.match(TokenKind.Colon) ? p.parseType.parse() : null;
            }
            while (p.match(TokenKind.Comma));
            p.consume(TokenKind.RBrace, "Esperado '}' após nomes.");
            p.consume(TokenKind.Equals, "Esperado '=' após desestruturação.");
            Node value = p.parseExpr.parse();
            dstring temp = p.hiddenName();
            Node[] body = [new VarDecl(temp, value, true, null, value.pos)];
            foreach (size_t i, Token name; names)
                body ~= new VarDecl(name.value.s, new MemberExpr(new Identifier(temp, value.pos),
                        new Identifier(name.value.s, name.pos), name.pos), isConst, memberTypes[i], name.pos);
            return new SequenceStmt(body, value.pos);
        }
        Token[] names;
        TypeExpr[] types;
        do
        {
            Token name = p.consume(TokenKind.Identifier, "Esperado nome de variável.");
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
            foreach (Token name; names)
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
            VarDecl variable = new VarDecl(names[0].value.s, values[0], isConst, types[0], names[0].pos);
            variable.uninitialized = !initialized;
            return variable;
        }
        Node[] body;
        dstring[] temps;
        foreach (Node value; values)
        {
            dstring name = p.hiddenName();
            temps ~= name;
            body ~= new VarDecl(name, value, true, null, value.pos);
        }
        foreach (size_t i, Token name; names)
        {
            VarDecl variable = new VarDecl(name.value.s, new Identifier(temps[i], name.pos),
                    isConst, types[i], name.pos);
            variable.uninitialized = !initialized;
            body ~= variable;
        }
        return new SequenceStmt(body, names[0].pos);
    }

    Node parseFnDecl(Token name = null, bool signatureOnly = false)
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

            FnArg arg = new FnArg(argName.value.s, type, val, argName.pos);
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
        Node[] body;
        if (!signatureOnly)
            body = p.parseBody();
        else
            p.match(TokenKind.Semicolon);
        // p.consume(TokenKind.RBrace, "Esperado '}' após o corpo da função.");

        return new FnDecl(name.value.s, args, retType, body, p.getAndResetFlags(), name.pos);
    }

    ClassDecl parseClass(bool isInterface = false)
    {
        bool isAbstract = p.match(TokenKind.Abstract) || isInterface;
        bool isForeign = p.check(TokenKind.Foreign);
        if (isForeign)
            p.advance();
        Token name = p.consume(TokenKind.Identifier, "Esperado nome da classe.");
        dstring parent;
        dstring[] parentQualifier;
        if (p.match(TokenKind.Extends))
        {
            parent = p.consume(TokenKind.Identifier, "Esperado nome da superclasse.").value.s;
            while (p.match(TokenKind.Dot))
            {
                parentQualifier ~= parent;
                parent = p.consume(TokenKind.Identifier, "Esperado nome da superclasse após '.'.").value.s;
            }
        }
        ClassDecl node = new ClassDecl(name.value.s, parent, name.pos);
        node.superQualifier = parentQualifier;
        node.isAbstract = isAbstract;
        node.isInterface = isInterface;
        node.isForeign = isForeign;
        if (isInterface && parent.length)
            p.err.error(name.pos, "Herança de interfaces ainda não é suportada.");
        if (p.match(TokenKind.Mixins))
        {
            if (isInterface || isForeign)
                p.err.error(name.pos, "Composição mescla exige uma classe gerenciada.");
            do
            {
                node.mixinNames ~= p.consume(TokenKind.Identifier, "Esperado nome da classe em mescla.").value.s;
            }
            while (p.match(TokenKind.Comma));
        }
        if (p.match(TokenKind.Implements))
        {
            do
            {
                node.interfaceNames ~= p.consume(TokenKind.Identifier, "Esperado nome de interface.").value.s;
            }
            while (p.match(TokenKind.Comma));
        }
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
                TokenKind kind = p.advance().kind;
                int visibility = kind == TokenKind.Private ? 1 : kind == TokenKind.Protected ? 2 : 0;
                p.consume(TokenKind.LBrace, "Esperado bloco de visibilidade.");
                parseClassMembers(node, visibility);
                continue;
            }
            if (p.match(TokenKind.Enum))
            {
                VarDecl enumeration = cast(VarDecl) parseEnum();
                ClassField field = ClassField(enumeration.name, enumeration.type_expr, access, enumeration.pos);
                field.isEnum = true;
                field.value = enumeration.value;
                node.fields ~= field;
                continue;
            }
            Decorator[] decorators = p.parseDecorators();
            bool abstractMethod = p.match(TokenKind.Abstract) || node.isInterface;
            bool isStatic = p.match(TokenKind.Static);
            bool isAsync = p.match(TokenKind.Async);
            Token name = p.consumeName("Esperado propriedade ou método.");
            if (p.match(TokenKind.Colon))
            {
                TypeExpr type = p.parseType.parse();
                if (isStatic && (node.isInterface || node.isForeign))
                    p.err.errorCode(name.pos, unsupportedStaticField);
                if (isAsync)
                    p.err.errorCode(name.pos, asyncContext);
                ClassField field = ClassField(name.value.s, type, access, name.pos);
                field.isStatic = isStatic;
                if (p.match(TokenKind.Equals))
                {
                    field.value = p.parseExpr.parse();
                    if (node.isInterface || node.isForeign)
                        p.err.error(name.pos, "Inicializador exige atributo de classe gerenciada.");
                }
                if (p.match(TokenKind.LBrace))
                {
                    field.customAccess = true;
                    while (!p.isAtEnd() && !p.check(TokenKind.RBrace))
                    {
                        Token token = p.consume(TokenKind.Identifier, "Esperado obter ou definir.");
                        bool getter = token.value.s == "obter";
                        if (!getter && token.value.s != "definir")
                            p.err.error(token.pos, "Acessor desconhecido.");
                        if (getter)
                            field.readable = true;
                        else
                            field.writable = true;
                        if (p.check(TokenKind.LParen))
                        {
                            FnDecl method = cast(FnDecl) parseFnDecl(token);
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
                foreach (Decorator d; decorators)
                    if (d.name == "puro")
                        p.err.error(name.pos, "O decorador @puro exige uma função ou método estático.");
                node.fields ~= field;
                p.match(TokenKind.Semicolon);
            }
            else
            {
                // Uma palavra de método ainda sendo digitada não descarta a classe.
                if (p.recoverIncomplete && !p.check(TokenKind.LParen) && (p.isAtEnd() || p.check(TokenKind.RBrace)))
                {
                    p.err.errorCode(name.pos, expectedToken, "Esperado '(' ou ':' após nome do membro.");
                    continue;
                }
                FnDecl method = cast(FnDecl) parseFnDecl(name, abstractMethod || node.isForeign);
                method.isAbstract = abstractMethod;
                method.isAsync = isAsync;
                if (abstractMethod && (!node.isAbstract || access == 1 || isStatic
                        || name.value.s == "construtor" || name.value.s == "destrutor"))
                    p.err.error(name.pos, "Método abstrato exige classe abstrata/interface e não pode ser estático ou de ciclo de vida.");
                if (name.value.s == "destrutor")
                {
                    if (method.args.length || isStatic || access != 0
                            || (method.type_expr.toStr() != "qualquer" && method.type_expr.toStr() != "vazio"))
                        p.err.errorCode(name.pos, invalidDestructor);
                    method.type_expr = new TypeExprNamed("vazio", name.pos);
                }
                method.isMethod = true;
                method.isStatic = isStatic || node.isForeign;
                if (isStatic && name.value.s == "construtor")
                    p.err.errorCode(name.pos, staticConstructor);
                method.ownerClass = node;
                method.access = access;
                method.decorators = decorators;
                foreach (Decorator d; decorators)
                {
                    if (d.name == "puro")
                    {
                        if (d.keys.length)
                            p.err.error(name.pos, "O decorador @puro não aceita argumentos.");
                        method.ctfe_flags |= CTFEFlags.Pure;
                    }
                    else if (d.name == "nativo")
                    {
                        if (d.keys.length)
                            p.err.error(name.pos, "O decorador @nativo não aceita argumentos.");
                        method.isNative = true;
                    }
                    else if (d.name == "gpu")
                    {
                        if (d.keys.length)
                            p.err.error(name.pos, "O decorador @gpu não aceita argumentos.");
                        method.isGpu = true;
                    }
                    else if (d.name == "operador")
                    {
                        if (d.values.length != 1 || cast(StringLit) d.values[0] is null)
                            p.err.errorCode(name.pos, invalidOperatorSymbol, "");
                        else
                            method.operatorSymbol = (cast(StringLit) d.values[0]).value;
                    }
                }
                node.methods ~= method;
            }
        }
        p.consume(TokenKind.RBrace, "Esperado '}' após classe/bloco de visibilidade.");
    }

    Node parseEnum()
    {
        Token name = p.consume(TokenKind.Identifier, "Esperado nome de enum.");
        p.consume(TokenKind.LBrace, "Esperado '{'.");
        Node[] keys, values;
        bool[dstring] seen;
        long next;
        while (!p.isAtEnd() && !p.check(TokenKind.RBrace))
        {
            Token member = p.consumeName("Esperado membro de enum.");
            if (member.value.s in seen)
                p.err.error(member.pos, "Membro de enum duplicado.");
            seen[member.value.s] = true;
            long value = next;
            if (p.match(TokenKind.Equals))
            {
                bool negative = p.match(TokenKind.Minus);
                Token number = p.consume(TokenKind.Int, "Enum exige literal inteiro.");
                value = negative ? -number.value.i : number.value.i;
            }
            keys ~= new StringLit(member.value.s, member.pos);
            values ~= new IntLit(value, member.pos);
            if (value == long.max && !p.check(TokenKind.RBrace))
                p.err.error(member.pos, "Enum excede o intervalo inteiro.");
            next = value == long.max ? value : value + 1;
            if (!p.match(TokenKind.Comma))
                break;
        }
        p.consume(TokenKind.RBrace, "Esperado '}'.");
        MapLit members = new MapLit(keys, values, name.pos);
        members.readonly = true;
        VarDecl result = new VarDecl(name.value.s, members, true, new TypeExprNamed("dicionario", name.pos), name.pos);
        result.isEnum = true;
        return result;
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
            case TokenKind.Interface:
                return parseClass(true);
            case TokenKind.Enum:
                return parseEnum();
            case TokenKind.Async:
                p.consume(TokenKind.Fn, "Esperado função após assincrona.");
                FnDecl asynchronous = cast(FnDecl) parseFnDecl();
                asynchronous.isAsync = true;
                return asynchronous;
            case TokenKind.Fn:
                bool envelope = p.match(TokenKind.Of);
                if (envelope)
                {
                    Token marker = p.consumeName("Esperado decorador após função de.");
                    if (marker.value.s != "decorador")
                        p.err.error(marker.pos, "Esperado decorador.");
                }
                FnDecl fn = cast(FnDecl) parseFnDecl();
                fn.decoratorEnvelope = envelope;
                return fn;

            default:
                return new Identifier("null", tk.pos);
        }
    }
}
