module frontend.modules;

import frontend;
import frontend.conditional;
import driver.target_info;
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

/// Aliases canônicos da biblioteca padrão hierárquica (sem duplicar implementações).
string resolveCgdAlias(string name)
{
    switch (name)
    {
        case "sistema/arquivos":
            return "arquivos";
        case "sistema/caminhos":
            return "caminhos";
        case "sistema/processos":
            return "processo";
        case "sistema/ambiente":
            return "ambiente";
        case "sistema/memoria":
            return "memoria";
        case "sistema/plataforma":
            return "sistema";
        case "sistema/cli":
            return "cli";
        case "sistema/tempo":
            return "tempo";
        case "sistema/io":
            return "io";
        case "sistema/log":
            return "log";
        case "sistema/terminal":
            return "interface/terminal";
        case "dados/json":
            return "json";
        case "dados/binario":
            return "bytes";
        case "dados/compressao":
            return "compressao";
        case "dados/sqlite":
            return "sqlite";
        case "rede/tcp":
        case "rede/udp":
        case "rede/dns":
        case "rede/sockets":
            return "sockets";
        case "rede/cliente":
            return "rede";
        case "rede/assincrono":
            return "servidor";
        case "matematica/base":
            return "matematica";
        case "matematica/estatistica":
            return "estatistica";
        case "matematica/algoritmos":
            return "algoritmos";
        case "texto/unicode":
        case "texto/formatacao":
        case "texto/utilitarios":
            return "textos";
        case "concorrencia/assincrono":
        case "concorrencia/rotinas":
        case "concorrencia/canais":
        case "concorrencia/tarefas":
            return "assincrono";
        case "seguranca/criptografia":
        case "seguranca/hashing":
        case "seguranca/aleatoriedade":
            return "cripto";
        default:
            return null;
    }
}

immutable string[] CGD_HIERARCHICAL_ALIASES = [
    "sistema/arquivos", "sistema/caminhos", "sistema/processos", "sistema/ambiente",
    "sistema/memoria", "sistema/plataforma", "sistema/cli", "sistema/tempo", "sistema/io",
    "sistema/log", "sistema/terminal", "dados/json", "dados/binario", "dados/compressao",
    "dados/sqlite", "rede/tcp", "rede/udp", "rede/dns", "rede/sockets", "rede/cliente",
    "rede/assincrono", "matematica/base", "matematica/estatistica", "matematica/algoritmos",
    "texto/unicode", "texto/formatacao", "texto/utilitarios", "concorrencia/assincrono",
    "concorrencia/rotinas", "concorrencia/canais", "concorrencia/tarefas",
    "seguranca/criptografia", "seguranca/hashing", "seguranca/aleatoriedade"
];

/// Resolve `cgd:<nome>` procurando `<nome>.delegua`, `<nome>/mod.delegua` ou `<nome>/indice.delegua`.
string resolveCgdLibrary(string name, string[string] overlays = null)
{
    if (!isValidCgdModuleName(name))
        return null;
    string[] namesToTry = [name];
    string aliased = resolveCgdAlias(name);
    if (aliased.length && aliased != name)
        namesToTry ~= aliased;
    foreach (string candidateName; namesToTry)
    {
        string[] segments = candidateName.split("/");
        string baseRel = buildPath(segments);
        string[] relatives = [
            baseRel ~ ".delegua",
            buildPath(baseRel, "mod.delegua"),
            buildPath(baseRel, "indice.delegua")
        ];
        foreach (string root; cgdLibraryRoots())
        {
            foreach (string relative; relatives)
            {
                string candidate = buildPath(root, relative);
                string normalized = absolutePath(candidate).asNormalizedPath.to!string;
                if (overlays !is null && (normalized in overlays))
                    return normalized;
                if (exists(candidate) && isFile(candidate))
                    return candidate;
            }
        }
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
                if (++scanned > 1024)
                    break;
                if (!entry.isFile || extension(entry.name) != ".delegua")
                    continue;
                string rel = relativePath(entry.name, root);
                string withoutExt = stripExtension(rel).replace("\\", "/");
                string logicalName = withoutExt;
                if (logicalName.endsWith("/mod"))
                    logicalName = logicalName[0 .. $ - 4];
                else if (logicalName.endsWith("/indice"))
                    logicalName = logicalName[0 .. $ - 7];
                if (!isValidCgdModuleName(logicalName) || (logicalName in seen))
                    continue;
                seen[logicalName] = true;
                entries ~= CgdLibraryEntry(logicalName, entry.name, fromUserDir);
            }
        }
        catch (FileException)
        {
            continue;
        }
    }
    foreach (string aliasName; CGD_HIERARCHICAL_ALIASES)
    {
        if (aliasName in seen)
            continue;
        string resolved = resolveCgdLibrary(aliasName);
        if (resolved.length)
        {
            seen[aliasName] = true;
            entries ~= CgdLibraryEntry(aliasName, resolved, false);
        }
    }
    entries.sort!((CgdLibraryEntry a, CgdLibraryEntry b) => a.name < b.name)();
    return entries;
}

/// Descobre raízes de busca de módulos a partir do arquivo de entrada e eventual `projeto.json` ancestral.
string[] discoverModuleRoots(string entryFilename, string[] extraRoots = null)
{
    string[] roots;
    void addRoot(string dir)
    {
        if (!dir.length)
            return;
        string norm = absolutePath(dir).asNormalizedPath.to!string;
        if (!roots.canFind(norm) && exists(norm) && isDir(norm))
            roots ~= norm;
    }

    foreach (string extra; extraRoots)
        addRoot(extra);

    string entryDir = dirName(absolutePath(entryFilename).asNormalizedPath.to!string);
    string cursor = entryDir;
    for (size_t i = 0; i < 16; i++)
    {
        string manifest = buildPath(cursor, "projeto.json");
        if (exists(manifest) && isFile(manifest))
        {
            addRoot(buildPath(cursor, "fontes"));
            addRoot(buildPath(cursor, "src"));
            addRoot(buildPath(cursor, "pacotes"));
            addRoot(cursor);
            break;
        }
        string parent = dirName(cursor);
        if (parent == cursor || !parent.length)
            break;
        cursor = parent;
    }
    addRoot(entryDir);
    return roots;
}

class ModuleLoader
{
    Diagnostics diagnostics;
    string[string] overlays;
    string[] moduleRoots;
    TargetInfo targetInfo;
    ModuleUnit[string] cache;
    bool[string] active;
    size_t depth;
    size_t totalBytes;
    string[] importStack;
    this(Diagnostics diagnostics, string[string] overlays = null, string[] moduleRoots = null,
            TargetInfo targetInfo = TargetInfo.hostDefault())
    {
        this.diagnostics = diagnostics;
        this.overlays = overlays;
        this.moduleRoots = moduleRoots;
        this.targetInfo = targetInfo;
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
        moduleRoots = discoverModuleRoots(path, moduleRoots);
        if (program !is null && program.modulePath.length > 1)
        {
            // Se o arquivo raiz declara `modulo a.b.c`, a raiz do namespace está (len-1) diretórios acima.
            string inferred = dirName(path);
            for (size_t i = 1; i < program.modulePath.length; i++)
            {
                string parent = dirName(inferred);
                if (parent == inferred || !parent.length)
                    break;
                inferred = parent;
            }
            if (exists(inferred) && isDir(inferred) && !moduleRoots.canFind(inferred))
                moduleRoots ~= inferred;
        }
        active[path] = true;
        importStack ~= path;
        scope (exit)
        {
            active.remove(path);
            importStack.length--;
        }
        applyConditionalCompilation(program, targetInfo, diagnostics);
        if (diagnostics.hasErrors())
            return;
        visit(program, path);
    }

    private string resolveQualifiedModule(dstring[] modulePath, string currentFilename)
    {
        if (!modulePath.length)
            return null;
        string[] segs;
        foreach (dstring seg; modulePath)
        {
            string s = seg.to!string;
            if (!s.length || s == "." || s == ".." || s.canFind('/') || s.canFind('\\') || s.canFind('\0'))
                return null;
            segs ~= s;
        }
        if (segs[0] == "cgd" && segs.length >= 2)
            return resolveCgdLibrary(segs[1 .. $].join("/"), overlays);

        string baseRel = buildPath(segs);
        string[] relatives = [
            baseRel ~ ".delegua",
            buildPath(baseRel, "mod.delegua"),
            buildPath(baseRel, "indice.delegua")
        ];
        string[] searchRoots = moduleRoots.dup;
        string currentDir = dirName(currentFilename);
        if (!searchRoots.canFind(currentDir))
            searchRoots ~= currentDir;

        foreach (string root; searchRoots)
        {
            foreach (string relative; relatives)
            {
                string candidate = buildPath(root, relative);
                string normalized = absolutePath(candidate).asNormalizedPath.to!string;
                if (overlays !is null && (normalized in overlays))
                    return normalized;
                if (exists(candidate) && isFile(candidate))
                    return candidate;
            }
        }
        return null;
    }

    void visit(Node node, string filename)
    {
        if (node is null)
            return;
        if (ImportExpr imported = cast(ImportExpr) node)
        {
            string path;
            if (imported.modulePath.length > 0)
            {
                string resolved = resolveQualifiedModule(imported.modulePath, filename);
                if (!resolved.length)
                {
                    dstring joined = imported.modulePath.join("."d);
                    diagnostics.error(node.pos, "Módulo não encontrado: " ~ joined.to!string, "E2003");
                    return;
                }
                path = resolved;
            }
            else
            {
                StringLit literal = cast(StringLit) imported.path;
                if (literal is null)
                {
                    diagnostics.error(node.pos, "Importação exige caminho literal conhecido na compilação.");
                    return;
                }
                path = literal.value.to!string;
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
                    if (imported.modulePath.length > 0 && (*cached).program !is null
                            && (*cached).program.modulePath.length > 0
                            && (*cached).program.modulePath != imported.modulePath)
                    {
                        diagnostics.error(node.pos,
                                "Nome de módulo incompatível: importado como '"
                                ~ imported.modulePath.join("."d).to!string ~ "', mas declarado como '"
                                ~ (*cached).program.modulePath.join("."d).to!string ~ "'.", "E2003");
                    }
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
                applyConditionalCompilation(program, targetInfo, diagnostics);
                if (diagnostics.hasErrors())
                    return;
                if (imported.modulePath.length > 0 && program.modulePath.length > 0
                        && program.modulePath != imported.modulePath)
                {
                    diagnostics.error(program.modulePos !is null ? program.modulePos : node.pos,
                            "Nome de módulo incompatível: importado como '"
                            ~ imported.modulePath.join("."d).to!string ~ "', mas declarado como '"
                            ~ program.modulePath.join("."d).to!string ~ "'.", "E2003");
                    return;
                }
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
