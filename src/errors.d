module errors;

public import diagnostics.catalog;

import frontend.lexer.token : Position;
import std.algorithm : any, count, min, max;
import std.array : array, split;
import std.file : readText;
import std.format : format;
import std.json : JSONValue;
import std.range : repeat;
import std.stdio : stderr;
import std.string : splitLines;
import std.conv : to;

/// JSON Lines em stderr permite consumir avisos de passes distintos sem texto misto.
enum DiagnosticFormat
{
    text,
    json
}

DiagnosticFormat diagnosticFormat;

enum Severity : ubyte
{
    Hint,
    Warning,
    Error
}

string label(Severity severity)
{
    final switch (severity)
    {
        case Severity.Hint:
            return "dica";
        case Severity.Warning:
            return "aviso";
        case Severity.Error:
            return "erro";
    }
}

struct Diagnostic
{
    Severity severity;
    Position position;
    string message;
    string code;
}

string diagnosticJSON(const Diagnostic d)
{
    JSONValue result = JSONValue([
        "severity": JSONValue(label(d.severity)),
        "code": JSONValue(d.code),
        "message": JSONValue(d.message)
    ]);
    if (const(MessageSpec)* spec = lookupMessage(d.code))
        result["explanation"] = spec.explanation;
    if (d.position !is null)
    {
        result["file"] = d.position.filename;
        result["range"] = JSONValue([
            "start": JSONValue([
                "line": JSONValue(d.position.start.line),
                "column": JSONValue(d.position.start.offset)
            ]),
            "end": JSONValue([
                "line": JSONValue(d.position.end.line),
                "column": JSONValue(d.position.end.offset)
            ])
        ]);
    }
    return result.toString();
}

/// Colunas do lexer são pontos de código, começando em 1. A tabulação usa 4 espaços.
string diagnosticText(const Diagnostic d, string source = "")
{
    string result = format("%s[%s]: %s\n", label(d.severity), d.code, d.message);
    if (d.position is null)
        return result;
    result ~= format(" --> %s\n", d.position.toStr());
    string[] lines = source.splitLines();
    if (!lines.length)
        return result;
    uint first = max(1u, d.position.start.line);
    uint last = min(cast(uint) lines.length, max(first, d.position.end.line));
    last = min(last, first + 4); // Limita snippets de erros que abrangem arquivos inteiros.
    foreach (uint lineNo; first .. last + 1)
    {
        dstring line;
        try
            line = lines[lineNo - 1].to!dstring;
        catch (Exception)
        {
            result ~= "     | [trecho indisponível: UTF-8 inválido]\n";
            continue;
        }
        uint start = lineNo == first ? min(line.length, max(1u, d.position.start.offset) - 1) : 0;
        size_t end = lineNo == d.position.end.line ? min(line.length, max(1u, d.position.end.offset) - 1) : line.length;
        size_t visualStart, visualEnd;
        string display;
        foreach (size_t i, dchar ch; line)
        {
            size_t width = ch == '\t' ? 4 - visualEnd % 4 : 1;
            if (i < start)
                visualStart += width;
            visualEnd += width;
            display ~= ch == '\t' ? ' '.repeat(width).array : [ch].to!string;
        }
        size_t markerWidth;
        foreach (dchar ch; line[start .. max(start, end)])
            markerWidth += ch == '\t' ? 4 - (visualStart + markerWidth) % 4 : 1;
        result ~= format("%4d | %s\n     | %s^%s\n", lineNo, display, ' '.repeat(visualStart)
                .array, '~'.repeat(markerWidth ? markerWidth - 1 : 0).array);
    }
    if (d.position.end.line > last)
        result ~= "     | …\n";
    return result;
}

void reportFatal(string message, string code = "E9001")
{
    Diagnostic d = Diagnostic(Severity.Error, null, message, code);
    stderr.write(diagnosticFormat == DiagnosticFormat.json ? diagnosticJSON(d) ~ "\n" : diagnosticText(d));
}

class Diagnostics
{
    private Diagnostic[] list;
    private string[string] sources;
    private size_t emitted;
    private size_t errors;
    enum size_t maxErrors = 100;

    void registerSource(string filename, string source)
    {
        if (filename !in sources)
            sources[filename] = source;
    }

    void add(Severity severity, Position pos, string message, string code = "")
    {
        if (errors > maxErrors)
            return;
        if (!code.length)
            code = severity == Severity.Error ? "E0001" : severity == Severity.Warning ? "W0001" : "H0001";
        foreach (Diagnostic d; list)
            if (d.severity == severity && d.code == code && d.message == message && ((d.position is null
                    && pos is null) || (d.position !is null && pos !is null
                    && d.position.filename == pos.filename
                    && d.position.start.line == pos.start.line && d.position.start.offset == pos.start.offset)))
                return;
        if (severity == Severity.Error && errors++ == maxErrors)
            list ~= Diagnostic(Severity.Error, pos,
                    "Limite de diagnósticos atingido; corrija os erros anteriores.", "E0002");
        else
            list ~= Diagnostic(severity, pos, message, code);
    }

    void errorCode(Args...)(Position pos, MessageSpec spec, Args arguments)
    {
        error(pos, format(spec.message, arguments), spec.code);
    }

    void warningCode(Args...)(Position pos, MessageSpec spec, Args arguments)
    {
        warning(pos, format(spec.message, arguments), spec.code);
    }

    void hintCode(Args...)(Position pos, MessageSpec spec, Args arguments)
    {
        hint(pos, format(spec.message, arguments), spec.code);
    }

    void error(Position pos, string message, string code = "")
    {
        add(Severity.Error, pos, message, code);
    }

    void warning(Position pos, string message, string code = "")
    {
        add(Severity.Warning, pos, message, code);
    }

    void hint(Position pos, string message, string code = "")
    {
        add(Severity.Hint, pos, message, code);
    }

    bool hasErrors() const
    {
        return list.any!((const(Diagnostic) d) => d.severity == Severity.Error);
    }

    bool hasWarnings() const
    {
        return list.any!((const(Diagnostic) d) => d.severity == Severity.Warning);
    }

    bool report()
    {
        foreach (Diagnostic d; list[emitted .. $])
        {
            if (diagnosticFormat == DiagnosticFormat.json)
                stderr.writeln(diagnosticJSON(d));
            else
            {
                string source;
                if (d.position !is null)
                {
                    if (string* cached = d.position.filename in sources)
                        source = *cached;
                    else
                        try
                            source = readText(d.position.filename);
                        catch (Exception)
                        {
                        }
                }
                stderr.write(diagnosticText(d, source));
            }
        }
        emitted = list.length;
        return hasErrors();
    }

    const(Diagnostic)[] entries() const
    {
        return list;
    }

    void merge(Diagnostics other)
    {
        foreach (Diagnostic diagnostic; other.list)
            add(diagnostic.severity, diagnostic.position, diagnostic.message, diagnostic.code);
        foreach (string filename, string source; other.sources)
            if (filename !in sources)
                sources[filename] = source;
    }

    void clear()
    {
        list.length = 0;
        emitted = 0;
        errors = 0;
    }
}
