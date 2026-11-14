module frontend.formatter;

import std.array : appender;
import std.string : strip, endsWith, indexOf;

/// Formatação lexical conservadora: nunca reescreve literais ou comentários.
/// Quebras existentes são mantidas; delimitadores estruturam linhas novas.
string formatDelegua(string source)
{
    struct Piece
    {
        string text;
        bool newline;
        bool comment;
        bool blank;
    }

    Piece[] pieces;
    size_t cursor;
    bool newline;
    bool blank;
    while (cursor < source.length)
    {
        char c = source[cursor];
        if (c == ' ' || c == '\t' || c == '\r' || c == '\n')
        {
            if (c == '\n')
            {
                blank = newline;
                newline = true;
            }
            cursor++;
            continue;
        }
        size_t start = cursor++;
        bool comment;
        if (c == '/' && cursor < source.length && source[cursor] == '/')
        {
            comment = true;
            while (cursor < source.length && source[cursor] != '\n')
                cursor++;
        }
        else if (c == '"' || c == '\'')
        {
            bool closed;
            while (cursor < source.length)
            {
                char next = source[cursor++];
                if (next == '\\' && cursor < source.length)
                    cursor++;
                else if (next == c)
                {
                    closed = true;
                    break;
                }
            }
            if (!closed)
                return source;
        }
        else if (word(c))
        {
            while (cursor < source.length && word(source[cursor]))
                cursor++;
        }
        else if (cursor < source.length)
        {
            string pair = source[start .. cursor + 1];
            foreach (string operator; [
                "==", "!=", "<=", ">=", "+=", "-=", "*=", "/=", "%=", "++", "--", "**", "<<", ">>",
                "<-", "?:"
            ])
                if (pair == operator)
                {
                    cursor++;
                    break;
                }
            if (source[start .. cursor] == "." && cursor + 1 < source.length && source[cursor .. cursor + 2] == "..")
                cursor += 2;
        }
        pieces ~= Piece(source[start .. cursor], newline, comment, blank);
        newline = false;
        blank = false;
    }
    string[] lines;
    string line;
    size_t indent;
    size_t parens;
    size_t brackets;
    string previous;
    bool continuation;
    bool[] compactBraces;
    size_t compactDepth;
    void flush()
    {
        if (!line.length)
            return;
        lines ~= replaceSpaces(new char[(indent + (continuation ? 1 : 0)) * 4]) ~ line.strip;
        line = "";
        continuation = false;
    }

    void append(string text, bool space = false)
    {
        if (space && line.length && !line.endsWith(" "))
            line ~= " ";
        line ~= text;
    }

    foreach (size_t index, Piece piece; pieces)
    {
        string text = piece.text;
        if (piece.newline && !parens && !brackets && !compactDepth)
        {
            flush();
            if (piece.blank && lines.length && lines[$ - 1].length && text != "}")
                lines ~= "";
        }
        if (piece.comment)
        {
            append(text, true);
            flush();
            previous = "";
            continue;
        }
        if (text == "{")
        {
            import std.algorithm : canFind;

            bool compact = [
                "=", "<-", "retorna", "retorne", ":", ",", "(", "[", "...", "var", "const",
                "fixo", "cada", "em", "de"
            ].canFind(previous) || compactDepth > 0 && previous == "{";
            compactBraces ~= compact;
            append(text, previous != "(" && previous != "[");
            if (compact)
            {
                compactDepth++;
                append(" ");
            }
            else
            {
                flush();
                indent++;
            }
        }
        else if (text == "}")
        {
            bool compact = compactBraces.length && compactBraces[$ - 1];
            if (compactBraces.length)
                compactBraces.length--;
            if (compact)
            {
                line = line.stripRight;
                append(text, previous != "{");
                if (compactDepth)
                    compactDepth--;
            }
            else
            {
                flush();
                if (indent)
                    indent--;
                append(text);
                if (index + 1 < pieces.length)
                {
                    string next = pieces[index + 1].text;
                    if (next != "," && next != ";" && next != ")" && next != "]" && next != "."
                            && next != "senao" && next != "senão" && next != "pegue" && next != "finalmente")
                    {
                        flush();
                        if (indent <= 1 && next != "}")
                            lines ~= "";
                    }
                }
            }
        }
        else if (text == ";")
        {
            append(text);
            if (!parens)
                flush();
            else
                append(" ");
        }
        else if (text == ",")
        {
            append(text);
            if ((parens || brackets) && indent * 4 + line.length >= 88)
            {
                flush();
                continuation = true;
            }
            else
                append(" ");
        }
        else if (text == ".")
            append(text);
        else if (text == ":")
        {
            append(text);
            append(" ");
        }
        else if (text == "(")
        {
            append(text, previous == "se" || previous == "enquanto" || previous == "para"
                    || previous == "escolha" || previous == "pegue");
            parens++;
        }
        else if (text == ")")
        {
            line = line.stripRight;
            append(text);
            if (parens)
                parens--;
        }
        else if (text == "[")
        {
            append(text, previous == "=" || previous == "retorna" || previous == "retorne"
                    || previous == "em" || previous == "de");
            brackets++;
        }
        else if (text == "]")
        {
            line = line.stripRight;
            append(text);
            if (brackets)
                brackets--;
        }
        else
        {
            bool separator = line.length && previous != "." && previous != "(" && previous != "["
                && previous != "!" && previous != "~";
            if (text == "++" || text == "--")
                separator = false;
            // Não separe a parte fracionária de um literal numérico.
            append(text, separator);
        }
        previous = text;
    }
    flush();
    while (lines.length && !lines[$ - 1].length)
        lines.length--;
    import std.array : join;

    return lines.length ? lines.join("\n") ~ "\n" : "";
}

private bool word(char c)
{
    return c >= 128 || c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= '0' && c <= '9' || c == '_';
}

private string replaceSpaces(char[] chars)
{
    chars[] = ' ';
    return cast(string) chars;
}

private string stripRight(string text)
{
    while (text.length && text[$ - 1] == ' ')
        text = text[0 .. $ - 1];
    return text;
}

unittest
{
    string original = "funcao soma(a: inteiro,b: inteiro): inteiro{retorna a+b;}\n// contrato intacto\nescreva(\"a  b\",soma(1,2));";
    string formatted = formatDelegua(original);
    assert(formatted == formatDelegua(formatted));
    assert(formatted.endsWith("escreva(\"a  b\", soma(1, 2));\n"));
    assert(formatted.indexOf("    retorna a + b;") >= 0);
}
