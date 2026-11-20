module lsp.server;

import lsp.model;
import lsp.features;
import env : VERSION;
import lsp.evaluation;
import lsp.builtins : builtinMethods, builtinMethod;
import frontend;
import frontend.analysis;
import lsp.completion;
import std.json;
import std.stdio;
import std.string : strip, startsWith, indexOf, lastIndexOf, splitLines;
import std.algorithm.searching : count;
import std.conv : to;
import std.algorithm : sort, filter, canFind, min;
import std.array : array, join;
import std.file : exists, readText;
import std.path : absolutePath, asNormalizedPath;
import std.utf : validate;

immutable string[] tokenTypes = semanticTokenTypes;
immutable string[] tokenModifiers = semanticTokenModifiers;

class LanguageServer
{
    Document[string] documents;
    bool shutdownRequested;
    size_t analysisCount;
    JSONValue notify(string method, JSONValue params)
    {
        send(JSONValue(["jsonrpc": JSONValue("2.0"), "method": JSONValue(method), "params": params]));
        return JSONValue.init;
    }

    void send(JSONValue message)
    {
        string bytes = message.toString();
        stdout.write("Content-Length: ", bytes.length, "\r\n\r\n", bytes);
        stdout.flush();
    }

    string[string] overlays()
    {
        string[string] result;
        foreach (Document doc; documents)
            if (doc.isOpen)
                result[doc.path] = doc.text;
        return result;
    }

    Document document(JSONValue params)
    {
        string uri = str(get(params, "textDocument"), "uri");
        if (Document* found = uri in documents)
            return *found;
        return null;
    }

    Document ensure(JSONValue params)
    {
        Document doc = document(params);
        if (doc !is null)
            return doc;
        string uri = str(get(params, "textDocument"), "uri");
        string path = uriPath(uri);
        if (exists(path))
        {
            doc = new Document(uri, readText(path), 0);
            documents[uri] = doc;
            analyze(doc);
        }
        return doc;
    }

    void analyze(Document doc)
    {
        analysisCount++;
        doc.analysis = analyzeSource(doc.text, doc.path, overlays());
        doc.symbols = null;
        doc.visited = null;
        doc.dependencies = null;
        doc.expressionEnds = null;
        doc.expressions = null;
        doc.constantPreview = null;
        doc.expressionClasses = null;
        doc.expressionFunctions = null;
        doc.functions = null;
        doc.expressionTypes = null;
        doc.declarationScopes = null;
        doc.variableDeclarations = null;
        doc.index(doc.analysis.program);
        doc.finishIndex();
    }

    void publish(Document doc)
    {
        JSONValue[] diagnostics;
        foreach (const(Diagnostic) entry; doc.analysis.diagnostics.entries)
        {
            bool imported = entry.position !is null && entry.position.filename != doc.path;
            JSONValue diagnostic = JSONValue([
                "range": entry.position is null || imported ? rangeJSON(point(0, 0), point(0,
                        1)) : doc.positionRange(entry.position),
                "severity": JSONValue(entry.severity == Severity.Error
                        ? 1 : entry.severity == Severity.Warning ? 2 : 3),
                "code": JSONValue(entry.code),
                "source": JSONValue("cgd"),
                "message": JSONValue(imported ? "Em " ~ entry.position.filename ~ ": " ~ entry.message : entry.message)
            ]);
            diagnostics ~= diagnostic;
        }
        notify("textDocument/publishDiagnostics", JSONValue([
            "uri": JSONValue(doc.uri),
            "version": JSONValue(doc.revision),
            "diagnostics": arrayJSON(diagnostics)
        ]));
    }

    void changed(Document doc)
    {
        analyze(doc);
        publish(doc); // Imported buffers invalidate dependents; bounded open set, no filesystem scan.
        foreach (Document other; documents)
            if (other !is doc && doc.path in other.dependencies)
            {
                analyze(other);
                publish(other);
            }
    }

    JSONValue location(Document doc, Position position, size_t length)
    {
        string target = position.filename == doc.path ? doc.uri : fileURI(position.filename);
        Document origin = doc;
        foreach (Document open; documents)
            if (open.path == position.filename)
            {
                origin = open;
                target = open.uri;
                break;
            }
        if (origin.path != position.filename && exists(position.filename))
            origin = new Document(target, readText(position.filename), 0);
        return JSONValue(["uri": JSONValue(target), "range": origin.positionRange(position, length)]);
    }

    JSONValue initialize()
    {
        JSONValue[string] capabilities;
        capabilities["positionEncoding"] = JSONValue("utf-16");
        capabilities["textDocumentSync"] = JSONValue([
            "openClose": JSONValue(true),
            "change": JSONValue(2),
            "save": JSONValue(["includeText": JSONValue(false)])
        ]);
        foreach (string name; [
            "hoverProvider", "definitionProvider", "referencesProvider",
            "documentHighlightProvider", "documentSymbolProvider",
            "workspaceSymbolProvider", "foldingRangeProvider", "selectionRangeProvider",
            "codeActionProvider"
        ])
            capabilities[name] = JSONValue(true);
        capabilities["renameProvider"] = JSONValue(["prepareProvider": JSONValue(true)]);
        capabilities["completionProvider"] = JSONValue([
            "triggerCharacters": arrayJSON([JSONValue("."), JSONValue(":"), JSONValue("/")]),
            "resolveProvider": JSONValue(false)
        ]);
        capabilities["signatureHelpProvider"] = JSONValue([
            "triggerCharacters": arrayJSON([JSONValue("("), JSONValue(",")])
        ]);
        capabilities["documentFormattingProvider"] = JSONValue(true);
        capabilities["inlayHintProvider"] = JSONValue(true);
        capabilities["codeLensProvider"] = JSONValue(["resolveProvider": JSONValue(false)]);
        capabilities["documentLinkProvider"] = JSONValue(["resolveProvider": JSONValue(false)]);
        capabilities["semanticTokensProvider"] = JSONValue(
                [
            "legend": JSONValue([
                "tokenTypes": arrayJSON(tokenTypes.mapJSON()),
                "tokenModifiers": arrayJSON(tokenModifiers.mapJSON())
            ]),
            "full": JSONValue(true),
            "range": JSONValue(false)
        ]);
        return JSONValue([
            "capabilities": JSONValue(capabilities),
            "serverInfo": JSONValue(["name": JSONValue("CGD LSP"), "version": JSONValue(VERSION)])
        ]);
    }

    JSONValue semanticTokens(Document doc)
    {
        return buildSemanticTokens(doc);
    }

    JSONValue request(string method, JSONValue params)
    {
        if (method == "initialize")
            return initialize();
        if (method == "shutdown")
        {
            shutdownRequested = true;
            return JSONValue.init;
        }
        if (method == "cgd/status")
            return JSONValue([
            "analyses": JSONValue(analysisCount),
            "documents": JSONValue(documents.length)
        ]);
        if (method == "workspace/symbol")
        {
            JSONValue[] symbols;
            string query = str(params, "query");
            foreach (Document doc; documents)
                foreach (SymbolEntry symbol; doc.symbols)
                    if (symbol.declaration && symbol.name.canFind(query))
                        symbols ~= JSONValue([
                        "name": JSONValue(symbol.name),
                        "kind": JSONValue(symbol.kind == "class" ? 5 : symbol.kind == "function"
                                ? 12 : 13),
                        "location": location(doc, symbol.position, symbol.name.to!dstring.length)
            ]);
            return arrayJSON(symbols);
        }
        Document doc = ensure(params);
        if (doc is null)
            return JSONValue.init;
        JSONValue position = get(params, "position");
        SymbolEntry* selected = doc.symbolAt(position);
        if (method == "textDocument/semanticTokens/full")
            return semanticTokens(doc);
        if (method == "textDocument/formatting")
        {
            import frontend.formatter : formatDelegua;

            string formatted = formatDelegua(doc.text);
            if (formatted == doc.text)
                return arrayJSON([]);
            return arrayJSON([
                JSONValue([
                    "range": JSONValue([
                        "start": JSONValue(["line": JSONValue(0), "character": JSONValue(0)]),
                        "end": JSONValue([
                            "line": JSONValue(doc.lines.length),
                            "character": JSONValue(0)
                        ])
                    ]),
                    "newText": JSONValue(formatted)
                ])
            ]);
        }
        if (method == "textDocument/completion")
            return completions(doc, params);
        if (method == "textDocument/hover")
        {
            string content = selected is null ? "" : "```delegua\n" ~ selected.detail ~ "\n```";
            JSONValue hoverRange = selected is null ? JSONValue.init
                : doc.positionRange(selected.position, selected.name.to!dstring.length);
            FnDecl target;
            if (selected !is null && (selected.kind == "function" || selected.kind == "method"))
                if (FnDecl* functionNode = selected.key in doc.functions)
                    target = *functionNode;
            if (target !is null && target.classFactory is null)
            {
                bool proven;
                foreach (FnDecl pureFunction; doc.analysis.pureFunctions)
                    proven = proven || pureFunction is target;
                content ~= proven ? "\n\nPureza: comprovada para CTFE."
                    : "\n\nPureza: não comprovada para CTFE (sem anotação aprovada ou recurso não suportado).";
                content ~= "\n\nComptime: exige função aprovada, argumentos constantes e otimização `-o`; sem `-o`, a chamada executa em runtime.";
            }
            bool computed;
            if (!doc.analysis.diagnostics.hasErrors())
                if (Node expression = doc.previewAt(get(params, "position")))
                {
                    if (doc.constantPreview is null)
                        doc.constantPreview = new ConstantPreview(doc.analysis.pureFunctions);
                    if (Node value = doc.constantPreview.evaluate(expression))
                    {
                        computed = true;
                        content ~= "\n\nResultado em tempo de compilação:\n\n```delegua\n" ~ previewText(value)
                            ~ "\n```\n\nComptime: pré-computação comprovada; substituição habilitada com `-o`.";
                        hoverRange = doc.positionRange(expression.pos);
                    }
                }
            if (!computed && cast(CallExpr) doc.previewAt(position))
                content ~= "\n\nComptime nesta chamada: não pré-computada (sem prova de pureza, argumentos dinâmicos, falha ou limite da avaliação).";
            if (!content.length)
                return JSONValue.init;
            return JSONValue([
                "contents": JSONValue(["kind": JSONValue("markdown"),
                    "value": JSONValue(content)]),
                "range": hoverRange
            ]);
        }

        if (method == "textDocument/definition")
        {
            if (selected is null || !selected.key.length)
                return JSONValue.init;
            foreach (SymbolEntry symbol; doc.symbols)
                if (symbol.declaration && symbol.key == selected.key)
                    return location(doc, symbol.position, symbol.name.to!dstring.length);
            return JSONValue.init;
        }
        if (method == "textDocument/references" || method == "textDocument/documentHighlight")
        {
            JSONValue[] result;
            if (selected is null || !selected.key.length)
                return arrayJSON();
            foreach (Document other; documents)
                foreach (SymbolEntry symbol; other.symbols)
                    if (symbol.key == selected.key && (method != "textDocument/documentHighlight"
                            || symbol.position.filename == doc.path))
                    {
                        if (method == "textDocument/documentHighlight")
                            result ~= JSONValue([
                            "range": doc.positionRange(symbol.position,
                                    symbol.name.to!dstring.length),
                            "kind": JSONValue(1)
                        ]);
                        else
                            result ~= location(other, symbol.position, symbol.name.to!dstring.length);
                    }
            return arrayJSON(result);
        }
        if (method == "textDocument/prepareRename")
        {
            if (selected is null || !selected.key.length)
                return JSONValue.init;
            return JSONValue([
                "range": doc.positionRange(selected.position, selected.name.to!dstring.length),
                "placeholder": JSONValue(selected.name)
            ]);
        }
        if (method == "textDocument/rename")
        {
            string name = str(params, "newName");
            Diagnostics diagnostics = new Diagnostics;
            Token[] tokens = new Lexer(name, "rename", diagnostics).tokenizer();
            if (diagnostics.hasErrors() || tokens.length != 1
                    || tokens[0].kind != TokenKind.Identifier || name != tokens[0].value.s.to!string)
                throw new Exception("Nome de identificador inválido.");
            if (selected !is null)
                foreach (SymbolEntry symbol; doc.symbols)
                    if (symbol.declaration && symbol.name == name && symbol.key != selected.key
                            && symbol.position.filename == selected.position.filename)
                        throw new Exception("Nome já declarado; renomeação recusada para preservar resolução.");
            JSONValue[string] edits;
            bool[string] unique;
            if (selected !is null && selected.key.length)
                foreach (Document other; documents)
                    foreach (SymbolEntry symbol; other.symbols)
                        if (symbol.key == selected.key)
                        {
                            string key = Document.identity(symbol.position);
                            if (key in unique)
                                continue;
                            unique[key] = true;
                            JSONValue loc = location(other, symbol.position, symbol.name.to!dstring.length);
                            string uri = str(loc, "uri");
                            JSONValue edit = JSONValue([
                                "range": get(loc, "range"),
                                "newText": JSONValue(name)
                            ]);
                            if (uri !in edits)
                                edits[uri] = arrayJSON();
                            edits[uri].array ~= edit;
                        }
            return JSONValue(["changes": JSONValue(edits)]);
        }
        if (method == "textDocument/documentSymbol")
        {
            JSONValue[] result;
            foreach (SymbolEntry symbol; doc.symbols)
                if (symbol.declaration && symbol.position.filename == doc.path)
                {
                    JSONValue range = doc.positionRange(symbol.position, symbol.name.to!dstring.length);
                    result ~= JSONValue([
                        "name": JSONValue(symbol.name),
                        "detail": JSONValue(symbol.detail),
                        "kind": JSONValue(symbol.kind == "class" ? 5 : symbol.kind == "function"
                                ? 12 : symbol.kind == "method" ? 6 : 13),
                        "range": range,
                        "selectionRange": range
                    ]);
                }
            return arrayJSON(result);
        }
        if (method == "textDocument/signatureHelp")
        {
            struct Frame
            {
                TokenKind opening;
                Token name;
                size_t argument;
            }

            Frame[] stack;
            Token previous;
            long row = integer(position, "line") + 1;
            uint col = doc.codepoints(cast(uint)(row - 1), cast(uint) integer(position, "character")) + 1;
            foreach (Token token; doc.analysis.tokens)
            {
                if (token.pos.start.line > row || (token.pos.start.line == row && token.pos.start.offset >= col))
                    break;
                if (token.kind == TokenKind.Comment)
                    continue;
                if (token.kind == TokenKind.LParen || token.kind == TokenKind.LBracket || token.kind == TokenKind
                        .LBrace)
                {
                    Token name;
                    if (token.kind == TokenKind.LParen && previous !is null
                            && (previous.kind == TokenKind.Identifier || previous.kind <= TokenKind.Of))
                        name = previous;
                    stack ~= Frame(token.kind, name, 0);
                }
                else if (token.kind == TokenKind.RParen || token.kind == TokenKind.RBracket
                        || token.kind == TokenKind.RBrace)
                {
                    if (stack.length)
                        stack.length--;
                }
                else if (token.kind == TokenKind.Comma && stack.length)
                    stack[$ - 1].argument++;
                previous = token;
            }
            foreach_reverse (Frame frame; stack)
                if (frame.name !is null)
                {
                    string name = frame.name.value.s.to!string;
                    string signature;
                    FnDecl declaration;
                    SymbolEntry* selectedName = doc.symbolAt(get(doc.positionRange(frame.name.pos), "start"));
                    if (selectedName !is null && (selectedName.kind == "function"
                            || selectedName.kind == "method" || selectedName.kind == "class"))
                    {
                        signature = selectedName.detail;
                        if (FnDecl* known = selectedName.key in doc.functions)
                            declaration = *known;
                    }
                    if (!signature.length)
                        foreach (SymbolEntry symbol; doc.symbols)
                            if (symbol.name == name && (symbol.kind == "function" || symbol.kind == "method"))
                            {
                                signature = symbol.detail;
                                break;
                            }
                    if (!signature.length && doc.analysis.context !is null)
                        if (Symbol* symbol = doc.analysis.context.get(name.to!dstring))
                            if (symbol.isFn())
                            {
                                declaration = (cast(SymbolFn*) symbol).node;
                                signature = doc.signature(declaration);
                            }
                    if (signature.length)
                    {
                        JSONValue[] parameters;
                        if (declaration !is null)
                            foreach (FnArg argument; declaration.args)
                                parameters ~= JSONValue([
                                "label": JSONValue(argument.name.to!string ~ ": " ~ (argument.type_expr is null
                                        ? "qualquer" : argument.type_expr.toStr().to!string))
                        ]);
                        ptrdiff_t opening = signature.indexOf('(');
                        ptrdiff_t closing = signature.lastIndexOf(')');
                        if (declaration is null && opening >= 0 && closing > opening + 1)
                        {
                            import std.string : split;

                            foreach (string parameter; signature[opening + 1 .. closing].split(", "))
                                parameters ~= JSONValue(["label": JSONValue(parameter)]);
                        }
                        size_t active = parameters.length ? min(frame.argument, parameters.length - 1) : 0;
                        return JSONValue([
                            "signatures": arrayJSON([
                                JSONValue([
                                    "label": JSONValue(signature),
                                    "parameters": arrayJSON(parameters),
                                    "activeParameter": JSONValue(active)
                                ])
                            ]),
                            "activeSignature": JSONValue(0),
                            "activeParameter": JSONValue(active)
                        ]);
                    }
                    break;
                }
            return JSONValue.init;
        }
        if (method == "textDocument/foldingRange")
        {
            JSONValue[] result;
            Token[] stack;
            foreach (Token token; doc.analysis.tokens)
            {
                if (token.kind == TokenKind.LBrace || token.kind == TokenKind.LBracket)
                    stack ~= token;
                else if ((token.kind == TokenKind.RBrace || token.kind == TokenKind.RBracket) && stack.length)
                {
                    Token first = stack[$ - 1];
                    stack.length--;
                    if (first.pos.start.line < token.pos.start.line)
                        result ~= JSONValue([
                        "startLine": JSONValue(first.pos.start.line - 1),
                        "endLine": JSONValue(token.pos.start.line - 1)
                    ]);
                }
            }
            return arrayJSON(result);
        }
        if (method == "textDocument/selectionRange")
        {
            JSONValue[] result;
            foreach (JSONValue pos; get(params, "positions").array)
            {
                Token token = doc.tokenAt(pos);
                JSONValue range = token is null ? rangeJSON(pos, pos) : doc.positionRange(token.pos);
                result ~= JSONValue(["range": range]);
            }
            return arrayJSON(result);
        }
        if (method == "textDocument/codeLens")
            return arrayJSON([
            JSONValue([
                "range": rangeJSON(point(0, 0), point(0, 0)),
                "command": JSONValue([
                    "title": JSONValue("▶ Compilar e executar"),
                    "command": JSONValue("cgd.executar")
                ])
            ]),
            JSONValue([
                "range": rangeJSON(point(0, 0), point(0, 0)),
                "command": JSONValue([
                    "title": JSONValue("Verificar"),
                    "command": JSONValue("cgd.verificar")
                ])
            ])
        ]);
        if (method == "textDocument/documentLink")
        {
            JSONValue[] links;
            bool[Node] seen;
            void visit(Node node)
            {
                if (node is null || node in seen)
                    return;
                seen[node] = true;
                if (ImportExpr imported = cast(ImportExpr) node)
                    if (imported.target !is null && imported.pos.filename == doc.path)
                        links ~= JSONValue([
                        "range": doc.positionRange(imported.path.pos),
                        "target": JSONValue(fileURI(imported.target.path)),
                        "tooltip": JSONValue("Abrir módulo Delégua")
                ]);
                foreach (Node child; childNodes(node))
                    visit(child);
            }

            visit(doc.analysis.program);
            return arrayJSON(links);
        }
        if (method == "textDocument/inlayHint")
        {
            JSONValue[] result;
            foreach (SymbolEntry symbol; doc.symbols)
                if (symbol.declaration && symbol.kind == "variable" && symbol.position.filename == doc.path)
                {
                    if (VarDecl* declaration = symbol.key in doc.variableDeclarations)
                        if ((*declaration).type_expr !is null)
                            continue;
                    JSONValue range = doc.positionRange(symbol.position, symbol.name.to!dstring.length);
                    long colon = symbol.detail.indexOf(": ");
                    if (colon >= 0)
                        result ~= JSONValue([
                        "position": get(range, "end"),
                        "label": JSONValue(": " ~ symbol.detail[colon + 2 .. $]),
                        "kind": JSONValue(1),
                        "tooltip": JSONValue(
                                "Tipo inferido pelo compilador. Dica virtual: o arquivo não é alterado."),
                        "paddingLeft": JSONValue(false)
                    ]);
                }
            return arrayJSON(result);
        }
        if (method == "textDocument/codeAction")
        {
            JSONValue[] actions;
            foreach (const(Diagnostic) diagnostic; doc.analysis.diagnostics.entries)
                if (diagnostic.code == "H3001" && diagnostic.position !is null
                        && diagnostic.position.filename == doc.path)
                {
                    ptrdiff_t first = diagnostic.message.indexOf('\'');
                    string rest = first >= 0 ? diagnostic.message[first + 1 .. $] : "";
                    ptrdiff_t last = rest.indexOf('\'');
                    if (last < 0)
                        continue;
                    string replacement = rest[0 .. last];
                    JSONValue range = doc.positionRange(diagnostic.position);
                    JSONValue edit = JSONValue(["range": range, "newText": JSONValue(replacement)]);
                    actions ~= JSONValue([
                        "title": JSONValue("Substituir por '" ~ replacement ~ "'"),
                        "kind": JSONValue("quickfix"),
                        "isPreferred": JSONValue(true),
                        "edit": JSONValue(["changes": JSONValue([doc.uri: arrayJSON([edit])])])
                    ]);
                }
            return arrayJSON(actions);
        }
        return JSONValue.init;
    }

    void notification(string method, JSONValue params)
    {
        if (method == "textDocument/didOpen")
        {
            JSONValue info = get(params, "textDocument");
            Document doc = new Document(str(info, "uri"), str(info, "text"), integer(info, "version"));
            doc.isOpen = true;
            documents[doc.uri] = doc;
            changed(doc);
        }
        else if (method == "textDocument/didChange")
        {
            Document doc = document(params);
            if (doc is null)
                return;
            JSONValue info = get(params, "textDocument");
            long revision = integer(info, "version");
            if (revision <= doc.revision)
                return;
            foreach (JSONValue change; get(params, "contentChanges").array)
            {
                JSONValue range = get(change, "range");
                if (range.type == JSONType.object)
                {
                    JSONValue start = get(range, "start"), end = get(range, "end");
                    ulong a = doc.byteOffset(cast(uint) integer(start, "line"),
                            cast(uint) integer(start, "character")), b = doc.byteOffset(cast(uint) integer(end,
                            "line"), cast(uint) integer(end, "character"));
                    doc.text = doc.text[0 .. a] ~ str(change, "text") ~ doc.text[b .. $];
                }
                else
                    doc.text = str(change, "text");
                doc.lines = doc.text.splitLines();
            }
            doc.revision = revision;
            changed(doc);
        }
        else if (method == "workspace/didChangeWatchedFiles")
        {
            foreach (JSONValue change; get(params, "changes").array)
            {
                string path = uriPath(str(change, "uri"));
                foreach (Document doc; documents)
                    if (path in doc.dependencies)
                    {
                        analyze(doc);
                        publish(doc);
                    }
            }
        }
        else if (method == "textDocument/didClose")
        {
            string uri = str(get(params, "textDocument"), "uri");
            string path = uriPath(uri);
            documents.remove(uri);
            notify("textDocument/publishDiagnostics", JSONValue([
                "uri": JSONValue(uri),
                "diagnostics": arrayJSON()
            ]));
            foreach (Document other; documents)
                if (path in other.dependencies)
                {
                    analyze(other);
                    publish(other);
                }
        }
    }

    void run()
    {
        while (!stdin.eof)
        {
            string line;
            size_t length;
            bool header;
            while ((line = stdin.readln()).length)
            {
                if (line == "\r\n" || line == "\n")
                {
                    header = true;
                    break;
                }
                if (line.length > 8192)
                    throw new Exception("Header LSP grande demais.");
                if (line.startsWith("Content-Length:"))
                    length = line[15 .. $].strip.to!size_t;
            }
            if (!header)
                break;
            if (length > 8 * 1024 * 1024)
                throw new Exception("Mensagem LSP grande demais.");
            ubyte[] buffer = new ubyte[length];
            size_t read;
            while (read < length)
            {
                ubyte[] part = stdin.rawRead(buffer[read .. $]);
                if (!part.length)
                    return;
                read += part.length;
            }
            JSONValue message;
            try
            {
                message = parseJSON(cast(string) buffer);
            }
            catch (Exception)
            {
                continue;
            }
            string method = str(message, "method");
            JSONValue params = get(message, "params"), id = get(message, "id");
            if (method == "exit")
                return;
            try
            {
                if (message.type == JSONType.object && "id" in message.object)
                {
                    JSONValue result = request(method, params);
                    send(JSONValue(["jsonrpc": JSONValue("2.0"), "id": id, "result": result]));
                }
                else
                    notification(method, params);
            }
            catch (Exception error)
            {
                if (message.type == JSONType.object && "id" in message.object)
                    send(JSONValue([
                    "jsonrpc": JSONValue("2.0"),
                    "id": id,
                    "error": JSONValue(["code": JSONValue(-32603), "message": JSONValue(error.msg)])
                ]));
                else
                    stderr.writeln("CGD LSP: ", error.msg);
            }
        }
    }
}

private JSONValue[] mapJSON(const(string)[] values)
{
    JSONValue[] result;
    foreach (const(string) value; values)
        result ~= JSONValue(value);
    return result;
}

void runLanguageServer()
{
    new LanguageServer().run();
}
