module lsp.completion;

import frontend;
import frontend.semantic.members;
import lsp.model;
import lsp.builtins : builtinMethod, builtinMethods;
import std.json;
import std.conv : to;
import std.string : lastIndexOf, startsWith;

private Context nativeContext;

JSONValue completionItem(string name, string kind, string detail)
{
    return JSONValue([
        "label": JSONValue(name),
        "kind": JSONValue(kind == "class" ? 7 : kind == "method" ? 2 : kind == "function"
                ? 3 : kind == "property" ? 5 : kind == "keyword" ? 14 : 6),
        "detail": JSONValue(detail)
    ]);
}

JSONValue completions(Document doc, JSONValue params)
{
    JSONValue[] items;
    bool[string] names;
    JSONValue position = get(params, "position");
    size_t offset = doc.byteOffset(cast(uint) integer(position, "line"), cast(uint) integer(position, "character"));
    string prefix = doc.text[0 .. offset];
    long dot = prefix.lastIndexOf('.');
    bool member = dot >= 0;
    if (member)
        foreach (dchar ch; prefix[dot + 1 .. $])
            if (!(ch == '_' || ch >= 'a' && ch <= 'z' || ch >= 'A' && ch <= 'Z' || ch >= '0' && ch <= '9' || ch >= 128))
                member = false;
    if (member)
    {
        uint line = 1, column = 1;
        foreach (dchar ch; prefix[0 .. dot])
        {
            if (ch == '\n')
            {
                line++;
                column = 1;
            }
            else
                column++;
        }
        ulong dotKey = Document.offsetKey(line, column);
        foreach (Token token; doc.analysis.tokens)
            if (token.kind != TokenKind.Comment && Document.offsetKey(token.pos.end.line,
                    token.pos.end.offset) <= dotKey)
            {
                line = token.pos.end.line;
                column = token.pos.end.offset;
            }
        Node node;
        bool superReceiver;
        if (Node* receiver = Document.offsetKey(line, column) in doc.expressionEnds)
            node = *receiver;
        if (node is null)
            foreach (Token token; doc.analysis.tokens)
                if ((token.kind == TokenKind.This || token.kind == TokenKind.Super)
                        && token.pos.end.line == line && token.pos.end.offset == column)
                {
                    FnDecl method = doc.functionAt(position);
                    if (method !is null && method.isMethod && !method.isStatic)
                    {
                        Identifier self = new Identifier("isto", token.pos);
                        superReceiver = token.kind == TokenKind.Super;
                        self.lexicalClass = superReceiver ? method.ownerClass.superClass : method.ownerClass;
                        node = self;
                    }
                }
        if (node is null)
            foreach (Token token; doc.analysis.tokens)
                if (token.kind == TokenKind.Identifier && token.pos.end.line == line && token.pos.end.offset == column)
                    foreach_reverse (SymbolEntry symbol; doc.symbols)
                        if (symbol.declaration && symbol.kind == "variable"
                                && symbol.name == token.value.s.to!string
                                && symbol.position.filename == doc.path && doc.visible(symbol, position))
                            if (VarDecl* declaration = symbol.key in doc.variableDeclarations)
                            {
                                Identifier id = new Identifier(token.value.s, token.pos);
                                id.variableRef = *declaration;
                                node = id;
                                break;
                            }
        if (node !is null)
        {
            MapLit enumMembers;
            if (Identifier enumReceiver = cast(Identifier) node)
                if (enumReceiver.variableRef !is null && enumReceiver.variableRef.isEnum)
                    enumMembers = cast(MapLit) enumReceiver.variableRef.value;
            if (MemberExpr enumReceiver = cast(MemberExpr) node)
                enumMembers = enumReceiver.enumMembers;
            if (enumMembers !is null)
            {
                foreach (Node key; enumMembers.keys)
                    if (StringLit name = cast(StringLit) key)
                    {
                        JSONValue item = completionItem(name.value.to!string, "variable", "membro de enum");
                        item["kind"] = JSONValue(20);
                        items ~= item;
                    }
                return JSONValue(["isIncomplete": JSONValue(false), "items": arrayJSON(items)]);
            }
            if (Identifier id = cast(Identifier) node)
                if (id.variableRef !is null)
                    if (ImportExpr imported = cast(ImportExpr) id.variableRef.value)
                        if (imported.target !is null)
                        {
                            foreach (Node exported; imported.target.program.body)
                            {
                                if (FnDecl fn = cast(FnDecl) exported)
                                    items ~= completionItem(fn.fn.to!string, "function", doc.signature(fn));
                                else if (ClassDecl cls = cast(ClassDecl) exported)
                                    items ~= completionItem(cls.name.to!string, "class",
                                            "classe " ~ cls.name.to!string);
                                else if (VarDecl variable = cast(VarDecl) exported)
                                    if (!variable.name.to!string.startsWith("#"))
                                        items ~= completionItem(variable.name.to!string, "variable", "exportação");
                            }
                            return JSONValue([
                                "isIncomplete": JSONValue(false),
                                "items": arrayJSON(items)
                            ]);
                        }
            if (ClassDecl cls = doc.instanceClass(node))
            {
                bool classReceiver = (node in doc.expressionClasses) !is null;
                FnDecl enclosing = doc.functionAt(position);
                ClassDecl caller = enclosing is null ? null : enclosing.ownerClass;
                if (Identifier receiver = cast(Identifier) node)
                {
                    classReceiver = classReceiver || receiver.classRef !is null;
                }
                bool[ClassDecl] seen;
                void visitClass(ClassDecl current)
                {
                    if (current is null || current in seen)
                        return;
                    seen[current] = true;
                    foreach (FnDecl method; current.methods)
                    {
                        string name = method.fn.to!string;
                        if (name in names)
                            continue;
                        names[name] = true;
                        if ((!classReceiver || method.isStatic) && resolveClassMember(cls,
                                method.fn).visibleFrom(caller) && method.fn != "construtor"
                                && method.fn != "destrutor" && !name.startsWith("#"))
                            items ~= completionItem(name, "method", doc.signature(method));
                    }
                    foreach (ClassField field; current.fields)
                    {
                        string name = field.name.to!string;
                        if (name in names)
                            continue;
                        names[name] = true;
                        if ((!classReceiver || field.isEnum || field.isStatic) && !superReceiver
                                && resolveClassMember(cls, field.name).visibleFrom(caller))
                            items ~= completionItem(name, "property",
                                    "campo " ~ name ~ ": " ~ field.type.toStr().to!string);
                    }
                    foreach_reverse (ClassDecl mixinClass; current.mixins)
                        visitClass(mixinClass);
                    visitClass(current.superClass);
                }

                visitClass(cls);
                return JSONValue(["isIncomplete": JSONValue(false), "items": arrayJSON(items)]);
            }
        }
        TypeSema receiverType = doc.expressionType(node);
        Token literal;
        foreach (Token token; doc.analysis.tokens)
            if (token.pos.end.line == line && token.pos.end.offset == column)
                literal = token;
        if (receiverType is null && literal !is null)
        {
            if (literal.kind == TokenKind.String)
                receiverType = new TypeSemaBuiltin(TypeSemaBase.String);
            else if (literal.kind == TokenKind.Int)
                receiverType = new TypeSemaBuiltin(TypeSemaBase.Int);
            else if (literal.kind == TokenKind.Double)
                receiverType = new TypeSemaBuiltin(TypeSemaBase.Double);
        }
        foreach (string name; builtinMethods(receiverType))
            items ~= completionItem(name, "method", doc.signature(builtinMethod(receiverType, name)));
        return JSONValue(["isIncomplete": JSONValue(false), "items": arrayJSON(items)]);
    }
    foreach_reverse (SymbolEntry symbol; doc.symbols)
        if (symbol.declaration && symbol.position.filename == doc.path && doc.visible(symbol,
                position) && symbol.name !in names)
        {
            names[symbol.name] = true;
            items ~= completionItem(symbol.name, symbol.kind, symbol.detail);
        }
    if (nativeContext is null)
    {
        nativeContext = new Context;
        new DeclarationAnalysis(nativeContext, new TypeRegistry, new Diagnostics).analyze(new Program([
        ]));
    }
    foreach (Scope scopeEntry; nativeContext.scopes)
        foreach (dstring name; scopeEntry.names())
            if (name.to!string !in names)
            {
                Symbol* sym = scopeEntry.get(name);
                if (sym !is null && sym.isFn())
                {
                    FnDecl fn = (cast(SymbolFn*) sym).node;
                    items ~= completionItem(name.to!string, "function", doc.signature(fn));
                }
            }
    items ~= completionItem("Promessa", "class", "tipo intrínseco Promessa<T>; sem construção implícita");
    foreach (dstring name, TokenKind kind; keywords)
        items ~= completionItem(name.to!string, "keyword", "palavra-chave");
    return JSONValue(["isIncomplete": JSONValue(false), "items": arrayJSON(items)]);
}
