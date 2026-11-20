module ctfe.evaluation;

import frontend;
import ctfe.context;
import ctfe.compile;
import ctfe.vm.cgd_vm;
import std.math : isFinite;

/// Resolve chamada direta a função livre ou método estático puro sem efeitos no receptor.
FnDecl pureCallTarget(CallExpr call)
{
    if (call is null)
        return null;
    if (Identifier id = cast(Identifier) call.fn)
        return id.functionRef;
    if (MemberExpr member = cast(MemberExpr) call.fn)
    {
        Identifier right = cast(Identifier) member.right;
        if (right is null || right.functionRef is null || !right.functionRef.isStatic)
            return null;
        if (Identifier recv = cast(Identifier) member.left)
        {
            if (recv.classRef !is null)
                return right.functionRef;
            if (recv.variableRef !is null && recv.variableRef.isConst)
                if (MemberExpr initMember = cast(MemberExpr) recv.variableRef.value)
                    if (Identifier initRight = cast(Identifier) initMember.right)
                        if (initRight.classRef !is null)
                            return right.functionRef;
            if (recv.variableRef !is null)
                if (ImportExpr varImport = cast(ImportExpr) recv.variableRef.value)
                    if (varImport.target !is null)
                        return right.functionRef;
        }
        if (MemberExpr leftMember = cast(MemberExpr) member.left)
            if (Identifier leftRight = cast(Identifier) leftMember.right)
                if (leftRight.classRef !is null)
                    if (Identifier modId = cast(Identifier) leftMember.left)
                        if (modId.variableRef !is null && cast(ImportExpr) modId.variableRef.value !is null)
                            return right.functionRef;
    }
    return null;
}

/// Mesma porta de avaliação para otimização e prévia. Falhas preservam o runtime.
Node evaluatePureCall(CallExpr call, CTFEContext context, size_t budget = 10_000_000)
{
    if (context is null || call is null)
        return null;
    FnDecl target = pureCallTarget(call);
    if (target is null)
        return null;
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
