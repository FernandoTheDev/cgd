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
        case "ci64":
            return "int64_t";
        case "cu64":
            return "uint64_t";
        case "ci32":
            return "int32_t";
        case "cu32":
            return "uint32_t";
        case "ci16":
            return "int16_t";
        case "cu16":
            return "uint16_t";
        case "ci8":
            return "int8_t";
        case "cu8":
            return "uint8_t";
        case "cchar":
            return "char";
        case "cschar":
            return "signed char";
        case "cuchar":
            return "unsigned char";
        case "cshort":
            return "short";
        case "cushort":
            return "unsigned short";
        case "cint":
            return "int";
        case "cuint":
            return "unsigned int";
        case "clong":
            return "long";
        case "culong":
            return "unsigned long";
        case "csize":
            return "size_t";
        case "cf32":
        case "cfloat":
            return "float";
        case "cf64":
        case "cdouble":
            return "double";
        case "logico":
        case "lógico":
        case "cbool":
            return "bool";
        case "texto":
            return "const char *";
        case "cponteiro":
            return "void *";
        case "vazio":
            return "void";
        default:
            return "double";
    }
}

bool isCIntegerTypeName(string t)
{
    return t == "int8_t" || t == "uint8_t" || t == "int16_t" || t == "uint16_t"
        || t == "int32_t" || t == "uint32_t" || t == "int64_t" || t == "uint64_t"
        || t == "short" || t == "unsigned short" || t == "int" || t == "unsigned int"
        || t == "long" || t == "unsigned long" || t == "size_t";
}

bool isCFloatTypeName(string t)
{
    return t == "float" || t == "double";
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

private bool isStdHeaderSymbol(dstring sym)
{
    switch (sym)
    {
        case "fopen":
        case "fclose":
        case "fseek":
        case "ftell":
        case "fgetc":
        case "fputc":
        case "fflush":
        case "fread":
        case "fwrite":
        case "ferror":
        case "feof":
        case "clearerr":
        case "rewind":
        case "remove":
        case "rename":
        case "malloc":
        case "calloc":
        case "realloc":
        case "free":
        case "memcpy":
        case "memmove":
        case "memset":
        case "memcmp":
        case "strlen":
        case "strcmp":
        case "strncmp":
            return true;
        default:
            return false;
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
    bool skipExtern = method.foreignDeclared || isStdHeaderSymbol(method.foreignSymbol);
    bool isPosixExit = method.foreignSymbol == "_exit" && method.args.length == 1
        && method.type_expr !is null && method.type_expr.toStr() == "vazio";
    foreach (size_t index, FnArg argument; method.args)
    {
        string type = isPosixExit ? "int" : nativeType(argument.type_expr);
        types ~= formatD("%s", type);
        bool isPtr = type == "void *";
        bool isInt = isCIntegerTypeName(type);
        bool isFlt = isCFloatTypeName(type);
        string kind = isFlt ? "DELEGUA_T_REAL" : (isInt || isPtr) ? "DELEGUA_T_NUM" : type == "bool"
            ? "DELEGUA_T_BOOL" : "DELEGUA_T_TEXT";
        string field = isFlt ? "real" : (isInt || isPtr) ? "num" : type == "bool" ? "b1" : "text.ptr";
        dstring local = formatD("cgd_ffi_arg_%s", index);
        dstring boxed = local ~ "_boxed";
        setup ~= formatD("delegua_value %s=delegua_op_cast(argv[%s],%s);\n", boxed, index, kind);
        if (type == "const char *")
            setup ~= formatD("if(memchr(%s.value.text.ptr,0,%s.value.text.len)) delegua_panic(\"Texto FFI C contém byte nulo.\");\n",
                    boxed, boxed);
        if (isPtr)
            setup ~= formatD("void *%s=(void *)(intptr_t)(%s.value.num);\n", local, boxed);
        else
            setup ~= formatD("%s %s=(%s)(%s.value.%s);\n", type, local, type, boxed, field);
        arguments ~= local;
    }
    string resultType = nativeType(method.type_expr);
    dstring call = method.foreignSymbol ~ "(" ~ arguments.join(",") ~ ")";
    dstring result;
    if (resultType == "void")
        result = call ~ "; return create_nulo();"d;
    else if (resultType == "void *")
        result = formatD("return create_num((int64_t)(intptr_t)(const void *)(%s));", call);
    else if (isCFloatTypeName(resultType))
        result = formatD("return create_real((double)(%s));", call);
    else if (isCIntegerTypeName(resultType))
        result = formatD("return create_num((int64_t)(%s));", call);
    else if (resultType == "bool")
        result = formatD("return create_bool(%s);", call);
    else
        result = formatD("return create_text(%s);", call);
    if (skipExtern)
        return formatD("%s { (void)argc; (void)argv; %s }", prototype, checks ~ setup ~ result);
    return formatD("extern %s %s(%s);\n%s { (void)argc; (void)argv; %s }", resultType,
            method.foreignSymbol, types.length ? types.join(",") : "void", prototype, checks ~ setup ~ result);
}
