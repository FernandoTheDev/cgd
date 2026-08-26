// rdmd testes/unitario.d
module testes.unitario;

import std.format;
import std.stdio;
import std.file;
import std.algorithm;
import std.array;
import std.process;
import std.typecons;
import std.range;
import std.conv;
import std.string;
import std.path;

string escape(string str)
{
    ulong offset;
    string buffer;
    while (offset < str.length)
    {
        char ch = str[offset++];
        if (ch == '\\' && offset < str.length)
        {
            char esc = str[offset];
            switch (esc)
            {
            case 'n':
                buffer ~= '\n';
                offset++;
                continue;
            case '\\':
                buffer ~= '\\';
                offset++;
                continue;
            default:
                break;
            }
        }
        buffer ~= [ch];
    }
    return buffer;
}

struct TestResult
{
    string filename;
    bool ok;
    string err;
    bool ignored;
}

TestResult runTest(string filename)
{
    TestResult res;
    res.filename = filename;
    // writefln("Processando '%s'.", filename);

    File content = File(filename, "r");
    auto lines = content.byLine();

    string line1 = lines.front.idup;
    lines.popFront();

    bool useOptFlag = line1.length >= 3 && line1[0 .. 3] == "//$";

    // se a linha 1 for o marcador //$, a diretiva real está na linha 2
    string directiveLine = useOptFlag ? lines.front.idup : line1;
    content.close();

    bool fromCode   = directiveLine.length > 3 && directiveLine[0 .. 3] == "//#";
    bool fromOutput = directiveLine.length > 3 && directiveLine[0 .. 3] == "//!";

    if (!fromCode && !fromOutput)
    {
        res.ignored = true;
        return res;
    }

    // conteúdo após o prefixo "//#" ou "//!"
    string directive = directiveLine[3 .. $].strip;

    string cFile   = filename ~ ".c";
    string binFile = filename.stripExtension.baseName;

    // garante que não sobrou binário de uma rodada anterior antes de compilar
    remove_if_exists(binFile);

    string compileCmd = useOptFlag
        ? format("./cgd %s -o", filename)
        : format("./cgd %s", filename);

    auto compile = executeShell(compileCmd);
    bool compileFailed = compile.status != 0;

    if (compileFailed)
    {
        remove_if_exists(cFile);

        if (fromCode)
        {
            int expected;
            try
                expected = to!int(directive);
            catch (Exception e)
            {
                res.ok  = false;
                res.err = format("Invalid //# directive: '%s' (%s)", directive, e.msg);
                return res;
            }

            res.ok = expected == compile.status;
            if (!res.ok)
                res.err = format(
                    "Expected compiler exit code '%d', got '%d'.\n%s",
                    expected, compile.status, compile.output
                );
            return res;
        }

        res.ok  = false;
        res.err = "CGD compiler failed:\n" ~ compile.output;
        return res;
    }

    auto run = executeShell(format("./%s", binFile));
    int code = run.status;
    string output = run.output.strip;

    res.ok = true;

    if (fromCode)
    {
        int expected;
        try
            expected = to!int(directive);
        catch (Exception e)
        {
            res.ok  = false;
            res.err = format("Invalid //# directive: '%s' (%s)", directive, e.msg);
            remove_if_exists(cFile);
            remove_if_exists(binFile);
            return res;
        }

        if (expected != code)
        {
            res.ok  = false;
            res.err = format("Expected exit code '%d', got '%d'.", expected, code);
        }
    }
    else if (fromOutput)
    {
        string expected = escape(directive).strip;
        if (output != expected)
        {
            res.ok  = false;
            res.err = format("Expected output '%s', got '%s'.", expected, output);
        }
    }

    remove_if_exists(cFile);
    remove_if_exists(binFile);
    return res;
}

void remove_if_exists(string path)
{
    if (exists(path))
        remove(path);
}

string readTextSafe(string path)
{
    if (!exists(path))
        return "(file not found)";
    return readText(path);
}

int main()
{
    string folder = "exemplos";
    ulong sucesso, erros, ignorados;

    DirEntry[] dir = dirEntries(folder, SpanMode.depth)
        .filter!(x => x.name.endsWith(".delegua"))
        .array
        .sort!((a, b) => a.name < b.name)
        .array;

    writeln("=== CGD ===");
    foreach (DirEntry key; dir)
    {
        TestResult res = runTest(key.name);
        if (res.ignored)
        {
            writefln("  IGNORED   %s", res.filename);
            ignorados++;
        }
        else if (res.ok)
        {
            writefln("  PASS      %s", res.filename);
            sucesso++;
        }
        else
        {
            writefln("  FAIL      %s", res.filename);
            writeln("            ", res.err);
            erros++;
        }
    }

    writeln();
    writefln("PASSED:  %d", sucesso);
    writefln("FAILED:  %d", erros);
    writefln("IGNORED: %d", ignorados);
    writefln("TOTAL:   %d", sucesso + erros + ignorados);

    return erros ? 1 : 0;
}
