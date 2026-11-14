module errors;

import core.stdc.stdlib : exit;
import std.stdio;
import std.format;
import std.file;
import std.string;
import std.array;
import std.range;
import std.algorithm;
import frontend.lexer;

private string[][string] _fileCache;

private string[] linesOf(string path)
{
    if (auto cached = path in _fileCache)
        return *cached;

    string[] lines = readText(path).splitLines().array;
    _fileCache[path] = lines;
    return lines;
}

enum Severity : ubyte
{
    Hint,
    Warning,
    Error,
}

private string label(Severity s)
{
    final switch (s)
    {
    case Severity.Hint:
        return "hint";
    case Severity.Warning:
        return "warning";
    case Severity.Error:
        return "error";
    }
}

struct Diagnostic
{
    Severity severity;
    Position position;
    string message;
}

private void renderDiagnostic(ref Diagnostic d)
{
    stderr.writefln("%s: %s", label(d.severity), d.message);
    if (d.position is null) return;
    stderr.writefln(" --> %s", d.position.toStr());

    string[] lines;

    try
        lines = linesOf(d.position.filename);
    catch (Exception)
    {
        stderr.writeln();
        return;
    }

    uint lineStart = d.position.start.line;
    uint lineEnd = d.position.end.line;
    uint colStart = d.position.start.offset;
    uint colEnd = d.position.end.offset;

    lineStart = min(lineStart, cast(uint) lines.length);
    lineEnd = min(lineEnd, cast(uint) lines.length);

    uint gutterWidth = cast(uint) format("%d", lineEnd).length;
    string gutter = ' '.repeat(gutterWidth + 1).array;

    stderr.writefln("%s|", gutter);

    foreach (uint n; lineStart .. lineEnd + 1)
    {
        if (n == 0 || n > lines.length)
            continue;

        string line = lines[n - 1];
        stderr.writefln("%*d | %s", gutterWidth, n, line);

        uint spanStart = (n == lineStart) ? colStart : 1;
        uint spanEnd = (n == lineEnd) ? colEnd : cast(uint) line.length;

        spanStart = max(spanStart, 1);
        spanEnd = max(spanEnd, spanStart);

        string spaces = ' '.repeat(gutterWidth + 3 + spanStart - 1).array;
        string caret = "^";
        string tilde = cast(string)(
            spanEnd > spanStart ? '~'.repeat(spanEnd - spanStart).array : "");

        stderr.writefln("%s%s%s", spaces, caret, tilde);
    }

    stderr.writefln("%s|", gutter);
    stderr.writeln();
}

class Diagnostics
{
private:
    Diagnostic[] _list;

public:
    void add(Severity sev, Position pos, string message)
    {
        _list ~= Diagnostic(sev, pos, message);
    }

    void error(Position pos, string message)
    {
        add(Severity.Error, pos, message);
    }

    void warning(Position pos, string message)
    {
        add(Severity.Warning, pos, message);
    }

    void hint(Position pos, string message)
    {
        add(Severity.Hint, pos, message);
    }

    bool hasErrors() const
    {
        return _list.any!(d => d.severity == Severity.Error);
    }

    bool hasWarnings() const
    {
        return _list.any!(d => d.severity == Severity.Warning);
    }

    bool report()
    {
        foreach (ref d; _list)
            renderDiagnostic(d);

        uint errors = cast(uint) _list.count!(d => d.severity == Severity.Error);
        uint warnings = cast(uint) _list.count!(d => d.severity == Severity.Warning);

        if (errors > 0 || warnings > 0)
        {
            stderr.writefln("resultado: %d erro(s), %d aviso(s)", errors, warnings);
            stderr.writeln();
        }

        return errors > 0;
    }

    const(Diagnostic)[] entries() const { return _list; }

    void clear()
    {
        _list.length = 0;
    }
}
