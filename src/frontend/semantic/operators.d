module frontend.semantic.operators;

import diagnostics.catalog;
import errors;
import frontend.lexer.token : Position, TokenKind;
import frontend.parser.ast;
import frontend.semantic.members;
import frontend.type_sema;
import std.conv : to;

/// Verifica se a string em `@operador("...")` é um operador suportado.
bool isValidOperatorSymbol(dstring sym)
{
    switch (sym)
    {
        case "+":
        case "-":
        case "*":
        case "/":
        case "%":
        case "==":
        case "!=":
        case "<":
        case "<=":
        case ">":
        case ">=":
        case "[]":
        case "[]=":
        case "unario-":
        case "unário-":
        case "unario+":
        case "unário+":
        case "unario!":
        case "unário!":
            return true;
        default:
            return false;
    }
}

/// Normaliza acentuação dos símbolos de operadores unários.
dstring normalizeOperatorSymbol(dstring sym, size_t argCount)
{
    if (sym == "unário-"d)
        return "unario-"d;
    if (sym == "unário+"d)
        return "unario+"d;
    if (sym == "unário!"d)
        return "unario!"d;
    return sym;
}

bool isComparisonOperator(dstring sym)
{
    return sym == "=="d || sym == "!="d || sym == "<"d || sym == "<="d || sym == ">"d || sym == ">="d;
}

bool isCommutativeOperator(dstring sym)
{
    return sym == "+"d || sym == "*"d || sym == "=="d || sym == "!="d;
}

dstring tokenToBinaryOperatorSymbol(TokenKind op)
{
    switch (op)
    {
        case TokenKind.Plus:
            return "+"d;
        case TokenKind.Minus:
            return "-"d;
        case TokenKind.Star:
            return "*"d;
        case TokenKind.Slash:
            return "/"d;
        case TokenKind.Modulo:
            return "%"d;
        case TokenKind.EEquals:
            return "=="d;
        case TokenKind.NEquals:
            return "!="d;
        case TokenKind.LThan:
            return "<"d;
        case TokenKind.LEquals:
            return "<="d;
        case TokenKind.GThan:
            return ">"d;
        case TokenKind.GEquals:
            return ">="d;
        default:
            return ""d;
    }
}

dstring tokenToUnaryOperatorSymbol(TokenKind op)
{
    switch (op)
    {
        case TokenKind.Minus:
            return "unario-"d;
        case TokenKind.Plus:
            return "unario+"d;
        case TokenKind.Bang:
            return "unario!"d;
        default:
            return ""d;
    }
}

/// Valida todas as declarações `@operador(...)` de uma classe.
void validateClassOperators(ClassDecl cls, Diagnostics diag)
{
    if (cls is null)
        return;

    struct OpSig
    {
        dstring symbol;
        dstring argSig;
        FnDecl fn;
    }

    OpSig[] declared;

    foreach (FnDecl method; cls.methods)
    {
        if (!method.operatorSymbol.length)
            continue;
        dstring rawSym = method.operatorSymbol;
        if (!isValidOperatorSymbol(rawSym))
        {
            diag.errorCode(method.pos, invalidOperatorSymbol, rawSym);
            continue;
        }
        dstring sym = normalizeOperatorSymbol(rawSym, method.args.length);
        method.operatorSymbol = sym;

        if (method.isStatic)
        {
            diag.errorCode(method.pos, invalidOperatorSignature, sym, method.fn,
                    "método operador não pode ser estático");
            continue;
        }
        if (method.isAsync)
        {
            diag.errorCode(method.pos, invalidOperatorSignature, sym, method.fn,
                    "método operador não pode ser assíncrono");
            continue;
        }
        if (method.fn == "construtor"d || method.fn == "destrutor"d)
        {
            diag.errorCode(method.pos, invalidOperatorSignature, sym, method.fn,
                    "construtor/destrutor não pode ser @operador");
            continue;
        }

        size_t expectedArity;
        if (sym == "unario-"d || sym == "unario+"d || sym == "unario!"d)
            expectedArity = 0;
        else if (sym == "[]="d)
            expectedArity = 2;
        else
            expectedArity = 1;

        if (method.args.length != expectedArity)
        {
            diag.errorCode(method.pos, invalidOperatorSignature, sym, method.fn,
                    "quantidade de parâmetros incompatível com o operador");
            continue;
        }

        foreach (FnArg arg; method.args)
            if (arg.rest)
                diag.errorCode(method.pos, invalidOperatorSignature, sym, method.fn,
                        "operador não aceita parâmetro variádico");

        if (isComparisonOperator(sym))
        {
            bool boolRet = false;
            if (method.type_sema !is null)
            {
                if (method.type_sema.isBool())
                    boolRet = true;
            }
            if (!boolRet)
            {
                dstring got = method.type_sema is null ? "qualquer"d : method.type_sema.toStr();
                diag.errorCode(method.pos, invalidOperatorReturn, sym, cls.name, got);
            }
        }

        dstring argSig = ""d;
        foreach (size_t i, FnArg arg; method.args)
        {
            if (i > 0)
                argSig ~= ","d;
            argSig ~= arg.type_sema is null ? "qualquer"d : arg.type_sema.toStr();
        }
        foreach (OpSig prev; declared)
        {
            if (prev.symbol == sym && prev.argSig == argSig)
            {
                diag.errorCode(method.pos, ambiguousOrDuplicateOperator, sym,
                        "já definido em '" ~ prev.fn.fn.to!string ~ "' com os mesmos tipos");
                break;
            }
        }
        declared ~= OpSig(sym, argSig, method);
    }
}

/// Verifica visibilidade de um método `@operador` a partir da classe léxica atual.
private bool operatorVisibleFrom(FnDecl method, ClassDecl callerClass)
{
    if (method is null || method.access == 0)
        return true;
    if (callerClass is null)
        return false;
    if (method.access == 1)
        return callerClass is method.ownerClass;
    for (ClassDecl c = callerClass; c !is null; c = c.superClass)
        if (c is method.ownerClass)
            return true;
    return false;
}

/// Busca sobrecargas `@operador` compatíveis em uma classe (respeitando sobrescrita na herança).
FnDecl[] findClassOperators(ClassDecl cls, dstring sym)
{
    FnDecl[] matches;
    bool[dstring] seenSigs;
    for (ClassDecl cur = cls; cur !is null; cur = cur.superClass)
    {
        foreach (FnDecl m; cur.methods)
        {
            if (m.operatorSymbol != sym)
                continue;
            dstring sig = ""d;
            foreach (size_t i, FnArg arg; m.args)
            {
                if (i > 0)
                    sig ~= ","d;
                sig ~= arg.type_sema is null ? "qualquer"d : arg.type_sema.toStr();
            }
            if (sig in seenSigs)
                continue;
            seenSigs[sig] = true;
            matches ~= m;
        }
    }
    return matches;
}

/// Resolve operador binário personalizado entre `leftType` e `rightType`.
/// Retorna o `FnDecl` escolhido (e `swapped = true` se resolvido pelo operando direito em operador comutativo).
FnDecl resolveBinaryOperator(dstring sym, TypeSema leftType, TypeSema rightType,
        ClassDecl callerClass, Position pos, Diagnostics diag, out bool swapped)
{
    swapped = false;
    if (!sym.length || leftType is null || rightType is null)
        return null;

    FnDecl[] exactMatches;
    FnDecl[] compatMatches;

    // 1) Tentar receptor esquerdo (prioritário)
    if (TypeSemaClass leftCls = cast(TypeSemaClass) leftType)
    {
        foreach (FnDecl m; findClassOperators(leftCls.declaration, sym))
        {
            if (m.args.length != 1)
                continue;
            TypeSema paramType = m.args[0].type_sema;
            if (paramType is null)
                continue;
            if (paramType.toStr() == rightType.toStr())
                exactMatches ~= m;
            else if (paramType.isComp(rightType))
                compatMatches ~= m;
        }
    }

    FnDecl[] chosen = exactMatches.length ? exactMatches : compatMatches;
    if (chosen.length == 1)
    {
        if (!operatorVisibleFrom(chosen[0], callerClass))
            diag.errorCode(pos, inaccessibleOperator, sym, chosen[0].ownerClass.name);
        return chosen[0];
    }
    if (chosen.length > 1)
    {
        diag.errorCode(pos, ambiguousOrDuplicateOperator, sym,
                "múltiplas sobrecargas compatíveis encontradas");
        return chosen[0];
    }

    // 2) Se comutativo (+, *, ==, !=) e o esquerdo NÃO é classe com operador, tentar direito
    if (isCommutativeOperator(sym))
    {
        if (TypeSemaClass rightCls = cast(TypeSemaClass) rightType)
        {
            FnDecl[] rExact;
            FnDecl[] rCompat;
            foreach (FnDecl m; findClassOperators(rightCls.declaration, sym))
            {
                if (m.args.length != 1)
                    continue;
                TypeSema paramType = m.args[0].type_sema;
                if (paramType is null)
                    continue;
                if (paramType.toStr() == leftType.toStr())
                    rExact ~= m;
                else if (paramType.isComp(leftType))
                    rCompat ~= m;
            }
            FnDecl[] rChosen = rExact.length ? rExact : rCompat;
            if (rChosen.length == 1)
            {
                if (!operatorVisibleFrom(rChosen[0], callerClass))
                    diag.errorCode(pos, inaccessibleOperator, sym, rChosen[0].ownerClass.name);
                swapped = true;
                return rChosen[0];
            }
            if (rChosen.length > 1)
            {
                diag.errorCode(pos, ambiguousOrDuplicateOperator, sym,
                        "múltiplas sobrecargas comutativas compatíveis encontradas");
                swapped = true;
                return rChosen[0];
            }
        }
    }
    return null;
}

/// Resolve operador unário personalizado (`unario-`, `unario+`, `unario!`).
FnDecl resolveUnaryOperator(dstring sym, TypeSema operandType, ClassDecl callerClass,
        Position pos, Diagnostics diag)
{
    if (!sym.length || operandType is null)
        return null;
    TypeSemaClass cls = cast(TypeSemaClass) operandType;
    if (cls is null)
        return null;
    FnDecl[] matches = findClassOperators(cls.declaration, sym);
    if (!matches.length)
        return null;
    if (matches.length > 1)
        diag.errorCode(pos, ambiguousOrDuplicateOperator, sym, "múltiplos operadores unários");
    if (!operatorVisibleFrom(matches[0], callerClass))
        diag.errorCode(pos, inaccessibleOperator, sym, matches[0].ownerClass.name);
    return matches[0];
}

/// Resolve operador de indexação `[]` ou `[]=`.
FnDecl resolveIndexOperator(dstring sym, TypeSema targetType, TypeSema indexType,
        TypeSema valueType, ClassDecl callerClass, Position pos, Diagnostics diag)
{
    TypeSemaClass cls = cast(TypeSemaClass) targetType;
    if (cls is null)
        return null;
    FnDecl[] exact;
    FnDecl[] compat;
    foreach (FnDecl m; findClassOperators(cls.declaration, sym))
    {
        if (sym == "[]"d && m.args.length == 1)
        {
            TypeSema p0 = m.args[0].type_sema;
            if (p0 !is null && indexType !is null)
            {
                if (p0.toStr() == indexType.toStr())
                    exact ~= m;
                else if (p0.isComp(indexType))
                    compat ~= m;
            }
        }
        else if (sym == "[]="d && m.args.length == 2)
        {
            TypeSema p0 = m.args[0].type_sema;
            TypeSema p1 = m.args[1].type_sema;
            if (p0 !is null && p1 !is null && indexType !is null && valueType !is null)
            {
                if (p0.toStr() == indexType.toStr() && p1.toStr() == valueType.toStr())
                    exact ~= m;
                else if (p0.isComp(indexType) && p1.isComp(valueType))
                    compat ~= m;
            }
        }
    }
    FnDecl[] chosen = exact.length ? exact : compat;
    if (!chosen.length)
        return null;
    if (chosen.length > 1)
        diag.errorCode(pos, ambiguousOrDuplicateOperator, sym, "múltiplas sobrecargas de indexação");
    if (!operatorVisibleFrom(chosen[0], callerClass))
        diag.errorCode(pos, inaccessibleOperator, sym, chosen[0].ownerClass.name);
    return chosen[0];
}
