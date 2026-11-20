module frontend.modules;

import frontend;
import std.algorithm : canFind, sort;
import std.array : join;
import std.conv;
import std.file;
import std.path;
import std.process : environment;
import std.string;

version (Posix) import core.sys.posix.stdlib : realpath;
import core.stdc.stdlib : free;

struct CgdLibraryEntry
{
    string name;
    string path;
    bool fromUserDir;
}

/// Diretórios de busca das bibliotecas `cgd:`, em ordem de prioridade:
/// 1) `CGD_LIBS_DIR` (se definida) ou `~/.delegua/cgd`
/// 2) `bibliotecas/` ao lado do executável (fallback de checkout/bundle)
string[] cgdLibraryRoots()
{
    string[] roots;
    string envLibs = environment.get("CGD_LIBS_DIR");
    if (envLibs.length)
        roots ~= envLibs;
    else
    {
        string home = environment.get("HOME");
        version (Windows)
            if (!home.length)
                home = environment.get("USERPROFILE");
        if (home.length)
            roots ~= buildPath(home, ".delegua", "cgd");
    }
    string exeLibs = buildPath(dirName(thisExePath()), "bibliotecas");
    if (!roots.canFind(exeLibs))
        roots ~= exeLibs;
    return roots;
}

/// Valida nome de módulo após `cgd:`, impedindo travessia de caminho e caracteres inválidos.
bool isValidCgdModuleName(string name)
{
    if (!name.length || name.startsWith("/") || name.endsWith("/") || name.canFind('\\')
            || name.canFind('\0') || name.canFind(':'))
        return false;
    string[] segments = name.split("/");
    foreach (string segment; segments)
    {
        if (!segment.length || segment == "." || segment == "..")
            return false;
        foreach (char ch; segment)
        {
            bool ok = cast(ubyte) ch >= 128 || (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z')
                || (ch >= '0' && ch <= '9') || ch == '_' || ch == '-';
            if (!ok)
                return false;
        }
    }
    return true;
}

/// Resolve `cgd:<nome>` procurando `<nome>.delegua` nos diretórios configurados.
string resolveCgdLibrary(string name, string[string] overlays = null)
{
    if (!isValidCgdModuleName(name))
        return null;
    string[] segments = name.split("/");
    string relative = buildPath(segments) ~ ".delegua";
    foreach (string root; cgdLibraryRoots())
    {
        string candidate = buildPath(root, relative);
        string normalized = absolutePath(candidate).asNormalizedPath.to!string;
        if (overlays !is null && (normalized in overlays))
            return normalized;
        if (exists(candidate) && isFile(candidate))
            return candidate;
    }
    return null;
}

/// Lista bibliotecas `.delegua` disponíveis para `importar("cgd:...")` (priorizando `~/.delegua/cgd`).
CgdLibraryEntry[] listCgdLibraries()
{
    CgdLibraryEntry[] entries;
    bool[string] seen;
    string[] roots = cgdLibraryRoots();
    foreach (size_t rootIndex, string root; roots)
    {
        if (!exists(root) || !isDir(root))
            continue;
        bool fromUserDir = rootIndex == 0 && root != buildPath(dirName(thisExePath()), "bibliotecas");
        size_t scanned;
        try
        {
            foreach (DirEntry entry; dirEntries(root, SpanMode.breadth))
            {
                if (++scanned > 512)
                    break;
                if (!entry.isFile || extension(entry.name) != ".delegua")
                    continue;
                string rel = relativePath(entry.name, root);
                string withoutExt = stripExtension(rel).replace("\\", "/");
                if (!isValidCgdModuleName(withoutExt) || (withoutExt in seen))
                    continue;
                seen[withoutExt] = true;
                entries ~= CgdLibraryEntry(withoutExt, entry.name, fromUserDir);
            }
        }
        catch (FileException)
        {
            continue;
        }
    }
    entries.sort!((CgdLibraryEntry a, CgdLibraryEntry b) => a.name < b.name)();
    return entries;
}

class ModuleLoader
{
    Diagnostics diagnostics;
    string[string] overlays;
    ModuleUnit[string] cache;
    bool[string] active;
    size_t depth;
    size_t totalBytes;
    string[] importStack;
    this(Diagnostics diagnostics, string[string] overlays = null)
    {
        this.diagnostics = diagnostics;
        this.overlays = overlays;
    }

    string canonical(string path)
    {
        string absolute = absolutePath(path).asNormalizedPath.to!string;
        if (absolute in overlays)
            return absolute;
        version (Posix)
        {
            char* resolved = realpath(path.toStringz, null);
            if (resolved is null)
                throw new Exception("Módulo não encontrado: " ~ path);
            scope (exit)
                free(resolved);
            return resolved.fromStringz.idup;
        }
        else
        {
            string normalized = absolutePath(path).asNormalizedPath.to!string;
            if (!exists(normalized) || !isFile(normalized))
                throw new Exception("Módulo não encontrado: " ~ path);
            // A resolução de junctions/symlinks Windows ainda requer validação nativa.
            version (Windows)
                return normalized.toLower;
            else
                return normalized;
        }
    }

    void load(Program program, string filename)
    {
        string path = canonical(filename);
        active[path] = true;
        importStack ~= path;
        scope (exit)
        {
            active.remove(path);
            importStack.length--;
        }
        visit(program, path);
    }

    void visit(Node node, string filename)
    {
        if (node is null)
            return;
        if (ImportExpr imported = cast(ImportExpr) node)
        {
            StringLit literal = cast(StringLit) imported.path;
            if (literal is null)
            {
                diagnostics.error(node.pos, "Importação exige caminho literal conhecido na compilação.");
                return;
            }
            string path = literal.value.to!string;
            if (path.startsWith("cgd:"))
            {
                string resolved = resolveCgdLibrary(path[4 .. $], overlays);
                if (!resolved.length)
                {
                    diagnostics.error(node.pos, "Biblioteca CGD desconhecida: " ~ path, "E2003");
                    return;
                }
                path = resolved;
            }
            if (path.canFind('\0'))
            {
                diagnostics.error(node.pos, "Caminho de módulo contém byte nulo.");
                return;
            }
            if (extension(path) != ".delegua")
            {
                diagnostics.warningCode(node.pos, dynamicWarning);
                diagnostics.errorCode(node.pos, dynamicError);
                return;
            }
            try
            {
                string target = canonical(isAbsolute(path) ? path : buildPath(dirName(filename), path));
                if (target in active)
                {
                    diagnostics.errorCode(node.pos, moduleCycle, importStack.join(" -> ") ~ " -> " ~ target);
                    return;
                }
                if (ModuleUnit* cached = target in cache)
                {
                    imported.target = *cached;
                    return;
                }
                if (depth >= 64)
                {
                    diagnostics.error(node.pos, "Limite de profundidade de módulos excedido.");
                    return;
                }
                string* buffer = target in overlays;
                size_t bytes = buffer is null ? getSize(target) : (*buffer).length;
                if (bytes > 4 * 1024 * 1024 || totalBytes + bytes > 64 * 1024 * 1024 || cache.length >= 1024)
                {
                    diagnostics.errorCode(node.pos, moduleBudget);
                    return;
                }
                totalBytes += cast(size_t) bytes;
                importStack ~= target;
                active[target] = true;
                depth++;
                scope (exit)
                {
                    active.remove(target);
                    depth--;
                    importStack.length--;
                }
                Token[] tokens = new Lexer(buffer is null
                        ? cast(string) std.file.read(target) : *buffer, target, diagnostics).tokenizer();
                if (diagnostics.hasErrors())
                    return;
                Program program = new Parser(tokens, diagnostics).parse();
                if (diagnostics.hasErrors())
                    return;
                ModuleUnit unit = new ModuleUnit(target, program, node.pos);
                cache[target] = unit;
                imported.target = unit;
                visit(program, target);
            }
            catch (Exception e)
            {
                diagnostics.errorCode(node.pos, moduleLoad, e.msg, importStack.join(" -> "));
            }
            return;
        }
        foreach (Node child; childNodes(node))
            visit(child, filename);
    }
}
