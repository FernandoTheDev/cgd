module lsp.model;

import frontend;
import frontend.analysis;
import lsp.builtins : builtinMethod;
import std.json;
import std.conv : to;
import std.algorithm : sort, startsWith;
import std.array : split, join;
import std.string : replace, splitLines;
import std.uri : encodeComponent, decode;
import std.path : absolutePath, asNormalizedPath;

JSONValue arrayJSON(JSONValue[] values = [])
{
    return JSONValue(values);
}

JSONValue objectJSON()
{
    return JSONValue(cast(JSONValue[string]) null);
}

JSONValue get(JSONValue value, string key, JSONValue fallback = JSONValue.init)
{
    if (value.type == JSONType.object)
        if (JSONValue* result = key in value.object)
            return *result;
    return fallback;
}

string str(JSONValue value, string key, string fallback = "")
{
    JSONValue v = get(value, key);
    return v.type == JSONType.string ? v.str : fallback;
}

long integer(JSONValue value, string key, long fallback = 0)
{
    JSONValue v = get(value, key);
    return v.type == JSONType.integer ? v.integer : v.type == JSONType.uinteger ? cast(long) v.uinteger : fallback;
}

string uriPath(string uri)
{
    if (uri.startsWith("untitled:"))
        return absolutePath(".cgd-untitled-" ~ encodeComponent(uri) ~ ".delegua");
    return uri.startsWith("file://") ? decode(uri[7 .. $]) : uri;
}

string fileURI(string path)
{
    string result = "file://";
    foreach (size_t i, string part; path.replace("\\", "/").split("/"))
    {
        if (i)
            result ~= "/";
        result ~= encodeComponent(part);
    }
    return result;
}

JSONValue point(uint line, uint column)
{
    return JSONValue(["line": JSONValue(line), "character": JSONValue(column)]);
}

JSONValue rangeJSON(JSONValue start, JSONValue end)
{
    return JSONValue(["start": start, "end": end]);
}

struct SymbolEntry
{
    string name, kind, detail, key;
    Position position;
    bool declaration;
}

class Document
{
    string uri, path, text;
    long revision;
    AnalysisResult analysis;
    SymbolEntry[] symbols;
    string[] lines;
    bool[Node] visited;
    bool[string] dependencies;
    bool isOpen;
    Node[ulong] expressionEnds;
    ClassDecl[Node] expressionClasses;
    FnDecl[Node] expressionFunctions;
    FnDecl[string] functions;
    TypeSema[Node] expressionTypes;
    VarDecl[string] variableDeclarations;
    size_t[ulong] symbolOffsets;
    struct LexicalScope
    {
        ulong start;
        ulong end = ulong.max;
    }

    LexicalScope[] lexicalScopes;
    size_t[ulong] declarationScopes;
    size_t scopeAt(ulong key)
    {
        size_t found;
        foreach (size_t i, LexicalScope lexical; lexicalScopes)
            if (key >= lexical.start && key < lexical.end)
                found = i;
        return found;
    }

    bool visible(SymbolEntry symbol, JSONValue position)
    {
        if (symbol.kind == "method" || symbol.kind == "property")
            return false;
        ulong declaration = offsetKey(symbol.position.start.line, symbol.position.start.offset);
        ulong cursor = offsetKey(cast(uint) integer(position, "line") + 1,
                codepoints(cast(uint) integer(position, "line"), cast(uint) integer(position, "character")) + 1);
        size_t definingScope = scopeAt(declaration);
        if (size_t* parameter = declaration in declarationScopes)
            definingScope = *parameter;
        if (definingScope && (cursor < lexicalScopes[definingScope].start || cursor >= lexicalScopes[definingScope].end))
            return false;
        return symbol.kind != "variable" || declaration <= cursor;
    }

    static ulong offsetKey(uint line, uint column)
    {
        return (cast(ulong) line << 32) | column;
    }

    void finishIndex()
    {
        symbolOffsets = null;
        lexicalScopes = [LexicalScope(0, ulong.max)];
        size_t[] stack;
        foreach (Token token; analysis.tokens)
        {
            if (token.kind == TokenKind.LBrace)
            {
                stack ~= lexicalScopes.length;
                lexicalScopes ~= LexicalScope(offsetKey(token.pos.start.line, token.pos.start.offset));
            }
            else if (token.kind == TokenKind.RBrace && stack.length)
            {
                lexicalScopes[stack[$ - 1]].end = offsetKey(token.pos.end.line, token.pos.end.offset);
                stack.length--;
            }
        }
        foreach (SymbolEntry symbol; symbols)
            if (symbol.declaration && symbol.kind == "parameter" && symbol.position.filename == path)
            {
                ulong key = offsetKey(symbol.position.start.line, symbol.position.start.offset);
                size_t nesting = 1;
                bool passed;
                foreach (Token token; analysis.tokens)
                {
                    ulong at = offsetKey(token.pos.start.line, token.pos.start.offset);
                    if (at <= key)
                        continue;
                    if (token.kind == TokenKind.LParen)
                        nesting++;
                    if (token.kind == TokenKind.RParen && nesting)
                    {
                        nesting--;
                        if (!nesting)
                            passed = true;
                    }
                    if (passed && token.kind == TokenKind.LBrace)
                    {
                        declarationScopes[key] = scopeAt(at);
                        break;
                    }
                }
            }
        foreach (size_t i, SymbolEntry symbol; symbols)
            if (symbol.position.filename == path)
                symbolOffsets[offsetKey(symbol.position.start.line, symbol.position.start.offset)] = i;
    }

    this(string uri, string text, long revision)
    {
        this.uri = uri;
        this.path = uriPath(uri);
        this.text = text;
        this.revision = revision;
        lines = text.splitLines();
    }

    uint utf16(uint line, uint codepoints)
    {
        if (line >= lines.length)
            return 0;
        uint result, index;
        foreach (dchar ch; lines[line])
        {
            if (index++ >= codepoints)
                break;
            result += ch > 0xffff ? 2 : 1;
        }
        return result;
    }

    uint codepoints(uint line, uint units)
    {
        if (line >= lines.length)
            return 0;
        uint result, used;
        foreach (dchar ch; lines[line])
        {
            if (used >= units)
                break;
            used += ch > 0xffff ? 2 : 1;
            result++;
        }
        return result;
    }

    size_t byteOffset(uint line, uint units)
    {
        size_t offset;
        uint currentLine, currentUnits;
        foreach (size_t i, dchar ch; text)
        {
            if (currentLine == line && currentUnits >= units)
                return i;
            if (ch == '\n')
            {
                currentLine++;
                currentUnits = 0;
            }
            else
                currentUnits += ch > 0xffff ? 2 : 1;
            offset = i + (ch <= 0x7f ? 1 : ch <= 0x7ff ? 2 : ch <= 0xffff ? 3 : 4);
        }
        return offset;
    }

    JSONValue positionRange(const(Position) pos, size_t nameLength = 0)
    {
        if (pos is null)
            return rangeJSON(point(0, 0), point(0, 0));
        uint startLine = pos.start.line ? pos.start.line - 1 : 0;
        uint start = pos.start.offset ? pos.start.offset - 1 : 0;
        uint endLine = nameLength ? startLine : pos.end.line ? pos.end.line - 1 : startLine;
        uint end = nameLength ? start + cast(uint) nameLength : pos.end.offset ? pos.end.offset - 1 : start;
        return rangeJSON(point(startLine, utf16(startLine, start)), point(endLine, utf16(endLine, end)));
    }

    static string identity(Position pos)
    {
        return pos is null ? "" : pos.filename ~ ":" ~ pos.start.line.to!string ~ ":" ~ pos.start.offset.to!string;
    }

    void add(string name, string kind, Position pos, Position definition, string detail = "", bool declaration = false)
    {
        if (pos is null || name.startsWith("#"))
            return;
        symbols ~= SymbolEntry(name, kind, detail.length ? detail : kind ~ " " ~ name,
                identity(definition), pos, declaration);
    }

    Position identifierDefinition(Identifier id)
    {
        if (id.variableRef !is null)
            return id.variableRef.pos;
        if (id.parameterRef !is null)
            return id.parameterRef.pos;
        if (id.classRef !is null)
            return id.classRef.pos;
        if (id.functionRef !is null)
            return id.functionRef.pos;
        return null;
    }

    string signature(FnDecl fn)
    {
        string[] args;
        foreach (FnArg arg; fn.args)
            args ~= (arg.rest ? "..." : "") ~ arg.name.to!string ~ ": " ~ (arg.type_expr is null
                    ? "qualquer" : arg.type_expr.toStr().to!string) ~ (arg.value is null ? "" : " = …");
        return fn.fn.to!string ~ "(" ~ args.join(", ") ~ "): " ~ (fn.type_expr is null
                ? "qualquer" : fn.type_expr.toStr().to!string);
    }

    TypeSema expressionType(Node node, size_t depth = 0)
    {
        if (node is null || depth > 16)
            return null;
        if (TypeSema* known = node in expressionTypes)
            return *known;
        if (node.type_sema !is null && !node.type_sema.isAny())
            return node.type_sema;
        if (Identifier id = cast(Identifier) node)
        {
            if (id.variableRef !is null)
            {
                if (id.variableRef.type_sema !is null && !id.variableRef.type_sema.isAny())
                    return id.variableRef.type_sema;
                return expressionType(id.variableRef.value, depth + 1);
            }
            if (id.parameterRef !is null)
                return id.parameterRef.type_sema;
        }
        if (CallExpr call = cast(CallExpr) node)
        {
            if (FnDecl* method = call.fn in expressionFunctions)
                return (*method).type_sema;
            if (Identifier id = cast(Identifier) call.fn)
                if (id.functionRef !is null)
                    return id.functionRef.type_sema;
            if (MemberExpr member = cast(MemberExpr) call.fn)
                if (Identifier name = cast(Identifier) member.right)
                {
                    TypeSema receiver = expressionType(member.left, depth + 1);
                    if (TypeSemaBuiltin builtin = cast(TypeSemaBuiltin) receiver)
                        if (builtin.base == TypeSemaBase.String)
                        {
                            import std.algorithm : canFind;

                            if ([
                                "aparar", "apararInicio", "apararFim", "maiusculo", "minusculo",
                                "fatiar", "subtexto", "substituir", "concatenar"
                            ].canFind(name.value.to!string))
                                return receiver;
                            if (name.value == "dividir")
                                return new TypeSemaArray(receiver);
                        }
                }
        }
        return node.type_sema;
    }

    ClassDecl instanceClass(Node node)
    {
        if (node is null)
            return null;
        if (ClassDecl* known = node in expressionClasses)
            return *known;
        if (TypeSemaClass type = cast(TypeSemaClass) expressionType(node))
            return type.declaration;
        if (Identifier id = cast(Identifier) node)
        {
            if (id.lexicalClass !is null)
                return id.lexicalClass;
            if (id.classRef !is null)
                return id.classRef;
            if (id.variableRef !is null)
            {
                CallExpr call = cast(CallExpr) id.variableRef.value;
                if (call !is null)
                {
                    if (Identifier target = cast(Identifier) call.fn)
                        return target.classRef;
                    if (ClassDecl* cls = call.fn in expressionClasses)
                        return *cls;
                }
            }
        }
        if (CallExpr call = cast(CallExpr) node)
        {
            if (Identifier id = cast(Identifier) call.fn)
                return id.classRef;
            if (ClassDecl* cls = call.fn in expressionClasses)
                return *cls;
        }
        return null;
    }

    void index(Node node)
    {
        if (node is null || node in visited)
            return;
        visited[node] = true;
        if (node.pos !is null && node.pos.filename == path && (cast(Identifier) node
                || cast(CallExpr) node || cast(MemberExpr) node || cast(StringLit) node
                || cast(IntLit) node || cast(DoubleLit) node || cast(ArrayLit) node || cast(MapLit) node))
            expressionEnds[offsetKey(node.pos.end.line, node.pos.end.offset)] = node;
        if (ModuleUnit unit = cast(ModuleUnit) node)
            dependencies[unit.path] = true;
        if (FnDecl fn = cast(FnDecl) node)
        {
            functions[identity(fn.pos)] = fn;
            add(fn.fn.to!string, fn.isMethod ? "method" : "function", fn.pos, fn.pos, signature(fn), true);
            foreach (FnArg arg; fn.args)
                add(arg.name.to!string, "parameter", arg.pos, arg.pos,
                        "parâmetro " ~ arg.name.to!string ~ ": " ~ (arg.type_expr is null
                            ? "qualquer" : arg.type_expr.toStr().to!string), true);
        }
        if (VarDecl variable = cast(VarDecl) node)
            if (variable.pos !is null && variable.pos.filename == path)
                variableDeclarations[variable.name.to!string] = variable;
        if (VarDecl variable = cast(VarDecl) node)
            add(variable.name.to!string, "variable", variable.pos, variable.pos,
                    (variable.isConst ? "const " : "var ") ~ variable.name.to!string ~ ": " ~ (variable.type_sema is null
                        ? "qualquer" : variable.type_sema.toStr().to!string), true);
        if (ClassDecl cls = cast(ClassDecl) node)
        {
            add(cls.name.to!string, "class", cls.pos, cls.pos, "classe " ~ cls.name.to!string, true);
            foreach (ClassField field; cls.fields)
                add(field.name.to!string, "property", field.pos, field.pos,
                        "campo " ~ field.name.to!string ~ ": " ~ field.type.toStr().to!string, true);
        }
        if (MemberExpr member = cast(MemberExpr) node)
        {
            index(member.left);
            if (node.type_sema !is null)
                expressionTypes[member] = node.type_sema;
            Identifier name = cast(Identifier) member.right;
            if (name is null)
                return;
            if (ClassDecl cls = instanceClass(member.left))
            {
                bool[ClassDecl] seen;
                for (ClassDecl current = cls; current !is null && current !in seen; current = current.superClass)
                {
                    seen[current] = true;
                    foreach (FnDecl method; current.methods)
                        if (method.fn == name.value)
                        {
                            expressionFunctions[member] = method;
                            add(name.value.to!string, "method", name.pos, method.pos, signature(method));
                            return;
                        }
                    foreach (ClassField field; current.fields)
                        if (field.name == name.value)
                        {
                            add(name.value.to!string, "property", name.pos, field.pos,
                                    "campo " ~ name.value.to!string);
                            return;
                        }
                }
            }
            if (Identifier left = cast(Identifier) member.left)
                if (left.variableRef !is null)
                    if (ImportExpr imported = cast(ImportExpr) left.variableRef.value)
                        if (imported.target !is null)
                        {
                            foreach (Node exported; imported.target.program.body)
                            {
                                if (FnDecl fn = cast(FnDecl) exported)
                                    if (fn.fn == name.value)
                                    {
                                        add(name.value.to!string, "function", name.pos, fn.pos, signature(fn));
                                        return;
                                    }
                                if (VarDecl variable = cast(VarDecl) exported)
                                    if (variable.name == name.value)
                                    {
                                        add(name.value.to!string, "variable", name.pos,
                                                variable.pos, "exportação " ~ name.value.to!string);
                                        return;
                                    }
                                if (ClassDecl cls = cast(ClassDecl) exported)
                                    if (cls.name == name.value)
                                    {
                                        expressionClasses[member] = cls;
                                        add(name.value.to!string, "class", name.pos, cls.pos,
                                                "classe " ~ name.value.to!string);
                                        return;
                                    }
                            }
                        }
            if (FnDecl builtin = builtinMethod(expressionType(member.left), name.value.to!string))
            {
                expressionFunctions[member] = builtin;
                add(name.value.to!string, "method", name.pos, null, signature(builtin));
                return;
            }
            add(name.value.to!string, "property", name.pos, null, "propriedade/método " ~ name.value.to!string);
            return;
        }
        if (Identifier id = cast(Identifier) node)
        {
            string kind = id.classRef !is null ? "class" : id.functionRef !is null
                ? "function" : id.parameterRef !is null ? "parameter" : "variable";
            add(id.value.to!string, kind, id.pos, identifierDefinition(id),
                    id.functionRef !is null
                    ? signature(id.functionRef) : kind ~ " " ~ id.value.to!string ~ (id.type_sema is null
                        ? "" : ": " ~ id.type_sema.toStr().to!string));
        }
        foreach (Node child; childNodes(node))
            index(child);
    }

    SymbolEntry* symbolAt(JSONValue position)
    {
        long line = integer(position, "line"), column = integer(position, "character");
        foreach (ref SymbolEntry symbol; symbols)
        {
            if (symbol.position.filename != path)
                continue;
            JSONValue r = positionRange(symbol.position, symbol.name.to!dstring.length);
            JSONValue a = get(r, "start"), b = get(r, "end");
            if (integer(a, "line") == line && column >= integer(a, "character") && column < integer(b, "character"))
                return &symbol;
        }
        return null;
    }

    Token tokenAt(JSONValue position)
    {
        long line = integer(position, "line"), column = codepoints(cast(uint) line,
                cast(uint) integer(position, "character"));
        foreach (Token token; analysis.tokens)
            if (token.pos.start.line == line + 1 && column + 1 >= token.pos.start.offset
                    && column + 1 <= token.pos.end.offset)
                return token;
        return null;
    }
}
