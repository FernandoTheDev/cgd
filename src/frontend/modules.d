module frontend.modules;
import frontend;
import std.file;
import std.path;
import std.conv;
import std.string;
import std.algorithm : canFind;
import std.array : join;

version (Posix) import core.sys.posix.stdlib : realpath;
import core.stdc.stdlib : free;

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
            if (path == "cgd:json" || path == "cgd:rede" || path == "cgd:colecoes" || path == "cgd:arquivos"
                    || path == "cgd:matematica" || path == "cgd:nativo" || path == "cgd:textos"
                    || path == "cgd:estatistica" || path == "cgd:caminhos"
                    || path == "cgd:processo" || path == "cgd:ambiente" || path == "cgd:sistema"
                    || path == "cgd:tempo" || path == "cgd:sockets"
                    || path == "cgd:assincrono" || path == "cgd:servidor" || path == "cgd:io"
                    || path == "cgd:algoritmos" || path == "cgd:cli"
                    || path == "cgd:log" || path == "cgd:bytes" || path == "cgd:cripto"
                    || path == "cgd:compressao" || path == "cgd:sqlite")
                path = buildPath(dirName(thisExePath()), "bibliotecas", path[4 .. $] ~ ".delegua");
            else if (path.startsWith("cgd:"))
            {
                diagnostics.error(node.pos, "Biblioteca CGD desconhecida: " ~ path, "E2003");
                return;
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
                string target = canonical(buildPath(dirName(filename), path));
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
