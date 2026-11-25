module lsp.model;

import frontend;
import frontend.analysis;
import lsp.builtins : builtinMethod;
import lsp.evaluation;
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
    Node[] expressions;
    ConstantPreview constantPreview;
    ClassDecl[Node] expressionClasses;
    FnDecl[Node] expressionFunctions;
    FnDecl[string] functions;
    TypeSema[Node] expressionTypes;
    VarDecl[string] variableDeclarations;
    ClassDecl[string] symbolTypeDecls;
    ClassDecl[ulong] offsetTypeDecls;
    Position[string] modulePositions;
    ImportExpr[] statementImports;
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
        string result = fn.classFactory !is null ? fn.classFactory.name.to!string
            : fn.type_expr is null ? "qualquer" : fn.type_expr.toStr().to!string;
        return (fn.isAsync ? "assincrona " : "") ~ fn.fn.to!string ~ "(" ~ args.join(
                ", ") ~ "): " ~ result ~ (fn.isAsync ? " → Promessa<" ~ result ~ ">" : "");
    }

    TypeSema expressionType(Node node, size_t depth = 0)
    {
        if (node is null || depth > 16)
            return null;
        if (TypeSema* known = node in expressionTypes)
            return *known;
        if (node.type_sema !is null && !node.type_sema.isAny())
            return node.type_sema;
        if (RoutineExpr routine = cast(RoutineExpr) node)
        {
            if (routine.target !is null && routine.target.type_sema !is null)
                return new TypeSemaTask(routine.target.type_sema);
            return new TypeSemaTask(new TypeSemaBuiltin(TypeSemaBase.Any));
        }
        if (AwaitExpr awaited = cast(AwaitExpr) node)
        {
            TypeSema inner = expressionType(awaited.value, depth + 1);
            if (TypeSemaPromise promise = cast(TypeSemaPromise) inner)
                return promise.result;
            if (TypeSemaTask task = cast(TypeSemaTask) inner)
                return task.result;
        }
        if (ArrayLit arr = cast(ArrayLit) node)
        {
            if (arr.elements.length)
            {
                TypeSema first = expressionType(arr.elements[0], depth + 1);
                if (first !is null && !first.isAny())
                {
                    bool uniform = true;
                    foreach (Node elem; arr.elements[1 .. $])
                    {
                        TypeSema et = expressionType(elem, depth + 1);
                        if (et is null || et.toStr() != first.toStr())
                        {
                            uniform = false;
                            break;
                        }
                    }
                    if (uniform)
                        return new TypeSemaArray(first);
                }
            }
            return new TypeSemaArray(new TypeSemaBuiltin(TypeSemaBase.Any));
        }
        if (IndexExpr idx = cast(IndexExpr) node)
        {
            TypeSema container = expressionType(idx.value, depth + 1);
            if (TypeSemaArray arrType = cast(TypeSemaArray) container)
                return arrType.base;
            if (TypeSemaBuiltin builtin = cast(TypeSemaBuiltin) container)
                if (builtin.base == TypeSemaBase.String)
                    return builtin;
        }
        if (ConditionalExpr cond = cast(ConditionalExpr) node)
        {
            TypeSema yesType = expressionType(cond.yes, depth + 1);
            TypeSema noType = expressionType(cond.no, depth + 1);
            if (yesType !is null && noType !is null && !yesType.isAny() && yesType.toStr() == noType.toStr())
                return yesType;
        }
        if (BinaryExpr bin = cast(BinaryExpr) node)
        {
            if (bin.op == TokenKind.EEquals || bin.op == TokenKind.NEquals
                    || bin.op == TokenKind.LThan || bin.op == TokenKind.GThan
                    || bin.op == TokenKind.LEquals || bin.op == TokenKind.GEquals || bin.op == TokenKind.In)
                return new TypeSemaBuiltin(TypeSemaBase.Bool);
            TypeSema lt = expressionType(bin.left, depth + 1);
            TypeSema rt = expressionType(bin.right, depth + 1);
            if (bin.op == TokenKind.Coalesce && rt !is null && !rt.isAny())
                return lt !is null && !lt.isAny() && lt.toStr() == rt.toStr() ? lt : rt;
            if (lt !is null && rt !is null && !lt.isAny() && !rt.isAny())
                return lt.promote(rt);
        }
        if (Identifier id = cast(Identifier) node)
        {
            if (id.classRef !is null)
                return new TypeSemaClass(id.classRef);
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
            {
                if ((*method).classFactory !is null)
                    return new TypeSemaClass((*method).classFactory);
                return (*method).isAsync && (*method).type_sema !is null
                    ? new TypeSemaPromise((*method).type_sema) : (*method).type_sema;
            }
            if (ClassDecl* cls = call.fn in expressionClasses)
                return new TypeSemaClass(*cls);
            if (Identifier id = cast(Identifier) call.fn)
            {
                if (id.classRef !is null)
                    return new TypeSemaClass(id.classRef);
                if (id.functionRef !is null)
                {
                    if (id.functionRef.classFactory !is null)
                        return new TypeSemaClass(id.functionRef.classFactory);
                    return id.functionRef.isAsync
                        ? new TypeSemaPromise(id.functionRef.type_sema) : id.functionRef.type_sema;
                }
            }
            if (MemberExpr member = cast(MemberExpr) call.fn)
                if (Identifier name = cast(Identifier) member.right)
                {
                    if (name.classRef !is null)
                        return new TypeSemaClass(name.classRef);
                    if (name.functionRef !is null)
                        return name.functionRef.isAsync
                            ? new TypeSemaPromise(name.functionRef.type_sema) : name.functionRef.type_sema;
                    TypeSema receiver = expressionType(member.left, depth + 1);
                    if (FnDecl builtin = builtinMethod(receiver, name.value.to!string))
                        if (builtin.type_sema !is null && !builtin.type_sema.isAny())
                            return builtin.type_sema;
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
                if (MemberExpr m = cast(MemberExpr) id.variableRef.value)
                {
                    if (ClassDecl* cls = m in expressionClasses)
                        return *cls;
                    if (Identifier right = cast(Identifier) m.right)
                        if (right.classRef !is null)
                            return right.classRef;
                }
                CallExpr call = cast(CallExpr) id.variableRef.value;
                if (call !is null)
                {
                    if (Identifier target = cast(Identifier) call.fn)
                        return target.classRef;
                    if (ClassDecl* cls = call.fn in expressionClasses)
                        return *cls;
                    if (TypeSemaClass retCls = cast(TypeSemaClass) expressionType(call))
                        return retCls.declaration;
                }
            }
        }
        if (CallExpr call = cast(CallExpr) node)
        {
            if (Identifier id = cast(Identifier) call.fn)
                return id.classRef;
            if (ClassDecl* cls = call.fn in expressionClasses)
                return *cls;
            if (TypeSemaClass retCls = cast(TypeSemaClass) expressionType(call))
                return retCls.declaration;
        }
        return null;
    }

    /// Função mais interna por delimitadores, mesmo com um membro incompleto.
    FnDecl functionAt(JSONValue position)
    {
        ulong cursor = offsetKey(cast(uint) integer(position, "line") + 1,
                codepoints(cast(uint) integer(position, "line"), cast(uint) integer(position, "character")) + 1);
        FnDecl found;
        ulong latest;
        foreach (FnDecl fn; functions)
        {
            if (fn is null || fn.classFactory !is null || fn.pos is null || fn.pos.filename != path)
                continue;
            ulong start = offsetKey(fn.pos.start.line, fn.pos.start.offset);
            size_t parens;
            bool parameters;
            foreach (Token token; analysis.tokens)
            {
                ulong at = offsetKey(token.pos.start.line, token.pos.start.offset);
                if (at < start)
                    continue;
                if (token.kind == TokenKind.LParen)
                {
                    parameters = true;
                    parens++;
                }
                if (token.kind == TokenKind.RParen && parens)
                    parens--;
                if (parameters && !parens && token.kind == TokenKind.LBrace)
                {
                    size_t scopeIndex = scopeAt(at);
                    if (cursor >= at && cursor < lexicalScopes[scopeIndex].end && start >= latest)
                    {
                        latest = start;
                        found = fn;
                    }
                    break;
                }
            }
        }
        return found;
    }

    Node previewAt(JSONValue position)
    {
        ulong cursor = offsetKey(cast(uint) integer(position, "line") + 1,
                codepoints(cast(uint) integer(position, "line"), cast(uint) integer(position, "character")) + 1);
        Node found;
        ulong span = ulong.max;
        foreach (Node expression; expressions)
        {
            if (!cast(CallExpr) expression && !cast(BinaryExpr) expression
                    && !cast(UnaryExpr) expression && !cast(ConditionalExpr) expression)
                continue;
            ulong start = offsetKey(expression.pos.start.line, expression.pos.start.offset);
            ulong end = offsetKey(expression.pos.end.line, expression.pos.end.offset);
            if (cursor >= start && cursor < end && end - start < span)
            {
                found = expression;
                span = end - start;
            }
        }
        return found;
    }

    Position modulePosition(ModuleUnit unit)
    {
        if (unit is null)
            return null;
        if (unit.program !is null && unit.program.modulePos !is null)
            return unit.program.modulePos;
        if (unit.program !is null && unit.program.pos !is null)
            return unit.program.pos;
        return new Position(unit.path, new PosLine(1, 1), new PosLine(1, 1));
    }

    ModuleUnit resolveImportedModule(Node node)
    {
        if (node is null)
            return null;
        if (ImportExpr directImport = cast(ImportExpr) node)
            return directImport.target;
        if (MemberExpr member = cast(MemberExpr) node)
            if (member.resolvedModule !is null)
                return member.resolvedModule;
        if (Identifier left = cast(Identifier) node)
        {
            if (left.moduleRef !is null)
                return left.moduleRef;
            if (left.variableRef !is null)
                if (ImportExpr imported = cast(ImportExpr) left.variableRef.value)
                    return imported.target;
        }
        return null;
    }

    ClassDecl classFromType(TypeSema type)
    {
        if (type is null)
            return null;
        if (TypeSemaClass clsType = cast(TypeSemaClass) type)
            return clsType.declaration;
        if (TypeSemaArray arrType = cast(TypeSemaArray) type)
            return classFromType(arrType.base);
        if (TypeSemaPromise promiseType = cast(TypeSemaPromise) type)
            return classFromType(promiseType.result);
        if (TypeSemaTask taskType = cast(TypeSemaTask) type)
            return classFromType(taskType.result);
        return null;
    }

    void recordTypeOffset(Position pos, ClassDecl cls)
    {
        if (pos is null || cls is null || pos.filename != path)
            return;
        offsetTypeDecls[offsetKey(pos.start.line, pos.start.offset)] = cls;
    }

    void indexTypeExpr(TypeExpr te, TypeSema resolved)
    {
        if (te is null || te.pos is null || te.pos.filename != path)
            return;
        if (TypeExprArray arr = cast(TypeExprArray) te)
        {
            TypeSema inner = cast(TypeSemaArray) resolved ? (cast(TypeSemaArray) resolved).base : resolved;
            indexTypeExpr(arr.base, inner);
            return;
        }
        if (TypeExprPromise prom = cast(TypeExprPromise) te)
        {
            TypeSema inner = cast(TypeSemaPromise) resolved ? (cast(TypeSemaPromise) resolved).result : resolved;
            indexTypeExpr(prom.result, inner);
            return;
        }
        if (TypeExprTask task = cast(TypeExprTask) te)
        {
            TypeSema inner = cast(TypeSemaTask) resolved ? (cast(TypeSemaTask) resolved).result : resolved;
            indexTypeExpr(task.result, inner);
            return;
        }
        if (TypeExprTuple tup = cast(TypeExprTuple) te)
        {
            foreach (TypeExpr elem; tup.types)
                indexTypeExpr(elem, null);
            return;
        }
        if (TypeExprNamed named = cast(TypeExprNamed) te)
        {
            ClassDecl cls = classFromType(resolved);
            if (cls is null)
                return;
            Position namePos = named.pos;
            if (named.qualifier.length)
            {
                ulong startKey = offsetKey(named.pos.start.line, named.pos.start.offset);
                size_t dotsNeeded = named.qualifier.length;
                size_t dotsSeen = 0;
                bool started = false;
                foreach (Token tk; analysis.tokens)
                {
                    if (tk.pos is null)
                        continue;
                    ulong k = offsetKey(tk.pos.start.line, tk.pos.start.offset);
                    if (!started)
                    {
                        if (k == startKey)
                            started = true;
                        else
                            continue;
                    }
                    if (tk.kind == TokenKind.Dot)
                        dotsSeen++;
                    else if (dotsSeen == dotsNeeded && tk.kind == TokenKind.Identifier && tk.value.s == named.name)
                    {
                        namePos = tk.pos;
                        break;
                    }
                    else if (k > startKey && tk.kind != TokenKind.Identifier && tk.kind != TokenKind.Dot)
                        break;
                }
            }
            add(named.name.to!string, "class", namePos, cls.pos, signature(cls.signature));
            recordTypeOffset(namePos, cls);
        }
    }

    ClassDecl typeDeclAt(JSONValue position)
    {
        SymbolEntry* selected = symbolAt(position);
        if (selected !is null)
        {
            if (ClassDecl* direct = offsetKey(selected.position.start.line,
                    selected.position.start.offset) in offsetTypeDecls)
                return *direct;
            if (ClassDecl* byKey = selected.key in symbolTypeDecls)
                return *byKey;
        }
        return null;
    }

    void index(Node node)
    {
        if (node is null || node in visited)
            return;
        visited[node] = true;
        if (node.pos !is null && node.pos.filename == path)
            expressions ~= node;
        if (node.pos !is null && node.pos.filename == path && (cast(Identifier) node
                || cast(CallExpr) node || cast(MemberExpr) node || cast(StringLit) node
                || cast(IntLit) node || cast(DoubleLit) node || cast(ArrayLit) node || cast(MapLit) node))
            expressionEnds[offsetKey(node.pos.end.line, node.pos.end.offset)] = node;
        if (ModuleUnit unit = cast(ModuleUnit) node)
            dependencies[unit.path] = true;
        if (ImportExpr imp = cast(ImportExpr) node)
        {
            if (imp.target !is null)
            {
                dependencies[imp.target.path] = true;
                Position mpos = modulePosition(imp.target);
                if (mpos !is null)
                    modulePositions[identity(mpos)] = mpos;
            }
            if (imp.isStatementImport && imp.pos !is null && imp.pos.filename == path)
                statementImports ~= imp;
        }
        if (FnDecl fn = cast(FnDecl) node)
        {
            functions[identity(fn.pos)] = fn;
            add(fn.fn.to!string, fn.isMethod ? "method" : "function", fn.pos, fn.pos, signature(fn), true);
            ClassDecl retCls = classFromType(fn.type_sema);
            if (retCls !is null)
            {
                symbolTypeDecls[identity(fn.pos)] = retCls;
                recordTypeOffset(fn.pos, retCls);
            }
            indexTypeExpr(fn.type_expr, fn.type_sema);
            foreach (FnArg arg; fn.args)
            {
                add(arg.name.to!string, "parameter", arg.pos, arg.pos,
                        "parâmetro " ~ arg.name.to!string ~ ": " ~ (arg.type_expr is null
                            ? "qualquer" : arg.type_expr.toStr().to!string), true);
                ClassDecl argCls = classFromType(arg.type_sema);
                if (argCls !is null)
                {
                    symbolTypeDecls[identity(arg.pos)] = argCls;
                    recordTypeOffset(arg.pos, argCls);
                }
                indexTypeExpr(arg.type_expr, arg.type_sema);
            }
        }
        if (VarDecl variable = cast(VarDecl) node)
            if (variable.pos !is null && variable.pos.filename == path)
                variableDeclarations[identity(variable.pos)] = variable;
        if (VarDecl variable = cast(VarDecl) node)
        {
            TypeSema inferred = (variable.type_sema !is null && !variable.type_sema.isAny()) ? variable.type_sema
                : expressionType(variable.value);
            string typeName = inferred is null ? "qualquer" : inferred.toStr().to!string;
            add(variable.name.to!string, "variable", variable.pos, variable.pos,
                    (variable.isConst ? "const " : "var ") ~ variable.name.to!string ~ ": " ~ typeName, true);
            ClassDecl varCls = classFromType(inferred);
            if (varCls !is null)
            {
                symbolTypeDecls[identity(variable.pos)] = varCls;
                recordTypeOffset(variable.pos, varCls);
            }
            indexTypeExpr(variable.type_expr, inferred);
        }
        if (ClassDecl cls = cast(ClassDecl) node)
        {
            functions[identity(cls.pos)] = cls.signature;
            symbolTypeDecls[identity(cls.pos)] = cls;
            recordTypeOffset(cls.pos, cls);
            add(cls.name.to!string, "class", cls.pos, cls.pos, signature(cls.signature), true);
            foreach (ClassField field; cls.fields)
            {
                add(field.name.to!string, "property", field.pos, field.pos,
                        "campo " ~ field.name.to!string ~ ": " ~ field.type.toStr().to!string, true);
                ClassDecl fieldCls = classFromType(field.type_sema);
                if (fieldCls !is null)
                {
                    symbolTypeDecls[identity(field.pos)] = fieldCls;
                    recordTypeOffset(field.pos, fieldCls);
                }
                indexTypeExpr(field.type, field.type_sema);
            }
        }
        if (MemberExpr member = cast(MemberExpr) node)
        {
            index(member.left);
            if (node.type_sema !is null)
                expressionTypes[member] = node.type_sema;
            Identifier name = cast(Identifier) member.right;
            if (name is null)
                return;
            if (member.resolvedModule !is null)
            {
                Position mpos = modulePosition(member.resolvedModule);
                if (mpos !is null)
                    modulePositions[identity(mpos)] = mpos;
                string nsName = member.namespacePath.length
                    ? member.namespacePath.join("."d).to!string : name.value.to!string;
                add(name.value.to!string, "namespace", name.pos, mpos, "módulo " ~ nsName);
                return;
            }
            if (member.namespacePath.length)
            {
                add(name.value.to!string, "namespace", name.pos, null,
                        "namespace " ~ member.namespacePath.join("."d).to!string);
                return;
            }
            if (ClassDecl cls = instanceClass(member.left))
            {
                import frontend.semantic.members : resolveClassMember, ClassMember;

                ClassMember resolved = resolveClassMember(cls, name.value);
                if (resolved.owner !is null)
                {
                    if (resolved.method !is null)
                    {
                        expressionFunctions[member] = resolved.method;
                        add(name.value.to!string, "method", name.pos, resolved.method.pos, signature(resolved.method));
                        recordTypeOffset(name.pos, classFromType(resolved.method.type_sema));
                        return;
                    }
                    if (resolved.field !is null)
                    {
                        add(name.value.to!string, "property", name.pos, resolved.field.pos,
                                "campo " ~ name.value.to!string ~ ": " ~ resolved.field.type.toStr().to!string);
                        recordTypeOffset(name.pos, classFromType(resolved.field.type_sema));
                        return;
                    }
                }
            }
            ModuleUnit importedMod = resolveImportedModule(member.left);
            if (importedMod !is null && importedMod.program !is null)
            {
                foreach (Node exported; importedMod.program.body)
                {
                    if (FnDecl fn = cast(FnDecl) exported)
                        if (fn.fn == name.value)
                        {
                            expressionFunctions[member] = fn;
                            functions[identity(fn.pos)] = fn;
                            add(name.value.to!string, "function", name.pos, fn.pos, signature(fn));
                            recordTypeOffset(name.pos, classFromType(fn.type_sema));
                            return;
                        }
                    if (VarDecl variable = cast(VarDecl) exported)
                        if (variable.name == name.value)
                        {
                            string varDetail = variable.isEnum ? "enum " ~ name.value.to!string
                                : "exportação " ~ name.value.to!string;
                            add(name.value.to!string, "variable", name.pos, variable.pos, varDetail);
                            recordTypeOffset(name.pos, classFromType(variable.type_sema));
                            return;
                        }
                    if (ClassDecl cls = cast(ClassDecl) exported)
                        if (cls.name == name.value)
                        {
                            expressionClasses[member] = cls;
                            functions[identity(cls.pos)] = cls.signature;
                            add(name.value.to!string, "class", name.pos, cls.pos, signature(cls.signature));
                            recordTypeOffset(name.pos, cls);
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
            if (id.moduleRef !is null)
            {
                Position mpos = modulePosition(id.moduleRef);
                if (mpos !is null)
                    modulePositions[identity(mpos)] = mpos;
                add(id.value.to!string, "namespace", id.pos, mpos, "módulo " ~ id.value.to!string);
                return;
            }
            if (id.namespacePath.length)
            {
                add(id.value.to!string, "namespace", id.pos, null,
                        "namespace " ~ id.namespacePath.join("."d).to!string);
                return;
            }
            string kind = id.classRef !is null ? "class" : id.functionRef !is null
                ? "function" : id.parameterRef !is null ? "parameter" : "variable";
            add(id.value.to!string, kind, id.pos, identifierDefinition(id),
                    id.functionRef !is null
                    ? signature(id.functionRef) : kind ~ " " ~ id.value.to!string ~ (id.type_sema is null
                        ? "" : ": " ~ id.type_sema.toStr().to!string));
            ClassDecl idCls = id.classRef !is null ? id.classRef : classFromType(expressionType(id));
            recordTypeOffset(id.pos, idCls);
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
