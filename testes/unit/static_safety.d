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
    new Sema1(context, diagnostics).analyze(program);
    new Sema2(registry).analyze(program);
    new Sema3(context, registry, new TypeResolver(registry, diagnostics), diagnostics).analyze(program);
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
