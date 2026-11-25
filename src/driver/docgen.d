module driver.docgen;

import driver.args;
import driver.compile;
import driver.target_info;
import errors;
import frontend;
import frontend.modules;
import frontend.semantic.pipeline;
import frontend.semantic.value_types;
import std.algorithm : canFind, sort, startsWith;
import std.array : join, replace;
import std.conv : to;
import std.file : DirEntry, SpanMode, dirEntries, exists, isDir, isFile, mkdirRecurse, readText, remove, tempDir, write;
import std.format : format;
import std.path : absolutePath, baseName, buildPath, dirName, extension, relativePath, stripExtension;
import std.stdio : writeln, writefln, stderr;
import std.string : splitLines, strip, stripLeft;
import utils : cgd_erro;

private struct DocItem
{
    string kind;
    string name;
    string signature;
    string visibility;
    string[] annotations;
    string docComment;
    string memoryContract;
    string[] examples;
    string[] members;
}

private struct DocModule
{
    string moduleName;
    string sourcePath;
    string[] imports;
    DocItem[] items;
}

private string extractLeadingDocComment(string[] lines, uint declLine)
{
    if (declLine <= 1 || declLine - 1 > lines.length)
        return "";
    string[] collected;
    long idx = cast(long) declLine - 2;
    // Pula linhas de decoradores (@...) imediatamente acima da declaração
    while (idx >= 0)
    {
        string trimmed = lines[cast(size_t) idx].strip();
        if (trimmed.startsWith("@"))
        {
            idx--;
            continue;
        }
        break;
    }
    while (idx >= 0)
    {
        string trimmed = lines[cast(size_t) idx].strip();
        if (trimmed.startsWith("///"))
        {
            string body = trimmed.length > 3 ? trimmed[3 .. $] : "";
            if (body.length && body[0] == ' ')
                body = body[1 .. $];
            collected = [body] ~ collected;
            idx--;
        }
        else
            break;
    }
    return collected.join("\n").strip();
}

private string[] extractCodeExamples(string docText)
{
    string[] examples;
    string[] lines = docText.splitLines();
    bool inBlock = false;
    string[] current;
    foreach (string ln; lines)
    {
        string tr = ln.strip();
        if (!inBlock && (tr == "```delegua" || tr == "```delégua"))
        {
            inBlock = true;
            current = null;
        }
        else if (inBlock && tr == "```")
        {
            inBlock = false;
            examples ~= current.join("\n");
        }
        else if (inBlock)
            current ~= ln;
    }
    return examples;
}

private string formatAnnotations(Decorator[] decorators, FnDecl fn = null, ClassDecl cls = null)
{
    string[] parts;
    foreach (Decorator d; decorators)
    {
        if (d.values.length)
            parts ~= "@" ~ d.name.to!string ~ "(...)";
        else
            parts ~= "@" ~ d.name.to!string;
    }
    if (fn !is null && fn.operatorSymbol.length && !parts.canFind("@operador(...)"))
        parts ~= format("@operador(\"%s\")", fn.operatorSymbol.to!string);
    if (cls !is null && cls.isValueType && !parts.canFind("@pilha") && !parts.canFind("@valor"))
        parts ~= "@pilha";
    return parts.join(" ");
}

private string[] annotationList(Decorator[] decorators, FnDecl fn = null, ClassDecl cls = null)
{
    string[] parts;
    foreach (Decorator d; decorators)
    {
        if (d.name == "operador"d && fn !is null && fn.operatorSymbol.length)
            parts ~= format("@operador(\"%s\")", fn.operatorSymbol.to!string);
        else if (d.values.length)
            parts ~= "@" ~ d.name.to!string ~ "(...)";
        else
            parts ~= "@" ~ d.name.to!string;
    }
    if (cls !is null && cls.isValueType && !parts.canFind("@pilha") && !parts.canFind("@valor"))
        parts ~= "@pilha";
    return parts;
}

private string formatFnSignature(FnDecl fn)
{
    string[] args;
    foreach (FnArg a; fn.args)
    {
        string s = (a.rest ? "..." : "") ~ a.name.to!string;
        if (a.type_expr !is null)
            s ~= ": " ~ a.type_expr.toStr().to!string;
        if (a.value !is null)
            s ~= " = ...";
        args ~= s;
    }
    string prefix = fn.isMethod ? (fn.isStatic ? "estatico " : "") : "funcao ";
    if (fn.isAsync)
        prefix = "assincrona " ~ prefix;
    string ret = fn.type_expr !is null ? ": " ~ fn.type_expr.toStr().to!string : "";
    return prefix ~ fn.fn.to!string ~ "(" ~ args.join(", ") ~ ")" ~ ret;
}

private string visibilityStr(int access)
{
    return access == 1 ? "privado" : access == 2 ? "protegido" : "publico";
}

private DocModule extractModuleDoc(string filePath, string rootDir)
{
    DocModule mod;
    mod.sourcePath = filePath;
    string source = readText(filePath);
    string[] lines = source.splitLines();

    Diagnostics diag = new Diagnostics;
    Lexer lexer = new Lexer(source, filePath, diag);
    Token[] tokens = lexer.tokenizer();
    Parser parser = new Parser(tokens, diag);
    parser.recoverIncomplete = true;
    Program program = parser.parse();

    if (program.modulePath.length)
    {
        string[] segs;
        foreach (dstring s; program.modulePath)
            segs ~= s.to!string;
        mod.moduleName = segs.join(".");
    }
    else
    {
        string rel = rootDir.length ? relativePath(filePath, rootDir) : baseName(filePath);
        mod.moduleName = stripExtension(rel).replace("\\", ".").replace("/", ".");
    }

    // Análise semântica opcional para enriquecer contratos de memória (`@pilha` trivial vs owned)
    Diagnostics semDiag = new Diagnostics;
    try
    {
        new ModuleLoader(semDiag).load(program, filePath);
        if (!semDiag.hasErrors())
            analyzeSemantics(program, semDiag);
    }
    catch (Exception)
    {
    }

    foreach (Node node; program.body)
    {
        if (ImportExpr imp = cast(ImportExpr) node)
        {
            if (imp.modulePath.length)
            {
                string[] segs;
                foreach (dstring s; imp.modulePath)
                    segs ~= s.to!string;
                mod.imports ~= segs.join(".");
            }
            else if (StringLit sl = cast(StringLit) imp.path)
                mod.imports ~= sl.value.to!string;
        }
        else if (ClassDecl cls = cast(ClassDecl) node)
        {
            DocItem item;
            item.kind = cls.isInterface ? "interface" : cls.isForeign ? "classe estrangeira"
                : cls.isValueType ? "classe @pilha" : "classe";
            item.name = cls.name.to!string;
            item.visibility = "publico";
            item.annotations = annotationList(cls.decorators, null, cls);
            item.signature = item.kind ~ " " ~ item.name;
            if (cls.superName.length)
                item.signature ~= " herda " ~ cls.superName.to!string;
            if (cls.pos !is null)
                item.docComment = extractLeadingDocComment(lines, cls.pos.start.line);
            item.examples = extractCodeExamples(item.docComment);
            if (cls.isValueType)
            {
                item.memoryContract = cls.isTrivialCopy
                    ? "Semântica de valor na stack (`Copy` trivial, sem alocação individual no GC)."
                    : "Semântica de valor proprietária (`Owned` não-trivial, destruição determinística RAII).";
            }
            else if (cls.isForeign)
            {
                item.memoryContract = "Fronteira FFI nativa (`" ~ cls.foreignLibrary.to!string ~ "`).";
            }
            foreach (ClassField f; cls.fields)
            {
                if (f.access == 1)
                    continue;
                string fSig = format("`%s: %s` (%s)", f.name.to!string,
                        f.type !is null ? f.type.toStr().to!string : "qualquer", visibilityStr(f.access));
                item.members ~= fSig;
            }
            foreach (FnDecl m; cls.methods)
            {
                if (m.accessor || m.access == 1 || m.fn.startsWith("#"d))
                    continue;
                string ann = formatAnnotations(m.decorators, m);
                string mDoc = m.pos !is null ? extractLeadingDocComment(lines, m.pos.start.line) : "";
                string entry = (ann.length ? ann ~ " " : "") ~ "`" ~ formatFnSignature(m) ~ "`";
                if (mDoc.length)
                    entry ~= " — " ~ mDoc.splitLines()[0];
                item.members ~= entry;
                item.examples ~= extractCodeExamples(mDoc);
            }
            mod.items ~= item;
        }
        else if (FnDecl fn = cast(FnDecl) node)
        {
            if (fn.fn.startsWith("#"d))
                continue;
            DocItem item;
            item.kind = "funcao";
            item.name = fn.fn.to!string;
            item.visibility = "publico";
            item.annotations = annotationList(fn.decorators, fn);
            item.signature = formatFnSignature(fn);
            if (fn.pos !is null)
                item.docComment = extractLeadingDocComment(lines, fn.pos.start.line);
            item.examples = extractCodeExamples(item.docComment);
            if (fn.isGpu)
                item.memoryContract = "Kernel `@gpu` verificável para computação numérica.";
            else if (fn.isNative)
                item.memoryContract = "Execução direta C99 (`@nativo`), sem boxing e sem GC interno.";
            else if (fn.ctfe_flags != 0)
                item.memoryContract = "Função pura (`@puro`) elegível para avaliação CTFE.";
            mod.items ~= item;
        }
        else if (VarDecl vd = cast(VarDecl) node)
        {
            if (vd.name.startsWith("#"d))
                continue;
            if (vd.isEnum || vd.isConst)
            {
                DocItem item;
                item.kind = vd.isEnum ? "enum" : "const";
                item.name = vd.name.to!string;
                item.visibility = "publico";
                item.signature = (vd.isEnum ? "enum " : "const ") ~ item.name
                    ~ (vd.type_expr !is null ? ": " ~ vd.type_expr.toStr().to!string : "");
                if (vd.pos !is null)
                    item.docComment = extractLeadingDocComment(lines, vd.pos.start.line);
                mod.items ~= item;
            }
        }
    }
    return mod;
}

private string renderMarkdown(const DocModule mod)
{
    string[] outLines;
    outLines ~= "# Módulo `" ~ mod.moduleName ~ "`";
    outLines ~= "";
    outLines ~= "Fonte: `" ~ mod.sourcePath ~ "`";
    outLines ~= "";
    if (mod.imports.length)
    {
        outLines ~= "## Dependências";
        outLines ~= "";
        foreach (string imp; mod.imports)
            outLines ~= "- `" ~ imp ~ "`";
        outLines ~= "";
    }
    foreach (const DocItem item; mod.items)
    {
        outLines ~= "## " ~ item.kind ~ " `" ~ item.name ~ "`";
        outLines ~= "";
        if (item.annotations.length)
            outLines ~= "**Anotações:** `" ~ item.annotations.join("` `") ~ "`";
        outLines ~= "";
        outLines ~= "```delegua";
        outLines ~= item.signature;
        outLines ~= "```";
        if (item.memoryContract.length)
        {
            outLines ~= "";
            outLines ~= "> **Contrato:** " ~ item.memoryContract;
        }
        if (item.docComment.length)
        {
            outLines ~= "";
            outLines ~= item.docComment;
        }
        if (item.members.length)
        {
            outLines ~= "";
            outLines ~= "### Membros";
            outLines ~= "";
            foreach (string m; item.members)
                outLines ~= "- " ~ m;
        }
        outLines ~= "";
    }
    return outLines.join("\n") ~ "\n";
}

private string escapeHtml(string s)
{
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;");
}

private string renderHtml(const DocModule mod)
{
    string html = "<!DOCTYPE html><html lang=\"pt-BR\"><head><meta charset=\"utf-8\">"
        ~ "<title>" ~ escapeHtml(mod.moduleName) ~ " — CGD Docs</title>"
        ~ "<style>body{font-family:system-ui,sans-serif;background:#0b0f14;color:#e6edf3;max-width:960px;margin:2rem auto;padding:0 1.5rem;}"
        ~ "h1,h2,h3{color:#58d68d;}code,pre{background:#161b22;border-radius:6px;padding:0.15rem 0.4rem;}"
        ~ "pre{padding:1rem;overflow-x:auto;}blockquote{border-left:3px solid #58d68d;padding-left:1rem;color:#9be7b5;}"
        ~ ".badge{display:inline-block;background:#1f3a2e;color:#7ee787;padding:2px 8px;border-radius:4px;margin-right:6px;font-size:0.85rem;}"
        ~ "</style></head><body>";
    html ~= "<h1>Módulo <code>" ~ escapeHtml(mod.moduleName) ~ "</code></h1>";
    html ~= "<p>Fonte: <code>" ~ escapeHtml(mod.sourcePath) ~ "</code></p>";
    if (mod.imports.length)
    {
        html ~= "<h2>Dependências</h2><ul>";
        foreach (string imp; mod.imports)
            html ~= "<li><code>" ~ escapeHtml(imp) ~ "</code></li>";
        html ~= "</ul>";
    }
    foreach (const DocItem item; mod.items)
    {
        html ~= "<h2>" ~ escapeHtml(item.kind) ~ " <code>" ~ escapeHtml(item.name) ~ "</code></h2>";
        if (item.annotations.length)
        {
            html ~= "<div>";
            foreach (string a; item.annotations)
                html ~= "<span class=\"badge\">" ~ escapeHtml(a) ~ "</span>";
            html ~= "</div>";
        }
        html ~= "<pre><code>" ~ escapeHtml(item.signature) ~ "</code></pre>";
        if (item.memoryContract.length)
            html ~= "<blockquote>" ~ escapeHtml(item.memoryContract) ~ "</blockquote>";
        if (item.docComment.length)
            html ~= "<p>" ~ escapeHtml(item.docComment).replace("\n", "<br>") ~ "</p>";
        if (item.members.length)
        {
            html ~= "<h3>Membros</h3><ul>";
            foreach (string m; item.members)
                html ~= "<li>" ~ escapeHtml(m) ~ "</li>";
            html ~= "</ul>";
        }
    }
    html ~= "</body></html>\n";
    return html;
}

void runDocumentCommand(string[] args)
{
    bool docLibraries = false;
    bool validateExamples = false;
    string fmt = "markdown";
    string outDir = "out/doc";
    string[] targets;

    for (size_t i = 0; i < args.length; i++)
    {
        string a = args[i];
        if (a == "--ajuda" || a == "-a" || a == "--help")
        {
            writeln("Uso: cgd documentar [arquivo|dir] [--bibliotecas] [--formato markdown|html] [--saida dir] [--validar]");
            return;
        }
        else if (a == "--bibliotecas")
            docLibraries = true;
        else if (a == "--validar")
            validateExamples = true;
        else if (a == "--formato" && i + 1 < args.length)
            fmt = args[++i];
        else if (a.startsWith("--formato="))
            fmt = a[10 .. $];
        else if ((a == "--saida" || a == "-s") && i + 1 < args.length)
            outDir = args[++i];
        else if (a.startsWith("--saida="))
            outDir = a[8 .. $];
        else
            targets ~= a;
    }

    if (fmt != "markdown" && fmt != "html")
        cgd_erro("Formato inválido em 'cgd documentar': use 'markdown' ou 'html'.");

    string[] files;
    string rootDir = "";
    if (docLibraries || !targets.length)
    {
        string[] roots = cgdLibraryRoots();
        string libRoot = exists("bibliotecas") && isDir("bibliotecas") ? "bibliotecas" : (roots.length ? roots[0] : "");
        if (!libRoot.length || !exists(libRoot))
            cgd_erro("Diretório de bibliotecas não encontrado.");
        rootDir = absolutePath(libRoot);
        foreach (DirEntry entry; dirEntries(rootDir, SpanMode.breadth))
            if (entry.isFile && extension(entry.name) == ".delegua")
                files ~= entry.name;
    }
    else
    {
        foreach (string t; targets)
        {
            if (!exists(t))
                cgd_erro("Caminho não encontrado para documentação: " ~ t);
            if (isFile(t) && extension(t) == ".delegua")
                files ~= absolutePath(t);
            else if (isDir(t))
            {
                rootDir = absolutePath(t);
                foreach (DirEntry entry; dirEntries(rootDir, SpanMode.breadth))
                    if (entry.isFile && extension(entry.name) == ".delegua")
                        files ~= entry.name;
            }
        }
    }

    files.sort();
    if (!exists(outDir))
        mkdirRecurse(outDir);

    DocModule[] modules;
    size_t exampleCount = 0;
    size_t exampleFailures = 0;

    foreach (string file; files)
    {
        DocModule mod = extractModuleDoc(file, rootDir);
        modules ~= mod;
        string safeName = mod.moduleName.replace(".", "_");
        string outFile = buildPath(outDir, safeName ~ (fmt == "html" ? ".html" : ".md"));
        write(outFile, fmt == "html" ? renderHtml(mod) : renderMarkdown(mod));

        if (validateExamples)
        {
            foreach (const DocItem item; mod.items)
            {
                foreach (string ex; item.examples)
                {
                    exampleCount++;
                    Diagnostics exDiag = new Diagnostics;
                    string tmpPath = buildPath(tempDir(), format("cgd_docex_%s.delegua", exampleCount));
                    try
                    {
                        write(tmpPath, ex);
                        scope (exit)
                            if (exists(tmpPath))
                                remove(tmpPath);
                        Lexer lx = new Lexer(ex, tmpPath, exDiag);
                        Token[] toks = lx.tokenizer();
                        Parser ps = new Parser(toks, exDiag);
                        Program pr = ps.parse();
                        if (!exDiag.hasErrors())
                        {
                            new ModuleLoader(exDiag).load(pr, tmpPath);
                            if (!exDiag.hasErrors())
                                analyzeSemantics(pr, exDiag);
                        }
                    }
                    catch (Exception e)
                    {
                        exDiag.error(null, e.msg);
                    }
                    if (exDiag.hasErrors())
                    {
                        exampleFailures++;
                        stderr.writefln("Exemplo inválido em %s (%s):", mod.moduleName, item.name);
                        exDiag.report();
                    }
                }
            }
        }
    }

    // Gera índice geral
    if (fmt == "html")
    {
        string idx = "<!DOCTYPE html><html lang=\"pt-BR\"><head><meta charset=\"utf-8\"><title>Índice CGD</title>"
            ~ "<style>body{font-family:system-ui,sans-serif;background:#0b0f14;color:#e6edf3;max-width:960px;margin:2rem auto;padding:0 1.5rem;}"
            ~ "a{color:#58d68d;}</style></head><body><h1>Documentação CGD</h1><ul>";
        foreach (const DocModule mod; modules)
        {
            string f = mod.moduleName.replace(".", "_") ~ ".html";
            idx ~= format("<li><a href=\"%s\">%s</a> (%d símbolos)</li>", f, escapeHtml(mod.moduleName), mod.items.length);
        }
        idx ~= "</ul></body></html>\n";
        write(buildPath(outDir, "index.html"), idx);
    }
    else
    {
        string[] idx = ["# Documentação Automática CGD", ""];
        foreach (const DocModule mod; modules)
        {
            string f = mod.moduleName.replace(".", "_") ~ ".md";
            idx ~= format("- [`%s`](%s) (%d símbolos)", mod.moduleName, f, mod.items.length);
        }
        write(buildPath(outDir, "README.md"), idx.join("\n") ~ "\n");
    }

    writefln("Documentação gerada em '%s' (%d módulo(s), formato %s).", outDir, modules.length, fmt);
    if (validateExamples)
    {
        writefln("Validação de exemplos: %d verificado(s), %d falha(s).", exampleCount, exampleFailures);
        if (exampleFailures > 0)
            cgd_erro("Há exemplos inválidos na documentação.");
    }
}
