module frontend.modules;
import frontend;
import std.file;
import std.path;
import std.conv;
import std.string;
import std.algorithm : canFind;
import core.sys.posix.stdlib : realpath;
import core.stdc.stdlib : free;

class ModuleLoader
{
    Diagnostics diagnostics;
    ModuleUnit[string] cache;
    bool[string] active;
    size_t depth;
    this(Diagnostics diagnostics)
    {
        this.diagnostics = diagnostics;
    }

    string canonical(string path)
    {
        auto resolved = realpath(path.toStringz, null);
        if (resolved is null)
            throw new Exception("Módulo não encontrado: " ~ path);
        scope (exit)
            free(resolved);
        return resolved.fromStringz.idup;
    }

    void load(Program program, string filename)
    {
        auto path = canonical(filename);
        active[path] = true;
        visit(program, path);
        active.remove(path);
    }

    void visit(Node node, string filename)
    {
        if (node is null)
            return;
        if (auto imported = cast(ImportExpr) node)
        {
            auto literal = cast(StringLit) imported.path;
            if (literal is null)
            {
                diagnostics.error(node.pos, "Importação exige caminho literal conhecido na compilação.");
                return;
            }
            auto path = literal.value.to!string;
            if (path.canFind('\0'))
            {
                diagnostics.error(node.pos, "Caminho de módulo contém byte nulo.");
                return;
            }
            if (extension(path) != ".delegua")
            {
                diagnostics.warning(node.pos, "Carregamento dinâmico/NPM/FFI não é suportado por segurança.");
                diagnostics.error(node.pos, "Importe um módulo fonte .delegua.");
                return;
            }
            try
            {
                auto target = canonical(buildPath(dirName(filename), path));
                if (target in active)
                {
                    diagnostics.error(node.pos, "Ciclo de importação detectado: " ~ target);
                    return;
                }
                if (auto cached = target in cache)
                {
                    imported.target = *cached;
                    return;
                }
                if (depth >= 64)
                {
                    diagnostics.error(node.pos, "Limite de profundidade de módulos excedido.");
                    return;
                }
                active[target] = true;
                depth++;
                scope (exit)
                {
                    active.remove(target);
                    depth--;
                }
                auto tokens = new Lexer(readText(target), target, diagnostics).tokenizer();
                auto program = new Parser(tokens, diagnostics).parse();
                auto unit = new ModuleUnit(target, program, node.pos);
                cache[target] = unit;
                imported.target = unit;
                visit(program, target);
            }
            catch (Exception e)
            {
                diagnostics.error(node.pos, e.msg);
            }
            return;
        }
        foreach (child; childNodes(node))
            visit(child, filename);
    }
}
