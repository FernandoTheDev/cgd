module tests.codegen;

import backend.c.utils;
import std.format : format;
import std.conv : to;

unittest
{
    foreach (dstring name; [""d, "main"d, "ação"d, "#fn_0"d, "int"d, "x_12"d])
    {
        dstring expected = "cgd_user"d;
        foreach (dchar ch; name)
            expected ~= format("_%x", cast(uint) ch).to!dstring;
        assert(cName(name) == expected);
    }
    assert(cName("a_b") != cName("a5fb"));
}

unittest
{
    foreach (dstring text; [""d, "a\\b\"c\n"d, "ação💚"d, "\0"d])
    {
        dstring expected = "\""d;
        foreach (ubyte byteValue; cast(const(ubyte)[]) text.to!string)
            expected ~= format("\\%03o", byteValue).to!dstring;
        expected ~= '"';
        assert(cString(text) == expected);
    }
}

unittest
{
    import frontend;
    import backend.c.codegen;
    import middle.lowering;
    import std.string : indexOf;

    Diagnostics diagnostics = new Diagnostics;
    Program program = new Parser(new Lexer("var a=1;var b=2;var c=3;escreva(a+b+c)",
            "origem.delegua", diagnostics).tokenizer(), diagnostics).parse();
    Context context = new Context;
    TypeRegistry registry = new TypeRegistry;
    new DeclarationAnalysis(context, registry, diagnostics).analyze(program);

    new SemanticAnalyzer(context, registry, new TypeResolver(registry, diagnostics), diagnostics).analyze(program);
    new CgdLowering(diagnostics).lowering(program);
    string code = new BackendC().compile(program).to!string;
    assert(code.indexOf("delegua_localizar(") < 0);
    assert(code.indexOf("static const delegua_local cgd_source_sites[]") >= 0);
    assert(code.indexOf("delegua_local_atual=&cgd_source_sites[") >= 0);
}

unittest
{
    import frontend.parser;
    import backend.c.codegen;

    BackendC generator = new BackendC;
    assert(generator.compileExpr(new IntLit(long.min, null)) == "create_num(INT64_MIN)");
    assert(generator.compileExpr(new DoubleLit(-0.0, null)) == "create_real(-0.0)");
    assert(generator.materialize(new IntLit(1, null)) == "create_num(1)");
}
