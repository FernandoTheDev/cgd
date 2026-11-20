module frontend.formatter;

import std.algorithm : canFind;
import std.array : join;
import std.string : strip, endsWith, indexOf, startsWith;

private struct Piece
{
    string text;
    bool newline;
    bool comment;
    bool blank;
    bool isString;
    bool isNumber;
}

private enum DelimKind
{
    Paren,
    Bracket,
    CompactBrace,
    BlockBrace,
    ClassBrace,
    DoBrace,
    SwitchBrace,
    MultiBracket,
    MultiBrace,
}

/// Formatação lexical conservadora: nunca reescreve literais ou comentários.
/// Quebras existentes são mantidas; delimitadores estruturam linhas novas.
string formatDelegua(string source)
{
    Piece[] pieces;
    if (!tokenizeDelegua(source, pieces))
        return source;

    bool[] genericAngle = computeGenericAngles(pieces);

    string[] lines;
    string line;
    size_t indent;
    size_t parens;
    size_t brackets;
    size_t compactDepth;
    size_t ternaryDepth;
    string previous;
    bool prevUnaryOp;
    bool prevGenericOpen;
    bool prevSliceColon;
    bool continuation;
    bool awaitingClass;
    bool awaitingDo;
    bool awaitingSwitch;
    bool inForHeader;
    bool inCadaBinding;
    DelimKind[] delims;

    bool inClassBody()
    {
        return delims.length > 0 && delims[$ - 1] == DelimKind.ClassBrace;
    }

    bool inMultilineDelim()
    {
        return delims.length > 0 && (delims[$ - 1] == DelimKind.MultiBracket || delims[$ - 1] == DelimKind.MultiBrace);
    }

    bool inBracketDelim()
    {
        return delims.length > 0 && (delims[$ - 1] == DelimKind.Bracket || delims[$ - 1] == DelimKind.MultiBracket);
    }

    void flush()
    {
        if (!line.length)
            return;
        lines ~= replaceSpaces(new char[(indent + (continuation ? 1 : 0)) * 4]) ~ line.strip;
        line = "";
        continuation = false;
        previous = "";
        prevUnaryOp = false;
        prevGenericOpen = false;
        prevSliceColon = false;
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
        string next = index + 1 < pieces.length ? pieces[index + 1].text : "";

        if (piece.comment)
        {
            if (piece.newline)
            {
                flush();
                if (piece.blank && lines.length && lines[$ - 1].length)
                    lines ~= "";
            }
            bool isLineComment = text.startsWith("//");
            if (isLineComment)
            {
                append(text, true);
                flush();
            }
            else
            {
                append(text, line.length && previous != "(" && previous != "[");
                if (index + 1 < pieces.length && pieces[index + 1].newline)
                    flush();
            }
            continue;
        }

        if (piece.newline)
        {
            if (inForHeader && previous != ";")
                inForHeader = false;
            bool allowBreak = (!parens && !brackets && !compactDepth && !inForHeader && !isClassModifier(previous))
                || inMultilineDelim();
            if (allowBreak)
            {
                flush();
                ternaryDepth = 0;
                inCadaBinding = false;
                if (piece.blank && lines.length && lines[$ - 1].length && text != "}" && text != "]")
                    lines ~= "";
            }
        }

        if ((text == "classe" || text == "interface") && previous != "." && next != ":")
            awaitingClass = true;
        if ((text == "faca" || text == "faça") && previous != ".")
            awaitingDo = true;
        if (text == "escolha" && previous != ".")
            awaitingSwitch = true;
        if (text == "para" && previous != "." && next != "cada" && next != "(")
            inForHeader = true;
        if (text == "cada" && previous == "para")
            inCadaBinding = true;
        else if (inCadaBinding && (text == "em" || text == "de"))
            inCadaBinding = false;

        if (inClassBody() && !parens && !compactDepth && index + 1 < pieces.length)
        {
            bool modifier = isClassModifier(text) && !isClassModifier(previous);
            bool method = next == "(" && previous != "@" && !isClassModifier(previous);
            bool field = next == ":" && previous != "var" && previous != "const" && previous != "fixo"
                && previous != "," && !isClassModifier(previous);
            bool visibility = isVisibilityKeyword(text);
            bool staticField = modifier && index + 2 < pieces.length && pieces[index + 2].text == ":";
            if (modifier || method || field || visibility)
                flush();
            if (((modifier && !staticField) || method || visibility) && lines.length
                    && lines[$ - 1].length && !lines[$ - 1].endsWith("{")
                    && !lines[$ - 1].strip.startsWith("//") && !lines[$ - 1].strip.startsWith("@"))
                lines ~= "";
        }

        if (text == "{")
        {
            inForHeader = false;
            inCadaBinding = false;
            bool compact = [
                "=", "<-", "retorna", "retorne", ":", ",", "(", "[", "...", "var", "const", "fixo",
                "cada", "em", "de", "=>", "?", "?:"
            ].canFind(previous) || (compactDepth > 0 && previous == "{") || (delims.length > 0
                    && (delims[$ - 1] == DelimKind.MultiBracket || delims[$ - 1] == DelimKind.MultiBrace)
                    && previous == "");
            bool visibility = isVisibilityKeyword(previous);
            bool multiMap = compact && index + 1 < pieces.length && pieces[index + 1].newline && next != "}";
            DelimKind kind;
            if (multiMap)
                kind = DelimKind.MultiBrace;
            else if (compact)
                kind = DelimKind.CompactBrace;
            else if (awaitingClass || (visibility && inClassBody()))
                kind = DelimKind.ClassBrace;
            else if (awaitingDo)
                kind = DelimKind.DoBrace;
            else if (awaitingSwitch)
                kind = DelimKind.SwitchBrace;
            else
                kind = DelimKind.BlockBrace;
            awaitingClass = false;
            awaitingDo = false;
            awaitingSwitch = false;
            delims ~= kind;
            append(text, line.length && previous != "(" && previous != "[");
            if (kind == DelimKind.CompactBrace)
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
            DelimKind closed = delims.length ? delims[$ - 1] : DelimKind.BlockBrace;
            if (delims.length)
                delims.length--;
            if (closed == DelimKind.CompactBrace)
            {
                line = line.stripRight;
                append(text, previous != "{");
                if (compactDepth)
                    compactDepth--;
            }
            else if (closed == DelimKind.MultiBrace)
            {
                flush();
                if (indent)
                    indent--;
                append(text);
            }
            else
            {
                flush();
                if (indent)
                    indent--;
                append(text);
                if (index + 1 < pieces.length)
                {
                    bool keepInline = next == "," || next == ";" || next == ")" || next == "]" || next == "."
                        || next == "senao" || next == "senão" || next == "pegue"
                        || next == "finalmente" || (closed == DelimKind.DoBrace && next == "enquanto");
                    if (!keepInline)
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
            ternaryDepth = 0;
            if (!parens && !inForHeader)
                flush();
            else
                append(" ");
        }
        else if (text == ",")
        {
            append(text);
            if ((parens || brackets) && !inMultilineDelim() && indent * 4 + line.length >= 88)
            {
                flush();
                continuation = true;
            }
            else if (!inMultilineDelim())
                append(" ");
        }
        else if (text == "=>")
        {
            append(text, true);
            append(" ");
        }
        else if (text == ".")
        {
            append(text);
        }
        else if (text == "?")
        {
            ternaryDepth++;
            append(text, true);
        }
        else if (text == ":")
        {
            if (ternaryDepth > 0)
            {
                ternaryDepth--;
                append(text, true);
                append(" ");
                prevSliceColon = false;
            }
            else if (inBracketDelim() && !inCadaBinding)
            {
                append(text, false);
                prevSliceColon = true;
            }
            else
            {
                append(text, false);
                append(" ");
                prevSliceColon = false;
            }
        }
        else if (text == "<" && genericAngle[index])
        {
            append(text, false);
            prevGenericOpen = true;
        }
        else if (text == ">" && genericAngle[index])
        {
            line = line.stripRight;
            append(text, false);
        }
        else if (text == "(")
        {
            bool spaceBefore = line.length && !prevUnaryOp && !prevGenericOpen && !prevSliceColon
                && (isControlParenKeyword(previous) || isBinarySpaceBeforeParen(previous));
            append(text, spaceBefore);
            delims ~= DelimKind.Paren;
            parens++;
        }
        else if (text == ")")
        {
            line = line.stripRight;
            append(text);
            if (parens)
                parens--;
            if (delims.length && delims[$ - 1] == DelimKind.Paren)
                delims.length--;
        }
        else if (text == "[")
        {
            bool spaceBefore = line.length && !prevUnaryOp && !prevGenericOpen && !prevSliceColon
                && isSpaceBeforeBracket(previous);
            bool multiArr = index + 1 < pieces.length && pieces[index + 1].newline && next != "]";
            append(text, spaceBefore);
            if (multiArr)
            {
                delims ~= DelimKind.MultiBracket;
                flush();
                indent++;
            }
            else
            {
                delims ~= DelimKind.Bracket;
                brackets++;
            }
        }
        else if (text == "]")
        {
            inCadaBinding = false;
            if (delims.length && delims[$ - 1] == DelimKind.MultiBracket)
            {
                delims.length--;
                flush();
                if (indent)
                    indent--;
                append(text);
            }
            else
            {
                line = line.stripRight;
                append(text);
                if (brackets)
                    brackets--;
                if (delims.length && delims[$ - 1] == DelimKind.Bracket)
                    delims.length--;
            }
        }
        else if (text == "-" || text == "+")
        {
            bool unary = isUnaryContext(previous);
            if (unary)
            {
                bool spaceBefore = line.length && (previous == text || (!prevSliceColon && previous != "("
                        && previous != "[" && previous != "!" && previous != "~" && previous != "..."));
                append(text, spaceBefore);
                prevUnaryOp = true;
            }
            else
            {
                append(text, line.length > 0);
                prevUnaryOp = false;
            }
        }
        else if (text == "++" || text == "--")
        {
            bool prefix = isUnaryContext(previous);
            if (prefix)
            {
                bool spaceBefore = line.length && !prevSliceColon && previous != "("
                    && previous != "[" && previous != "!" && previous != "~" && previous != "...";
                append(text, spaceBefore);
                prevUnaryOp = true;
            }
            else
            {
                append(text, false);
                prevUnaryOp = false;
            }
        }
        else
        {
            bool separator = line.length && !prevUnaryOp && !prevGenericOpen && !prevSliceColon
                && previous != "." && previous != "(" && previous != "[" && previous != "!"
                && previous != "~" && previous != "@" && previous != "...";
            append(text, separator);
        }

        if (text != "-" && text != "+" && text != "++" && text != "--")
            prevUnaryOp = false;
        if (!(text == "<" && genericAngle[index]))
            prevGenericOpen = false;
        if (text != ":")
            prevSliceColon = false;
        previous = text;
    }

    flush();
    while (lines.length && !lines[$ - 1].length)
        lines.length--;

    return lines.length ? lines.join("\n") ~ "\n" : "";
}

private bool tokenizeDelegua(string source, out Piece[] pieces)
{
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
        bool isString;
        bool isNumber;
        if (c == '/' && cursor < source.length && source[cursor] == '/')
        {
            comment = true;
            while (cursor < source.length && source[cursor] != '\n')
                cursor++;
        }
        else if (c == '/' && cursor < source.length && source[cursor] == '*')
        {
            comment = true;
            cursor++;
            bool closed;
            while (cursor + 1 < source.length)
            {
                if (source[cursor] == '*' && source[cursor + 1] == '/')
                {
                    cursor += 2;
                    closed = true;
                    break;
                }
                cursor++;
            }
            if (!closed)
                return false;
        }
        else if (c == '"' || c == '\'')
        {
            isString = true;
            bool closed;
            while (cursor < source.length)
            {
                char next = source[cursor++];
                if (next == '\\' && cursor < source.length)
                    cursor++;
                else if (next == '$' && cursor < source.length && source[cursor] == '{')
                {
                    cursor++;
                    size_t nesting = 1;
                    char innerQuote = 0;
                    bool escaped;
                    while (cursor < source.length && nesting > 0)
                    {
                        char x = source[cursor++];
                        if (innerQuote)
                        {
                            if (escaped)
                                escaped = false;
                            else if (x == '\\')
                                escaped = true;
                            else if (x == innerQuote)
                                innerQuote = 0;
                        }
                        else if (x == '\'' || x == '"')
                            innerQuote = x;
                        else if (x == '{')
                            nesting++;
                        else if (x == '}')
                            nesting--;
                    }
                    if (nesting > 0)
                        return false;
                }
                else if (next == c)
                {
                    closed = true;
                    break;
                }
            }
            if (!closed)
                return false;
        }
        else if (c >= '0' && c <= '9')
        {
            isNumber = true;
            while (cursor < source.length && source[cursor] >= '0' && source[cursor] <= '9')
                cursor++;
            if (cursor + 1 < source.length && source[cursor] == '.' && source[cursor + 1] >= '0'
                    && source[cursor + 1] <= '9')
            {
                cursor++;
                while (cursor < source.length && source[cursor] >= '0' && source[cursor] <= '9')
                    cursor++;
            }
        }
        else if (word(c))
        {
            while (cursor < source.length && word(source[cursor]))
                cursor++;
        }
        else if (cursor < source.length)
        {
            if (c == '.' && cursor + 1 < source.length && source[cursor .. cursor + 2] == "..")
                cursor += 2;
            else
            {
                string pair = source[start .. cursor + 1];
                foreach (string operator; [
                    "==", "!=", "<=", ">=", "+=", "-=", "*=", "/=", "%=", "++", "--", "**", "<<",
                    ">>", "<-", "?:", "=>"
                ])
                    if (pair == operator)
                    {
                        cursor++;
                        break;
                    }
            }
        }
        pieces ~= Piece(source[start .. cursor], newline, comment, blank, isString, isNumber);
        newline = false;
        blank = false;
    }
    return true;
}

private bool[] computeGenericAngles(ref Piece[] pieces)
{
    Piece[] expanded;
    size_t[] opens;
    bool[] flags;
    size_t i;
    while (i < pieces.length)
    {
        Piece cur = pieces[i];
        if (cur.text == "<" && expanded.length > 0 && isGenericTypeName(expanded[$ - 1].text))
        {
            size_t scan = i + 1;
            int depth = 1;
            bool valid = true;
            while (scan < pieces.length && depth > 0)
            {
                string t = pieces[scan].text;
                if (t == "<")
                    depth++;
                else if (t == ">")
                    depth--;
                else if (t == ">>")
                {
                    if (depth >= 2)
                        depth -= 2;
                    else if (depth == 1 && opens.length > 0)
                        depth = 0;
                    else
                    {
                        valid = false;
                        break;
                    }
                }
                else if (!isTypeArgToken(pieces[scan]))
                {
                    valid = false;
                    break;
                }
                scan++;
            }
            if (valid && depth == 0)
            {
                opens ~= expanded.length;
                expanded ~= cur;
                flags ~= true;
                i++;
                continue;
            }
        }
        if (opens.length > 0 && cur.text == ">")
        {
            opens.length--;
            expanded ~= cur;
            flags ~= true;
            i++;
            continue;
        }
        if (opens.length >= 2 && cur.text == ">>")
        {
            opens.length -= 2;
            expanded ~= Piece(">", cur.newline, false, cur.blank, false, false);
            flags ~= true;
            expanded ~= Piece(">", false, false, false, false, false);
            flags ~= true;
            i++;
            continue;
        }
        expanded ~= cur;
        flags ~= false;
        i++;
    }
    pieces = expanded;
    return flags;
}

private bool isGenericTypeName(string name)
{
    return name == "Promessa" || name == "Tarefa";
}

private bool isTypeArgToken(Piece piece)
{
    if (piece.comment || piece.isString || piece.isNumber)
        return false;
    string t = piece.text;
    if (t == "[" || t == "]" || t == "(" || t == ")" || t == "," || t == ".")
        return true;
    return t.length > 0 && word(t[0]);
}

private bool isClassModifier(string text)
{
    return [
        "estatico", "estático", "estatica", "estática", "abstrato", "abstrata", "assincrona",
        "assíncrona"
    ].canFind(text);
}

private bool isVisibilityKeyword(string text)
{
    return text == "privado" || text == "protegido" || text == "publico" || text == "público";
}

private bool isUnaryContext(string prev)
{
    if (!prev.length)
        return true;
    return [
        "(", "[", "{", ",", ";", "=", "<-", ":", "?", "?:", "=>", "+", "-", "*", "/", "\\", "%",
        "**", "==", "!=", "<", "<=", ">", ">=", "+=", "-=", "*=", "/=", "%=", "&", "|", "^", "<<",
        ">>", "!", "~", "...", "retorna", "retorne", "falhar", "em", "de", "se", "senao",
        "senão", "enquanto", "caso", "e", "ou", "aguardar", "rotina"
    ].canFind(prev);
}

private bool isControlParenKeyword(string prev)
{
    return [
        "se", "enquanto", "para", "escolha", "pegue", "retorna", "retorne", "falhar", "em", "de",
        "e", "ou", "aguardar", "rotina", "caso"
    ].canFind(prev);
}

private bool isBinarySpaceBeforeParen(string prev)
{
    return [
        "=", "<-", "+", "-", "*", "/", "\\", "%", "**", "==", "!=", "<", "<=", ">", ">=", "+=",
        "-=", "*=", "/=", "%=", "&", "|", "^", "<<", ">>", "?", "?:", "=>"
    ].canFind(prev);
}

private bool isSpaceBeforeBracket(string prev)
{
    return [
        "=", "<-", "retorna", "retorne", "em", "de", "==", "!=", "+", "-", "*", "/", "%", "?",
        "?:", "=>", "e", "ou", "se", "caso", "+=", "falhar", "aguardar"
    ].canFind(prev);
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

    string members = formatDelegua("classe A{x:inteiro y:texto estatico contador:inteiro=0 estatico dobro(x:inteiro):inteiro{retorna x*2} metodo():texto{retorna 'x'}}");
    assert(members.indexOf(
            "    x: inteiro\n    y: texto\n    estatico contador: inteiro = 0\n\n    estatico dobro") >= 0, members);
    assert(members == formatDelegua(members));

    // Genéricos Promessa<T> e Tarefa<T>, inclusive aninhados
    string generics = formatDelegua(
            "const f: Promessa < inteiro > = g()\nconst t: Tarefa < Promessa < texto[] >> = h()\nescreva(a < b, n >> 2)");
    assert(generics.indexOf("Promessa<inteiro>") >= 0, generics);
    assert(generics.indexOf("Tarefa<Promessa<texto[]>>") >= 0, generics);
    assert(generics.indexOf("a < b, n >> 2") >= 0, generics);
    assert(generics == formatDelegua(generics));

    // Unários, prefixo ++/--, fatias, ternário e spread
    string exprs = formatDelegua(
            "escreva(valores[:: -1], valores[1 : 3], idade>=18?\"a\":\"b\")\nescreva(++a+1, a++ +1, - -1, [...xs, -5])");
    assert(exprs == "escreva(valores[::-1], valores[1:3], idade >= 18 ? \"a\" : \"b\")\nescreva(++a + 1, a++ + 1, - -1, [...xs, -5])\n",
            exprs);
    assert(exprs == formatDelegua(exprs));

    // Cabeçalho para sem parênteses (mesmo já quebrado), campo estático e faca/enquanto
    string loops = formatDelegua(
            "para var i:inteiro=0;\ni<3;\ni++{escreva(i)}\nfaca{x++}enquanto(x<5)\nclasse R{estatico\ncriados:inteiro=0}");
    assert(loops.indexOf("para var i: inteiro = 0; i < 3; i++ {") >= 0, loops);
    assert(loops.indexOf("} enquanto (x < 5)") >= 0, loops);
    assert(loops.indexOf("    estatico criados: inteiro = 0") >= 0, loops);
    assert(loops == formatDelegua(loops));

    // Interpolação com aspas internas e comentários de bloco
    string interp = formatDelegua("/* bloco */ var s: texto = \"v=${m[\"k\"]}\"\n");
    assert(interp == "/* bloco */ var s: texto = \"v=${m[\"k\"]}\"\n", interp);
    assert(interp == formatDelegua(interp));

    // Coleções multilinha preservadas com indentação de 4 espaços
    string multi = formatDelegua("var m: dicionario = {\n\"a\":1,\n\"b\":2\n}\n");
    assert(multi == "var m: dicionario = {\n    \"a\": 1,\n    \"b\": 2\n}\n", multi);
    assert(multi == formatDelegua(multi));
}
