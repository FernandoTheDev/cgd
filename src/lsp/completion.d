module lsp.completion;

import frontend;
import frontend.modules : CgdLibraryEntry, discoverModuleRoots, listCgdLibraries;
import frontend.semantic.members;
import lsp.model;
import lsp.builtins : builtinMethod, builtinMethods;
import std.algorithm : sort;
import std.array : split;
import std.file : DirEntry, FileException, SpanMode, dirEntries, exists, isDir;
import std.json;
import std.conv : to;
import std.path : extension, relativePath, stripExtension;
import std.string : endsWith, lastIndexOf, replace, startsWith, stripLeft, stripRight;

private Context nativeContext;

private bool isIdentChar(dchar ch)
{
    return ch == '_' || (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z')
        || (ch >= '0' && ch <= '9') || ch >= 128;
}

private bool isModulePathChar(char ch)
{
    return cast(ubyte) ch >= 128 || (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0'
            && ch <= '9') || ch == '_' || ch == '-' || ch == '/' || ch == ':';
}

private bool isDottedModuleChar(char ch)
{
    return cast(ubyte) ch >= 128 || (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0'
            && ch <= '9') || ch == '_' || ch == '.';
}

private bool importStatementContext(string prefix, out string typed, out size_t lineStart, out size_t contentStart)
{
    long nl = prefix.lastIndexOf('\n');
    lineStart = nl >= 0 ? cast(size_t)(nl + 1) : 0;
    string currentLine = prefix[lineStart .. $];
    string trimmed = currentLine.stripLeft();
    size_t leading = currentLine.length - trimmed.length;
    if (!trimmed.startsWith("importar"))
        return false;
    string afterKw = trimmed["importar".length .. $];
    if (!afterKw.length || (afterKw[0] != ' ' && afterKw[0] != '\t'))
        return false;
    string afterSpaces = afterKw.stripLeft();
    if (afterSpaces.startsWith("(") || afterSpaces.startsWith("\"") || afterSpaces.startsWith("'"))
        return false;
    foreach (char ch; afterSpaces)
        if (!isDottedModuleChar(ch))
            return false;
    size_t spacesLen = afterKw.length - afterSpaces.length;
    contentStart = lineStart + leading + "importar".length + spacesLen;
    typed = afterSpaces;
    return true;
}

private string[] extractDottedChainBeforeDot(string prefix, size_t dotIndex)
{
    size_t end = dotIndex;
    while (end > 0 && (prefix[end - 1] == ' ' || prefix[end - 1] == '\t'))
        end--;
    size_t start = end;
    while (start > 0)
    {
        char ch = prefix[start - 1];
        if (isDottedModuleChar(ch))
            start--;
        else
            break;
    }
    if (start >= end)
        return null;
    string raw = prefix[start .. end];
    if (!raw.length || raw.startsWith(".") || raw.endsWith("."))
        return null;
    string[] parts = raw.split(".");
    foreach (string part; parts)
        if (!part.length)
            return null;
    return parts;
}

private void appendModuleMembers(Document doc, ModuleUnit mod, ref JSONValue[] items, ref bool[string] names)
{
    if (mod is null || mod.program is null)
        return;
    foreach (Node exported; mod.program.body)
    {
        if (FnDecl fn = cast(FnDecl) exported)
        {
            string name = fn.fn.to!string;
            if (name !in names && !name.startsWith("#"))
            {
                names[name] = true;
                items ~= completionItem(name, "function", doc.signature(fn));
            }
        }
        else if (ClassDecl cls = cast(ClassDecl) exported)
        {
            string name = cls.name.to!string;
            if (name !in names && !name.startsWith("#"))
            {
                names[name] = true;
                items ~= completionItem(name, "class", "classe " ~ name);
            }
        }
        else if (VarDecl variable = cast(VarDecl) exported)
        {
            string name = variable.name.to!string;
            if (name !in names && !name.startsWith("#"))
            {
                names[name] = true;
                string detail = variable.isEnum ? "enum " ~ name : "exportação";
                items ~= completionItem(name, "variable", detail);
            }
        }
    }
}

private string[] listProjectModuleNames(string docPath)
{
    string[] found;
    bool[string] seen;
    string[] roots = discoverModuleRoots(docPath);
    foreach (string root; roots)
    {
        if (!exists(root) || !isDir(root))
            continue;
        size_t scanned = 0;
        try
        {
            foreach (DirEntry entry; dirEntries(root, SpanMode.breadth))
            {
                if (++scanned > 512)
                    break;
                if (!entry.isFile || extension(entry.name) != ".delegua")
                    continue;
                string rel = relativePath(entry.name, root).replace("\\", "/");
                if (rel.startsWith("compilacao/") || rel.startsWith("out/") || rel.startsWith("."))
                    continue;
                string withoutExt = stripExtension(rel);
                if (withoutExt.endsWith("/mod"))
                    withoutExt = withoutExt[0 .. $ - 4];
                else if (withoutExt.endsWith("/indice"))
                    withoutExt = withoutExt[0 .. $ - 7];
                string dotted = withoutExt.replace("/", ".");
                if (!dotted.length || dotted in seen)
                    continue;
                seen[dotted] = true;
                found ~= dotted;
            }
        }
        catch (FileException)
        {
            continue;
        }
    }
    found.sort();
    return found;
}

private bool importStringContext(string prefix, out string typed, out size_t lineStart, out size_t contentStart)
{
    long nl = prefix.lastIndexOf('\n');
    lineStart = nl >= 0 ? cast(size_t)(nl + 1) : 0;
    string currentLine = prefix[lineStart .. $];
    char quote = 0;
    bool escaped;
    size_t quoteIndex;
    foreach (size_t i, char ch; currentLine)
    {
        if (quote)
        {
            if (escaped)
                escaped = false;
            else if (ch == '\\')
                escaped = true;
            else if (ch == quote)
                quote = 0;
        }
        else if (ch == '"' || ch == '\'')
        {
            quote = ch;
            quoteIndex = i;
        }
    }
    if (!quote)
        return false;
    string beforeQuote = currentLine[0 .. quoteIndex].stripRight;
    if (!beforeQuote.endsWith("("))
        return false;
    string beforeParen = beforeQuote[0 .. $ - 1].stripRight;
    if (!beforeParen.endsWith("importar"))
        return false;
    if (beforeParen.length > "importar".length)
    {
        char prev = beforeParen[$ - "importar".length - 1];
        bool wordChar = cast(ubyte) prev >= 128 || (prev >= 'a' && prev <= 'z') || (prev >= 'A'
                && prev <= 'Z') || (prev >= '0' && prev <= '9') || prev == '_';
        if (wordChar)
            return false;
    }
    contentStart = lineStart + quoteIndex + 1;
    typed = currentLine[quoteIndex + 1 .. $];
    return true;
}

JSONValue completionItem(string name, string kind, string detail)
{
    return JSONValue([
        "label": JSONValue(name),
        "kind": JSONValue(kind == "class" ? 7 : kind == "method" ? 2 : kind == "function"
                ? 3 : kind == "property" ? 5 : kind == "keyword" ? 14 : kind == "module" ? 9 : 6),
        "detail": JSONValue(detail)
    ]);
}

JSONValue completions(Document doc, JSONValue params)
{
    JSONValue[] items;
    bool[string] names;
    JSONValue position = get(params, "position");
    uint lineIndex = cast(uint) integer(position, "line");
    uint characterIndex = cast(uint) integer(position, "character");
    size_t offset = doc.byteOffset(lineIndex, characterIndex);
    string prefix = doc.text[0 .. offset];
    // Completion de anotações após '@' (sem novas keywords)
    {
        size_t p = prefix.length;
        while (p > 0 && isIdentChar(prefix[p - 1]))
            p--;
        if (p > 0 && prefix[p - 1] == '@')
        {
            string typedAnn = prefix[p .. $];
            struct AnnSpec
            {
                string name;
                string detail;
            }
            immutable AnnSpec[] anns = [
                AnnSpec("nativo", "Compilação direta C99 sem boxing nem GC"),
                AnnSpec("pilha", "Classe por valor com layout C struct na stack"),
                AnnSpec("valor", "Alias de @pilha: classe por valor com layout C"),
                AnnSpec("operador", "Sobrecarga de operador (@operador(\"+\"), \"*\", \"==\", \"[]\", ...)"),
                AnnSpec("quando", "Compilação condicional estrutural (@quando(Compilacao.sistemaOperacional() == \"linux\"))"),
                AnnSpec("puro", "Função/método estático puro elegível para CTFE"),
                AnnSpec("gpu", "Kernel numérico verificável para backend CPU/GPU"),
                AnnSpec("definicao", "Ligação FFI C explícita (@definicao(biblioteca = \"...\", abi = \"c\"))")
            ];
            foreach (immutable AnnSpec a; anns)
                if (!typedAnn.length || a.name.startsWith(typedAnn))
                    items ~= completionItem(a.name, "keyword", "@" ~ a.name ~ " — " ~ a.detail);
            return JSONValue(["isIncomplete": JSONValue(false), "items": arrayJSON(items)]);
        }
    }
    string importTyped;
    size_t importLineStart;
    size_t importContentStart;
    if (importStringContext(prefix, importTyped, importLineStart, importContentStart))
    {
        if (importTyped.startsWith("cgd:") || "cgd:".startsWith(importTyped))
        {
            size_t endOffset = offset;
            while (endOffset < doc.text.length && doc.text[endOffset] != '\n'
                    && doc.text[endOffset] != '"' && doc.text[endOffset] != '\''
                    && isModulePathChar(doc.text[endOffset]))
                endOffset++;
            uint startCol = doc.utf16(lineIndex,
                    cast(uint) doc.text[importLineStart .. importContentStart].to!dstring.length);
            uint endCol = doc.utf16(lineIndex, cast(uint) doc.text[importLineStart .. endOffset].to!dstring.length);
            JSONValue editRange = rangeJSON(point(lineIndex, startCol), point(lineIndex, endCol));
            string filterPrefix = importTyped.startsWith("cgd:") ? importTyped[4 .. $] : "";
            foreach (CgdLibraryEntry entry; listCgdLibraries())
            {
                if (filterPrefix.length && !entry.name.startsWith(filterPrefix))
                    continue;
                string fullName = "cgd:" ~ entry.name;
                string detail = entry.fromUserDir ? "~/.delegua/cgd/" ~ entry.name ~ ".delegua" : entry.path;
                JSONValue item = completionItem(fullName, "module", detail);
                item["filterText"] = JSONValue(fullName);
                item["textEdit"] = JSONValue(["range": editRange, "newText": JSONValue(fullName)]);
                items ~= item;
            }
            return JSONValue(["isIncomplete": JSONValue(false), "items": arrayJSON(items)]);
        }
    }
    if (importStatementContext(prefix, importTyped, importLineStart, importContentStart))
    {
        size_t endOffset = offset;
        while (endOffset < doc.text.length && doc.text[endOffset] != '\n'
                && isDottedModuleChar(doc.text[endOffset]))
            endOffset++;
        uint startCol = doc.utf16(lineIndex,
                cast(uint) doc.text[importLineStart .. importContentStart].to!dstring.length);
        uint endCol = doc.utf16(lineIndex, cast(uint) doc.text[importLineStart .. endOffset].to!dstring.length);
        JSONValue editRange = rangeJSON(point(lineIndex, startCol), point(lineIndex, endCol));
        foreach (string modName; listProjectModuleNames(doc.path))
        {
            if (importTyped.length && !modName.startsWith(importTyped))
                continue;
            if (modName in names)
                continue;
            names[modName] = true;
            JSONValue item = completionItem(modName, "module", "módulo do projeto");
            item["filterText"] = JSONValue(modName);
            item["textEdit"] = JSONValue(["range": editRange, "newText": JSONValue(modName)]);
            items ~= item;
        }
        foreach (CgdLibraryEntry entry; listCgdLibraries())
        {
            string dotted = "cgd." ~ entry.name.replace("/", ".");
            if (importTyped.length && !dotted.startsWith(importTyped))
                continue;
            if (dotted in names)
                continue;
            names[dotted] = true;
            string detail = entry.fromUserDir ? "~/.delegua/cgd/" ~ entry.name ~ ".delegua" : entry.path;
            JSONValue item = completionItem(dotted, "module", detail);
            item["filterText"] = JSONValue(dotted);
            item["textEdit"] = JSONValue(["range": editRange, "newText": JSONValue(dotted)]);
            items ~= item;
        }
        return JSONValue(["isIncomplete": JSONValue(false), "items": arrayJSON(items)]);
    }
    long dot = prefix.lastIndexOf('.');
    bool member = dot >= 0;
    if (member)
        foreach (dchar ch; prefix[dot + 1 .. $])
            if (!isIdentChar(ch))
                member = false;
    if (member)
    {
        string[] chain = extractDottedChainBeforeDot(prefix, cast(size_t) dot);
        if (chain.length && doc.statementImports.length)
        {
            bool matchedImport;
            foreach (ImportExpr imp; doc.statementImports)
            {
                if (imp.aliasName.length && chain.length == 1 && chain[0] == imp.aliasName.to!string)
                {
                    appendModuleMembers(doc, imp.target, items, names);
                    matchedImport = true;
                    continue;
                }
                if (imp.modulePath.length == chain.length)
                {
                    bool exact = true;
                    foreach (size_t idx, string seg; chain)
                        if (imp.modulePath[idx].to!string != seg)
                        {
                            exact = false;
                            break;
                        }
                    if (exact)
                    {
                        appendModuleMembers(doc, imp.target, items, names);
                        matchedImport = true;
                        continue;
                    }
                }
                if (imp.modulePath.length > chain.length)
                {
                    bool matchesPrefix = true;
                    foreach (size_t idx, string seg; chain)
                        if (imp.modulePath[idx].to!string != seg)
                        {
                            matchesPrefix = false;
                            break;
                        }
                    if (matchesPrefix)
                    {
                        string nextSeg = imp.modulePath[chain.length].to!string;
                        if (nextSeg !in names)
                        {
                            names[nextSeg] = true;
                            string kindDetail = chain.length + 1 == imp.modulePath.length
                                ? "módulo" : "namespace";
                            items ~= completionItem(nextSeg, "module", kindDetail);
                        }
                        matchedImport = true;
                    }
                }
            }
            if (matchedImport)
                return JSONValue(["isIncomplete": JSONValue(false), "items": arrayJSON(items)]);
        }
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
            if (ModuleUnit importedMod = doc.resolveImportedModule(node))
            {
                appendModuleMembers(doc, importedMod, items, names);
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
        if (TypeSemaNativeContainer nc = cast(TypeSemaNativeContainer) receiverType)
        {
            string[][NativeContainerKind] ncMethods = [
                NativeContainerKind.VetorNativo: [
                    "adicionar", "obter", "definir", "tamanho", "capacidade", "vazio",
                    "removerUltimo", "limpar", "reservar", "fatia", "clonar", "liberar", "paraVetor"
                ],
                NativeContainerKind.MapaNativo: [
                    "definir", "obter", "contem", "remover", "tamanho", "capacidade",
                    "vazio", "limpar", "clonar", "liberar", "paraDicionario"
                ],
                NativeContainerKind.FatiaNativa: ["tamanho", "vazio", "obter", "fatia"],
                NativeContainerKind.StringNativa: [
                    "criar", "vazia", "tamanho", "capacidade", "anexar", "visao",
                    "igual", "comecaCom", "limpar", "clonar", "liberar", "paraTexto"
                ],
                NativeContainerKind.VisaoTexto: ["tamanho", "vazia", "igual", "comecaCom", "paraTexto"],
                NativeContainerKind.OpcionalNativo: ["algum", "nenhum", "temValor", "ehNenhum", "valor", "valorOu"],
                NativeContainerKind.ResultadoNativo: ["ok", "erro", "ehOk", "ehErro", "valor", "valorOu"],
                NativeContainerKind.MatrizNativa: [
                    "linhas", "colunas", "tamanho", "obter", "definir", "transpor",
                    "multiplicar", "clonar", "liberar"
                ]
            ];
            if (string[]* mlist = nc.containerKind in ncMethods)
                foreach (string m; *mlist)
                    items ~= completionItem(m, "method", nc.toStr().to!string ~ "." ~ m);
            return JSONValue(["isIncomplete": JSONValue(false), "items": arrayJSON(items)]);
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
    foreach (ImportExpr imp; doc.statementImports)
    {
        if (imp.aliasName.length)
        {
            string aliasStr = imp.aliasName.to!string;
            if (aliasStr !in names)
            {
                names[aliasStr] = true;
                items ~= completionItem(aliasStr, "module", "módulo importado");
            }
        }
        else if (imp.modulePath.length)
        {
            string rootStr = imp.modulePath[0].to!string;
            if (rootStr !in names)
            {
                names[rootStr] = true;
                items ~= completionItem(rootStr, "module",
                        imp.modulePath.length == 1 ? "módulo importado" : "namespace importado");
            }
        }
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
    items ~= completionItem("Tarefa", "class", "tipo intrínseco Tarefa<T>; resultado de rotina paralela");
    items ~= completionItem("Compilacao", "class", "consultas puras do alvo em tempo de compilação (CTFE)");
    foreach (string[2] ct; [
        ["ci8", "int8_t (inteiro C 8 bits com sinal)"],
        ["cu8", "uint8_t (inteiro C 8 bits sem sinal)"],
        ["ci16", "int16_t (inteiro C 16 bits com sinal)"],
        ["cu16", "uint16_t (inteiro C 16 bits sem sinal)"],
        ["ci32", "int32_t (inteiro C 32 bits com sinal)"],
        ["cu32", "uint32_t (inteiro C 32 bits sem sinal)"],
        ["ci64", "int64_t (inteiro C 64 bits com sinal)"],
        ["cu64", "uint64_t (inteiro C 64 bits sem sinal)"],
        ["cchar", "char (ABI C)"],
        ["cschar", "signed char (ABI C)"],
        ["cuchar", "unsigned char (ABI C)"],
        ["cshort", "short (ABI C)"],
        ["cushort", "unsigned short (ABI C)"],
        ["cint", "int (ABI C)"],
        ["cuint", "unsigned int (ABI C)"],
        ["clong", "long (ABI C)"],
        ["culong", "unsigned long (ABI C)"],
        ["csize", "size_t (ABI C)"],
        ["cf32", "float (IEEE-754 32 bits)"],
        ["cf64", "double (IEEE-754 64 bits)"],
        ["cfloat", "float (ABI C)"],
        ["cdouble", "double (ABI C)"],
        ["cbool", "bool (C99)"],
        ["VetorNativo", "VetorNativo<T> — vetor contíguo nativo (Owned, RAII)"],
        ["MapaNativo", "MapaNativo<K, V> — hash table nativa (Owned, RAII)"],
        ["FatiaNativa", "FatiaNativa<T> — visão emprestada (BorrowedView)"],
        ["StringNativa", "StringNativa — texto UTF-8 nativo (Owned, RAII)"],
        ["VisaoTexto", "VisaoTexto — visão de texto emprestada (BorrowedView)"],
        ["ResultadoNativo", "ResultadoNativo<T, E> — resultado tipado por valor"],
        ["OpcionalNativo", "OpcionalNativo<T> — opcional tipado por valor"],
        ["MatrizNativa", "MatrizNativa<T> — matriz 2D densa nativa (Owned, RAII)"]
    ])
        if (ct[0] !in names)
        {
            names[ct[0]] = true;
            items ~= completionItem(ct[0], "class", ct[1]);
        }
    foreach (dstring name, TokenKind kind; keywords)
        items ~= completionItem(name.to!string, "keyword", "palavra-chave");
    return JSONValue(["isIncomplete": JSONValue(false), "items": arrayJSON(items)]);
}
