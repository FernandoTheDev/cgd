module tests.expansion;

import frontend;
import frontend.analysis;
import frontend.semantic.pipeline;
import frontend.semantic.native_methods;
import lsp.model;
import lsp.completion;
import lsp.evaluation;
import std.algorithm : any, canFind;
import std.json;
import std.string : indexOf;

private AnalysisResult analyzed(string source)
{
    string path = "/tmp/cgd-expansao.delegua";
    return analyzeSource(source, path, [path: source]);
}

private Document indexed(string source)
{
    Document document = new Document("file:///tmp/cgd-expansao.delegua", source, 1);
    document.analysis = analyzed(source);
    document.index(document.analysis.program);
    document.finishIndex();
    return document;
}

unittest
{
    Diagnostics diagnostics = new Diagnostics;
    Token[] tokens = new Lexer("construtor destrutor estatico estático ação αβ cafe\u0301",
            "tokens.delegua", diagnostics).tokenizer();
    assert(!diagnostics.hasErrors());
    assert(tokens[0].kind == TokenKind.Constructor);
    assert(tokens[1].kind == TokenKind.Destructor);
    assert(tokens[2].kind == TokenKind.Static && tokens[3].kind == TokenKind.Static);
    assert(tokens[5].value.s == "αβ" && tokens[6].value.s == "cafe\u0301");
}

unittest
{
    assert(!analyzed("classe A { destrutor() {} } destruir(A())").diagnostics.hasErrors());
    foreach (string source; [
        "classe A { estatico destrutor() {} }", "classe A { destrutor(x: inteiro) {} }",
        "classe A { destrutor(): inteiro { retorna 1 } }", "classe A { privado { destrutor() {} } }"
    ])
        assert(analyzed(source).diagnostics.entries.any!((const(Diagnostic) diagnostic) => diagnostic.code == "E3013"));
}

unittest
{
    assert(analyzed("classe A { privado { x: inteiro } } var a=A(); escreva(a.x)")
            .diagnostics.entries.any!((const(Diagnostic) diagnostic) => diagnostic.code == "E3014"));
    assert(analyzed("classe A { x: inteiro } escreva(A.x)")
            .diagnostics.entries.any!((const(Diagnostic) diagnostic) => diagnostic.code == "E3015"));
    assert(analyzed("classe A { f(x: inteiro) {} } A().f()")
            .diagnostics.entries.any!((const(Diagnostic) diagnostic) => diagnostic.code == "E3016"));
    assert(!analyzed("classe A { privado { x: inteiro } f(outro: A) { retorna outro.x } }").diagnostics.hasErrors());
}

unittest
{
    string source = "classe A { x: inteiro construtor() { isto.x=1 } f() { isto. } }";
    Document document = indexed(source);
    JSONValue params = JSONValue(["position": point(0, cast(uint) source.indexOf("isto. }") + 5)]);
    JSONValue completion = completions(document, params);
    bool field, method;
    foreach (JSONValue item; completion["items"].array)
    {
        field = field || item["label"].str == "x" && item["kind"].integer == 5;
        method = method || item["label"].str == "f" && item["kind"].integer == 2;
        assert(item["label"].str != "escreva");
    }
    assert(field && method);
}

unittest
{
    Document document = indexed("classe A { constr }");
    JSONValue completion = completions(document, JSONValue(["position": point(0, 17)]));
    assert(completion["items"].array.any!((JSONValue item) => item["label"].str == "construtor"
            && item["kind"].integer == 14));
}

unittest
{
    AnalysisResult result = analyzed("//>puro\nfuncao dobro(x: inteiro): inteiro { retorna x*2 } var y=dobro(6+1)");
    assert(!result.diagnostics.hasErrors());
    VarDecl variable = cast(VarDecl) result.program.body[$ - 1];
    ConstantPreview preview = new ConstantPreview(result.pureFunctions);
    assert(previewText(preview.evaluate(variable.value)) == "14");
    assert(cast(CallExpr) variable.value); // A AST do documento não foi otimizada.
    assert(previewText(preview.evaluate(variable.value)) == "14");
}

unittest
{
    AnalysisResult result = analyzed(
            "//>puro\nfuncao infinito(x: inteiro): inteiro { enquanto verdadeiro {} retorna x } var y=infinito(1)");
    assert(!result.diagnostics.hasErrors());
    VarDecl variable = cast(VarDecl) result.program.body[$ - 1];
    assert(new ConstantPreview(result.pureFunctions).evaluate(variable.value) is null);
}

unittest
{
    TypeSema receiver = new TypeSemaBuiltin(TypeSemaBase.Map);
    assert(builtinMethods(receiver).canFind("obter"));
    assert(builtinMethod(receiver, "obter").args.length == 2);
    assert(builtinMethod(receiver, "obter").args[1].value !is null);
    assert(builtinMethod(receiver, "definir").args.length == 2);
    assert(builtinMethod(receiver, "contemChave").type_sema.toStr() == "logico");
}

unittest
{
    assert(!analyzed("classe A { x: inteiro construtor() { isto.x=0 } f() { isto.x++ } }").diagnostics.hasErrors());
    assert(analyzed("const x=1; x++")
            .diagnostics.entries.any!((const(Diagnostic) diagnostic) => diagnostic.code == "E3017"));
    AnalysisResult result = analyzed("//>puro\nfuncao soma(x: inteiro): inteiro { var total: inteiro=0; enquanto x>0 { total+=x; x-- } retorna total } const n: inteiro=4; var y=soma(n)");
    assert(!result.diagnostics.hasErrors());
    VarDecl variable = cast(VarDecl) result.program.body[$ - 1];
    assert(previewText(new ConstantPreview(result.pureFunctions).evaluate(variable.value)) == "10");
}

unittest
{
    AnalysisResult result = analyzed(
            "//>puro\nfuncao crescer(x: texto): texto { enquanto verdadeiro { x=x+x } retorna x } var y=crescer('a')");
    assert(!result.diagnostics.hasErrors());
    VarDecl variable = cast(VarDecl) result.program.body[$ - 1];
    assert(new ConstantPreview(result.pureFunctions).evaluate(variable.value) is null);
}

unittest
{
    string source = "classe Base { protegido { campo: inteiro } f() {} } classe Filha herda Base { g() { super. } }";
    Document document = indexed(source);
    JSONValue completion = completions(document, JSONValue([
        "position": point(0, cast(uint) source.indexOf("super.") + 6)
    ]));
    assert(completion["items"].array.any!((JSONValue item) => item["label"].str == "f"));
    assert(!completion["items"].array.any!((JSONValue item) => item["label"].str == "campo"));
}

unittest
{
    import std.array : replicate;

    Diagnostics diagnostics = new Diagnostics;
    new Lexer("var enorme=" ~ "9".replicate(400) ~ ".0", "literal.delegua", diagnostics).tokenizer();
    assert(diagnostics.entries.any!((const(Diagnostic) diagnostic) => diagnostic.code == "E1005"));
}

unittest
{
    assert(!analyzed(
            "classe abstrata A { abstrato valor(): inteiro; } classe B herda A { valor(): inteiro { retorna 1 } } var b=B()")
            .diagnostics.hasErrors());
    assert(analyzed("classe abstrata A {} var a=A()").diagnostics.hasErrors());
    assert(analyzed("classe abstrata A { abstrato f(): inteiro; } classe B herda A {} var b=B()")
            .diagnostics.hasErrors());
    assert(!analyzed("interface I { f(x: inteiro): inteiro; } classe C implementa I { f(x: inteiro): inteiro { retorna x } } var c: I=C()")
            .diagnostics.hasErrors());
    assert(analyzed("interface I { f(): inteiro; } classe C implementa I {}").diagnostics.hasErrors());
    assert(!analyzed("enum Estado { Inicial, Final=7 } var estado: Estado=Estado.Final").diagnostics.hasErrors());
    assert(!analyzed("var f: funcao=(x: inteiro): inteiro => x+1; var g: funcao=x=>x*2").diagnostics.hasErrors());
    assert(analyzed("var f=(a=1,b)=>a+b").diagnostics.hasErrors());
    assert(analyzed("funcao f(x) { retorna y=>x+y }").diagnostics.hasErrors());
    assert(!analyzed("@definicao(biblioteca='m') classe estrangeira M { @definicao(simbolo='cos') cos(x: numero): numero; } escreva(M.cos(0))")
            .diagnostics.hasErrors());
}

unittest
{
    import frontend.formatter;

    string formatted = formatDelegua(
            "@ definicao(biblioteca=\"m\")\nclasse estrangeira M { @ definicao(simbolo=\"cos\") cos(x: numero): numero; }");
    assert(formatted.indexOf("@definicao") >= 0);
    assert(formatted.indexOf("@ definicao") < 0);
    assert(formatDelegua(formatted) == formatted);
    assert(formatDelegua("var f=(x: inteiro)=>x+1").indexOf("=>") >= 0);
    AnalysisResult result = analyzed(
            "var numero: numero; var texto: texto; var itens: inteiro[]; classe C { x: inteiro = 2; valores: inteiro[] }");
    assert(!result.diagnostics.hasErrors());
    assert(cast(IntLit)(cast(VarDecl) result.program.body[0]).value);
    assert(cast(StringLit)(cast(VarDecl) result.program.body[1]).value);
    assert(cast(ArrayLit)(cast(VarDecl) result.program.body[2]).value);
    ClassDecl cls = cast(ClassDecl) result.program.body[3];
    assert(cls.fields[0].initializer !is null && cls.fields[1].initializer !is null);
}

unittest
{
    import frontend.formatter;

    foreach (string source; [
        "var f=x=>(x+1)", "var f=x=>[x]", "var f=x=>{retorna x}", "var f=(x: inteiro)=>x+1"
    ])
    {
        string result = formatDelegua(source);
        assert(result.indexOf(" => ") >= 0, result);
        assert(result.indexOf("=>(") < 0 && result.indexOf("=>[") < 0, result);
        assert(formatDelegua(result) == result, result);
    }
    foreach (string source; [
        "funcao f() { enum E { A, B=8 } var valor: E=E.B; retorna valor } f()",
        "se verdadeiro { enum E { A } var valor: E=E.A } se verdadeiro { enum E { B=2 } var valor: E=E.B }",
        "tente { falhar 'x' } pegue { enum E { A } var valor: E=E.A }",
        "classe C { enum E { A, B=4 } x: E=1; f(): E { enum L { Valor=2 } retorna L.Valor } } escreva(C.E.B)",
        "interface I { enum E { A } } classe C implementa I {} escreva(I.E.A)",
        "enum Global { A=3 } funcao f(): inteiro { retorna Global.A } f()",
        "//>puro\nfuncao f(): inteiro { enum E { A=3 } retorna E.A } var x=f()",
        "funcao f(): inteiro { enum E { A=3 } funcao g(): inteiro { retorna E.A } retorna g() } f()",
    ])
        assert(!analyzed(source).diagnostics.hasErrors(), source);
    assert(analyzed("se verdadeiro { enum Local { A } } var x: Local=0").diagnostics.hasErrors());
    assert(analyzed("classe C { enum E { A } } C.E={}").diagnostics.hasErrors());
    assert(analyzed("enum E { A } enum E { B }").diagnostics.hasErrors());
    assert(analyzed("classe A { enum E { Valor } f() { retorna B() } } classe B { valor: E }").diagnostics.hasErrors());
}

unittest
{
    AnalysisResult result = analyzed("enum G { Valor=7 }\n//>puro\nfuncao f(x: inteiro): inteiro { enum E { Dobro=2 } retorna x*E.Dobro } var resultado=f(G.Valor)");
    assert(!result.diagnostics.hasErrors());
    ConstantPreview preview = new ConstantPreview(result.pureFunctions);
    IntLit value = cast(IntLit) preview.evaluate((cast(VarDecl) result.program.body[$ - 1]).value);
    assert(value !is null && value.value == 14);
}
