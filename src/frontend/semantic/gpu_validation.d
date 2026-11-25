module frontend.semantic.gpu_validation;

import diagnostics.catalog;
import errors;
import frontend.parser.ast;
import frontend.semantic.value_types;
import frontend.type_sema;

final class GpuValidator
{
private:
    Diagnostics diag;
    bool[Node] visited;

    void validateGpuFn(FnDecl fn)
    {
        if (fn.isAsync)
        {
            diag.errorCode(fn.pos, gpuUnsupportedFeature, "função assíncrona não pode ser kernel @gpu");
            return;
        }
        if (fn.isAbstract)
        {
            diag.errorCode(fn.pos, gpuUnsupportedFeature, "método abstrato não pode ser kernel @gpu");
            return;
        }
        foreach (FnArg arg; fn.args)
        {
            if (arg.type_sema is null || !isStaticNativeLayoutType(arg.type_sema, false))
                diag.errorCode(arg.pos, gpuUnsupportedFeature,
                        "parâmetro de kernel @gpu exige tipo escalar C ou @pilha");
        }
        if (fn.type_sema is null || !isStaticNativeLayoutType(fn.type_sema, true))
            diag.errorCode(fn.pos, gpuUnsupportedFeature,
                    "retorno de kernel @gpu exige tipo escalar C, @pilha ou vazio");
        // Verifica corpo do kernel quanto a chamadas/recursos gerenciados incompatíveis com GPU
        foreach (Node st; fn.body)
            validateGpuBody(st);
        // Kernels @gpu também são compiláveis como código nativo direto sem GC!
        fn.isNative = true;
    }

    void validateGpuBody(Node node)
    {
        if (node is null)
            return;
        if (CallExpr c = cast(CallExpr) node)
        {
            if (Identifier id = cast(Identifier) c.fn)
            {
                if (id.functionRef !is null && !id.functionRef.isNative && !id.functionRef.isGpu)
                    diag.errorCode(c.pos, gpuUnsupportedFeature,
                            "chamada a função gerenciada/IO proibida em kernel @gpu");
            }
        }
        else if (cast(TryStmt) node !is null || cast(ThrowStmt) node !is null
                || cast(MapLit) node !is null || cast(ArrayLit) node !is null)
        {
            diag.errorCode(node.pos, gpuUnsupportedFeature,
                    "exceções e coleções dinâmicas GC são proibidas em kernel @gpu");
        }
        foreach (Node ch; childNodes(node))
            validateGpuBody(ch);
    }

    void visit(Node node)
    {
        if (node is null || node in visited)
            return;
        visited[node] = true;
        if (FnDecl fn = cast(FnDecl) node)
            if (fn.isGpu && !fn.builtinName.length)
                validateGpuFn(fn);
        foreach (Node child; childNodes(node))
            visit(child);
    }

public:
    this(Diagnostics diag)
    {
        this.diag = diag;
    }

    void analyze(Program program)
    {
        visit(program);
    }
}

void validateGpuKernels(Program program, Diagnostics diag)
{
    new GpuValidator(diag).analyze(program);
}
