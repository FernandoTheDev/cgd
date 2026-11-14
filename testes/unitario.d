// rdmd testes/unitario.d
// rdmd testes/unitario.d -- --coverage
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
import std.getopt;

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

// Diretório raiz onde cada teste grava seus .lst isoladamente quando --coverage está ativo
enum COV_RAW_DIR = "cov_raw";

auto runExample(string binary, string input)
{
    if (!input.length) return execute([absolutePath(binary)]);
    auto process = pipeProcess([absolutePath(binary)], Redirect.stdin | Redirect.stdout | Redirect.stderrToStdout);
    process.stdin.write(input);
    process.stdin.close();
    string output = cast(string) process.stdout.byChunk(4096).join;
    auto status = wait(process.pid);
    return tuple!("status", "output")(status, output);
}

TestResult runTest(string filename, bool coverageMode)
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

    // cada teste grava seus .lst numa subpasta própria, isolada, pra não
    // sobrescrever o resultado do teste anterior que tocou nos mesmos módulos
    string[string] env;
    if (coverageMode)
    {
        string covDir = buildPath(COV_RAW_DIR, sanitizeTestName(filename));
        if (!covDir.exists)
            mkdirRecurse(covDir);
        env["COVDIR"] = covDir;
    }

    string compileCmd = useOptFlag
        ? format("./cgd %s -o", filename)
        : format("./cgd %s", filename);

    auto compile = executeShell(compileCmd, env);
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

    string input;
    foreach (line; readText(filename).splitLines())
        if (line.startsWith("//? entrada:")) input = escape(line[12 .. $].strip());
    auto run = runExample(binFile, input);
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

// Transforma "exemplos/ctfe/1.delegua" em "exemplos_ctfe_1" pra usar como
// nome de subpasta sem colidir e sem precisar de path separators
string sanitizeTestName(string filename)
{
    return filename.stripExtension.replace("/", "_").replace("\\", "_");
}

// ===================== Merge de coverage =====================

struct ModuleCoverage
{
    string sourceFile;      // ex: src/frontend/lexer/lexer.d
    long[] execCounts;      // execCounts[i] = quantas vezes a linha i executou (soma de todas as runs); -1 = linha não executável
    string[] lines;         // texto da linha, sem o prefixo de contagem
}

// Um .lst do D tem o formato:
//         12|void foo() {
//          0|    never_called();
//           |// comentário, linha não executável
// linha final: "arquivo.d is XX% covered"
ModuleCoverage parseLst(string path)
{
    ModuleCoverage mc;
    mc.sourceFile = path.baseName.stripExtension;

    auto raw = readText(path).splitLines;
    foreach (line; raw)
    {
        auto pipeIdx = line.indexOf('|');
        if (pipeIdx < 0)
            continue; // linha de rodapé tipo "X.d is YY% covered" ou lixo

        string countPart = line[0 .. pipeIdx].strip;
        string codePart  = pipeIdx + 1 <= line.length ? line[pipeIdx + 1 .. $] : "";

        long count = -1; // não executável
        if (countPart.length)
        {
            try
                count = to!long(countPart);
            catch (Exception)
                count = -1;
        }

        mc.execCounts ~= count;
        mc.lines ~= codePart;
    }

    return mc;
}

void mergeInto(ref ModuleCoverage acc, ModuleCoverage incoming)
{
    if (acc.sourceFile.length == 0)
    {
        acc = incoming;
        return;
    }

    // Módulos devem ter o mesmo número de linhas entre execuções diferentes
    // (mesmo binário instrumentado); se não bater, algo mudou no meio do
    // caminho — mantemos o maior conjunto e ignoramos o excesso por segurança.
    size_t n = min(acc.execCounts.length, incoming.execCounts.length);
    foreach (i; 0 .. n)
    {
        if (incoming.execCounts[i] >= 0)
        {
            if (acc.execCounts[i] < 0)
                acc.execCounts[i] = incoming.execCounts[i];
            else
                acc.execCounts[i] += incoming.execCounts[i];
        }
    }
}

double coveragePercent(ModuleCoverage mc)
{
    long executable, covered;
    foreach (c; mc.execCounts)
    {
        if (c < 0)
            continue;
        executable++;
        if (c > 0)
            covered++;
    }
    if (executable == 0)
        return -1; // "has no code"
    return (cast(double) covered / cast(double) executable) * 100.0;
}

// Lê todos os .lst espalhados nas subpastas de COV_RAW_DIR, funde por nome
// de arquivo-fonte e imprime a % final agregada de todas as execuções.
void reportCoverage()
{
    if (!COV_RAW_DIR.exists)
    {
        writeln("Nenhum dado de coverage encontrado (", COV_RAW_DIR, " não existe).");
        return;
    }

    ModuleCoverage[string] merged;

    auto lstFiles = dirEntries(COV_RAW_DIR, SpanMode.depth)
        .filter!(x => x.name.endsWith(".lst"))
        .array;

    foreach (entry; lstFiles)
    {
        auto mc = parseLst(entry.name);
        if (mc.sourceFile !in merged)
            merged[mc.sourceFile] = ModuleCoverage.init;
        mergeInto(merged[mc.sourceFile], mc);
    }

    writeln();
    writeln("=== Coverage (acumulado de ", lstFiles.length, " execuções) ===");

    auto names = merged.keys.sort!((a, b) => a < b).array;

    double totalPct = 0;
    size_t countedModules = 0;

    foreach (name; names)
    {
        auto mc = merged[name];
        double pct = coveragePercent(mc);
        if (pct < 0)
        {
            writefln("  %-45s  (sem código executável)", name);
            continue;
        }
        writefln("  %-45s  %6.2f%%", name, pct);
        totalPct += pct;
        countedModules++;
    }

    if (countedModules > 0)
    {
        writeln();
        writefln("Média simples entre módulos: %.2f%%", totalPct / countedModules);
    }

    // limpa os dados brutos; o merge acima já é o resultado final
    rmdirRecurse(COV_RAW_DIR);
}

int main(string[] args)
{
    bool coverageMode = false;
    auto helpInfo = getopt(args, "coverage", &coverageMode);

    // limpa uma pasta de coverage órfã de uma rodada anterior interrompida
    if (coverageMode && COV_RAW_DIR.exists)
        rmdirRecurse(COV_RAW_DIR);

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
        TestResult res = runTest(key.name, coverageMode);
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

    if (coverageMode)
        reportCoverage();

    return erros ? 1 : 0;
}
