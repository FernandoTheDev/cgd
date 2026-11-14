module tests.diagnostics;

import frontend;
import std.json : parseJSON, JSONValue;
import std.string : indexOf;

unittest
{
    Position pos = new Position("ação.delegua", new PosLine(3, 1), new PosLine(4, 1));
    Diagnostic d = Diagnostic(Severity.Error, pos, "Mensagem com 'aspas' e ç", "E1001");
    JSONValue json = parseJSON(diagnosticJSON(d));
    assert(json["code"].str == "E1001");
    assert(json["range"]["start"]["column"].integer == 3);
    string text = diagnosticText(d, "\táx");
    assert(text.indexOf("    áx") >= 0);
    assert(text.indexOf("E1001") >= 0);
}

unittest
{
    Diagnostics diagnostics = new Diagnostics;
    diagnostics.error(null, "duplicado", "E1001");
    diagnostics.error(null, "duplicado", "E1001");
    assert(diagnostics.entries.length == 1);
    foreach (int i; 0 .. 200)
    {
        import std.conv : to;

        diagnostics.error(null, i.to!string);
    }
    assert(diagnostics.entries.length == Diagnostics.maxErrors + 1);
    assert(diagnostics.entries[$ - 1].code == "E0002");
}

unittest
{
    Diagnostics diagnostics = new Diagnostics;
    Program p = new Parser(new Lexer("var a=; var b=; var c=3", "teste.delegua", diagnostics).tokenizer(), diagnostics)
        .parse();
    assert(diagnostics.entries.length == 2);
    assert(p.body.length == 1 && (cast(VarDecl) p.body[0]).name == "c");
}

unittest
{
    Diagnostics diagnostics = new Diagnostics;
    new Lexer("\xff", "invalido.delegua", diagnostics).tokenizer();
    assert(diagnostics.entries.length == 1 && diagnostics.entries[0].code == "E1002");
}

unittest
{
    import std.array : replicate;

    Diagnostics diagnostics = new Diagnostics;
    new Parser(new Lexer("var x=" ~ "(".replicate(300) ~ "1" ~ ")".replicate(300), "profundo.delegua",
            diagnostics).tokenizer(), diagnostics).parse();
    import std.algorithm : any;

    assert(diagnostics.entries.any!((const(Diagnostic) d) => d.code == "E1003"));
}

unittest
{
    import frontend.validation;

    Diagnostics diagnostics = new Diagnostics;
    Node expression = new IntLit(1, null);
    foreach (int _; 0 .. 600)
        expression = new BinaryExpr(expression, new IntLit(1, null), TokenKind.Plus, null);
    assert(!validateStructure(new Program([expression]), diagnostics));
    assert(diagnostics.entries[0].code == "E1004");
}

unittest
{
    Diagnostics diagnostics = new Diagnostics;
    new Lexer("//>", "qualificador.delegua", diagnostics).tokenizer();
    assert(diagnostics.entries[0].code == "E1001");
}

unittest
{
    Diagnostics diagnostics = new Diagnostics;
    string source = "funcao f(){var a=;var b=2; retorna b} var fim=3";
    Program parsed = new Parser(new Lexer(source, "blocos.delegua", diagnostics).tokenizer(), diagnostics).parse();
    assert(diagnostics.entries.length == 1 && parsed.body.length == 2);
    assert((cast(FnDecl) parsed.body[0]).body.length == 2);
}

unittest
{
    import frontend.flow;

    Diagnostics diagnostics = new Diagnostics;
    string source = "funcao f(x):inteiro{se x{retorna 1}}";
    Program parsed = new Parser(new Lexer(source, "retorno.delegua", diagnostics).tokenizer(), diagnostics).parse();
    new FlowAnalysis(diagnostics).analyze(parsed);
    import std.algorithm : any;

    assert(diagnostics.entries.any!((const(Diagnostic) d) => d.code == "W3002"));
}

unittest
{
    Diagnostics diagnostics = new Diagnostics;
    Token[] tokens = new Lexer("var ação = 1", "unicode.delegua", diagnostics).tokenizer();
    assert(tokens[0].pos.start.offset == 1 && tokens[0].pos.end.offset == 4);
    assert(tokens[1].pos.start.offset == 5 && tokens[1].pos.end.offset == 9);
    assert(tokens[2].pos.start.offset == 10 && tokens[2].pos.end.offset == 11);
    assert(tokens[3].pos.start.offset == 12 && tokens[3].pos.end.offset == 13);
}
