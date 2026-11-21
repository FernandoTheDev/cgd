module backend.c.foreign;

import frontend;
import backend.c.utils;
import std.array : join;

string nativeType(TypeExpr type)
{
    switch (type.toStr())
    {
        case "inteiro":
        case "longo":
            return "int64_t";
        case "logico":
        case "lógico":
            return "bool";
        case "texto":
            return "const char *";
        case "vazio":
            return "void";
        default:
            return "double";
    }
}

private dstring fastCheckHelper(TypeExpr type)
{
    if (type is null)
        return null;
    switch (type.toStr())
    {
        case "inteiro":
        case "longo":
            return "delegua_assegurar_inteiro_em"d;
        case "numero":
        case "número":
            return "delegua_assegurar_numero_em"d;
        case "real":
        case "decimal":
            return "delegua_assegurar_real_em"d;
        case "texto":
            return "delegua_assegurar_texto_em"d;
        case "logico":
        case "lógico":
        case "booleano":
        case "binario":
        case "binário":
            return "delegua_assegurar_logico_em"d;
        case "dicionario":
        case "dicionário":
            return "delegua_assegurar_dicionario_em"d;
        case "funcao":
        case "função":
            return "delegua_assegurar_funcao_em"d;
        case "tupla":
            return "delegua_assegurar_tupla_simples_em"d;
        case "vazio":
        case "nulo":
            return "delegua_assegurar_vazio_em"d;
        default:
            return null;
    }
}

dstring foreignWrapper(FnDecl method, dstring prototype, dstring descriptor, dstring[] parameterContracts)
{
    dstring checks;
    foreach (size_t index, dstring contract; parameterContracts)
        if (method.args[index].type_expr !is null && method.args[index].type_expr.toStr() != "qualquer")
        {
            dstring helper = fastCheckHelper(method.args[index].type_expr);
            checks ~= helper.length
                ? formatD("(void)%s(argv[%s],NULL);\n", helper, index)
                : formatD("(void)delegua_assegurar_descr(argv[%s],%s);\n", index, contract);
        }
    if (method.foreignManaged)
    {
        bool anyReturn = method.type_expr is null || method.type_expr.toStr() == "qualquer";
        dstring call = formatD("%s(argc,argv)", method.foreignSymbol);
        dstring retHelper = anyReturn ? null : fastCheckHelper(method.type_expr);
        dstring retExpr = anyReturn ? call
            : (retHelper.length ? formatD("%s(%s,NULL)", retHelper, call)
            : formatD("delegua_assegurar_descr(%s,%s)", call, descriptor));
        return formatD("extern delegua_value %s(sz,delegua_value*);\n%s { %s return %s; }", method.foreignSymbol,
                prototype, checks, retExpr);
    }
    dstring[] types, arguments;
    dstring setup;
    bool isPosixExit = method.foreignSymbol == "_exit" && method.args.length == 1
        && method.type_expr !is null && method.type_expr.toStr() == "vazio";
    foreach (size_t index, FnArg argument; method.args)
    {
        string type = isPosixExit ? "int" : nativeType(argument.type_expr);
        types ~= formatD("%s", type);
        string kind = type == "double" ? "DELEGUA_T_REAL" : (type == "int64_t" || type == "int")
            ? "DELEGUA_T_NUM" : type == "bool" ? "DELEGUA_T_BOOL" : "DELEGUA_T_TEXT";
        string field = type == "double" ? "real" : (type == "int64_t" || type == "int")
            ? "num" : type == "bool" ? "b1" : "text.ptr";
        dstring local = formatD("cgd_ffi_arg_%s", index);
        dstring boxed = local ~ "_boxed";
        setup ~= formatD("delegua_value %s=delegua_op_cast(argv[%s],%s);\n", boxed, index, kind);
        if (type == "const char *")
            setup ~= formatD("if(memchr(%s.value.text.ptr,0,%s.value.text.len)) delegua_panic(\"Texto FFI C contém byte nulo.\");\n",
                    boxed, boxed);
        setup ~= formatD("%s %s=%s%s.value.%s;\n", type, local, type == "int" ? "(int)" : "", boxed, field);
        arguments ~= local;
    }
    string resultType = nativeType(method.type_expr);
    dstring call = method.foreignSymbol ~ "(" ~ arguments.join(",") ~ ")";
    dstring result = resultType == "void" ? call ~ "; return create_nulo();" : "return "d ~ (resultType == "double"
            ? "create_real("d : resultType == "int64_t"
            ? "create_num("d : resultType == "bool" ? "create_bool("d : "create_text("d) ~ call ~ ");";
    return formatD("extern %s %s(%s);\n%s { (void)argc; (void)argv; %s }", resultType,
            method.foreignSymbol, types.length ? types.join(",") : "void", prototype, checks ~ setup ~ result);
}
