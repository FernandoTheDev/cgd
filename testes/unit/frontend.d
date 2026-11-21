module tests.frontend;

import frontend;
import frontend.modules;
import std.algorithm : any, count;
import std.file : mkdirRecurse, readText, rmdirRecurse, tempDir, write;
import std.path : buildPath;
import std.uuid : randomUUID;
import std.string : indexOf;

private Program parsed(string source, Diagnostics diagnostics)
{
    return new Parser(new Lexer(source, "teste.delegua", diagnostics).tokenizer(), diagnostics).parse();
}

private Diagnostics analyzed(string source)
{
    Diagnostics diagnostics = new Diagnostics;
    Program program = parsed(source, diagnostics);
    if (diagnostics.hasErrors())
        return diagnostics;
    Context context = new Context;
    TypeRegistry registry = new TypeRegistry;
    new DeclarationAnalysis(context, registry, diagnostics).analyze(program);

    new SemanticAnalyzer(context, registry, new TypeResolver(registry, diagnostics), diagnostics).analyze(program);
    return diagnostics;
}

unittest
{
    Diagnostics diagnostics = new Diagnostics;
    Token[] tokens = new Lexer("classe A {} tente {} pegue {} finalmente {} importar('m.delegua')",
            "teste.delegua", diagnostics).tokenizer();
    assert(!diagnostics.hasErrors());
    assert(tokens.any!((Token t) => t.kind == TokenKind.Class));
    assert(tokens.any!((Token t) => t.kind == TokenKind.Try));
    assert(tokens.any!((Token t) => t.kind == TokenKind.Catch));
    assert(tokens.any!((Token t) => t.kind == TokenKind.Finally));
    assert(tokens.any!((Token t) => t.kind == TokenKind.Import));
}

unittest
{
    Diagnostics diagnostics = analyzed("funcao criar(x) { retorna funcao() { retorna x } }");
    assert(diagnostics.hasErrors());
    assert(diagnostics.hasWarnings());
    assert(diagnostics.entries.any!((const(Diagnostic) d) => d.severity == Severity.Warning
            && d.message.indexOf("upvalues") >= 0));
}

unittest
{
    assert(!analyzed("funcao criar() { retorna funcao(x) { retorna x + 1 } }").hasErrors());
    assert(!analyzed("funcao criar() { retorna f; funcao f(x) { retorna x } }").hasErrors());
    assert(!analyzed("var x=1; se verdadeiro { var x=2; escreva(x) }").hasErrors());
    assert(analyzed("var x=1; var x=2").hasErrors());
    assert(analyzed("var texto=1; funcao f() { retorna texto }").hasWarnings());
}

unittest
{
    assert(analyzed("funcao f(x) { retorna x } f(1,2)").hasErrors());
    assert(analyzed("funcao f(x) { retorna x } f()").hasErrors());
    assert(!analyzed("funcao f(a,b=a+2) { retorna b } f(1)").hasErrors());
    assert(!analyzed("funcao f(...valores:inteiro) { retorna valores } f(1,2)").hasErrors());
    assert(analyzed("const x=1; x++").hasErrors());
    assert(analyzed("retorna 1").hasErrors());
    assert(analyzed("sustar").hasErrors());
}

unittest
{
    Diagnostics diagnostics = new Diagnostics;
    bool failed;
    try
        parsed("funcao f() { retorna 1", diagnostics);
    catch (Exception)
        failed = true;
    assert(diagnostics.hasErrors());
}

unittest
{
    assert(!analyzed(q{
        classe A { privado { x:numero } construtor() { isto.x=1 } valor() { retorna isto.x } }
        classe B herda A { valor() { retorna super.valor()+1 } }
        var f=B().valor;
        escreva(f());
    }).hasErrors());
    assert(analyzed("classe A herda B {} classe B herda A {}").hasErrors());
    assert(analyzed("classe A { privado { x:numero } } classe B herda A { x() {} }").hasErrors());
    assert(analyzed("classe A { criar() { retorna funcao() { retorna isto } } }").hasWarnings());
}

unittest
{
    assert(!analyzed(q{
        var resultado=para(var i=0;i<3;i++){tente{retorna i}finalmente{escreva(i)}}
        tente{falhar "erro"}pegue(erro:Excecao){escreva(erro.mensagem)}
    }).hasErrors());
}

unittest
{
    Diagnostics diagnostics = analyzed(q{
        var x=2;
        escreva("valor ${x+1}");
        var v=[x*2 para cada x em [1,2,3] se x>1];
        escreva(v[::-1]);
    });
    assert(!diagnostics.hasErrors());
}

unittest
{
    Diagnostics diagnostics = new Diagnostics;
    Program program = parsed("classe A {} classe B herda A {}", diagnostics);
    ClassDecl a = cast(ClassDecl) program.body[0];
    ClassDecl b = cast(ClassDecl) program.body[1];
    b.superClass = a;
    ClassDecl other = new ClassDecl("A", "", null);
    assert(new TypeSemaClass(a).isComp(new TypeSemaClass(b)));
    assert(!new TypeSemaClass(a).isComp(new TypeSemaClass(other)));
}

unittest
{
    string folder = buildPath(tempDir(), "cgd-module-" ~ randomUUID().toString());
    mkdirRecurse(folder);
    scope (exit)
        rmdirRecurse(folder);
    string root = buildPath(folder, "main.delegua");
    write(root, "var a=importar('a.delegua')");
    write(buildPath(folder, "a.delegua"), "var b=importar('b.delegua')");
    write(buildPath(folder, "b.delegua"), "var a=importar('a.delegua')");
    Diagnostics diagnostics = new Diagnostics;
    Program program = parsed(readText(root), diagnostics);
    new ModuleLoader(diagnostics).load(program, root);
    assert(diagnostics.hasErrors());
    assert(diagnostics.entries.any!((const(Diagnostic) d) => d.message.indexOf("Ciclo") >= 0));
}

unittest
{
    // Identidade/signatura pronta antes dos corpos: referências mútuas não são herança.
    assert(!analyzed("classe A{criar():qualquer{retorna B()}} classe B{criar():qualquer{retorna A()}}").hasErrors());
    assert(!analyzed("classe A{estatico dobro(x:inteiro):inteiro{retorna x*2}} var a:inteiro=A.dobro(2)").hasErrors());
    assert(analyzed("classe A{estatico erro():qualquer{retorna isto}}").hasErrors());
    assert(analyzed("classe A{estatico construtor(){}}").entries.any!((const(Diagnostic) d) => d.code == "E3012"));
    assert(!analyzed("classe A{estatico contador:inteiro}").hasErrors());
    assert(analyzed("interface I{estatico contador:inteiro}").entries.any!((const(Diagnostic) d) => d.code == "E3011"));
    assert(!analyzed("para cada valor:inteiro em [1,2]{escreva(valor)}").hasErrors());
}

unittest
{
    import frontend.flow : terminates;

    Diagnostics diagnostics = new Diagnostics;
    Program program = parsed("funcao a():inteiro{tente{retorna 1}finalmente{escreva(2)}} funcao b():inteiro{tente{retorna 1}pegue(erro){escreva(erro)}}",
            diagnostics);
    assert(terminates((cast(FnDecl) program.body[0]).body));
    assert(!terminates((cast(FnDecl) program.body[1]).body));
}

unittest
{
    assert(!analyzed("const {nome:texto, idade:inteiro}={nome:'CGD',idade:1}").hasErrors());
    assert(!analyzed("para cada {nome:texto, valor:inteiro} em {x:1}{escreva(nome,valor)}").hasErrors());
    assert(!analyzed("var v:inteiro[]=[1,2];escreva([x+1 para cada x:inteiro em v])").hasErrors());
}

unittest
{
    import std.process : environment;

    assert(isValidCgdModuleName("json"));
    assert(isValidCgdModuleName("sub/minha_lib-2"));
    assert(!isValidCgdModuleName(""));
    assert(!isValidCgdModuleName("../segredo"));
    assert(!isValidCgdModuleName("a/../b"));
    assert(!isValidCgdModuleName("/etc/passwd"));
    assert(!isValidCgdModuleName("a\\b"));
    assert(!isValidCgdModuleName("a:b"));

    string folder = buildPath(tempDir(), "cgd-libs-" ~ randomUUID().toString());
    mkdirRecurse(buildPath(folder, "sub"));
    scope (exit)
        rmdirRecurse(folder);
    string customFile = buildPath(folder, "custom.delegua");
    string nestedFile = buildPath(folder, "sub", "helper.delegua");
    write(customFile, "funcao ping(): inteiro { retorna 42 }\n");
    write(nestedFile, "funcao ok(): logico { retorna verdadeiro }\n");
    string previousEnv = environment.get("CGD_LIBS_DIR");
    environment["CGD_LIBS_DIR"] = folder;
    scope (exit)
    {
        if (previousEnv.length)
            environment["CGD_LIBS_DIR"] = previousEnv;
        else
            environment.remove("CGD_LIBS_DIR");
    }
    assert(resolveCgdLibrary("custom") == customFile);
    assert(resolveCgdLibrary("sub/helper") == nestedFile);
    assert(resolveCgdLibrary("../custom") is null);
    CgdLibraryEntry[] libs = listCgdLibraries();
    assert(libs.any!((CgdLibraryEntry e) => e.name == "custom" && e.fromUserDir));
    assert(libs.any!((CgdLibraryEntry e) => e.name == "sub/helper" && e.fromUserDir));
}

unittest
{
    import std.math : isClose;

    // Literais numéricos: hex, binário, octal, separadores, notação científica, hex-float e comentários /* */
    Diagnostics diag = new Diagnostics;
    Token[] tks = new Lexer("/* comentário\nde bloco */ 0xFF 0xFFFF_FFFF 0b101010 0b1111_0000 0o755 1_000_000 1.25e-8 6.022e23 3_141.592_653 0x1.fp+3 _100",
            "literais.delegua", diag).tokenizer();
    assert(!diag.hasErrors());
    assert(tks.length == 11);
    assert(tks[0].kind == TokenKind.Int && tks[0].value.i == 255);
    assert(tks[1].kind == TokenKind.Int && tks[1].value.i == 4_294_967_295L);
    assert(tks[2].kind == TokenKind.Int && tks[2].value.i == 42);
    assert(tks[3].kind == TokenKind.Int && tks[3].value.i == 240);
    assert(tks[4].kind == TokenKind.Int && tks[4].value.i == 493);
    assert(tks[5].kind == TokenKind.Int && tks[5].value.i == 1_000_000);
    assert(tks[6].kind == TokenKind.Double && isClose(tks[6].value.d, 1.25e-8));
    assert(tks[7].kind == TokenKind.Double && isClose(tks[7].value.d, 6.022e23));
    assert(tks[8].kind == TokenKind.Double && isClose(tks[8].value.d, 3141.592653));
    assert(tks[9].kind == TokenKind.Double && isClose(tks[9].value.d, 15.5));
    assert(tks[10].kind == TokenKind.Identifier && tks[10].value.s == "_100");

    // Chamadas de método após literal numérico continuam funcionando (ex: 0xFF.formatar(), 10.absoluto())
    assert(!analyzed("escreva(0xFF.formatar(), 10.absoluto(), 3.14.formatar())").hasErrors());

    // Casos negativos que devem produzir E1005 controlado
    string[] invalidLiterals = [
        "0x", "0b", "0o", "0b102", "0o89", "1__000", "100_", "0x_FF", "0xFF_", "1_.0", "1._0",
        "1e", "1e+", "1e-", "1e_5", "1e5_", "0xGG", "0x1.fp", "0x1.fp+", "0x8000_0000_0000_0000"
    ];
    foreach (string bad; invalidLiterals)
    {
        Diagnostics badDiag = new Diagnostics;
        new Lexer("const x = " ~ bad, "invalido.delegua", badDiag).tokenizer();
        assert(badDiag.hasErrors(), "Deveria falhar: " ~ bad);
        assert(badDiag.entries.any!((const(Diagnostic) d) => d.code == "E1005"), "Esperado E1005 para: " ~ bad);
    }

    // Diagnóstico claro quando palavra reservada (ex: 'e') é usada como identificador
    Diagnostics kwDiag = analyzed("tente { escreva(1) } pegue (e: Excecao) { escreva(2) }");
    assert(kwDiag.hasErrors());
    assert(kwDiag.entries.any!((const(Diagnostic) d) => d.code == "E1001" && d.message.indexOf("palavra reservada") >= 0));
}
