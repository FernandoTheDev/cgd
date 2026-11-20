module tests.async_features;
import frontend;
import frontend.analysis;
import middle.lowering;
import middle.async_ir;
import std.algorithm : any;
import std.path : absolutePath;

private AnalysisResult analyzedAsync(string source, string filename)
{
    string path = absolutePath(filename);
    return analyzeSource(source, path, [path: source]);
}

unittest
{
    AnalysisResult result = analyzedAsync(`
assincrona funcao valor(): inteiro { retorna 1 }
funcao embrulhar(p: Promessa<Promessa<inteiro>>): Promessa<Promessa<inteiro>> { retorna p }
const p: Promessa<inteiro> = valor()
assincrona funcao consumidor(): inteiro { retorna aguardar p }
`, "async.delegua");
    // Uma Promise externa continua sendo captura, mesmo sendo imutável.
    assert(result.diagnostics.entries.any!((const(Diagnostic) d) => d.code == "E4001"));
    result = analyzedAsync(`assincrona funcao valor(): inteiro { retorna 1 }
const p: Promessa<inteiro> = valor()`, "async.delegua");
    assert(!result.diagnostics.hasErrors());
    VarDecl variable = cast(VarDecl) result.program.body[1];
    assert(variable.value.type_sema.toStr() == "Promessa<numero>");
    assert((cast(TypeSemaPromise) variable.type_sema) !is null);
}

unittest
{
    foreach (string source, string code; [
        "funcao f() { aguardar 1 }": "E3301",
        "assincrona funcao f() { aguardar 1 }": "E3302",
        "assincrona funcao f(x=aguardar g()) {} funcao g() {}": "E3301",
        "assincrona funcao f() { funcao g() { aguardar f() } }": "E3301",
        "classe A { assincrona construtor() {} }": "E3301",
        "assincrona funcao f(): inteiro { retorna 1 } var p: Promessa<real> = f()": "E3002",
        "assincrona funcao f(): qualquer[] { retorna [] } var p: Promessa<inteiro> = f()": "E3002",
        "interface A { assincrona f(): inteiro } classe B implementa A { f(): inteiro { retorna 1 } }": "E3304",
    ])
    {
        AnalysisResult result = analyzedAsync(source, "invalido.delegua");
        assert(result.diagnostics.entries.any!((const(Diagnostic) d) => d.code == code), source);
    }
}

unittest
{
    AnalysisResult result = analyzedAsync(`
funcao efeito(): inteiro { escreva("efeito"); retorna 3 }
assincrona funcao valor(): inteiro { retorna 1 }
assincrona funcao cenario(): inteiro {
    const morto: inteiro = efeito()
    var sobrescrito: inteiro = 1
    const vivo: inteiro = 9
    const x: inteiro = aguardar valor()
    sobrescrito = 2
    retorna vivo + x + sobrescrito
}`, "vivacidade.delegua");
    assert(!result.diagnostics.hasErrors());
    new CgdLowering(result.diagnostics).lowering(result.program);
    AsyncIR ir = new AsyncLowering().lower(cast(FnDecl) result.program.body[2]);
    assert(ir.verify());
    bool retainedLive;
    foreach (size_t index, AsyncSlot slot; ir.slots)
    {
        if (slot.sourceName == "morto" || slot.sourceName == "sobrescrito")
            assert((index in ir.persistent) is null);
        if (slot.sourceName == "vivo")
        {
            assert((index in ir.persistent) !is null);
            retainedLive = true;
        }
    }
    assert(retainedLive);
    size_t previous = ir.instructions[0].next;
    ir.instructions[0].next = ir.instructions.length + 1;
    assert(!ir.verify());
    ir.instructions[0].next = previous;
    ir.factBudget = 1;
    bool limited;
    try
        ir.analyzeLiveness();
    catch (AsyncLimitException error)
        limited = true;
    assert(limited);
}

unittest
{
    string source = "classe A { estatico assincrona f(x:Promessa<inteiro>):inteiro { retorna aguardar x } }";
    // O formatador lexical não pode separar os modificadores em membros novos.
    // A API exata é exercitada pelos testes de CLI/protocolo, além do parser.
    AnalysisResult result = analyzedAsync(source, "metodo.delegua");
    assert(!result.diagnostics.hasErrors());
}

unittest
{
    import lsp.model;

    FnDecl incomplete = new FnDecl("parcial", [], cast(TypeExpr) null, [], 0, null);
    incomplete.isAsync = true;
    Identifier callee = new Identifier("parcial", null);
    callee.functionRef = incomplete;
    CallExpr call = new CallExpr(callee, [], null);
    Document document = new Document("file:///tmp/async-parcial.delegua", "", 1);
    assert(document.expressionType(call).toStr() == "Promessa<qualquer>");
}

unittest
{
    import std.array : replicate;

    AnalysisResult result = analyzedAsync("var x: inteiro" ~ "[]".replicate(600) ~ " = []", "profundo.delegua");
    assert(result.diagnostics.entries.any!((const(Diagnostic) d) => d.code == "E1004"));
    result = analyzedAsync("var x: " ~ "Promessa<".replicate(350) ~ "inteiro" ~ ">".replicate(350), "profundo.delegua");
    assert(result.diagnostics.entries.any!((const(Diagnostic) d) => d.code == "E1003"));
}

unittest
{
    AnalysisResult result = analyzedAsync(`
assincrona funcao imediato(x: inteiro): inteiro { retorna x }
assincrona funcao protegida(): inteiro {
    var anterior: inteiro = 7
    tente {
        anterior = aguardar imediato(1)
    } pegue (erro: Excecao) {
        retorna anterior
    } finalmente {
        aguardar imediato(2)
    }
    retorna anterior
}`, "handlers.delegua");
    assert(!result.diagnostics.hasErrors());
    new CgdLowering(result.diagnostics).lowering(result.program);
    AsyncIR ir = new AsyncLowering().lower(cast(FnDecl) result.program.body[1]);
    assert(ir.verify());
    assert(ir.instructions.any!((AsyncInstruction instruction) => instruction.exceptional != size_t.max));
    assert(ir.instructions.any!((AsyncInstruction instruction) => instruction.op == AsyncOp.Await && instruction
            .cleanup));
    bool retained;
    foreach (size_t index, AsyncSlot slot; ir.slots)
        if (slot.sourceName == "anterior")
            retained = (index in ir.persistent) !is null;
    assert(retained);
}

unittest
{
    AnalysisResult result = analyzedAsync(`
assincrona funcao pausa(): vazio {}
assincrona funcao visitar(): vazio {
    para cada item: inteiro em [1, 2] {
        aguardar pausa()
        escolha item {
            caso 1: aguardar pausa()
            padrao: aguardar pausa()
        }
    }
}`, "await-comando.delegua");
    assert(!result.diagnostics.hasErrors());
}
