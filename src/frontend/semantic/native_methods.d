module frontend.semantic.native_methods;

import frontend;
import std.algorithm : canFind, endsWith;
import std.array : split;
import std.conv : to;

/// Metadados de ferramentas: nomes permitidos devem coincidir com method_allowed no runtime.
string[] builtinMethods(TypeSema receiver)
{
    if (receiver is null)
        return [];
    string[] names = ["tipo", "paraTexto", "eInstanciaDe", "éInstânciaDe", "respondeA"];
    if (cast(TypeSemaPromise) receiver || cast(TypeSemaTask) receiver)
        return names ~ ["entao", "capturar", "cancelar", "concluida", "cancelada"];
    if (receiver.isArray())
        return names ~ [
        "adicionar", "empilhar", "tamanho", "inclui", "contem", "contém", "fatiar", "mapear",
        "filtrarPor", "remover", "removerPrimeiro", "removerUltimo", "inverter", "somar",
        "juntar", "concatenar", "encaixar", "ordenar", "limpar"
    ];
    if (TypeSemaBuiltin type = cast(TypeSemaBuiltin) receiver)
    {
        if (type.base == TypeSemaBase.String)
            return names ~ [
            "tamanho", "inclui", "contem", "contém", "fatiar", "subtexto", "aparar",
            "apararInicio", "apararFim", "maiusculo",
            "minusculo", "tudoMaiusculo", "tudoMinusculo", "encontrar", "dividir", "substituir",
            "concatenar"
        ];
        if (type.isNumeric())
            return names ~ ["absoluto", "arredondarParaBaixo", "arredondarParaCima", "formatar"];
        if (type.base == TypeSemaBase.Map)
            return names ~ [
            "chaves", "valores", "tamanho", "remover", "inclui", "contem", "contém", "obter",
            "definir", "contemChave", "itens", "limpar"
        ];
        if (type.base == TypeSemaBase.Tuple)
            return names ~ ["tamanho", "inclui", "contem", "contém", "fatiar"];
    }
    return names;
}

FnDecl builtinMethod(TypeSema receiver, string name)
{
    if (receiver is null)
        return null;
    if (cast(TypeSemaPromise) receiver || cast(TypeSemaTask) receiver)
    {
        if (name == "cancelar" || name == "concluida" || name == "cancelada")
        {
            FnDecl method = new FnDecl(name.to!dstring, [], new TypeExprNamed("logico", null), [], 0, null);
            method.type_sema = new TypeSemaBuiltin(TypeSemaBase.Bool);
            return method;
        }
        if (name != "entao" && name != "capturar")
            return builtinMethod(new TypeSemaBuiltin(TypeSemaBase.Any), name);
        FnArg callback = new FnArg("callback", new TypeExprNamed("funcao", null), null, null);
        FnDecl method = new FnDecl(name.to!dstring, [callback],
                new TypeExprPromise(new TypeExprNamed("qualquer", null), null), [], 0, null);
        method.type_sema = new TypeSemaPromise(new TypeSemaBuiltin(TypeSemaBase.Any));
        return method;
    }
    string family = receiver.isArray() ? "vetor" : "objeto";
    if (TypeSemaBuiltin type = cast(TypeSemaBuiltin) receiver)
        family = type.base.to!string;
    string key = family ~ "." ~ name;
    static FnDecl[string] cache;
    if (FnDecl* cached = key in cache)
        return *cached;
    if (!builtinMethods(receiver).canFind(name))
        return null;
    string[] parameters;
    string result = "qualquer";
    switch (name)
    {
        case "obter":
            parameters = ["chave:qualquer", "padrao:qualquer?"];
            break;
        case "definir":
            parameters = ["chave:qualquer", "valor:qualquer"];
            break;
        case "contemChave":
            parameters = ["chave:qualquer"];
            result = "logico";
            break;
        case "itens":
            result = "qualquer[]";
            break;
        case "limpar":
            result = receiver.isArray() ? "qualquer[]" : "dicionario";
            break;
        case "tipo":
        case "paraTexto":
            result = "texto";
            break;
        case "eInstanciaDe":
        case "éInstânciaDe":
            parameters = ["classe:qualquer"];
            result = "logico";
            break;
        case "respondeA":
            parameters = ["nome:texto"];
            result = "logico";
            break;
        case "tamanho":
            result = "inteiro";
            break;
        case "inclui":
        case "contem":
        case "contém":
            parameters = ["valor:qualquer"];
            result = "logico";
            break;
        case "fatiar":
        case "subtexto":
            parameters = ["inicio:inteiro", "fim:qualquer?"];
            result = receiver.toStr() == "texto" ? "texto" : receiver.toStr() == "tupla" ? "tupla" : "qualquer[]";
            break;
        case "mapear":
        case "filtrarPor":
            parameters = ["funcao:funcao"];
            result = "qualquer[]";
            break;
        case "adicionar":
        case "empilhar":
        case "remover":
            parameters = ["valor:qualquer"];
            break;
        case "chaves":
        case "valores":
        case "inverter":
            result = "qualquer[]";
            break;
        case "aparar":
        case "apararInicio":
        case "apararFim":
        case "maiusculo":
        case "minusculo":
            result = "texto";
            break;
        case "tudoMaiusculo":
        case "tudoMinusculo":
            result = "logico";
            break;
        case "encontrar":
            parameters = ["valor:texto"];
            result = "inteiro";
            break;
        case "dividir":
            parameters = ["separador:texto"];
            result = "texto[]";
            break;
        case "substituir":
            parameters = ["alvo:texto", "substituto:texto"];
            result = "texto";
            break;
        case "absoluto":
            result = receiver.toStr().to!string;
            break;
        case "arredondarParaBaixo":
        case "arredondarParaCima":
            result = "inteiro";
            break;
        case "formatar":
            parameters = ["opcoes:qualquer?"];
            result = "texto";
            break;
        case "juntar":
            parameters = ["separador:texto?"];
            result = "texto";
            break;
        case "concatenar":
            parameters = ["...valores:qualquer"];
            result = receiver.toStr() == "texto" ? "texto" : "qualquer[]";
            break;
        case "encaixar":
            parameters = ["inicio:inteiro", "quantidade:qualquer?", "...valores:qualquer"];
            result = "qualquer[]";
            break;
        case "ordenar":
            parameters = ["comparador:qualquer?"];
            result = "qualquer[]";
            break;
        default:
            break;
    }
    TypeExpr typeExpr(string type)
    {
        if (type.endsWith("[]"))
            return new TypeExprArray(new TypeExprNamed(type[0 .. $ - 2].to!dstring, null), null);
        return new TypeExprNamed(type.to!dstring, null);
    }

    FnArg[] arguments;
    foreach (string parameter; parameters)
    {
        string[] parts = parameter.split(":");
        bool rest = parts[0].length > 3 && parts[0][0 .. 3] == "...";
        bool optional = parts[1].endsWith("?");
        FnArg argument = new FnArg((rest ? parts[0][3 .. $] : parts[0]).to!dstring,
                typeExpr(optional ? parts[1][0 .. $ - 1] : parts[1]), optional ? new NullLit(null) : null, null);
        argument.rest = rest;
        arguments ~= argument;
    }
    FnDecl declaration = new FnDecl(name.to!dstring, arguments, typeExpr(result), [], 0, null);
    TypeSema semanticType(string type)
    {
        if (type.endsWith("[]"))
            return new TypeSemaArray(semanticType(type[0 .. $ - 2]));
        switch (type)
        {
            case "texto":
                return new TypeSemaBuiltin(TypeSemaBase.String);
            case "inteiro":
            case "numero":
                return new TypeSemaBuiltin(TypeSemaBase.Int);
            case "real":
                return new TypeSemaBuiltin(TypeSemaBase.Double);
            case "dicionario":
                return new TypeSemaBuiltin(TypeSemaBase.Map);
            case "tupla":
                return new TypeSemaBuiltin(TypeSemaBase.Tuple);
            case "logico":
                return new TypeSemaBuiltin(TypeSemaBase.Bool);
            default:
                return new TypeSemaBuiltin(TypeSemaBase.Any);
        }
    }

    declaration.type_sema = semanticType(result);
    cache[key] = declaration;
    return declaration;
}

unittest
{
    TypeSema text = new TypeSemaBuiltin(TypeSemaBase.String);
    TypeSema vector = new TypeSemaArray(new TypeSemaBuiltin(TypeSemaBase.Any));
    assert(builtinMethods(vector).canFind("adicionar"));
    assert(!builtinMethods(text).canFind("adicionar"));
    assert(builtinMethod(text, "substituir").args.length == 2);
    assert(builtinMethod(text, "substituir") is builtinMethod(text, "substituir"));
    assert(builtinMethod(text, "dividir").type_sema.isArray());
}
