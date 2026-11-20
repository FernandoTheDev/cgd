module lsp.features;

import frontend;
import lsp.model;
import std.conv : to;
import std.json;

immutable string[] semanticTokenTypes = [
    "namespace", "type", "class", "parameter", "variable", "property", "function", "method",
    "keyword", "comment", "string", "number", "operator", "decorator"
];
immutable string[] semanticTokenModifiers = ["declaration", "readonly", "defaultLibrary"];

JSONValue buildSemanticTokens(Document doc)
{
    uint[] data;
    uint previousLine, previousColumn;
    bool afterAt, metadata;
    size_t metadataParens;
    bool[string] typeNames;
    foreach (string name; [
        "numero", "número", "inteiro", "longo", "real", "decimal", "texto", "logico", "lógico",
        "booleano", "binario", "binário", "qualquer", "vazio", "nulo", "tupla", "dicionario",
        "dicionário", "funcao", "função", "Objeto", "Excecao", "Promessa", "Tarefa"
    ])
        typeNames[name] = true;
    foreach (SymbolEntry symbol; doc.symbols)
        if (symbol.declaration && symbol.kind == "class")
            typeNames[symbol.name] = true;
    foreach (size_t tokenIndex, Token token; doc.analysis.tokens)
    {
        if (token.pos is null)
            continue;
        string category;
        uint modifiers;
        switch (token.kind)
        {
            case TokenKind.Identifier:
                category = "variable";
                break;
            case TokenKind.String:
                category = "string";
                break;
            case TokenKind.Int:
            case TokenKind.Double:
                category = "number";
                break;
            case TokenKind.Comment:
            case TokenKind.Pure:
                category = "comment";
                break;
            case TokenKind.True:
            case TokenKind.False:
            case TokenKind.Null:
                category = "keyword";
                break;
            default:
                category = token.kind < TokenKind.Identifier ? "keyword" : "operator";
                break;
        }
        if (token.kind == TokenKind.Identifier)
            if (size_t* offset = Document.offsetKey(token.pos.start.line, token.pos.start.offset) in doc.symbolOffsets)
            {
                SymbolEntry symbol = doc.symbols[*offset];
                category = symbol.kind;
                if (symbol.declaration)
                    modifiers |= 1;
            }

        if (token.kind == TokenKind.Identifier)
        {
            if (token.value.s.to!string in typeNames)
                if (Document.offsetKey(token.pos.start.line, token.pos.start.offset) !in doc.symbolOffsets)
                    category = "type";
            if (afterAt)
            {
                category = "decorator";
                afterAt = false;
                metadata = true;
            }
            else if (metadata && metadataParens && tokenIndex + 1 < doc.analysis.tokens.length
                    && doc.analysis.tokens[tokenIndex + 1].kind == TokenKind.Equals)
                category = "property";
        }
        if (token.kind == TokenKind.At)
            afterAt = true;
        else if (metadata && token.kind == TokenKind.LParen)
            metadataParens++;
        else if (metadata && token.kind == TokenKind.RParen)
        {
            if (metadataParens)
                metadataParens--;
            if (!metadataParens)
                metadata = false;
        }
        else if (metadata && !metadataParens && token.kind != TokenKind.Identifier)
            metadata = false;
        uint typeIndex = 4;
        foreach (size_t i, immutable(string) name; semanticTokenTypes)
            if (name == category)
                typeIndex = cast(uint) i;
        uint first = token.pos.start.line - 1, last = token.pos.end.line - 1;
        foreach (uint line; first .. last + 1)
        {
            if (line >= doc.lines.length)
                continue;
            uint start = line == first ? token.pos.start.offset - 1 : 0;
            uint end = line == last ? token.pos.end.offset - 1 : cast(uint) doc.lines[line].to!dstring.length;
            uint column = doc.utf16(line, start), endColumn = doc.utf16(line, end);
            if (endColumn <= column)
                continue;
            data ~= [
                line - previousLine, line == previousLine ? column - previousColumn : column,
                endColumn - column, typeIndex, modifiers
            ];
            previousLine = line;
            previousColumn = column;
        }
    }
    JSONValue[] result;
    foreach (uint n; data)
        result ~= JSONValue(n);
    return JSONValue(["data": arrayJSON(result), "resultId": JSONValue(doc.revision.to!string)]);
}
