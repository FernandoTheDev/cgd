module tests.optimizer;

import frontend;
import ctfe;
import frontend.flow;
import frontend.semantic.purity;
import opt.pass_manager;
import opt.constant_folding;
import opt.dead_code;
import std.algorithm : any;

private Program program(string source, out Context context)
{
    Diagnostics diagnostics = new Diagnostics;
    Program result = new Parser(new Lexer(source, "opt.delegua", diagnostics).tokenizer(), diagnostics).parse();
    context = new Context;
    TypeRegistry registry = new TypeRegistry;
    TypeResolver resolver = new TypeResolver(registry, diagnostics);
    new DeclarationAnalysis(context, registry, diagnostics).analyze(result);

    new SemanticAnalyzer(context, registry, resolver, diagnostics).analyze(result);
    if (diagnostics.hasErrors())
        diagnostics.report();
    assert(!diagnostics.hasErrors());
    return result;
}

unittest
{
    Context context;
    Program p = program("var a=(2+3)*4; var b=7%3; var c='a'+'b'; var d=1!=2; var flag=verdadeiro==falso", context);
    OptimizationStats stats = optimize(p, new CTFEContext);
    assert(stats.iterations == 2 && stats.folded >= 6);
    assert((cast(IntLit)(cast(VarDecl) p.body[0]).value).value == 20);
    assert((cast(IntLit)(cast(VarDecl) p.body[1]).value).value == 1);
    assert((cast(StringLit)(cast(VarDecl) p.body[2]).value).value == "ab");
    assert((cast(BoolLit)(cast(VarDecl) p.body[3]).value).value);
    assert(!(cast(BoolLit)(cast(VarDecl) p.body[4]).value).value);
    assert(optimize(p, new CTFEContext).iterations == 1);
}

unittest
{
    Context context;
    Program p = program("var a=9223372036854775807+1; var b=1/0; var c=7/2; var d=2.0+3.0", context);
    optimize(p, new CTFEContext);
    assert(cast(BinaryExpr)(cast(VarDecl) p.body[0]).value);
    assert(cast(BinaryExpr)(cast(VarDecl) p.body[1]).value);
    assert((cast(DoubleLit)(cast(VarDecl) p.body[2]).value).value == 3.5);
}

unittest
{
    Context context;
    Program p = program("const x=2; se verdadeiro { const x=9; escreva(x+1) } escreva(x+1)", context);
    optimize(p, new CTFEContext);
    BlockStmt inner = cast(BlockStmt) p.body[1];
    assert((cast(IntLit)(cast(CallExpr) inner.body[1]).args[0]).value == 10);
    assert((cast(IntLit)(cast(CallExpr) p.body[2]).args[0]).value == 3);
}

unittest
{
    Context context;
    Program p = program("funcao f(){escreva(1);retorna 2} var x=f(); var y=f()*0; enquanto falso {f()} var z=falso e f(); var t=verdadeiro?7:f()",
            context);
    optimize(p, new CTFEContext);
    assert(cast(CallExpr)(cast(VarDecl) p.body[1]).value); // inicializador com efeito
    assert(cast(BinaryExpr)(cast(VarDecl) p.body[2]).value); // não aplicar x*0
    assert(p.body.length == 5);
    assert(cast(BoolLit)(cast(VarDecl) p.body[3]).value);
    assert((cast(IntLit)(cast(VarDecl) p.body[4]).value).value == 7);
}

unittest
{
    Context context;
    Program p = program("funcao f(x){se x {retorna 1} senao {falhar 'erro'} escreva(99); funcao g(){retorna 2}}",
            context);
    FnDecl fn = cast(FnDecl) p.body[0];
    Diagnostics diagnostics = new Diagnostics;
    new FlowAnalysis(diagnostics).analyze(p);
    assert(diagnostics.entries.any!((const(Diagnostic) d) => d.code == "W3001"));
    optimize(p, new CTFEContext);
    assert(fn.body.length == 2 && cast(FnDecl) fn.body[1]);
}

unittest
{
    Context context;
    Program p = program("funcao f(){tente{retorna 1;escreva(99)}finalmente{escreva(2)}}", context);
    optimize(p, new CTFEContext);
    TryStmt attempt = cast(TryStmt)(cast(FnDecl) p.body[0]).body[0];
    assert(attempt.body.length == 1 && attempt.finalBody.length == 1);
}

unittest
{
    Context context;
    Program p = program(
            "var a=[(1+2) para cada x em [1+2]]; var b=funcao(x=1+2){retorna 2+3}; classe C{f(){retorna 3+4}}", context);
    optimize(p, new CTFEContext);
    Comprehension comprehension = cast(Comprehension)(cast(VarDecl) p.body[0]).value;
    assert((cast(IntLit) comprehension.value).value == 3);
    FunctionExpr lambda = cast(FunctionExpr)(cast(VarDecl) p.body[1]).value;
    assert((cast(IntLit) lambda.declaration.args[0].value).value == 3);
    ClassDecl c = cast(ClassDecl) p.body[2];
    assert((cast(IntLit)(cast(ReturnStmt) c.methods[0].body[0]).val).value == 7);
}

unittest
{
    Context context;
    Program p = program("//>puro\nfuncao soma(x){retorna x+1} var resultado=soma(2)", context);
    Diagnostics diagnostics = new Diagnostics;
    CTFEContext ctfe = new CTFEContext;
    prepareCTFE(ctfe, new PureFunctionAnalysis(diagnostics).analyze(p));
    assert(!diagnostics.hasErrors());
    optimize(p, ctfe);
    assert((cast(IntLit)(cast(VarDecl) p.body[1]).value).value == 3);
}

unittest
{
    Context context;
    Program p = program("funcao soma(x){retorna x+10} var resultado=soma(2)", context);
    FnDecl impostor = new FnDecl("soma", [], new TypeExprNamed("qualquer", null), [], 0, null);
    CTFEContext ctfe = new CTFEContext;
    ctfe.declarations[(cast(FnDecl) p.body[0]).linkName] = impostor;
    // Há nome registrado, mas a identidade não corresponde: não chama a VM.
    optimize(p, ctfe);
    assert(cast(CallExpr)(cast(VarDecl) p.body[1]).value);
}

unittest
{
    import middle.rewrite;

    ModuleUnit unit = new ModuleUnit("modulo.delegua", new Program([new IntLit(1, null)]), null);
    ImportExpr a = new ImportExpr(new StringLit("modulo.delegua", null), null);
    ImportExpr b = new ImportExpr(new StringLit("modulo.delegua", null), null);
    a.target = unit;
    b.target = unit;
    class Counter : AstRewriter
    {
        size_t modules;
        override protected Node transform(Node node)
        {
            if (cast(ModuleUnit) node)
                modules++;
            return node;
        }
    }

    Counter counter = new Counter;
    counter.rewrite(new Program([a, b]));
    assert(counter.modules == 1);
}

unittest
{
    Context context;
    Program p = program("//>puro\nfuncao f(x){se x{retorna 1}senao{retorna 2}} var resultado=f(falso)", context);
    Diagnostics diagnostics = new Diagnostics;
    CTFEContext ctfe = new CTFEContext;
    prepareCTFE(ctfe, new PureFunctionAnalysis(diagnostics).analyze(p));
    optimize(p, ctfe);
    assert((cast(IntLit)(cast(VarDecl) p.body[1]).value).value == 2);
}

unittest
{
    Context context;
    Program p = program("//>puro\nfuncao f(x:inteiro){retorna x+1} var resultado=f(2.5)", context);
    Diagnostics diagnostics = new Diagnostics;
    CTFEContext ctfe = new CTFEContext;
    prepareCTFE(ctfe, new PureFunctionAnalysis(diagnostics).analyze(p));
    optimize(p, ctfe);
    assert(cast(CallExpr)(cast(VarDecl) p.body[1]).value);
}

unittest
{
    Context context;
    Program p = program("//>puro\nfuncao f(x){retorna 1/x} var resultado=f(0)", context);
    Diagnostics diagnostics = new Diagnostics;
    CTFEContext ctfe = new CTFEContext;
    prepareCTFE(ctfe, new PureFunctionAnalysis(diagnostics).analyze(p));
    optimize(p, ctfe);
    assert(cast(CallExpr)(cast(VarDecl) p.body[1]).value);
    assert(ctfe.depth == 0);
}

unittest
{
    Context context;
    Program p = program("//>puro\nfuncao f(g){retorna g()}", context);
    Diagnostics diagnostics = new Diagnostics;
    new PureFunctionAnalysis(diagnostics).analyze(p);
    assert(diagnostics.hasErrors());
}

unittest
{
    Context context;
    Program p = program("//>puro\nfuncao f(x){retorna x} //>puro\nfuncao g(){retorna f(escreva(1))}", context);
    Diagnostics diagnostics = new Diagnostics;
    new PureFunctionAnalysis(diagnostics).analyze(p);
    assert(diagnostics.hasErrors());
}

unittest
{
    Context context;
    Program p = program("funcao g(){retorna 1} //>puro\nfuncao f(){retorna g}", context);
    Diagnostics diagnostics = new Diagnostics;
    new PureFunctionAnalysis(diagnostics).analyze(p);
    assert(diagnostics.hasErrors());
}

unittest
{
    Context context;
    Program p = program(
            "var a = (0xFF & 0x0F) | (1 << 4); var b = 100 \\ 3; var c = 2 ** 10; var x: inteiro = 7; var d = (x + 0) * 1",
            context);
    optimize(p, new CTFEContext);
    assert((cast(IntLit)(cast(VarDecl) p.body[0]).value).value == 31);
    assert((cast(IntLit)(cast(VarDecl) p.body[1]).value).value == 33);
    assert((cast(IntLit)(cast(VarDecl) p.body[2]).value).value == 1024);
    assert(cast(Identifier)(cast(VarDecl) p.body[4]).value);
}
