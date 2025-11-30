module common.reporter;

import std.stdio, std.file, std.string, std.conv, std.algorithm, std.range, std.array;
import frontend : Token, TokenKind, Loc, LocLine;

// Códigos ANSI para cores
struct Color
{
    static immutable string RESET = "\033[0m";
    static immutable string BOLD = "\033[1m";
    static immutable string DIM = "\033[2m";

    static immutable string RED = "\033[31m";
    static immutable string GREEN = "\033[32m";
    static immutable string YELLOW = "\033[33m";
    static immutable string BLUE = "\033[34m";
    static immutable string MAGENTA = "\033[35m";
    static immutable string CYAN = "\033[36m";
    static immutable string WHITE = "\033[37m";

    static immutable string BRIGHT_RED = "\033[91m";
    static immutable string BRIGHT_GREEN = "\033[92m";
    static immutable string BRIGHT_YELLOW = "\033[93m";
    static immutable string BRIGHT_BLUE = "\033[94m";
    static immutable string BRIGHT_MAGENTA = "\033[95m";
    static immutable string BRIGHT_CYAN = "\033[96m";
}

enum DiagnosticSeverity : string
{
    WARNING = "warning",
    ERROR = "error",
    INFO = "info",
    HINT = "hint",
}

struct DiagnosticOptions
{
    bool showSuggestions = true;
    bool useColors = true;
    bool showContext = true;
    uint contextLines = 1;
}

struct Suggestion
{
    string message;
    string replacement;
}

struct Diagnostic
{
    string message;
    Loc loc;
    Suggestion[] suggestions;
    TokenKind tkType;
    DiagnosticSeverity severity;
}

private struct AnnotationLine
{
    ulong lineNum;
    string content;
    bool isErrorLine;
    ulong startCol;
    ulong endCol;
}

class DiagnosticError
{
private:
    Diagnostic[] diagnostics;
    DiagnosticOptions options;
    string[string] fileCache;

    string colorize(string text, string color) const
    {
        return options.useColors ? (color ~ text ~ Color.RESET) : text;
    }

    string getSeverityColor(DiagnosticSeverity severity) const
    {
        final switch (severity)
        {
        case DiagnosticSeverity.ERROR:
            return Color.BRIGHT_RED;
        case DiagnosticSeverity.WARNING:
            return Color.BRIGHT_YELLOW;
        case DiagnosticSeverity.INFO:
            return Color.BRIGHT_CYAN;
        case DiagnosticSeverity.HINT:
            return Color.BRIGHT_BLUE;
        }
    }

    string getSeverityLabel(DiagnosticSeverity severity) const
    {
        final switch (severity)
        {
        case DiagnosticSeverity.ERROR:
            return "erro";
        case DiagnosticSeverity.WARNING:
            return "aviso";
        case DiagnosticSeverity.INFO:
            return "info";
        case DiagnosticSeverity.HINT:
            return "dica";
        }
    }

    string[] getFileLines(string filename)
    {
        if (filename in fileCache)
            return fileCache[filename].split("\n");

        if (!exists(filename))
            return [];

        string content = readText(filename);
        fileCache[filename] = content;
        return content.split("\n");
    }

    string formatLineNumber(ulong num, ulong maxWidth) const
    {
        string numStr = to!string(num);
        ulong padding = maxWidth > numStr.length ? maxWidth - numStr.length : 0;
        return colorize(" ".replicate(padding) ~ numStr, Color.BRIGHT_BLUE);
    }

    AnnotationLine[] prepareAnnotationLines(const Diagnostic diagnostic, string[] fileLines)
    {
        const loc = diagnostic.loc;
        ulong startLine = loc.start.line;
        ulong endLine = loc.end.line;

        ulong contextStart = startLine > options.contextLines ? startLine - options.contextLines : 1;
        ulong contextEnd = min(endLine + options.contextLines, fileLines.length);

        AnnotationLine[] lines;

        foreach (lineNum; contextStart .. contextEnd + 1)
        {
            if (lineNum < 1 || lineNum > fileLines.length)
                continue;

            bool isErrorLine = (lineNum >= startLine && lineNum <= endLine);
            ulong startCol = (lineNum == startLine) ? loc.start.offset : 0;
            ulong endCol = (lineNum == endLine) ? loc.end.offset
                : cast(int) fileLines[lineNum - 1].length - 1;

            lines ~= AnnotationLine(
                lineNum,
                fileLines[lineNum - 1],
                isErrorLine,
                startCol,
                endCol
            );
        }

        return lines;
    }

    string highlightLine(string line, ulong startCol, ulong endCol, string highlightColor) const
    {
        if (line.length == 0)
            return line;

        string result;

        // Parte antes do erro
        if (startCol > 0 && startCol <= line.length)
            result ~= line[0 .. startCol];

        // Parte destacada
        if (startCol < line.length)
        {
            ulong highlightEnd = min(endCol + 1, line.length);
            result ~= colorize(line[startCol .. highlightEnd], highlightColor);

            // Parte depois do erro
            if (highlightEnd < line.length)
                result ~= line[highlightEnd .. $];
        }

        return result;
    }

    string createUnderline(ulong startCol, ulong endCol, string color) const
    {
        ulong underlineLen = (endCol >= startCol) ? (endCol - startCol + 1) : 1;
        return " ".replicate(startCol) ~ colorize("^".replicate(underlineLen), color);
    }

    string formatMultilineSpan(const AnnotationLine[] lines, const Diagnostic diagnostic, ulong maxLineNumWidth)
    {
        string output;
        const severityColor = getSeverityColor(diagnostic.severity);
        const loc = diagnostic.loc;
        bool needsUnderline = false;
        ulong underlineCol = 0;
        ulong underlineEndCol = 0;

        foreach (i, line; lines)
        {
            string gutter = colorize(" | ", Color.BRIGHT_BLUE);
            string lineNumStr = formatLineNumber(line.lineNum, maxLineNumWidth);

            if (!line.isErrorLine && options.showContext)
            {
                // Linha de contexto
                output ~= lineNumStr ~ gutter ~ colorize(line.content, Color.DIM) ~ "\n";
            }
            else if (line.isErrorLine)
            {
                // Linha com erro
                bool isSingleLine = (loc.start.line == loc.end.line);
                bool isFirstLine = (line.lineNum == loc.start.line);
                bool isLastLine = (line.lineNum == loc.end.line);

                if (isSingleLine)
                {
                    // Erro em uma única linha
                    output ~= lineNumStr ~ gutter;
                    output ~= highlightLine(line.content, line.startCol, line.endCol, severityColor ~ Color
                            .BOLD);
                    output ~= "\n";
                    needsUnderline = true;
                    underlineCol = line.startCol;
                    underlineEndCol = line.endCol;
                }
                else
                {
                    // Erro multilinha
                    if (isFirstLine)
                    {
                        // Primeira linha do erro multilinha
                        output ~= lineNumStr ~ colorize(" / ", Color.BRIGHT_BLUE);

                        if (line.startCol < line.content.length)
                        {
                            output ~= line.content[0 .. line.startCol];
                            output ~= colorize(line.content[line.startCol .. $], severityColor ~ Color
                                    .BOLD);
                        }
                        else
                        {
                            output ~= line.content;
                        }
                        output ~= "\n";
                    }
                    else if (isLastLine)
                    {
                        // Última linha do erro multilinha
                        output ~= lineNumStr ~ colorize(" \\_", Color.BRIGHT_BLUE) ~ " ";

                        ulong endCol = min(line.endCol + 1, line.content.length);
                        if (endCol > 0)
                        {
                            output ~= colorize(line.content[0 .. endCol], severityColor ~ Color
                                    .BOLD);
                            if (endCol < line.content.length)
                                output ~= line.content[endCol .. $];
                        }
                        output ~= "\n";
                    }
                    else
                    {
                        // Linha do meio do erro multilinha
                        output ~= lineNumStr ~ colorize(" | ", Color.BRIGHT_BLUE);
                        output ~= colorize(line.content, severityColor ~ Color.BOLD);
                        output ~= "\n";
                    }
                }

                // Adiciona underline apenas para erros de linha única
                if (needsUnderline && isSingleLine)
                {
                    output ~= " ".replicate(maxLineNumWidth) ~ gutter;
                    output ~= createUnderline(underlineCol, underlineEndCol, severityColor ~ Color
                            .BOLD);
                    output ~= "\n";
                    needsUnderline = false;
                }
            }
        }

        return output;
    }

    string formatDiagnostic(const Diagnostic diagnostic)
    {
        const loc = diagnostic.loc;
        const severity = diagnostic.severity;
        const severityColor = getSeverityColor(severity);
        const severityLabel = getSeverityLabel(severity);

        string output;

        // Cabeçalho do erro no estilo Rust
        output ~= colorize(severityLabel, severityColor ~ Color.BOLD);
        output ~= colorize(": ", Color.BOLD);
        output ~= colorize(diagnostic.message, Color.BOLD) ~ "\n";

        // Localização
        string location = format("  --> %s:%d:%d", loc.filename, loc.start.line, loc.start.offset + 1);
        output ~= colorize(location, Color.BRIGHT_BLUE) ~ "\n";

        // Obtém as linhas do arquivo
        string[] fileLines = getFileLines(loc.filename);
        if (fileLines.length == 0)
        {
            output ~= colorize("   |", Color.BRIGHT_BLUE) ~ "\n";
            output ~= colorize("   = ", Color.BRIGHT_BLUE) ~ "arquivo não encontrado\n";
            return output;
        }

        // Prepara as linhas de anotação
        AnnotationLine[] lines = prepareAnnotationLines(diagnostic, fileLines);
        if (lines.length == 0)
            return output;

        // Calcula largura máxima do número de linha
        ulong maxLineNum = lines[$ - 1].lineNum;
        ulong maxLineNumWidth = to!string(maxLineNum).length;

        // Linha separadora
        output ~= " ".replicate(maxLineNumWidth) ~ colorize(" |\n", Color.BRIGHT_BLUE);

        // Formata as linhas com spans multilinha
        output ~= formatMultilineSpan(lines, diagnostic, maxLineNumWidth);

        // Sugestões
        if (options.showSuggestions && diagnostic.suggestions.length > 0)
        {
            output ~= " ".replicate(maxLineNumWidth) ~ colorize(" |\n", Color.BRIGHT_BLUE);
            foreach (suggestion; diagnostic.suggestions)
            {
                output ~= " ".replicate(maxLineNumWidth) ~ colorize(" = ", Color.BRIGHT_BLUE);
                output ~= colorize("ajuda: ", Color.BOLD) ~ suggestion.message;

                if (suggestion.replacement.length > 0)
                {
                    output ~= ": " ~ colorize("`" ~ suggestion.replacement ~ "`", Color.GREEN);
                }
                output ~= "\n";
            }
        }

        return output;
    }

public:
    this(DiagnosticOptions options = DiagnosticOptions())
    {
        this.options = options;
    }

    Suggestion makeSuggestion(string message, string replacement = "")
    {
        return Suggestion(message, replacement);
    }

    void addError(Diagnostic d)
    {
        d.severity = DiagnosticSeverity.ERROR;
        this.diagnostics ~= d;
    }

    void addWarning(Diagnostic d)
    {
        d.severity = DiagnosticSeverity.WARNING;
        this.diagnostics ~= d;
    }

    void addInfo(Diagnostic d)
    {
        d.severity = DiagnosticSeverity.INFO;
        this.diagnostics ~= d;
    }

    void addHint(Diagnostic d)
    {
        d.severity = DiagnosticSeverity.HINT;
        this.diagnostics ~= d;
    }

    string formatDiagnostics()
    {
        if (diagnostics.length == 0)
            return "";

        return diagnostics.map!(d => formatDiagnostic(d)).join("\n");
    }

    void printDiagnostics()
    {
        string output = formatDiagnostics();
        if (output.length > 0)
            writeln(output);

        string summary = getSummary();
        if (summary.length > 0)
            writeln(summary);
    }

    bool hasErrors() const
    {
        return diagnostics.any!(d => d.severity == DiagnosticSeverity.ERROR);
    }

    bool hasWarnings() const
    {
        return diagnostics.any!(d => d.severity == DiagnosticSeverity.WARNING);
    }

    int getErrorCount() const
    {
        return cast(int) diagnostics.count!(d => d.severity == DiagnosticSeverity.ERROR);
    }

    int getWarningCount() const
    {
        return cast(int) diagnostics.count!(d => d.severity == DiagnosticSeverity.WARNING);
    }

    int getInfoCount() const
    {
        return cast(int) diagnostics.count!(d => d.severity == DiagnosticSeverity.INFO);
    }

    int getHintCount() const
    {
        return cast(int) diagnostics.count!(d => d.severity == DiagnosticSeverity.HINT);
    }

    void clear()
    {
        diagnostics = [];
        fileCache.clear();
    }

    void updateOptions(DiagnosticOptions newOptions)
    {
        this.options = newOptions;
    }

    string getSummary() const
    {
        int errorCount = getErrorCount();
        int warningCount = getWarningCount();

        if (errorCount == 0 && warningCount == 0)
            return "";

        string[] parts;

        if (errorCount > 0)
        {
            string errorText = errorCount == 1 ? "erro" : "erros";
            parts ~= colorize(format("%d %s", errorCount, errorText), Color.BRIGHT_RED ~ Color.BOLD);
        }

        if (warningCount > 0)
        {
            string warningText = warningCount == 1 ? "aviso" : "avisos";
            parts ~= colorize(format("%d %s", warningCount, warningText), Color.BRIGHT_YELLOW ~ Color
                    .BOLD);
        }

        return colorize("erro", Color.BRIGHT_RED ~ Color.BOLD) ~ ": " ~
            "não foi possível compilar devido a " ~ parts.join(" e ");
    }
}
