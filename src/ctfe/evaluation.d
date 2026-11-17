module ctfe.evaluation;

import frontend;
import ctfe.context;
import ctfe.compile;
import ctfe.vm.cgd_vm;
import std.math : isFinite;

/// Mesma porta de avaliação para otimização e prévia. Falhas preservam o runtime.
Node evaluatePureCall(CallExpr call, CTFEContext context, size_t budget = 10_000_000)
{
    if (context is null || call is null)
        return null;
    Identifier id = cast(Identifier) call.fn;
    if (id is null || id.functionRef is null)
        return null;
    FnDecl target = id.functionRef;
    FnDecl* declaration = target.linkName in context.declarations;
    if (declaration is null || *declaration !is target || call.args.length != target.args.length)
        return null;
    try
    {
        CGDValue[] arguments;
        foreach (Node argument; call.args)
            arguments ~= CTFECompile.nodeToCgdValue(argument);
        Node result = context.call(target.linkName, arguments, budget);
        if (DoubleLit number = cast(DoubleLit) result)
            if (!isFinite(number.value))
                return null;
        return result;
    }
    catch (Exception)
        return null;
}
