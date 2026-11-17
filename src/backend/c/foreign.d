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

dstring foreignWrapper(FnDecl method, dstring prototype, dstring descriptor, dstring[] parameterContracts)
{
    dstring checks;
    foreach (size_t index, dstring contract; parameterContracts)
        checks ~= formatD("(void)delegua_assegurar_descr(argv[%s],%s);\n", index, contract);
    if (method.foreignManaged)
        return formatD(
                "extern delegua_value %s(sz,delegua_value*);\n%s { %s return delegua_assegurar_descr(%s(argc,argv),%s); }",
                method.foreignSymbol, prototype, checks, method.foreignSymbol, descriptor);
    dstring[] types, arguments;
    dstring setup;
    foreach (size_t index, FnArg argument; method.args)
    {
        string type = nativeType(argument.type_expr);
        types ~= formatD("%s", type);
        string kind = type == "double" ? "DELEGUA_T_REAL" : type == "int64_t"
            ? "DELEGUA_T_NUM" : type == "bool" ? "DELEGUA_T_BOOL" : "DELEGUA_T_TEXT";
        string field = type == "double" ? "real" : type == "int64_t" ? "num" : type == "bool" ? "b1" : "text.ptr";
        dstring local = formatD("cgd_ffi_arg_%s", index);
        dstring boxed = local ~ "_boxed";
        setup ~= formatD("delegua_value %s=delegua_op_cast(argv[%s],%s);\n", boxed, index, kind);
        if (type == "const char *")
            setup ~= formatD("if(memchr(%s.value.text.ptr,0,%s.value.text.len)) delegua_panic(\"Texto FFI C contém byte nulo.\");\n",
                    boxed, boxed);
        setup ~= formatD("%s %s=%s.value.%s;\n", type, local, boxed, field);
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
