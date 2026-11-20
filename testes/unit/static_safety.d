module tests.static_safety;

import frontend;
import frontend.static_safety;
import std.algorithm : any;

private Diagnostics analyze(string source)
{
    Diagnostics diagnostics = new Diagnostics;
    Program program = new Parser(new Lexer(source, "seguranca.delegua", diagnostics).tokenizer(), diagnostics).parse();
    Context context = new Context;
    TypeRegistry registry = new TypeRegistry;
    new DeclarationAnalysis(context, registry, diagnostics).analyze(program);

    new SemanticAnalyzer(context, registry, new TypeResolver(registry, diagnostics), diagnostics).analyze(program);
    if (!diagnostics.hasErrors())
        new StaticSafety(diagnostics).analyze(program);
    return diagnostics;
}

unittest
{
    foreach (string source; ["escreva(1/0)", "const zero=3-3; escreva(1/zero)"])
        assert(analyze(source).entries.any!((const(Diagnostic) d) => d.code == "E3101"));
    foreach (string source; ["escreva(9223372036854775807+1)", "escreva(2**100)"])
        assert(analyze(source).entries.any!((const(Diagnostic) d) => d.code == "E3102"));
}

unittest
{
    assert(analyze("escreva([1,2][-3])").entries.any!((const(Diagnostic) d) => d.code == "E3103"));
    assert(analyze("escreva('ação'[4])").entries.any!((const(Diagnostic) d) => d.code == "E3103"));
    assert(!analyze("escreva('ação'[3])").hasErrors());
    assert(analyze("escreva([1][0.5])").hasErrors());
    assert(analyze("escreva([1][::0])").entries.any!((const(Diagnostic) d) => d.code == "E3108"));
}

unittest
{
    assert(analyze("var x:inteiro=2.5").entries.any!((const(Diagnostic) d) => d.code == "E3104"));
    assert(analyze("funcao f(x:inteiro){retorna x}f(2.5)").entries.any!((const(Diagnostic) d) => d.code == "E3104"));
    assert(analyze("funcao f():inteiro{retorna 2.5}").entries.any!((const(Diagnostic) d) => d.code == "E3104"));
    assert(!analyze("var x:real=2;var y:inteiro=3").hasErrors());
}

unittest
{
    assert(!analyze("escreva(falso e 1/0, verdadeiro ou 1/0, verdadeiro?7:1/0)").hasErrors());
    assert(!analyze("se !verdadeiro{escreva(1/0)}enquanto falso{escreva(1/0)}").hasErrors());
    assert(!analyze("para(;falso;){escreva(1/0)}para cada x em []{escreva(1/0)}").hasErrors());
    Diagnostics diagnostics = analyze("tente{escreva(1/0)}pegue(erro){escreva(erro)}");
    assert(!diagnostics.hasErrors() && diagnostics.entries.any!((const(Diagnostic) d) => d.code == "W3101"));
}

unittest
{
    assert(analyze("escreva(inteiro('12abc'))").entries.any!((const(Diagnostic) d) => d.code == "E3106"));
    assert(analyze("escreva(1<<64)").entries.any!((const(Diagnostic) d) => d.code == "E3107"));
    assert(analyze("escreva(1.5%2)").entries.any!((const(Diagnostic) d) => d.code == "E3105"));
    assert(!analyze("funcao f(x,y){retorna x/y}f(1,0)").hasErrors()); // dado interprocedural desconhecido
}

unittest
{
    bool[string] codes;
    foreach (MessageSpec spec; messages)
    {
        assert(spec.code !in codes);
        codes[spec.code] = true;
        assert(lookupMessage(spec.code) !is null);
    }
    assert(lookupMessage("W3101") !is null);
    assert(lookupMessage("E9999") is null);
}

unittest
{
    assert(!analyze("escreva(real('0x1p2'))").hasErrors());
    assert(analyze("escreva(inteiro('12 '))").entries.any!((const(Diagnostic) d) => d.code == "E3106"));
    assert(!analyze("escreva(inteiro(' 12'))").hasErrors());
    assert(analyze("escreva(real('1e999'))").entries.any!((const(Diagnostic) d) => d.code == "E3106"));
}

unittest
{
    assert(!analyze("var x:inteiro=1;x+=verdadeiro").hasErrors());
}

unittest
{
    assert(analyze("para cada valor:inteiro em ['x']{escreva(valor)}")
            .entries.any!((const(Diagnostic) d) => d.code == "E3104"));
    assert(!analyze("tente{para cada valor:inteiro em ['x']{escreva(valor)}}pegue(erro){escreva(erro)}").hasErrors());
    assert(!analyze("const {nome:texto}={nome:'CGD'};escreva(nome)").hasErrors());
}

unittest
{
    // E3109: membro inexistente em tipo primitivo, classe exata e polimorfismo seguro
    assert(analyze("var s:texto='oi'; escreva(s.naoExiste())").entries.any!((const(Diagnostic) d) => d.code == "E3109"));
    assert(analyze("classe A{x:inteiro} var a=A(); escreva(a.y)")
            .entries.any!((const(Diagnostic) d) => d.code == "E3109"));
    // Subclasse define campo acessado via referência à base: permitido
    assert(!analyze("classe Base{k:inteiro} classe Sub herda Base{valor:inteiro} funcao ler(b:Base){retorna b.valor}")
            .hasErrors());
    // Instância exata da base NÃO possui campo exclusivo de subclasse: E3109
    assert(analyze("classe Base{k:inteiro} classe Sub herda Base{valor:inteiro} var b=Base(); escreva(b.valor)")
            .entries.any!((const(Diagnostic) d) => d.code == "E3109"));
    // Membro inexistente na base e em todas as subclasses: E3109
    assert(analyze("classe Base{k:inteiro} classe Sub herda Base{valor:inteiro} funcao ler(b:Base){retorna b.ausente}")
            .entries.any!((const(Diagnostic) d) => d.code == "E3109"));
    // E3110: mutação de texto/tupla imutável
    assert(analyze("var s:texto='abc'; s[0]='z'").entries.any!((const(Diagnostic) d) => d.code == "E3110"));
    assert(analyze("var t:tupla=tupla([1,2]); t[0]=9").entries.any!((const(Diagnostic) d) => d.code == "E3110"));
    // E3111: operação sobre nulo
    assert(analyze("const n=nulo; escreva(n.tamanho())").entries.any!((const(Diagnostic) d) => d.code == "E3111"));
    assert(analyze("var n=nulo; escreva(n[0])").entries.any!((const(Diagnostic) d) => d.code == "E3111"));
    assert(analyze("var n=nulo; n()").entries.any!((const(Diagnostic) d) => d.code == "E3111"));
    // E3112: valor não invocável (estático e dinâmico constante)
    assert(analyze("const x=42; x()").entries.any!((const(Diagnostic) d) => d.code == "E3112"));
    assert(analyze("var x:qualquer=42; x()").entries.any!((const(Diagnostic) d) => d.code == "E3112"));
    // Contrato de vetor tipado em .adicionar e atribuição por índice
    assert(analyze("var v:inteiro[]=[]; v.adicionar('x')").entries.any!((const(Diagnostic) d) => d.code == "E3104"));
    assert(analyze("var v:inteiro[]=[1]; v[0]='x'").entries.any!((const(Diagnostic) d) => d.code == "E3002"));
    assert(analyze("var v:inteiro[]=[1]; v[0]=2.5").entries.any!((const(Diagnostic) d) => d.code == "E3104"));
    assert(analyze("var v:inteiro[]=[1]; var s:qualquer='x'; v[0]=s")
            .entries.any!((const(Diagnostic) d) => d.code == "E3104"));
    // Aviso W31xx em região protegida por pegue
    Diagnostics guarded = analyze("tente{var x:qualquer=42; x()}pegue(erro){escreva(erro)}");
    assert(!guarded.hasErrors() && guarded.entries.any!((const(Diagnostic) d) => d.code == "W3112"));
    assert(lookupMessage("W3109") !is null && lookupMessage("W3112") !is null);
}
