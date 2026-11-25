module backend.c.native_codegen;

import backend.c.utils;
import frontend.lexer.token : TokenKind;
import frontend.parser.ast;
import frontend.semantic.native_validation : isNativeCastName, isNativeMathIntrinsic;
import frontend.semantic.ownership : OwnershipInfo, ParamMode;
import frontend.semantic.value_types : hasOwnershipResource, isStaticNativeLayoutType;
import frontend.type_expr;
import frontend.type_sema;
import std.array : join;
import std.conv : to;
import std.format : format;
import std.math : isFinite;

/// Gerador C99 direto para funções `@nativo`, tipos por valor `@pilha`,
/// operadores nativos, RAII automático e containers nativos especializados.
final class NativeCodegen
{
public:
    bool emitDebugLines = false;

private:
    size_t tmpId;
    dstring[] typeDecls;
    dstring[] protoDecls;
    dstring[] fnDefs;
    bool[string] emittedContainers;
    bool[ClassDecl] emittedValueStructs;
    bool[ClassDecl] emittedValueMethods;
    bool[FnDecl] emittedNativeFns;
    bool emittedMathInclude;
    bool emittedStringNativa;
    bool emittedVisaoTexto;

    struct ScopeDrop
    {
        dstring cVar;
        dstring dropFn;
        dstring cType;
    }

    struct LoopContext
    {
        size_t bodyDropDepth;
        dstring continueLabel;
        bool hasContinueTarget;
        bool usedContinue;
    }

    ScopeDrop[][] dropScopes;
    LoopContext[] loopStack;
    FnDecl currentFn;
    ClassDecl currentValueClass;
    OwnershipInfo ownership;

    dstring freshTmp(string prefix = "cgd_nt")
    {
        return formatD("%s_%s", prefix, tmpId++);
    }

    void pushDropScope()
    {
        dropScopes ~= cast(ScopeDrop[]) null;
    }

    dstring emitDropsFrom(size_t fromDepth, dstring skipVar = ""d)
    {
        dstring[] lines;
        for (size_t d = dropScopes.length; d > fromDepth; d--)
        {
            ScopeDrop[] sc = dropScopes[d - 1];
            foreach_reverse (ScopeDrop sd; sc)
            {
                if (skipVar.length && sd.cVar == skipVar)
                    continue;
                lines ~= formatD("%s(&%s);", sd.dropFn, sd.cVar);
            }
        }
        return lines.join("\n");
    }

    void popDropScope()
    {
        if (dropScopes.length > 0)
            dropScopes.length--;
    }

    void registerDrop(dstring cVar, TypeSema type)
    {
        if (!dropScopes.length || type is null || !hasOwnershipResource(type))
            return;
        dstring dropFn = dropFnForType(type);
        if (!dropFn.length)
            return;
        dropScopes[$ - 1] ~= ScopeDrop(cVar, dropFn, cTypeFor(type));
    }

    string typeMangleKey(TypeSema t)
    {
        if (t is null)
            return "i64";
        if (TypeSemaNative nat = cast(TypeSemaNative) t)
            return nat.name.to!string;
        if (TypeSemaBuiltin b = cast(TypeSemaBuiltin) t)
        {
            if (b.base == TypeSemaBase.Int)
                return "i64";
            if (b.base == TypeSemaBase.Double)
                return "f64";
            if (b.base == TypeSemaBase.Bool)
                return "bool";
            if (b.base == TypeSemaBase.Void)
                return "void";
            return "dv";
        }
        if (TypeSemaClass cls = cast(TypeSemaClass) t)
        {
            if (cls.declaration !is null && cls.declaration.isValueType)
                return "v_" ~ cName(cls.declaration.signature.linkName).to!string;
            return "dv";
        }
        if (TypeSemaNativeContainer nc = cast(TypeSemaNativeContainer) t)
        {
            string base;
            final switch (nc.containerKind)
            {
                case NativeContainerKind.VetorNativo:
                    base = "vec";
                    break;
                case NativeContainerKind.MapaNativo:
                    base = "map";
                    break;
                case NativeContainerKind.FatiaNativa:
                    base = "slc";
                    break;
                case NativeContainerKind.StringNativa:
                    return "nstr";
                case NativeContainerKind.VisaoTexto:
                    return "sv";
                case NativeContainerKind.ResultadoNativo:
                    base = "res";
                    break;
                case NativeContainerKind.OpcionalNativo:
                    base = "opt";
                    break;
                case NativeContainerKind.MatrizNativa:
                    base = "mat";
                    break;
            }
            foreach (TypeSema ta; nc.typeArgs)
                base ~= "_" ~ typeMangleKey(ta);
            return base;
        }
        return "dv";
    }

    void ensureVisaoTexto()
    {
        if (emittedVisaoTexto)
            return;
        emittedVisaoTexto = true;
        typeDecls ~= q{
typedef struct cgd_sv {
    const char *ptr;
    size_t len;
} cgd_sv;
static inline size_t cgd_sv_tamanho(cgd_sv s) { return s.len; }
static inline bool cgd_sv_vazia(cgd_sv s) { return s.len == 0; }
static inline bool cgd_sv_igual(cgd_sv a, cgd_sv b) {
    return a.len == b.len && (a.len == 0 || memcmp(a.ptr, b.ptr, a.len) == 0);
}
static inline bool cgd_sv_igual_cstr(cgd_sv a, const char *b) {
    size_t bl = strlen(b);
    return a.len == bl && (bl == 0 || memcmp(a.ptr, b, bl) == 0);
}
static inline bool cgd_sv_comeca_com(cgd_sv a, const char *p) {
    size_t pl = strlen(p);
    return a.len >= pl && (pl == 0 || memcmp(a.ptr, p, pl) == 0);
}
static inline delegua_value cgd_sv_para_texto(cgd_sv s) {
    return create_text_len(s.ptr ? s.ptr : "", s.len);
}
}d;
    }

    void ensureStringNativa()
    {
        if (emittedStringNativa)
            return;
        emittedStringNativa = true;
        ensureVisaoTexto();
        typeDecls ~= q{
typedef struct cgd_nstr {
    char *ptr;
    size_t len;
    size_t cap;
} cgd_nstr;
static inline cgd_nstr cgd_nstr_vazia(void) {
    cgd_nstr s = {NULL, 0, 0};
    return s;
}
static inline cgd_nstr cgd_nstr_criar_len(const char *src, size_t len) {
    cgd_nstr s = {NULL, 0, 0};
    size_t cap = len + 1;
    char *buf = (char *)malloc(cap);
    if (!buf) delegua_panic("StringNativa: falta de memória.");
    if (len > 0 && src) memcpy(buf, src, len);
    buf[len] = '\0';
    s.ptr = buf;
    s.len = len;
    s.cap = cap;
    return s;
}
static inline cgd_nstr cgd_nstr_criar(const char *src) {
    return cgd_nstr_criar_len(src ? src : "", src ? strlen(src) : 0);
}
static inline cgd_nstr cgd_nstr_criar_dv(delegua_value v) {
    delegua_value tv = delegua_op_cast(v, DELEGUA_T_TEXT);
    return cgd_nstr_criar_len(tv.value.text.ptr, tv.value.text.len);
}
static inline void cgd_nstr_drop(cgd_nstr *s) {
    if (s && s->ptr) {
        free(s->ptr);
        s->ptr = NULL;
        s->len = 0;
        s->cap = 0;
    }
}
static inline void cgd_nstr_limpar(cgd_nstr *s) {
    if (s && s->ptr) {
        s->len = 0;
        s->ptr[0] = '\0';
    }
}
static inline void cgd_nstr_anexar_len(cgd_nstr *s, const char *src, size_t extra) {
    if (!s || extra == 0) return;
    if (extra > SIZE_MAX - s->len - 1) delegua_panic("StringNativa: overflow de tamanho.");
    size_t need = s->len + extra + 1;
    if (need > s->cap) {
        size_t new_cap = s->cap ? s->cap * 2 : 16;
        while (new_cap < need) {
            if (new_cap > SIZE_MAX / 2) { new_cap = need; break; }
            new_cap *= 2;
        }
        char *nb = (char *)realloc(s->ptr, new_cap);
        if (!nb) delegua_panic("StringNativa: falha ao realocar.");
        s->ptr = nb;
        s->cap = new_cap;
    }
    memcpy(s->ptr + s->len, src, extra);
    s->len += extra;
    s->ptr[s->len] = '\0';
}
static inline void cgd_nstr_anexar_cstr(cgd_nstr *s, const char *src) {
    if (src) cgd_nstr_anexar_len(s, src, strlen(src));
}
static inline void cgd_nstr_anexar_nstr(cgd_nstr *s, const cgd_nstr *o) {
    if (o && o->ptr) cgd_nstr_anexar_len(s, o->ptr, o->len);
}
static inline cgd_sv cgd_nstr_visao(const cgd_nstr *s) {
    cgd_sv v = {s && s->ptr ? s->ptr : "", s ? s->len : 0};
    return v;
}
static inline cgd_nstr cgd_nstr_clonar(const cgd_nstr *s) {
    return cgd_nstr_criar_len(s && s->ptr ? s->ptr : "", s ? s->len : 0);
}
static inline bool cgd_nstr_igual_cstr(const cgd_nstr *a, const char *b) {
    size_t bl = b ? strlen(b) : 0;
    size_t al = a ? a->len : 0;
    return al == bl && (al == 0 || memcmp(a->ptr, b, al) == 0);
}
static inline bool cgd_nstr_igual_nstr(const cgd_nstr *a, const cgd_nstr *b) {
    size_t al = a ? a->len : 0;
    size_t bl = b ? b->len : 0;
    return al == bl && (al == 0 || memcmp(a->ptr, b->ptr, al) == 0);
}
static inline delegua_value cgd_nstr_para_texto(const cgd_nstr *s) {
    return create_text_len(s && s->ptr ? s->ptr : "", s ? s->len : 0);
}
static inline delegua_value cgd_nstr_box_and_drop(cgd_nstr s) {
    delegua_value dv = cgd_nstr_para_texto(&s);
    cgd_nstr_drop(&s);
    return dv;
}
static inline uint64_t cgd_hash_bytes(const void *data, size_t len) {
    const uint8_t *p = (const uint8_t *)data;
    uint64_t h = UINT64_C(14695981039346656037);
    for (size_t i = 0; i < len; i++) {
        h ^= (uint64_t)p[i];
        h *= UINT64_C(1099511628211);
    }
    return h;
}
}d;
    }

    void ensureContainer(TypeSemaNativeContainer nc)
    {
        if (nc is null)
            return;
        if (nc.containerKind == NativeContainerKind.StringNativa)
        {
            ensureStringNativa();
            return;
        }
        if (nc.containerKind == NativeContainerKind.VisaoTexto)
        {
            ensureVisaoTexto();
            return;
        }
        foreach (TypeSema ta; nc.typeArgs)
        {
            if (TypeSemaClass cls = cast(TypeSemaClass) ta)
                if (cls.declaration !is null && cls.declaration.isValueType)
                    ensureValueStruct(cls.declaration);
            if (TypeSemaNativeContainer sub = cast(TypeSemaNativeContainer) ta)
                ensureContainer(sub);
        }

        string key = typeMangleKey(nc);
        if (key in emittedContainers)
            return;
        emittedContainers[key] = true;

        final switch (nc.containerKind)
        {
            case NativeContainerKind.StringNativa:
            case NativeContainerKind.VisaoTexto:
                return;
            case NativeContainerKind.FatiaNativa:
            {
                dstring elemT = cTypeFor(nc.typeArgs[0]);
                dstring name = "cgd_"d ~ key.to!dstring;
                typeDecls ~= formatD(
                    "typedef struct %s { const %s *data; size_t len; } %s;\n"
                    ~ "static inline size_t %s_tamanho(%s s) { return s.len; }\n"
                    ~ "static inline bool %s_vazio(%s s) { return s.len == 0; }\n"
                    ~ "static inline %s %s_obter(%s s, size_t idx) {\n"
                    ~ "    if (idx >= s.len) delegua_panic(\"FatiaNativa: índice fora dos limites.\");\n"
                    ~ "    return s.data[idx];\n"
                    ~ "}\n"
                    ~ "static inline %s %s_fatia(%s s, size_t ini, size_t fim) {\n"
                    ~ "    if (ini > fim || fim > s.len) delegua_panic(\"FatiaNativa: intervalo inválido.\");\n"
                    ~ "    %s r = { s.data + ini, fim - ini }; return r;\n"
                    ~ "}\n",
                    name, elemT, name,
                    name, name,
                    name, name,
                    elemT, name, name,
                    name, name, name, name);
                return;
            }
            case NativeContainerKind.VetorNativo:
            {
                TypeSema elemSema = nc.typeArgs[0];
                dstring elemT = cTypeFor(elemSema);
                dstring name = "cgd_"d ~ key.to!dstring;
                TypeSemaNativeContainer sliceType = new TypeSemaNativeContainer(
                        NativeContainerKind.FatiaNativa, [elemSema]);
                ensureContainer(sliceType);
                dstring sliceName = "cgd_"d ~ typeMangleKey(sliceType).to!dstring;
                dstring elemDrop = hasOwnershipResource(elemSema) ? dropFnForType(elemSema) : ""d;
                dstring elemDropLoop = elemDrop.length
                    ? formatD("    for (size_t i = 0; i < v->len; i++) %s(&v->data[i]);\n", elemDrop)
                    : ""d;
                dstring cloneBody;
                if (elemDrop.length)
                {
                    if (TypeSemaNativeContainer enc = cast(TypeSemaNativeContainer) elemSema)
                    {
                        dstring ec = enc.containerKind == NativeContainerKind.StringNativa
                            ? "cgd_nstr_clonar"d : ("cgd_"d ~ typeMangleKey(enc).to!dstring ~ "_clonar"d);
                        cloneBody = formatD(
                            "    for (size_t i = 0; i < v->len; i++) r.data[i] = %s(&v->data[i]);\n", ec);
                    }
                    else
                    {
                        cloneBody = "    delegua_panic(\"VetorNativo: elemento proprietário não clonável.\");\n"d;
                    }
                }
                else
                {
                    cloneBody = formatD("    if (v->len > 0) memcpy(r.data, v->data, v->len * sizeof(%s));\n", elemT);
                }

                dstring boxElem = boxValueExpr(elemSema, "v->data[i]"d);
                dstring unboxElem = unboxValueExpr(elemSema, "delegua_obter(dv, create_num((int64_t)i))"d);
                typeDecls ~= formatD(
                    "typedef struct %s { %s *data; size_t len; size_t cap; } %s;\n"
                    ~ "static inline %s %s_novo(void) { %s v = {NULL, 0, 0}; return v; }\n"
                    ~ "static inline void %s_drop(%s *v) {\n"
                    ~ "    if (!v || !v->data) return;\n"
                    ~ "%s"
                    ~ "    free(v->data); v->data = NULL; v->len = 0; v->cap = 0;\n"
                    ~ "}\n"
                    ~ "static inline void %s_reservar(%s *v, size_t n) {\n"
                    ~ "    if (n <= v->cap) return;\n"
                    ~ "    if (n > SIZE_MAX / sizeof(%s)) delegua_panic(\"VetorNativo: overflow de capacidade.\");\n"
                    ~ "    %s *nd = (%s *)realloc(v->data, n * sizeof(%s));\n"
                    ~ "    if (!nd) delegua_panic(\"VetorNativo: falha de alocação.\");\n"
                    ~ "    v->data = nd; v->cap = n;\n"
                    ~ "}\n"
                    ~ "static inline void %s_adicionar(%s *v, %s val) {\n"
                    ~ "    if (v->len == v->cap) {\n"
                    ~ "        size_t nc = v->cap ? v->cap * 2 : 8;\n"
                    ~ "        if (nc < v->cap || nc > SIZE_MAX / sizeof(%s)) delegua_panic(\"VetorNativo: overflow.\");\n"
                    ~ "        %s_reservar(v, nc);\n"
                    ~ "    }\n"
                    ~ "    v->data[v->len++] = val;\n"
                    ~ "}\n"
                    ~ "static inline %s %s_obter(const %s *v, size_t idx) {\n"
                    ~ "    if (idx >= v->len) delegua_panic(\"VetorNativo: índice fora dos limites.\");\n"
                    ~ "    return v->data[idx];\n"
                    ~ "}\n"
                    ~ "static inline void %s_definir(%s *v, size_t idx, %s val) {\n"
                    ~ "    if (idx >= v->len) delegua_panic(\"VetorNativo: índice fora dos limites.\");\n"
                    ~ "    %s"
                    ~ "    v->data[idx] = val;\n"
                    ~ "}\n"
                    ~ "static inline %s %s_remover_ultimo(%s *v) {\n"
                    ~ "    if (v->len == 0) delegua_panic(\"VetorNativo: removerUltimo em vetor vazio.\");\n"
                    ~ "    return v->data[--v->len];\n"
                    ~ "}\n"
                    ~ "static inline void %s_limpar(%s *v) {\n"
                    ~ "%s"
                    ~ "    v->len = 0;\n"
                    ~ "}\n"
                    ~ "static inline %s %s_fatia(const %s *v, size_t ini, size_t fim) {\n"
                    ~ "    if (ini > fim || fim > v->len) delegua_panic(\"VetorNativo: intervalo de fatia inválido.\");\n"
                    ~ "    %s s = { v->data + ini, fim - ini }; return s;\n"
                    ~ "}\n"
                    ~ "static inline %s %s_clonar(const %s *v) {\n"
                    ~ "    %s r = %s_novo();\n"
                    ~ "    if (v->len > 0) { %s_reservar(&r, v->len); r.len = v->len;\n%s    }\n"
                    ~ "    return r;\n"
                    ~ "}\n"
                    ~ "static inline delegua_value %s_para_vetor(const %s *v) {\n"
                    ~ "    delegua_value out = create_vetor();\n"
                    ~ "    for (size_t i = 0; i < v->len; i++) delegua_vetor_adicionar(&out, %s);\n"
                    ~ "    return out;\n"
                    ~ "}\n"
                    ~ "static inline delegua_value %s_box_and_drop(%s v) {\n"
                    ~ "    delegua_value out = %s_para_vetor(&v);\n"
                    ~ "    %s_drop(&v);\n"
                    ~ "    return out;\n"
                    ~ "}\n"
                    ~ "static inline %s %s_from_dv(delegua_value dv) {\n"
                    ~ "    %s out = %s_novo();\n"
                    ~ "    size_t n = (size_t)delegua_tamanho(dv);\n"
                    ~ "    %s_reservar(&out, n);\n"
                    ~ "    for (size_t i = 0; i < n; i++) %s_adicionar(&out, %s);\n"
                    ~ "    return out;\n"
                    ~ "}\n",
                    name, elemT, name,
                    name, name, name,
                    name, name, elemDropLoop,
                    name, name, elemT, elemT, elemT, elemT,
                    name, name, elemT, elemT, name,
                    elemT, name, name,
                    name, name, elemT,
                    elemDrop.length ? formatD("%s(&v->data[idx]); ", elemDrop) : ""d,
                    elemT, name, name,
                    name, name, elemDropLoop,
                    sliceName, name, name, sliceName,
                    name, name, name, name, name, name, cloneBody,
                    name, name, boxElem,
                    name, name, name, name,
                    name, name, name, name, name, name, unboxElem);
                return;
            }
            case NativeContainerKind.MapaNativo:
            {
                ensureStringNativa();
                TypeSema kSema = nc.typeArgs[0];
                TypeSema vSema = nc.typeArgs[1];
                dstring kT = cTypeFor(kSema);
                dstring vT = cTypeFor(vSema);
                dstring name = "cgd_"d ~ key.to!dstring;
                bool strKey = cast(TypeSemaNativeContainer) kSema !is null
                    && (cast(TypeSemaNativeContainer) kSema).containerKind == NativeContainerKind.StringNativa;
                dstring hashExpr = strKey
                    ? "cgd_hash_bytes(k.ptr ? k.ptr : \"\", k.len)"d
                    : formatD("cgd_hash_bytes(&k, sizeof(%s))", kT);
                dstring eqExpr = strKey
                    ? "cgd_nstr_igual_nstr(&m->keys[idx], &k)"d
                    : formatD("(memcmp(&m->keys[idx], &k, sizeof(%s)) == 0)", kT);
                dstring kDrop = hasOwnershipResource(kSema) ? dropFnForType(kSema) : ""d;
                dstring vDrop = hasOwnershipResource(vSema) ? dropFnForType(vSema) : ""d;
                dstring dropItem = (kDrop.length ? formatD("%s(&m->keys[i]); ", kDrop) : ""d)
                    ~ (vDrop.length ? formatD("%s(&m->vals[i]); ", vDrop) : ""d);
                dstring boxKey = strKey ? "cgd_nstr_para_texto(&m->keys[i])"d : boxValueExpr(kSema, "m->keys[i]"d);
                dstring boxVal = boxValueExpr(vSema, "m->vals[i]"d);
                dstring cloneKey = strKey ? "cgd_nstr_clonar(&m->keys[i])"d : "m->keys[i]"d;
                dstring cloneVal = vDrop.length ? "m->vals[i]"d : "m->vals[i]"d;
                if (TypeSemaNativeContainer vnc = cast(TypeSemaNativeContainer) vSema)
                {
                    if (vnc.containerKind == NativeContainerKind.StringNativa)
                        cloneVal = "cgd_nstr_clonar(&m->vals[i])"d;
                    else if (vnc.isOwnedResource())
                        cloneVal = formatD("cgd_%s_clonar(&m->vals[i])", typeMangleKey(vnc));
                }

                typeDecls ~= formatD(
                    "typedef struct %s { uint8_t *states; %s *keys; %s *vals; size_t len; size_t cap; } %s;\n"
                    ~ "static inline %s %s_novo(void) { %s m = {NULL, NULL, NULL, 0, 0}; return m; }\n"
                    ~ "static inline void %s_drop(%s *m) {\n"
                    ~ "    if (!m || !m->states) return;\n"
                    ~ "    for (size_t i = 0; i < m->cap; i++) { if (m->states[i] == 1) { %s } }\n"
                    ~ "    free(m->states); free(m->keys); free(m->vals);\n"
                    ~ "    m->states = NULL; m->keys = NULL; m->vals = NULL; m->len = 0; m->cap = 0;\n"
                    ~ "}\n"
                    ~ "static inline void %s_rehash(%s *m, size_t nc) {\n"
                    ~ "    uint8_t *ns = (uint8_t *)calloc(nc, 1);\n"
                    ~ "    %s *nk = (%s *)calloc(nc, sizeof(%s));\n"
                    ~ "    %s *nv = (%s *)calloc(nc, sizeof(%s));\n"
                    ~ "    if (!ns || !nk || !nv) delegua_panic(\"MapaNativo: falha de alocação.\");\n"
                    ~ "    for (size_t i = 0; i < m->cap; i++) {\n"
                    ~ "        if (m->states[i] == 1) {\n"
                    ~ "            %s k = m->keys[i];\n"
                    ~ "            size_t idx = (size_t)(%s & (uint64_t)(nc - 1));\n"
                    ~ "            while (ns[idx] == 1) idx = (idx + 1) & (nc - 1);\n"
                    ~ "            ns[idx] = 1; nk[idx] = k; nv[idx] = m->vals[i];\n"
                    ~ "        }\n"
                    ~ "    }\n"
                    ~ "    free(m->states); free(m->keys); free(m->vals);\n"
                    ~ "    m->states = ns; m->keys = nk; m->vals = nv; m->cap = nc;\n"
                    ~ "}\n"
                    ~ "static inline void %s_definir(%s *m, %s k, %s v) {\n"
                    ~ "    if (m->cap == 0 || (m->len + 1) * 10 >= m->cap * 7) {\n"
                    ~ "        %s_rehash(m, m->cap ? m->cap * 2 : 16);\n"
                    ~ "    }\n"
                    ~ "    size_t idx = (size_t)(%s & (uint64_t)(m->cap - 1));\n"
                    ~ "    size_t first_tomb = m->cap;\n"
                    ~ "    while (m->states[idx] != 0) {\n"
                    ~ "        if (m->states[idx] == 1 && %s) {\n"
                    ~ "            %s%s"
                    ~ "            m->vals[idx] = v; return;\n"
                    ~ "        }\n"
                    ~ "        if (m->states[idx] == 2 && first_tomb == m->cap) first_tomb = idx;\n"
                    ~ "        idx = (idx + 1) & (m->cap - 1);\n"
                    ~ "    }\n"
                    ~ "    if (first_tomb != m->cap) idx = first_tomb;\n"
                    ~ "    m->states[idx] = 1; m->keys[idx] = k; m->vals[idx] = v; m->len++;\n"
                    ~ "}\n"
                    ~ "static inline bool %s_contem(const %s *m, %s k) {\n"
                    ~ "    if (m->cap == 0) return false;\n"
                    ~ "    size_t idx = (size_t)(%s & (uint64_t)(m->cap - 1));\n"
                    ~ "    size_t probes = 0;\n"
                    ~ "    while (m->states[idx] != 0 && probes < m->cap) {\n"
                    ~ "        if (m->states[idx] == 1 && %s) return true;\n"
                    ~ "        idx = (idx + 1) & (m->cap - 1); probes++;\n"
                    ~ "    }\n"
                    ~ "    return false;\n"
                    ~ "}\n"
                    ~ "static inline %s %s_obter(const %s *m, %s k) {\n"
                    ~ "    if (m->cap == 0) delegua_panic(\"MapaNativo: chave não encontrada.\");\n"
                    ~ "    size_t idx = (size_t)(%s & (uint64_t)(m->cap - 1));\n"
                    ~ "    size_t probes = 0;\n"
                    ~ "    while (m->states[idx] != 0 && probes < m->cap) {\n"
                    ~ "        if (m->states[idx] == 1 && %s) return m->vals[idx];\n"
                    ~ "        idx = (idx + 1) & (m->cap - 1); probes++;\n"
                    ~ "    }\n"
                    ~ "    delegua_panic(\"MapaNativo: chave não encontrada.\");\n"
                    ~ "    %s z; memset(&z, 0, sizeof(z)); return z;\n"
                    ~ "}\n"
                    ~ "static inline bool %s_remover(%s *m, %s k) {\n"
                    ~ "    if (m->cap == 0) return false;\n"
                    ~ "    size_t idx = (size_t)(%s & (uint64_t)(m->cap - 1));\n"
                    ~ "    size_t probes = 0;\n"
                    ~ "    while (m->states[idx] != 0 && probes < m->cap) {\n"
                    ~ "        if (m->states[idx] == 1 && %s) {\n"
                    ~ "            %s%s m->states[idx] = 2; m->len--; return true;\n"
                    ~ "        }\n"
                    ~ "        idx = (idx + 1) & (m->cap - 1); probes++;\n"
                    ~ "    }\n"
                    ~ "    return false;\n"
                    ~ "}\n"
                    ~ "static inline void %s_limpar(%s *m) {\n"
                    ~ "    if (!m->states) return;\n"
                    ~ "    for (size_t i = 0; i < m->cap; i++) { if (m->states[i] == 1) { %s } m->states[i] = 0; }\n"
                    ~ "    m->len = 0;\n"
                    ~ "}\n"
                    ~ "static inline %s %s_clonar(const %s *m) {\n"
                    ~ "    %s r = %s_novo();\n"
                    ~ "    for (size_t i = 0; i < m->cap; i++) {\n"
                    ~ "        if (m->states[i] == 1) %s_definir(&r, %s, %s);\n"
                    ~ "    }\n"
                    ~ "    return r;\n"
                    ~ "}\n"
                    ~ "static inline delegua_value %s_para_dicionario(const %s *m) {\n"
                    ~ "    delegua_value d = create_map();\n"
                    ~ "    for (size_t i = 0; i < m->cap; i++) {\n"
                    ~ "        if (m->states[i] == 1) delegua_map_setar(d, %s, %s);\n"
                    ~ "    }\n"
                    ~ "    return d;\n"
                    ~ "}\n"
                    ~ "static inline delegua_value %s_box_and_drop(%s m) {\n"
                    ~ "    delegua_value d = %s_para_dicionario(&m);\n"
                    ~ "    %s_drop(&m);\n"
                    ~ "    return d;\n"
                    ~ "}\n",
                    name, kT, vT, name,
                    name, name, name,
                    name, name, dropItem,
                    name, name, kT, kT, kT, vT, vT, vT, kT, hashExpr,
                    name, name, kT, vT, name, hashExpr, eqExpr,
                    kDrop.length ? formatD("%s(&k); ", kDrop) : ""d,
                    vDrop.length ? formatD("%s(&m->vals[idx]); ", vDrop) : ""d,
                    name, name, kT, hashExpr, eqExpr,
                    vT, name, name, kT, hashExpr, eqExpr, vT,
                    name, name, kT, hashExpr, eqExpr,
                    kDrop.length ? formatD("%s(&m->keys[idx]); ", kDrop) : ""d,
                    vDrop.length ? formatD("%s(&m->vals[idx]); ", vDrop) : ""d,
                    name, name, dropItem,
                    name, name, name, name, name, name, cloneKey, cloneVal,
                    name, name, boxKey, boxVal,
                    name, name, name, name);
                return;
            }
            case NativeContainerKind.OpcionalNativo:
            {
                TypeSema elemSema = nc.typeArgs[0];
                dstring elemT = cTypeFor(elemSema);
                dstring name = "cgd_"d ~ key.to!dstring;
                dstring dropFn = hasOwnershipResource(elemSema) ? dropFnForType(elemSema) : ""d;
                typeDecls ~= formatD(
                    "typedef struct %s { bool has; %s val; } %s;\n"
                    ~ "static inline %s %s_algum(%s v) { %s o; o.has = true; o.val = v; return o; }\n"
                    ~ "static inline %s %s_nenhum(void) { %s o; memset(&o, 0, sizeof(o)); return o; }\n"
                    ~ "static inline bool %s_tem_valor(%s o) { return o.has; }\n"
                    ~ "static inline bool %s_eh_nenhum(%s o) { return !o.has; }\n"
                    ~ "static inline %s %s_valor(%s o) {\n"
                    ~ "    if (!o.has) delegua_panic(\"OpcionalNativo: tentativa de ler valor ausente.\");\n"
                    ~ "    return o.val;\n"
                    ~ "}\n"
                    ~ "static inline %s %s_valor_ou(%s o, %s padrao) { return o.has ? o.val : padrao; }\n"
                    ~ "static inline void %s_drop(%s *o) { if (o && o->has) { %s o->has = false; } }\n",
                    name, elemT, name,
                    name, name, elemT, name,
                    name, name, name,
                    name, name,
                    name, name,
                    elemT, name, name,
                    elemT, name, name, elemT,
                    name, name, dropFn.length ? formatD("%s(&o->val);", dropFn) : ""d);
                return;
            }
            case NativeContainerKind.ResultadoNativo:
            {
                TypeSema okSema = nc.typeArgs[0];
                TypeSema errSema = nc.typeArgs[1];
                dstring okT = cTypeFor(okSema);
                dstring errT = cTypeFor(errSema);
                dstring name = "cgd_"d ~ key.to!dstring;
                dstring okDrop = hasOwnershipResource(okSema) ? dropFnForType(okSema) : ""d;
                dstring errDrop = hasOwnershipResource(errSema) ? dropFnForType(errSema) : ""d;
                typeDecls ~= formatD(
                    "typedef struct %s { bool is_ok; union { %s ok; %s err; } u; } %s;\n"
                    ~ "static inline %s %s_ok(%s v) { %s r; r.is_ok = true; r.u.ok = v; return r; }\n"
                    ~ "static inline %s %s_erro(%s e) { %s r; r.is_ok = false; r.u.err = e; return r; }\n"
                    ~ "static inline bool %s_eh_ok(%s r) { return r.is_ok; }\n"
                    ~ "static inline bool %s_eh_erro(%s r) { return !r.is_ok; }\n"
                    ~ "static inline %s %s_valor(%s r) {\n"
                    ~ "    if (!r.is_ok) delegua_panic(\"ResultadoNativo: tentativa de ler valor de erro.\");\n"
                    ~ "    return r.u.ok;\n"
                    ~ "}\n"
                    ~ "static inline %s %s_erro_val(%s r) {\n"
                    ~ "    if (r.is_ok) delegua_panic(\"ResultadoNativo: tentativa de ler erro de sucesso.\");\n"
                    ~ "    return r.u.err;\n"
                    ~ "}\n"
                    ~ "static inline %s %s_valor_ou(%s r, %s padrao) { return r.is_ok ? r.u.ok : padrao; }\n"
                    ~ "static inline void %s_drop(%s *r) { if (!r) return; if (r->is_ok) { %s } else { %s } }\n",
                    name, okT, errT, name,
                    name, name, okT, name,
                    name, name, errT, name,
                    name, name,
                    name, name,
                    okT, name, name,
                    errT, name, name,
                    okT, name, name, okT,
                    name, name,
                    okDrop.length ? formatD("%s(&r->u.ok);", okDrop) : ""d,
                    errDrop.length ? formatD("%s(&r->u.err);", errDrop) : ""d);
                return;
            }
            case NativeContainerKind.MatrizNativa:
            {
                TypeSema elemSema = nc.typeArgs[0];
                dstring elemT = cTypeFor(elemSema);
                dstring name = "cgd_"d ~ key.to!dstring;
                typeDecls ~= formatD(
                    "typedef struct %s { %s *data; size_t rows; size_t cols; } %s;\n"
                    ~ "static inline %s %s_novo(size_t r, size_t c) {\n"
                    ~ "    if (r > 0 && c > SIZE_MAX / r) delegua_panic(\"MatrizNativa: overflow de dimensão.\");\n"
                    ~ "    size_t n = r * c;\n"
                    ~ "    if (n > SIZE_MAX / sizeof(%s)) delegua_panic(\"MatrizNativa: overflow de memória.\");\n"
                    ~ "    %s *buf = n ? (%s *)calloc(n, sizeof(%s)) : NULL;\n"
                    ~ "    if (n && !buf) delegua_panic(\"MatrizNativa: falha de alocação.\");\n"
                    ~ "    %s m = {buf, r, c}; return m;\n"
                    ~ "}\n"
                    ~ "static inline void %s_drop(%s *m) {\n"
                    ~ "    if (m && m->data) { free(m->data); m->data = NULL; m->rows = 0; m->cols = 0; }\n"
                    ~ "}\n"
                    ~ "static inline %s %s_obter(const %s *m, size_t r, size_t c) {\n"
                    ~ "    if (r >= m->rows || c >= m->cols) delegua_panic(\"MatrizNativa: índice fora dos limites.\");\n"
                    ~ "    return m->data[r * m->cols + c];\n"
                    ~ "}\n"
                    ~ "static inline void %s_definir(%s *m, size_t r, size_t c, %s v) {\n"
                    ~ "    if (r >= m->rows || c >= m->cols) delegua_panic(\"MatrizNativa: índice fora dos limites.\");\n"
                    ~ "    m->data[r * m->cols + c] = v;\n"
                    ~ "}\n"
                    ~ "static inline %s %s_transpor(const %s *m) {\n"
                    ~ "    %s out = %s_novo(m->cols, m->rows);\n"
                    ~ "    for (size_t i = 0; i < m->rows; i++)\n"
                    ~ "        for (size_t j = 0; j < m->cols; j++)\n"
                    ~ "            out.data[j * out.cols + i] = m->data[i * m->cols + j];\n"
                    ~ "    return out;\n"
                    ~ "}\n"
                    ~ "static inline %s %s_multiplicar(const %s *a, const %s *b) {\n"
                    ~ "    if (a->cols != b->rows) delegua_panic(\"MatrizNativa: dimensões incompatíveis em multiplicar.\");\n"
                    ~ "    %s out = %s_novo(a->rows, b->cols);\n"
                    ~ "    for (size_t i = 0; i < a->rows; i++)\n"
                    ~ "        for (size_t k = 0; k < a->cols; k++) {\n"
                    ~ "            %s aik = a->data[i * a->cols + k];\n"
                    ~ "            for (size_t j = 0; j < b->cols; j++)\n"
                    ~ "                out.data[i * out.cols + j] += aik * b->data[k * b->cols + j];\n"
                    ~ "        }\n"
                    ~ "    return out;\n"
                    ~ "}\n"
                    ~ "static inline %s %s_clonar(const %s *m) {\n"
                    ~ "    %s out = %s_novo(m->rows, m->cols);\n"
                    ~ "    size_t n = m->rows * m->cols;\n"
                    ~ "    if (n > 0) memcpy(out.data, m->data, n * sizeof(%s));\n"
                    ~ "    return out;\n"
                    ~ "}\n",
                    name, elemT, name,
                    name, name, elemT, elemT, elemT, elemT, name,
                    name, name,
                    elemT, name, name,
                    name, name, elemT,
                    name, name, name, name, name,
                    name, name, name, name, name, name, elemT,
                    name, name, name, name, name, elemT);
                return;
            }
        }
    }

public:
    this(OwnershipInfo ownership = null)
    {
        this.ownership = ownership;
    }

    dstring valueStructName(ClassDecl cls)
    {
        return "cgd_val_"d ~ cName(cls.signature.linkName);
    }

    dstring nativeFnName(FnDecl fn)
    {
        return "cgd_nat_"d ~ cName(fn.linkName);
    }

    dstring cTypeFor(TypeSema t)
    {
        if (t is null)
            return "int64_t"d;
        if (TypeSemaNative nat = cast(TypeSemaNative) t)
            return nat.cTypeName().to!dstring;
        if (TypeSemaBuiltin b = cast(TypeSemaBuiltin) t)
        {
            if (b.base == TypeSemaBase.Int)
                return "int64_t"d;
            if (b.base == TypeSemaBase.Double)
                return "double"d;
            if (b.base == TypeSemaBase.Bool)
                return "bool"d;
            if (b.base == TypeSemaBase.Void)
                return "void"d;
            return "delegua_value"d;
        }
        if (TypeSemaClass cls = cast(TypeSemaClass) t)
        {
            if (cls.declaration !is null && cls.declaration.isValueType)
            {
                ensureValueStruct(cls.declaration);
                return valueStructName(cls.declaration);
            }
            return "delegua_value"d;
        }
        if (TypeSemaNativeContainer nc = cast(TypeSemaNativeContainer) t)
        {
            ensureContainer(nc);
            if (nc.containerKind == NativeContainerKind.StringNativa)
                return "cgd_nstr"d;
            if (nc.containerKind == NativeContainerKind.VisaoTexto)
                return "cgd_sv"d;
            return "cgd_"d ~ typeMangleKey(nc).to!dstring;
        }
        return "delegua_value"d;
    }

    dstring dropFnForType(TypeSema t)
    {
        if (TypeSemaNativeContainer nc = cast(TypeSemaNativeContainer) t)
        {
            ensureContainer(nc);
            if (nc.containerKind == NativeContainerKind.StringNativa)
                return "cgd_nstr_drop"d;
            if (nc.containerKind == NativeContainerKind.VisaoTexto || nc.containerKind == NativeContainerKind.FatiaNativa)
                return ""d;
            return "cgd_"d ~ typeMangleKey(nc).to!dstring ~ "_drop"d;
        }
        if (TypeSemaClass cls = cast(TypeSemaClass) t)
        {
            if (cls.declaration !is null && cls.declaration.isValueType && cls.declaration.hasNonTrivialDrop)
            {
                ensureValueStruct(cls.declaration);
                return valueStructName(cls.declaration) ~ "_drop"d;
            }
        }
        return ""d;
    }

    dstring boxValueExpr(TypeSema t, dstring cExpr)
    {
        if (t is null)
            return formatD("create_num((int64_t)(%s))", cExpr);
        if (TypeSemaNative nat = cast(TypeSemaNative) t)
        {
            if (nat.isBool())
                return formatD("create_bool(%s)", cExpr);
            if (nat.isFloat())
                return formatD("create_real((double)(%s))", cExpr);
            return formatD("create_num((int64_t)(%s))", cExpr);
        }
        if (TypeSemaBuiltin b = cast(TypeSemaBuiltin) t)
        {
            if (b.base == TypeSemaBase.Bool)
                return formatD("create_bool(%s)", cExpr);
            if (b.base == TypeSemaBase.Double)
                return formatD("create_real((double)(%s))", cExpr);
            if (b.base == TypeSemaBase.Int)
                return formatD("create_num((int64_t)(%s))", cExpr);
            if (b.base == TypeSemaBase.Void)
                return "create_nulo()"d;
            return cExpr;
        }
        if (TypeSemaClass cls = cast(TypeSemaClass) t)
        {
            if (cls.declaration !is null && cls.declaration.isValueType)
            {
                ensureValueStruct(cls.declaration);
                return formatD("%s_box(%s)", valueStructName(cls.declaration), cExpr);
            }
            return cExpr;
        }
        if (TypeSemaNativeContainer nc = cast(TypeSemaNativeContainer) t)
        {
            ensureContainer(nc);
            if (nc.containerKind == NativeContainerKind.StringNativa)
                return formatD("cgd_nstr_box_and_drop(%s)", cExpr);
            if (nc.containerKind == NativeContainerKind.VisaoTexto)
                return formatD("cgd_sv_para_texto(%s)", cExpr);
            if (nc.containerKind == NativeContainerKind.VetorNativo)
            {
                dstring cn = "cgd_"d ~ typeMangleKey(nc).to!dstring;
                return formatD("%s_box_and_drop(%s)", cn, cExpr);
            }
            if (nc.containerKind == NativeContainerKind.MapaNativo)
            {
                dstring cn = "cgd_"d ~ typeMangleKey(nc).to!dstring;
                return formatD("%s_box_and_drop(%s)", cn, cExpr);
            }
        }
        return "create_nulo()"d;
    }

    dstring unboxValueExpr(TypeSema t, dstring dvExpr)
    {
        if (t is null)
            return formatD("(delegua_op_cast(%s, DELEGUA_T_NUM).value.num)", dvExpr);
        if (TypeSemaNative nat = cast(TypeSemaNative) t)
        {
            dstring ct = nat.cTypeName().to!dstring;
            if (nat.isBool())
                return formatD("(delegua_op_cast(%s, DELEGUA_T_BOOL).value.b1)", dvExpr);
            if (nat.isFloat())
                return formatD("((%s)(delegua_op_cast(%s, DELEGUA_T_REAL).value.real))", ct, dvExpr);
            return formatD("((%s)(delegua_op_cast(%s, DELEGUA_T_NUM).value.num))", ct, dvExpr);
        }
        if (TypeSemaBuiltin b = cast(TypeSemaBuiltin) t)
        {
            if (b.base == TypeSemaBase.Bool)
                return formatD("(delegua_op_cast(%s, DELEGUA_T_BOOL).value.b1)", dvExpr);
            if (b.base == TypeSemaBase.Double)
                return formatD("(delegua_op_cast(%s, DELEGUA_T_REAL).value.real)", dvExpr);
            if (b.base == TypeSemaBase.Int)
                return formatD("(delegua_op_cast(%s, DELEGUA_T_NUM).value.num)", dvExpr);
            return dvExpr;
        }
        if (TypeSemaClass cls = cast(TypeSemaClass) t)
        {
            if (cls.declaration !is null && cls.declaration.isValueType)
            {
                ensureValueStruct(cls.declaration);
                return formatD("%s_unbox(%s)", valueStructName(cls.declaration), dvExpr);
            }
            return dvExpr;
        }
        if (TypeSemaNativeContainer nc = cast(TypeSemaNativeContainer) t)
        {
            ensureContainer(nc);
            if (nc.containerKind == NativeContainerKind.StringNativa)
                return formatD("cgd_nstr_criar_dv(%s)", dvExpr);
            if (nc.containerKind == NativeContainerKind.VetorNativo)
                return formatD("cgd_%s_from_dv(%s)", typeMangleKey(nc), dvExpr);
            dstring cn = "cgd_"d ~ typeMangleKey(nc).to!dstring;
            if (nc.containerKind == NativeContainerKind.OpcionalNativo)
                return formatD("%s_nenhum()", cn);
            if (nc.containerKind == NativeContainerKind.MapaNativo)
                return formatD("%s_novo()", cn);
            return formatD("((%s){0})", cn);
        }
        return dvExpr;
    }

    /// Emite `typedef struct cgd_val_<id>`, helpers de box/unbox e drop de uma classe `@pilha`.
    void ensureValueStruct(ClassDecl cls)
    {
        if (cls is null || !cls.isValueType || cls in emittedValueStructs)
            return;
        emittedValueStructs[cls] = true;

        // Garante primeiro os tipos dos campos aninhados
        foreach (ClassField f; cls.fields)
        {
            if (f.isEnum)
                continue;
            if (TypeSemaClass nested = cast(TypeSemaClass) f.type_sema)
                if (nested.declaration !is null && nested.declaration.isValueType)
                    ensureValueStruct(nested.declaration);
            if (TypeSemaNativeContainer nc = cast(TypeSemaNativeContainer) f.type_sema)
                ensureContainer(nc);
        }

        dstring sname = valueStructName(cls);
        dstring[] fieldsC;
        foreach (ClassField f; cls.fields)
        {
            if (f.isEnum)
                continue;
            fieldsC ~= formatD("    %s %s;", cTypeFor(f.type_sema), cName(f.name));
        }
        if (!fieldsC.length)
            fieldsC ~= "    uint8_t _cgd_empty;"d;

        typeDecls ~= formatD("typedef struct %s {\n%s\n} %s;\n", sname, fieldsC.join("\n"), sname);

        // Protótipos de box/unbox e drop ficam em typeDecls logo após a struct,
        // para que containers nativos especializados (ex.: VetorNativo<Esfera>) possam usá-los.
        typeDecls ~= formatD("static delegua_value %s_box(%s v);", sname, sname);
        typeDecls ~= formatD("static %s %s_unbox(delegua_value obj);", sname, sname);
        if (cls.hasNonTrivialDrop)
            typeDecls ~= formatD("static void %s_drop(%s *cgd_self);", sname, sname);

        // Box / unbox usando a representação de objeto gerenciado da classe na fronteira GC
        dstring clsVar = cName(cls.signature.linkName);
        dstring[] boxStmts;
        dstring[] unboxStmts;
        foreach (ClassField f; cls.fields)
        {
            if (f.isEnum)
                continue;
            dstring fn = cName(f.name);
            boxStmts ~= formatD("    delegua_definir_em(obj, %s, %s, %s);",
                    cString(f.name), boxValueExpr(f.type_sema, "v."d ~ fn), clsVar);
            unboxStmts ~= formatD("    v.%s = %s;", fn,
                    unboxValueExpr(f.type_sema, formatD("delegua_propriedade_em(obj, %s, %s)",
                        cString(f.name), clsVar)));
        }
        fnDefs ~= formatD(
            "static delegua_value %s_box(%s v) {\n"
            ~ "    delegua_value obj = delegua_instanciar_sem_construtor(%s);\n"
            ~ "%s\n"
            ~ "    return obj;\n"
            ~ "}\n"
            ~ "static %s %s_unbox(delegua_value obj) {\n"
            ~ "    %s v; memset(&v, 0, sizeof(v));\n"
            ~ "%s\n"
            ~ "    return v;\n"
            ~ "}\n",
            sname, sname, clsVar, boxStmts.join("\n"),
            sname, sname, sname, unboxStmts.join("\n"));

        // Construtor nativo `cgd_val_new_<id>`
        FnDecl ctor = null;
        foreach (FnDecl m; cls.methods)
            if (m.fn == "construtor"d)
            {
                ctor = m;
                break;
            }

        dstring[] ctorParams;
        if (ctor !is null)
        {
            foreach (FnArg a; ctor.args)
                ctorParams ~= formatD("%s %s", cTypeFor(a.type_sema), cName(a.name));
        }
        else
        {
            // Construtor posicional automático quando a classe `@pilha` não declara `construtor(...)`!
            foreach (ClassField f; cls.fields)
                if (!f.isEnum)
                    ctorParams ~= formatD("%s %s", cTypeFor(f.type_sema), cName(f.name));
        }
        protoDecls ~= formatD("static %s %s_new(%s);", sname, sname,
                ctorParams.length ? ctorParams.join(", ") : "void"d);

        // Protótipos de todos os métodos da classe `@pilha`
        foreach (FnDecl m; cls.methods)
        {
            if (m.accessor || m.fn == "construtor"d)
                continue;
            dstring[] mparams;
            if (!m.isStatic)
                mparams ~= formatD("%s *cgd_self", sname);
            foreach (FnArg a; m.args)
                mparams ~= formatD("%s %s", cTypeFor(a.type_sema), cName(a.name));
            dstring retT = m.fn == "destrutor"d ? "void"d : cTypeFor(m.type_sema);
            protoDecls ~= formatD("static %s %s(%s);", retT, nativeFnName(m),
                    mparams.length ? mparams.join(", ") : "void"d);
        }
    }

    /// Emite o corpo do construtor, drop e métodos nativos de uma classe `@pilha`.
    void emitValueClassBodies(ClassDecl cls)
    {
        if (cls is null || !cls.isValueType || cls in emittedValueMethods)
            return;
        ensureValueStruct(cls);
        emittedValueMethods[cls] = true;

        dstring sname = valueStructName(cls);
        FnDecl ctor = null;
        FnDecl dtor = null;
        foreach (FnDecl m; cls.methods)
        {
            if (m.fn == "construtor"d)
                ctor = m;
            else if (m.fn == "destrutor"d)
                dtor = m;
        }

        // 1) Corpo do construtor nativo
        dstring[] ctorParams;
        dstring[] ctorBody;
        ctorBody ~= formatD("    %s cgd_self_val; memset(&cgd_self_val, 0, sizeof(cgd_self_val));", sname);
        ctorBody ~= formatD("    %s *cgd_self = &cgd_self_val; (void)cgd_self;", sname);

        if (ctor !is null)
        {
            foreach (FnArg a; ctor.args)
                ctorParams ~= formatD("%s %s", cTypeFor(a.type_sema), cName(a.name));
            ClassDecl prevCls = currentValueClass;
            FnDecl prevFn = currentFn;
            currentValueClass = cls;
            currentFn = ctor;
            pushDropScope();
            foreach (Node st; ctor.body)
                ctorBody ~= compileNativeStmt(st);
            dstring drops = emitDropsFrom(0);
            if (drops.length)
                ctorBody ~= drops;
            popDropScope();
            currentValueClass = prevCls;
            currentFn = prevFn;
        }
        else
        {
            foreach (ClassField f; cls.fields)
                if (!f.isEnum)
                {
                    dstring fn = cName(f.name);
                    ctorParams ~= formatD("%s %s", cTypeFor(f.type_sema), fn);
                    ctorBody ~= formatD("    cgd_self->%s = %s;", fn, fn);
                }
        }
        ctorBody ~= "    return cgd_self_val;"d;
        fnDefs ~= formatD("static %s %s_new(%s) {\n%s\n}\n", sname, sname,
                ctorParams.length ? ctorParams.join(", ") : "void"d, ctorBody.join("\n"));

        // 2) Métodos da classe `@pilha`
        foreach (FnDecl m; cls.methods)
        {
            if (m.accessor || m.fn == "construtor"d)
                continue;
            emitNativeFunctionImpl(m, cls);
        }

        // 3) Drop determinístico de `@pilha` não-trivial
        if (cls.hasNonTrivialDrop)
        {
            dstring[] dropLines;
            if (dtor !is null)
                dropLines ~= formatD("    %s(cgd_self);", nativeFnName(dtor));
            foreach_reverse (ClassField f; cls.fields)
            {
                if (!f.isEnum && hasOwnershipResource(f.type_sema))
                {
                    dstring df = dropFnForType(f.type_sema);
                    if (df.length)
                        dropLines ~= formatD("    %s(&cgd_self->%s);", df, cName(f.name));
                }
            }
            fnDefs ~= formatD("static void %s_drop(%s *cgd_self) {\n    if (!cgd_self) return;\n%s\n}\n",
                    sname, sname, dropLines.join("\n"));
        }
    }

    /// Emite função C nativa pura para `fn` (sem `delegua_value`, sem boxing, sem GC).
    void emitNativeFunctionImpl(FnDecl fn, ClassDecl ownerValueClass = null)
    {
        if (fn is null || fn in emittedNativeFns)
            return;
        emittedNativeFns[fn] = true;

        ClassDecl prevCls = currentValueClass;
        FnDecl prevFn = currentFn;
        currentValueClass = ownerValueClass;
        currentFn = fn;
        scope (exit)
        {
            currentValueClass = prevCls;
            currentFn = prevFn;
        }

        dstring[] params;
        if (ownerValueClass !is null && !fn.isStatic)
            params ~= formatD("%s *cgd_self", valueStructName(ownerValueClass));

        ParamMode[] modes = ownership !is null && (fn in ownership.paramModes) ? ownership.paramModes[fn] : null;
        foreach (size_t i, FnArg a; fn.args)
        {
            dstring ct = cTypeFor(a.type_sema);
            bool byPtr = hasOwnershipResource(a.type_sema) && i < modes.length && modes[i] != ParamMode.Consume;
            params ~= byPtr ? formatD("%s *%s_ptr", ct, cName(a.name)) : formatD("%s %s", ct, cName(a.name));
        }

        dstring retT = fn.fn == "destrutor"d ? "void"d : cTypeFor(fn.type_sema);
        dstring sig = formatD("static %s %s(%s)", retT, nativeFnName(fn),
                params.length ? params.join(", ") : "void"d);
        if (ownerValueClass is null)
            protoDecls ~= sig ~ ";";

        pushDropScope();
        dstring[] bodyLines;
        foreach (size_t i, FnArg a; fn.args)
        {
            if (hasOwnershipResource(a.type_sema) && !(i < modes.length && modes[i] != ParamMode.Consume))
                registerDrop(cName(a.name), a.type_sema);
        }
        foreach (Node st; fn.body)
            bodyLines ~= compileNativeStmt(st);
        dstring endDrops = emitDropsFrom(0);
        if (endDrops.length)
            bodyLines ~= endDrops;
        popDropScope();

        fnDefs ~= formatD("%s {\n%s\n}\n", sig, bodyLines.join("\n"));
    }

    /// Emite o thunk gerenciado do construtor de uma classe `@pilha` (explícito ou posicional),
    /// chamando o construtor C nativo `cgd_val_<id>_new(...)` e preenchendo `argv[0]`.
    dstring emitManagedValueConstructor(ClassDecl cls, dstring managedProto)
    {
        emitValueClassBodies(cls);
        dstring sname = valueStructName(cls);
        dstring clsVar = cName(cls.signature.linkName);

        FnDecl ctor = null;
        foreach (FnDecl m; cls.methods)
            if (m.fn == "construtor"d)
            {
                ctor = m;
                break;
            }

        dstring[] setup;
        dstring[] callArgs;
        if (ctor !is null)
        {
            foreach (size_t i, FnArg a; ctor.args)
            {
                dstring ct = cTypeFor(a.type_sema);
                dstring aname = formatD("cgd_ca_%s", i);
                setup ~= formatD("    %s %s = %s;", ct, aname, unboxValueExpr(a.type_sema,
                        formatD("argv[%s]", i + 1)));
                callArgs ~= aname;
            }
        }
        else
        {
            size_t idx = 0;
            foreach (ClassField f; cls.fields)
            {
                if (f.isEnum)
                    continue;
                dstring ct = cTypeFor(f.type_sema);
                dstring aname = formatD("cgd_ca_%s", idx);
                setup ~= formatD("    %s %s; memset(&%s, 0, sizeof(%s));", ct, aname, aname, aname);
                setup ~= formatD("    if (argc > %s) %s = %s;", idx + 1, aname,
                        unboxValueExpr(f.type_sema, formatD("argv[%s]", idx + 1)));
                callArgs ~= aname;
                idx++;
            }
        }

        dstring[] assignFields;
        foreach (ClassField f; cls.fields)
        {
            if (f.isEnum)
                continue;
            dstring fn = cName(f.name);
            assignFields ~= formatD("    delegua_definir_em(argv[0], %s, %s, %s);",
                    cString(f.name), boxValueExpr(f.type_sema, "cgd_v."d ~ fn), clsVar);
        }

        return formatD(
            "%s {\n    (void)argc; (void)argv;\n%s\n    %s cgd_v = %s_new(%s);\n%s\n    return argv[0];\n}",
            managedProto, setup.join("\n"), sname, sname, callArgs.join(", "), assignFields.join("\n"));
    }

    /// Emite o thunk gerenciado `delegua_value cgd_fn_<id>(sz argc, delegua_value *argv)`
    /// que chama a função C nativa `cgd_nat_<id>`.
    dstring emitManagedThunk(FnDecl fn, dstring managedProto)
    {
        emitNativeFunctionImpl(fn, fn.ownerClass !is null && fn.ownerClass.isValueType ? fn.ownerClass : null);

        dstring[] setup;
        dstring[] callArgs;
        dstring[] cleanup;
        size_t argOffset = 0;

        if (fn.ownerClass !is null && fn.ownerClass.isValueType && !fn.isStatic)
        {
            dstring sname = valueStructName(fn.ownerClass);
            setup ~= formatD("    %s cgd_self_val = %s_unbox(argv[0]);", sname, sname);
            callArgs ~= "&cgd_self_val"d;
            argOffset = 1;
        }

        ParamMode[] modes = ownership !is null && (fn in ownership.paramModes) ? ownership.paramModes[fn] : null;
        foreach (size_t i, FnArg a; fn.args)
        {
            dstring ct = cTypeFor(a.type_sema);
            dstring aname = formatD("cgd_ta_%s", i);
            setup ~= formatD("    %s %s = %s;", ct, aname, unboxValueExpr(a.type_sema,
                    formatD("argv[%s]", i + argOffset)));
            bool byPtr = hasOwnershipResource(a.type_sema) && i < modes.length && modes[i] != ParamMode.Consume;
            if (byPtr)
            {
                callArgs ~= "&"d ~ aname;
                dstring df = dropFnForType(a.type_sema);
                if (df.length)
                    cleanup ~= formatD("    %s(&%s);", df, aname);
            }
            else
            {
                callArgs ~= aname;
            }
        }

        dstring retT = fn.fn == "destrutor"d ? "void"d : cTypeFor(fn.type_sema);
        dstring callExpr = formatD("%s(%s)", nativeFnName(fn), callArgs.join(", "));
        dstring bodyStr;
        if (retT == "void"d)
        {
            bodyStr = formatD("%s\n    %s;\n%s\n    return create_nulo();",
                    setup.join("\n"), callExpr, cleanup.join("\n"));
        }
        else
        {
            bodyStr = formatD("%s\n    %s cgd_res = %s;\n%s\n    return %s;",
                    setup.join("\n"), retT, callExpr, cleanup.join("\n"),
                    boxValueExpr(fn.type_sema, "cgd_res"d));
        }

        return formatD("%s {\n    (void)argc; (void)argv;\n%s\n}", managedProto, bodyStr);
    }

    private bool isParamPassedByPtr(Identifier id)
    {
        if (id is null || id.parameterRef is null || currentFn is null || ownership is null)
            return false;
        if (!hasOwnershipResource(id.parameterRef.type_sema))
            return false;
        ParamMode[]* modes = currentFn in ownership.paramModes;
        if (modes is null)
            return false;
        foreach (size_t i, FnArg a; currentFn.args)
            if (a is id.parameterRef && i < (*modes).length)
                return (*modes)[i] != ParamMode.Consume;
        return false;
    }

    private dstring compileNativeExpr(Node node, ref dstring[] pre)
    {
        if (node is null)
            return "0"d;
        switch (node.kind)
        {
            case NodeKind.IntLit:
            {
                long v = (cast(IntLit) node).value;
                if (v == long.min)
                    return "(INT64_MIN)"d;
                return formatD("INT64_C(%s)", v);
            }
            case NodeKind.DoubleLit:
            {
                double v = (cast(DoubleLit) node).value;
                return formatD("(%.17g)", v);
            }
            case NodeKind.BoolLit:
                return (cast(BoolLit) node).value ? "true"d : "false"d;
            case NodeKind.StringLit:
                return cString((cast(StringLit) node).value);
            case NodeKind.Identifier:
            {
                Identifier id = cast(Identifier) node;
                if (id.value == "isto"d && currentValueClass !is null)
                    return "(*cgd_self)"d;
                if (isParamPassedByPtr(id))
                    return formatD("(*%s_ptr)", cName(id.value));
                return cName(id.value);
            }
            case NodeKind.MemberExpr:
            {
                MemberExpr m = cast(MemberExpr) node;
                if (m.enumValue !is null)
                    return formatD("INT64_C(%s)", m.enumValue.value);
                Identifier rightId = cast(Identifier) m.right;
                if (Identifier leftId = cast(Identifier) m.left)
                {
                    if (leftId.value == "isto"d && currentValueClass !is null)
                        return formatD("cgd_self->%s", cName(rightId.value));
                    if (isParamPassedByPtr(leftId))
                        return formatD("%s_ptr->%s", cName(leftId.value), cName(rightId.value));
                }
                dstring lhs = compileNativeExpr(m.left, pre);
                return formatD("(%s).%s", lhs, cName(rightId.value));
            }
            case NodeKind.UnaryExpr:
            {
                UnaryExpr un = cast(UnaryExpr) node;
                if (un.resolvedOperator !is null)
                {
                    emitValueClassBodies(un.resolvedOperator.ownerClass);
                    dstring recv = compileNativeExpr(un.value, pre);
                    dstring tmp = freshTmp("cgd_uop");
                    dstring ct = cTypeFor(un.value.type_sema);
                    pre ~= formatD("    %s %s = %s;", ct, tmp, recv);
                    return formatD("%s(&%s)", nativeFnName(un.resolvedOperator), tmp);
                }
                dstring val = compileNativeExpr(un.value, pre);
                switch (un.op)
                {
                    case TokenKind.Minus:
                        return formatD("(-(%s))", val);
                    case TokenKind.Plus:
                        return formatD("(+(%s))", val);
                    case TokenKind.Bang:
                        return formatD("(!(%s))", val);
                    case TokenKind.BITNot:
                        return formatD("(~(%s))", val);
                    case TokenKind.PPlus:
                        return un.post ? formatD("((%s)++)", val) : formatD("(++(%s))", val);
                    case TokenKind.MMinus:
                        return un.post ? formatD("((%s)--)", val) : formatD("(--(%s))", val);
                    default:
                        return val;
                }
            }
            case NodeKind.BinaryExpr:
            {
                BinaryExpr bin = cast(BinaryExpr) node;
                if (bin.resolvedOperator !is null)
                {
                    emitValueClassBodies(bin.resolvedOperator.ownerClass);
                    dstring lhs = compileNativeExpr(bin.left, pre);
                    dstring rhs = compileNativeExpr(bin.right, pre);
                    dstring recvExpr = bin.operatorSwapped ? rhs : lhs;
                    dstring argExpr = bin.operatorSwapped ? lhs : rhs;
                    TypeSema recvType = bin.operatorSwapped ? bin.right.type_sema : bin.left.type_sema;
                    dstring tmp = freshTmp("cgd_op");
                    pre ~= formatD("    %s %s = %s;", cTypeFor(recvType), tmp, recvExpr);
                    return formatD("%s(&%s, %s)", nativeFnName(bin.resolvedOperator), tmp, argExpr);
                }
                dstring lhs = compileNativeExpr(bin.left, pre);
                dstring rhs = compileNativeExpr(bin.right, pre);
                if (bin.op == TokenKind.Pow)
                {
                    emittedMathInclude = true;
                    return formatD("pow((double)(%s), (double)(%s))", lhs, rhs);
                }
                dstring opStr;
                switch (bin.op)
                {
                    case TokenKind.Plus:
                        opStr = "+"d;
                        break;
                    case TokenKind.Minus:
                        opStr = "-"d;
                        break;
                    case TokenKind.Star:
                        opStr = "*"d;
                        break;
                    case TokenKind.Slash:
                    case TokenKind.IntDiv:
                        opStr = "/"d;
                        break;
                    case TokenKind.Modulo:
                        opStr = "%"d;
                        break;
                    case TokenKind.EEquals:
                        opStr = "=="d;
                        break;
                    case TokenKind.NEquals:
                        opStr = "!="d;
                        break;
                    case TokenKind.LThan:
                        opStr = "<"d;
                        break;
                    case TokenKind.LEquals:
                        opStr = "<="d;
                        break;
                    case TokenKind.GThan:
                        opStr = ">"d;
                        break;
                    case TokenKind.GEquals:
                        opStr = ">="d;
                        break;
                    case TokenKind.And:
                        opStr = "&&"d;
                        break;
                    case TokenKind.Or:
                        opStr = "||"d;
                        break;
                    case TokenKind.BITAnd:
                        opStr = "&"d;
                        break;
                    case TokenKind.BITOr:
                        opStr = "|"d;
                        break;
                    case TokenKind.BITXor:
                        opStr = "^"d;
                        break;
                    case TokenKind.BITSL:
                        opStr = "<<"d;
                        break;
                    case TokenKind.BITSR:
                        opStr = ">>"d;
                        break;
                    default:
                        opStr = "+"d;
                        break;
                }
                return formatD("((%s) %s (%s))", lhs, opStr, rhs);
            }
            case NodeKind.ConditionalExpr:
            {
                ConditionalExpr c = cast(ConditionalExpr) node;
                dstring cond = compileNativeExpr(c.condition, pre);
                dstring y = compileNativeExpr(c.yes, pre);
                dstring n = compileNativeExpr(c.no, pre);
                return formatD("((%s) ? (%s) : (%s))", cond, y, n);
            }
            case NodeKind.IndexExpr:
            {
                IndexExpr idx = cast(IndexExpr) node;
                if (idx.resolvedOperator !is null)
                {
                    emitValueClassBodies(idx.resolvedOperator.ownerClass);
                    dstring recv = compileNativeExpr(idx.value, pre);
                    dstring index = compileNativeExpr(idx.idx, pre);
                    dstring tmp = freshTmp("cgd_iop");
                    pre ~= formatD("    %s %s = %s;", cTypeFor(idx.value.type_sema), tmp, recv);
                    return formatD("%s(&%s, %s)", nativeFnName(idx.resolvedOperator), tmp, index);
                }
                if (TypeSemaNativeContainer nc = cast(TypeSemaNativeContainer) idx.value.type_sema)
                {
                    ensureContainer(nc);
                    dstring cn = "cgd_"d ~ typeMangleKey(nc).to!dstring;
                    dstring ptr = compileNativeAddr(idx.value, pre);
                    dstring index = compileNativeExpr(idx.idx, pre);
                    if (nc.containerKind == NativeContainerKind.FatiaNativa)
                        return formatD("%s_obter(%s, (size_t)(%s))", cn, compileNativeExpr(idx.value, pre), index);
                    if (nc.containerKind == NativeContainerKind.MapaNativo)
                        return compileMapKeyCall(nc, cn ~ "_obter"d, ptr, idx.idx, pre);
                    return formatD("%s_obter(%s, (size_t)(%s))", cn, ptr, index);
                }
                return "0"d;
            }
            case NodeKind.CallExpr:
                return compileNativeCall(cast(CallExpr) node, pre);
            default:
                return "0"d;
        }
    }

    private dstring compileNativeAddr(Node expr, ref dstring[] pre)
    {
        if (Identifier id = cast(Identifier) expr)
        {
            if (id.value == "isto"d && currentValueClass !is null)
                return "cgd_self"d;
            if (isParamPassedByPtr(id))
                return cName(id.value) ~ "_ptr"d;
            return "&"d ~ cName(id.value);
        }
        if (MemberExpr m = cast(MemberExpr) expr)
        {
            dstring base = compileNativeExpr(m, pre);
            return "&("d ~ base ~ ")"d;
        }
        dstring tmp = freshTmp("cgd_addr");
        dstring val = compileNativeExpr(expr, pre);
        pre ~= formatD("    %s %s = %s;", cTypeFor(expr.type_sema), tmp, val);
        return "&"d ~ tmp;
    }

    private dstring compileMapKeyCall(TypeSemaNativeContainer nc, dstring fnName, dstring mapPtr,
            Node keyNode, ref dstring[] pre, dstring extraArg = ""d)
    {
        bool strKey = nc.typeArgs.length >= 1 && cast(TypeSemaNativeContainer) nc.typeArgs[0] !is null
            && (cast(TypeSemaNativeContainer) nc.typeArgs[0]).containerKind == NativeContainerKind.StringNativa;
        bool isLookup = fnName.length >= 6 && (fnName[$ - 5 .. $] == "obter"d || fnName[$ - 6 .. $] == "contem"d
                || fnName[$ - 7 .. $] == "remover"d);
        if (strKey && cast(StringLit) keyNode !is null)
        {
            dstring lit = cString((cast(StringLit) keyNode).value);
            if (isLookup)
            {
                dstring tmp = freshTmp("cgd_mk");
                pre ~= formatD("    cgd_nstr %s = { (char *)%s, strlen(%s), 0 };", tmp, lit, lit);
                return extraArg.length ? formatD("%s(%s, %s, %s)", fnName, mapPtr, tmp, extraArg)
                    : formatD("%s(%s, %s)", fnName, mapPtr, tmp);
            }
            else
            {
                dstring kexpr = formatD("cgd_nstr_criar(%s)", lit);
                return extraArg.length ? formatD("%s(%s, %s, %s)", fnName, mapPtr, kexpr, extraArg)
                    : formatD("%s(%s, %s)", fnName, mapPtr, kexpr);
            }
        }
        dstring ke = compileNativeExpr(keyNode, pre);
        if (!isLookup && hasOwnershipResource(keyNode.type_sema))
            ke = moveExpr(keyNode, ke, pre);
        return extraArg.length ? formatD("%s(%s, %s, %s)", fnName, mapPtr, ke, extraArg)
            : formatD("%s(%s, %s)", fnName, mapPtr, ke);
    }

    private dstring moveExpr(Node node, dstring cExpr, ref dstring[] pre)
    {
        if (Identifier id = cast(Identifier) node)
        {
            if (hasOwnershipResource(id.type_sema) && !isParamPassedByPtr(id))
            {
                dstring tmp = freshTmp("cgd_mv");
                dstring ct = cTypeFor(id.type_sema);
                pre ~= formatD("    %s %s = %s; memset(&%s, 0, sizeof(%s));",
                        ct, tmp, cExpr, cName(id.value), cName(id.value));
                return tmp;
            }
        }
        return cExpr;
    }

    private dstring compileNativeCall(CallExpr call, ref dstring[] pre)
    {
        // 1) Cast explícito C: ci32(x), cf64(x), csize(x)...
        if (Identifier id = cast(Identifier) call.fn)
        {
            if (isNativeCastName(id.value) && call.args.length == 1)
            {
                dstring arg = compileNativeExpr(call.args[0], pre);
                dstring ct = cTypeFor(call.type_sema);
                return formatD("((%s)(%s))", ct, arg);
            }
            // 2) Construtor de container nativo: VetorNativo<T>(), MapaNativo<K, V>(), MatrizNativa<T>(r, c)
            if (id.functionRef is null && id.classRef is null)
            {
                if (TypeSemaNativeContainer nc = cast(TypeSemaNativeContainer) call.type_sema)
                {
                    ensureContainer(nc);
                    dstring cn = "cgd_"d ~ typeMangleKey(nc).to!dstring;
                    if (nc.containerKind == NativeContainerKind.MatrizNativa && call.args.length == 2)
                    {
                        dstring r = compileNativeExpr(call.args[0], pre);
                        dstring c = compileNativeExpr(call.args[1], pre);
                        return formatD("%s_novo((size_t)(%s), (size_t)(%s))", cn, r, c);
                    }
                    return formatD("%s_novo()", cn);
                }
            }
            // 3) Construtor de classe `@pilha`
            if (id.classRef !is null && id.classRef.isValueType)
            {
                emitValueClassBodies(id.classRef);
                dstring[] cargs;
                foreach (Node a; call.args)
                {
                    dstring e = compileNativeExpr(a, pre);
                    if (hasOwnershipResource(a.type_sema))
                        e = moveExpr(a, e, pre);
                    cargs ~= e;
                }
                return formatD("%s_new(%s)", valueStructName(id.classRef), cargs.join(", "));
            }
            // 4) Função livre `@nativo`
            if (id.functionRef !is null && id.functionRef.isNative)
            {
                emitNativeFunctionImpl(id.functionRef);
                ParamMode[] modes = ownership !is null && (id.functionRef in ownership.paramModes)
                    ? ownership.paramModes[id.functionRef] : null;
                dstring[] cargs;
                foreach (size_t i, Node a; call.args)
                {
                    bool byPtr = hasOwnershipResource(a.type_sema) && i < modes.length
                        && modes[i] != ParamMode.Consume;
                    if (byPtr)
                        cargs ~= compileNativeAddr(a, pre);
                    else
                    {
                        dstring e = compileNativeExpr(a, pre);
                        if (hasOwnershipResource(a.type_sema))
                            e = moveExpr(a, e, pre);
                        cargs ~= e;
                    }
                }
                return formatD("%s(%s)", nativeFnName(id.functionRef), cargs.join(", "));
            }
        }

        // 5) Chamada de membro (Matematica.*, containers nativos, métodos de `@pilha`, FFI C)
        if (MemberExpr m = cast(MemberExpr) call.fn)
        {
            Identifier leftId = cast(Identifier) m.left;
            Identifier rightId = cast(Identifier) m.right;
            if (leftId !is null && rightId !is null && isNativeMathIntrinsic(leftId.value, rightId.value))
            {
                emittedMathInclude = true;
                dstring[] cargs;
                foreach (Node a; call.args)
                    cargs ~= compileNativeExpr(a, pre);
                return emitMathCall(rightId.value, cargs);
            }

            // Métodos estáticos de containers nativos
            if (leftId !is null && rightId !is null && leftId.value == "StringNativa"d)
            {
                ensureStringNativa();
                if (rightId.value == "vazia"d)
                    return "cgd_nstr_vazia()"d;
                if (rightId.value == "criar"d && call.args.length == 1)
                {
                    if (StringLit sl = cast(StringLit) call.args[0])
                        return formatD("cgd_nstr_criar(%s)", cString(sl.value));
                    dstring arg = compileNativeExpr(call.args[0], pre);
                    return formatD("cgd_nstr_criar_dv(%s)", arg);
                }
            }
            if (leftId !is null && rightId !is null && cast(TypeExprGeneric) leftId.type_expr !is null)
            {
                if (TypeSemaNativeContainer nc = cast(TypeSemaNativeContainer) m.left.type_sema)
                {
                    ensureContainer(nc);
                    dstring cn = "cgd_"d ~ typeMangleKey(nc).to!dstring;
                    if (nc.containerKind == NativeContainerKind.OpcionalNativo)
                    {
                        if (rightId.value == "nenhum"d)
                            return formatD("%s_nenhum()", cn);
                        if (rightId.value == "algum"d && call.args.length == 1)
                        {
                            dstring e = compileNativeExpr(call.args[0], pre);
                            if (hasOwnershipResource(call.args[0].type_sema))
                                e = moveExpr(call.args[0], e, pre);
                            return formatD("%s_algum(%s)", cn, e);
                        }
                    }
                    if (nc.containerKind == NativeContainerKind.ResultadoNativo)
                    {
                        if (rightId.value == "ok"d && call.args.length == 1)
                        {
                            dstring e = compileNativeExpr(call.args[0], pre);
                            if (hasOwnershipResource(call.args[0].type_sema))
                                e = moveExpr(call.args[0], e, pre);
                            return formatD("%s_ok(%s)", cn, e);
                        }
                        if (rightId.value == "erro"d && call.args.length == 1)
                        {
                            dstring e = compileNativeExpr(call.args[0], pre);
                            if (hasOwnershipResource(call.args[0].type_sema))
                                e = moveExpr(call.args[0], e, pre);
                            return formatD("%s_erro(%s)", cn, e);
                        }
                    }
                }
            }

            // Métodos de instância de containers nativos
            if (m.left !is null && rightId !is null)
            {
                if (TypeSemaNativeContainer nc = cast(TypeSemaNativeContainer) m.left.type_sema)
                {
                    return compileNativeContainerMethodCall(nc, m.left, rightId.value, call.args, pre);
                }
            }

            // Construtor qualificado de `@pilha` (`Mod.Vetor2(...)`)
            if (rightId !is null && rightId.classRef !is null && rightId.classRef.isValueType)
            {
                emitValueClassBodies(rightId.classRef);
                dstring[] cargs;
                foreach (Node a; call.args)
                {
                    dstring e = compileNativeExpr(a, pre);
                    if (hasOwnershipResource(a.type_sema))
                        e = moveExpr(a, e, pre);
                    cargs ~= e;
                }
                return formatD("%s_new(%s)", valueStructName(rightId.classRef), cargs.join(", "));
            }

            // Método de classe `@pilha` ou função `@nativo` qualificada de módulo
            if (rightId !is null && rightId.functionRef !is null)
            {
                FnDecl target = rightId.functionRef;
                if (target.ownerClass !is null && target.ownerClass.isValueType)
                {
                    emitValueClassBodies(target.ownerClass);
                    dstring[] cargs;
                    if (!target.isStatic)
                        cargs ~= compileNativeAddr(m.left, pre);
                    foreach (Node a; call.args)
                    {
                        dstring e = compileNativeExpr(a, pre);
                        if (hasOwnershipResource(a.type_sema))
                            e = moveExpr(a, e, pre);
                        cargs ~= e;
                    }
                    return formatD("%s(%s)", nativeFnName(target), cargs.join(", "));
                }
                if (target.isNative)
                {
                    emitNativeFunctionImpl(target);
                    dstring[] cargs;
                    foreach (Node a; call.args)
                    {
                        dstring e = compileNativeExpr(a, pre);
                        if (hasOwnershipResource(a.type_sema))
                            e = moveExpr(a, e, pre);
                        cargs ~= e;
                    }
                    return formatD("%s(%s)", nativeFnName(target), cargs.join(", "));
                }
                if (target.ownerClass !is null && target.ownerClass.isForeign && !target.foreignManaged)
                {
                    dstring[] cargs;
                    foreach (Node a; call.args)
                        cargs ~= compileNativeExpr(a, pre);
                    return formatD("%s(%s)", target.foreignSymbol, cargs.join(", "));
                }
            }
        }
        return "0"d;
    }

    private dstring compileNativeContainerMethodCall(TypeSemaNativeContainer nc, Node receiver,
            dstring meth, Node[] args, ref dstring[] pre)
    {
        ensureContainer(nc);
        dstring cn = nc.containerKind == NativeContainerKind.StringNativa ? "cgd_nstr"d
            : nc.containerKind == NativeContainerKind.VisaoTexto ? "cgd_sv"d
            : ("cgd_"d ~ typeMangleKey(nc).to!dstring);

        final switch (nc.containerKind)
        {
            case NativeContainerKind.VetorNativo:
            {
                dstring ptr = compileNativeAddr(receiver, pre);
                switch (meth)
                {
                    case "tamanho":
                        return formatD("(%s)->len", ptr);
                    case "capacidade":
                        return formatD("(%s)->cap", ptr);
                    case "vazio":
                        return formatD("((%s)->len == 0)", ptr);
                    case "adicionar":
                    {
                        dstring v = compileNativeExpr(args[0], pre);
                        if (hasOwnershipResource(args[0].type_sema))
                            v = moveExpr(args[0], v, pre);
                        return formatD("%s_adicionar(%s, %s)", cn, ptr, v);
                    }
                    case "obter":
                        return formatD("%s_obter(%s, (size_t)(%s))", cn, ptr, compileNativeExpr(args[0], pre));
                    case "definir":
                    {
                        dstring i = compileNativeExpr(args[0], pre);
                        dstring v = compileNativeExpr(args[1], pre);
                        if (hasOwnershipResource(args[1].type_sema))
                            v = moveExpr(args[1], v, pre);
                        return formatD("%s_definir(%s, (size_t)(%s), %s)", cn, ptr, i, v);
                    }
                    case "removerUltimo":
                        return formatD("%s_remover_ultimo(%s)", cn, ptr);
                    case "limpar":
                        return formatD("%s_limpar(%s)", cn, ptr);
                    case "reservar":
                        return formatD("%s_reservar(%s, (size_t)(%s))", cn, ptr, compileNativeExpr(args[0], pre));
                    case "fatia":
                        return formatD("%s_fatia(%s, (size_t)(%s), (size_t)(%s))", cn, ptr,
                                compileNativeExpr(args[0], pre), compileNativeExpr(args[1], pre));
                    case "clonar":
                        return formatD("%s_clonar(%s)", cn, ptr);
                    case "liberar":
                        return formatD("%s_drop(%s)", cn, ptr);
                    case "paraVetor":
                        return formatD("%s_para_vetor(%s)", cn, ptr);
                    default:
                        return "0"d;
                }
            }
            case NativeContainerKind.FatiaNativa:
            {
                dstring val = compileNativeExpr(receiver, pre);
                switch (meth)
                {
                    case "tamanho":
                        return formatD("%s_tamanho(%s)", cn, val);
                    case "vazio":
                        return formatD("%s_vazio(%s)", cn, val);
                    case "obter":
                        return formatD("%s_obter(%s, (size_t)(%s))", cn, val, compileNativeExpr(args[0], pre));
                    case "fatia":
                        return formatD("%s_fatia(%s, (size_t)(%s), (size_t)(%s))", cn, val,
                                compileNativeExpr(args[0], pre), compileNativeExpr(args[1], pre));
                    default:
                        return "0"d;
                }
            }
            case NativeContainerKind.MapaNativo:
            {
                dstring ptr = compileNativeAddr(receiver, pre);
                switch (meth)
                {
                    case "tamanho":
                        return formatD("(%s)->len", ptr);
                    case "capacidade":
                        return formatD("(%s)->cap", ptr);
                    case "vazio":
                        return formatD("((%s)->len == 0)", ptr);
                    case "definir":
                    {
                        dstring v = compileNativeExpr(args[1], pre);
                        if (hasOwnershipResource(args[1].type_sema))
                            v = moveExpr(args[1], v, pre);
                        return compileMapKeyCall(nc, cn ~ "_definir"d, ptr, args[0], pre, v);
                    }
                    case "obter":
                        return compileMapKeyCall(nc, cn ~ "_obter"d, ptr, args[0], pre);
                    case "contem":
                    case "contém":
                        return compileMapKeyCall(nc, cn ~ "_contem"d, ptr, args[0], pre);
                    case "remover":
                        return compileMapKeyCall(nc, cn ~ "_remover"d, ptr, args[0], pre);
                    case "limpar":
                        return formatD("%s_limpar(%s)", cn, ptr);
                    case "clonar":
                        return formatD("%s_clonar(%s)", cn, ptr);
                    case "liberar":
                        return formatD("%s_drop(%s)", cn, ptr);
                    case "paraDicionario":
                        return formatD("%s_para_dicionario(%s)", cn, ptr);
                    default:
                        return "0"d;
                }
            }
            case NativeContainerKind.StringNativa:
            {
                dstring ptr = compileNativeAddr(receiver, pre);
                switch (meth)
                {
                    case "tamanho":
                        return formatD("(%s)->len", ptr);
                    case "capacidade":
                        return formatD("(%s)->cap", ptr);
                    case "vazia":
                        return formatD("((%s)->len == 0)", ptr);
                    case "anexar":
                    {
                        if (StringLit sl = cast(StringLit) args[0])
                            return formatD("cgd_nstr_anexar_cstr(%s, %s)", ptr, cString(sl.value));
                        dstring a = compileNativeAddr(args[0], pre);
                        return formatD("cgd_nstr_anexar_nstr(%s, %s)", ptr, a);
                    }
                    case "visao":
                    case "visão":
                        return formatD("cgd_nstr_visao(%s)", ptr);
                    case "igual":
                    {
                        if (StringLit sl = cast(StringLit) args[0])
                            return formatD("cgd_nstr_igual_cstr(%s, %s)", ptr, cString(sl.value));
                        return formatD("cgd_nstr_igual_nstr(%s, %s)", ptr, compileNativeAddr(args[0], pre));
                    }
                    case "limpar":
                        return formatD("cgd_nstr_limpar(%s)", ptr);
                    case "clonar":
                        return formatD("cgd_nstr_clonar(%s)", ptr);
                    case "liberar":
                        return formatD("cgd_nstr_drop(%s)", ptr);
                    case "paraTexto":
                        return formatD("cgd_nstr_para_texto(%s)", ptr);
                    default:
                        return "0"d;
                }
            }
            case NativeContainerKind.VisaoTexto:
            {
                dstring val = compileNativeExpr(receiver, pre);
                switch (meth)
                {
                    case "tamanho":
                        return formatD("cgd_sv_tamanho(%s)", val);
                    case "vazia":
                        return formatD("cgd_sv_vazia(%s)", val);
                    case "igual":
                    {
                        if (StringLit sl = cast(StringLit) args[0])
                            return formatD("cgd_sv_igual_cstr(%s, %s)", val, cString(sl.value));
                        return formatD("cgd_sv_igual(%s, %s)", val, compileNativeExpr(args[0], pre));
                    }
                    case "comecaCom":
                    {
                        if (StringLit sl = cast(StringLit) args[0])
                            return formatD("cgd_sv_comeca_com(%s, %s)", val, cString(sl.value));
                        return "false"d;
                    }
                    case "paraTexto":
                        return formatD("cgd_sv_para_texto(%s)", val);
                    default:
                        return "0"d;
                }
            }
            case NativeContainerKind.OpcionalNativo:
            {
                dstring val = compileNativeExpr(receiver, pre);
                switch (meth)
                {
                    case "temValor":
                        return formatD("%s_tem_valor(%s)", cn, val);
                    case "ehNenhum":
                        return formatD("%s_eh_nenhum(%s)", cn, val);
                    case "valor":
                        return formatD("%s_valor(%s)", cn, val);
                    case "valorOu":
                        return formatD("%s_valor_ou(%s, %s)", cn, val, compileNativeExpr(args[0], pre));
                    default:
                        return "0"d;
                }
            }
            case NativeContainerKind.ResultadoNativo:
            {
                dstring val = compileNativeExpr(receiver, pre);
                switch (meth)
                {
                    case "ehOk":
                        return formatD("%s_eh_ok(%s)", cn, val);
                    case "ehErro":
                        return formatD("%s_eh_erro(%s)", cn, val);
                    case "valor":
                        return formatD("%s_valor(%s)", cn, val);
                    case "erro":
                        return formatD("%s_erro_val(%s)", cn, val);
                    case "valorOu":
                        return formatD("%s_valor_ou(%s, %s)", cn, val, compileNativeExpr(args[0], pre));
                    default:
                        return "0"d;
                }
            }
            case NativeContainerKind.MatrizNativa:
            {
                dstring ptr = compileNativeAddr(receiver, pre);
                switch (meth)
                {
                    case "linhas":
                        return formatD("(%s)->rows", ptr);
                    case "colunas":
                        return formatD("(%s)->cols", ptr);
                    case "tamanho":
                        return formatD("((%s)->rows * (%s)->cols)", ptr, ptr);
                    case "obter":
                        return formatD("%s_obter(%s, (size_t)(%s), (size_t)(%s))", cn, ptr,
                                compileNativeExpr(args[0], pre), compileNativeExpr(args[1], pre));
                    case "definir":
                        return formatD("%s_definir(%s, (size_t)(%s), (size_t)(%s), %s)", cn, ptr,
                                compileNativeExpr(args[0], pre), compileNativeExpr(args[1], pre),
                                compileNativeExpr(args[2], pre));
                    case "transpor":
                        return formatD("%s_transpor(%s)", cn, ptr);
                    case "multiplicar":
                        return formatD("%s_multiplicar(%s, %s)", cn, ptr, compileNativeAddr(args[0], pre));
                    case "clonar":
                        return formatD("%s_clonar(%s)", cn, ptr);
                    case "liberar":
                        return formatD("%s_drop(%s)", cn, ptr);
                    default:
                        return "0"d;
                }
            }
        }
    }

    private dstring emitMathCall(dstring fn, dstring[] args)
    {
        switch (fn)
        {
            case "raiz":
            case "raizQuadrada":
                return formatD("sqrt((double)(%s))", args[0]);
            case "seno":
                return formatD("sin((double)(%s))", args[0]);
            case "cosseno":
                return formatD("cos((double)(%s))", args[0]);
            case "tangente":
                return formatD("tan((double)(%s))", args[0]);
            case "absoluto":
                return formatD("fabs((double)(%s))", args[0]);
            case "piso":
                return formatD("floor((double)(%s))", args[0]);
            case "teto":
                return formatD("ceil((double)(%s))", args[0]);
            case "arredondar":
                return formatD("round((double)(%s))", args[0]);
            case "potencia":
            case "potência":
                return formatD("pow((double)(%s), (double)(%s))", args[0], args[1]);
            case "logaritmo":
                return formatD("log((double)(%s))", args[0]);
            case "exponencial":
                return formatD("exp((double)(%s))", args[0]);
            case "minimo":
            case "mínimo":
                return formatD("fmin((double)(%s), (double)(%s))", args[0], args[1]);
            case "maximo":
            case "máximo":
                return formatD("fmax((double)(%s), (double)(%s))", args[0], args[1]);
            case "arcoSeno":
                return formatD("asin((double)(%s))", args[0]);
            case "arcoCosseno":
                return formatD("acos((double)(%s))", args[0]);
            case "arcoTangente":
                return formatD("atan((double)(%s))", args[0]);
            case "arcoTangente2":
                return formatD("atan2((double)(%s), (double)(%s))", args[0], args[1]);
            default:
                return "0.0"d;
        }
    }

    private dstring debugLineDirective(Node node)
    {
        if (!emitDebugLines || node is null || node.pos is null || !node.pos.filename.length || node.pos.start.line == 0)
            return ""d;
        import std.path : absolutePath, asNormalizedPath;

        string absFile = absolutePath(node.pos.filename).asNormalizedPath.to!string;
        dstring escaped;
        foreach (char ch; absFile)
        {
            if (ch == '\\' || ch == '"')
                escaped ~= '\\';
            escaped ~= ch;
        }
        return formatD("\n#line %s \"%s\"\n", node.pos.start.line, escaped);
    }

    private dstring compileNativeStmt(Node node)
    {
        if (node is null)
            return ""d;
        dstring bodyCode = compileNativeStmtInner(node);
        if (!bodyCode.length)
            return ""d;
        dstring lineDir = debugLineDirective(node);
        return lineDir.length ? lineDir ~ bodyCode : bodyCode;
    }

    private dstring compileNativeStmtInner(Node node)
    {
        if (node is null)
            return ""d;
        dstring[] pre;
        switch (node.kind)
        {
            case NodeKind.VarDecl:
            {
                VarDecl v = cast(VarDecl) node;
                if (v.isEnum)
                    return ""d;
                dstring ct = cTypeFor(v.type_sema);
                dstring vn = cName(v.name);
                if (v.uninitialized || v.value is null)
                {
                    registerDrop(vn, v.type_sema);
                    return formatD("    %s %s; memset(&%s, 0, sizeof(%s));", ct, vn, vn, vn);
                }
                dstring rhs = compileNativeExpr(v.value, pre);
                if (hasOwnershipResource(v.type_sema))
                    rhs = moveExpr(v.value, rhs, pre);
                registerDrop(vn, v.type_sema);
                dstring decl = formatD("    %s %s = %s;", ct, vn, rhs);
                return pre.length ? pre.join("\n") ~ "\n"d ~ decl : decl;
            }
            case NodeKind.AssignStmt:
            {
                AssignStmt ass = cast(AssignStmt) node;
                if (ass.resolvedIndexSetOperator !is null)
                {
                    IndexExpr idx = cast(IndexExpr) ass.left;
                    emitValueClassBodies(ass.resolvedIndexSetOperator.ownerClass);
                    dstring recvPtr = compileNativeAddr(idx.value, pre);
                    dstring index = compileNativeExpr(idx.idx, pre);
                    dstring val = compileNativeExpr(ass.value, pre);
                    dstring stmt = formatD("    %s(%s, %s, %s);",
                            nativeFnName(ass.resolvedIndexSetOperator), recvPtr, index, val);
                    return pre.length ? pre.join("\n") ~ "\n"d ~ stmt : stmt;
                }
                if (IndexExpr idx = cast(IndexExpr) ass.left)
                {
                    if (TypeSemaNativeContainer nc = cast(TypeSemaNativeContainer) idx.value.type_sema)
                    {
                        ensureContainer(nc);
                        dstring cn = "cgd_"d ~ typeMangleKey(nc).to!dstring;
                        dstring ptr = compileNativeAddr(idx.value, pre);
                        dstring val = compileNativeExpr(ass.value, pre);
                        if (hasOwnershipResource(ass.value.type_sema))
                            val = moveExpr(ass.value, val, pre);
                        dstring call;
                        if (nc.containerKind == NativeContainerKind.MapaNativo)
                            call = compileMapKeyCall(nc, cn ~ "_definir"d, ptr, idx.idx, pre, val);
                        else
                            call = formatD("%s_definir(%s, (size_t)(%s), %s)", cn, ptr,
                                    compileNativeExpr(idx.idx, pre), val);
                        return pre.length ? pre.join("\n") ~ "\n    "d ~ call ~ ";"d : "    "d ~ call ~ ";"d;
                    }
                }
                dstring lhs = compileNativeExpr(ass.left, pre);
                dstring rhs = compileNativeExpr(ass.value, pre);
                if (ass.op == TokenKind.Equals && hasOwnershipResource(ass.left.type_sema))
                {
                    rhs = moveExpr(ass.value, rhs, pre);
                    dstring df = dropFnForType(ass.left.type_sema);
                    if (df.length)
                        pre ~= formatD("    %s(&(%s));", df, lhs);
                }
                dstring opStr = "="d;
                switch (ass.op)
                {
                    case TokenKind.PlusAssign:
                        opStr = "+="d;
                        break;
                    case TokenKind.MinusAssign:
                        opStr = "-="d;
                        break;
                    case TokenKind.MulAssign:
                        opStr = "*="d;
                        break;
                    case TokenKind.DivAssign:
                        opStr = "/="d;
                        break;
                    case TokenKind.ModAssign:
                        opStr = "%="d;
                        break;
                    default:
                        break;
                }
                dstring stmt = formatD("    %s %s %s;", lhs, opStr, rhs);
                return pre.length ? pre.join("\n") ~ "\n"d ~ stmt : stmt;
            }
            case NodeKind.ReturnStmt:
            {
                ReturnStmt ret = cast(ReturnStmt) node;
                if (ret.val is null || (currentFn !is null && currentFn.fn == "destrutor"d))
                {
                    dstring drops = emitDropsFrom(0);
                    return drops.length ? drops ~ "\n    return;"d : "    return;"d;
                }
                dstring skipVar = ""d;
                if (Identifier retId = cast(Identifier) ret.val)
                    if (hasOwnershipResource(retId.type_sema))
                        skipVar = cName(retId.value);
                dstring val = compileNativeExpr(ret.val, pre);
                dstring retTmp = freshTmp("cgd_ret");
                dstring retT = cTypeFor(currentFn !is null ? currentFn.type_sema : ret.val.type_sema);
                if (retT == "void"d)
                {
                    dstring drops = emitDropsFrom(0);
                    dstring s = (pre.length ? pre.join("\n") ~ "\n"d : ""d)
                        ~ formatD("    (void)(%s);\n", val) ~ drops ~ "\n    return;";
                    return s;
                }
                dstring drops = emitDropsFrom(0, skipVar);
                dstring[] lines = pre;
                lines ~= formatD("    %s %s = %s;", retT, retTmp, val);
                if (drops.length)
                    lines ~= drops;
                lines ~= formatD("    return %s;", retTmp);
                return lines.join("\n");
            }
            case NodeKind.IfStmt:
                return compileNativeIf(cast(IfStmt) node);
            case NodeKind.WhileStmt:
            {
                WhileStmt w = cast(WhileStmt) node;
                dstring cond = compileNativeExpr(w.expr, pre);
                size_t bodyDepth = dropScopes.length;
                pushDropScope();
                loopStack ~= LoopContext(bodyDepth, ""d, false, false);
                dstring[] bodyLines;
                foreach (Node st; w.body)
                    bodyLines ~= compileNativeStmt(st);
                loopStack.length--;
                dstring drops = emitDropsFrom(bodyDepth);
                if (drops.length)
                    bodyLines ~= drops;
                popDropScope();
                if (pre.length)
                    return formatD("    while (1) {\n%s\n    if (!(%s)) break;\n%s\n    }",
                            pre.join("\n"), cond, bodyLines.join("\n"));
                return formatD("    while (%s) {\n%s\n    }", cond, bodyLines.join("\n"));
            }
            case NodeKind.ForStmt:
            {
                ForStmt f = cast(ForStmt) node;
                pushDropScope();
                dstring initStr = f.init !is null ? compileNativeStmt(f.init) : ""d;
                dstring[] condPre;
                dstring condStr = f.condition !is null ? compileNativeExpr(f.condition, condPre) : "1"d;
                size_t bodyDepth = dropScopes.length;
                pushDropScope();
                dstring contLbl = freshTmp("cgd_cont");
                loopStack ~= LoopContext(bodyDepth, contLbl, true, false);
                dstring[] bodyLines;
                foreach (Node st; f.body)
                    bodyLines ~= compileNativeStmt(st);
                bool needContLbl = loopStack[$ - 1].usedContinue;
                loopStack.length--;
                dstring innerDrops = emitDropsFrom(bodyDepth);
                if (innerDrops.length)
                    bodyLines ~= innerDrops;
                popDropScope();
                dstring stepStr = f.step !is null ? compileNativeStmt(f.step) : ""d;
                dstring outerDrops = emitDropsFrom(dropScopes.length - 1);
                popDropScope();
                dstring contPart = needContLbl ? formatD("    %s:;\n", contLbl) : ""d;
                return formatD("    {\n%s\n    for (; %s; ) {\n%s\n%s\n%s%s\n    }\n%s\n    }",
                        initStr, condPre.length ? "1"d : condStr,
                        condPre.length ? (condPre.join("\n") ~ formatD("\n    if (!(%s)) break;", condStr)) : ""d,
                        bodyLines.join("\n"), contPart, stepStr, outerDrops);
            }
            case NodeKind.DoStmt:
            {
                DoStmt d = cast(DoStmt) node;
                size_t bodyDepth = dropScopes.length;
                pushDropScope();
                loopStack ~= LoopContext(bodyDepth, ""d, false, false);
                dstring[] bodyLines;
                foreach (Node st; d.body)
                    bodyLines ~= compileNativeStmt(st);
                loopStack.length--;
                dstring drops = emitDropsFrom(bodyDepth);
                if (drops.length)
                    bodyLines ~= drops;
                popDropScope();
                dstring cond = compileNativeExpr(d.condition, pre);
                return formatD("    do {\n%s\n%s\n    } while (%s);",
                        bodyLines.join("\n"), pre.join("\n"), cond);
            }
            case NodeKind.EachStmt:
            {
                EachStmt e = cast(EachStmt) node;
                TypeSemaNativeContainer nc = cast(TypeSemaNativeContainer) e.iterable.type_sema;
                if (nc is null)
                    return ""d;
                ensureContainer(nc);
                dstring elemT = cTypeFor(nc.typeArgs[0]);
                dstring idxVar = freshTmp("cgd_i");
                dstring lenExpr;
                dstring elemExpr;
                if (nc.containerKind == NativeContainerKind.FatiaNativa)
                {
                    dstring sv = compileNativeExpr(e.iterable, pre);
                    dstring stmp = freshTmp("cgd_sl");
                    pre ~= formatD("    %s %s = %s;", cTypeFor(nc), stmp, sv);
                    lenExpr = stmp ~ ".len"d;
                    elemExpr = formatD("%s.data[%s]", stmp, idxVar);
                }
                else
                {
                    dstring ptr = compileNativeAddr(e.iterable, pre);
                    lenExpr = formatD("(%s)->len", ptr);
                    elemExpr = formatD("(%s)->data[%s]", ptr, idxVar);
                }
                size_t bodyDepth = dropScopes.length;
                pushDropScope();
                loopStack ~= LoopContext(bodyDepth, ""d, false, false);
                dstring[] bodyLines;
                bodyLines ~= formatD("    %s %s = %s;", elemT, cName(e.name), elemExpr);
                foreach (Node st; e.body)
                    bodyLines ~= compileNativeStmt(st);
                loopStack.length--;
                dstring drops = emitDropsFrom(bodyDepth);
                if (drops.length)
                    bodyLines ~= drops;
                popDropScope();
                return formatD("%s\n    for (size_t %s = 0; %s < %s; %s++) {\n%s\n    }",
                        pre.join("\n"), idxVar, idxVar, lenExpr, idxVar, bodyLines.join("\n"));
            }
            case NodeKind.SwitchStmt:
            {
                SwitchStmt sw = cast(SwitchStmt) node;
                dstring disc = compileNativeExpr(sw.value, pre);
                dstring dtmp = freshTmp("cgd_sw");
                dstring[] lines = pre;
                lines ~= formatD("    %s %s = %s;", cTypeFor(sw.value.type_sema), dtmp, disc);
                bool first = true;
                foreach (SwitchCase c; sw.cases)
                {
                    dstring[] conds;
                    foreach (Node v; c.values)
                    {
                        dstring[] vpre;
                        dstring ve = compileNativeExpr(v, vpre);
                        conds ~= formatD("(%s == (%s))", dtmp, ve);
                    }
                    pushDropScope();
                    dstring[] cbody;
                    foreach (Node st; c.body)
                        cbody ~= compileNativeStmt(st);
                    dstring cdrops = emitDropsFrom(dropScopes.length - 1);
                    if (cdrops.length)
                        cbody ~= cdrops;
                    popDropScope();
                    lines ~= formatD("    %sif (%s) {\n%s\n    }", first ? ""d : "else "d,
                            conds.join(" || "), cbody.join("\n"));
                    first = false;
                }
                if (sw.fallback.length)
                {
                    pushDropScope();
                    dstring[] fbody;
                    foreach (Node st; sw.fallback)
                        fbody ~= compileNativeStmt(st);
                    dstring fdrops = emitDropsFrom(dropScopes.length - 1);
                    if (fdrops.length)
                        fbody ~= fdrops;
                    popDropScope();
                    lines ~= formatD("    %s{\n%s\n    }", first ? ""d : "else "d, fbody.join("\n"));
                }
                return lines.join("\n");
            }
            case NodeKind.BlockStmt:
            {
                BlockStmt blk = cast(BlockStmt) node;
                pushDropScope();
                dstring[] lines;
                foreach (Node st; blk.body)
                    lines ~= compileNativeStmt(st);
                dstring drops = emitDropsFrom(dropScopes.length - 1);
                if (drops.length)
                    lines ~= drops;
                popDropScope();
                return "{\n"d ~ lines.join("\n") ~ "\n}"d;
            }
            case NodeKind.SequenceStmt:
            {
                dstring[] lines;
                foreach (Node st; (cast(SequenceStmt) node).body)
                    lines ~= compileNativeStmt(st);
                return lines.join("\n");
            }
            case NodeKind.BreakStmt:
            {
                if (loopStack.length > 0)
                {
                    dstring drops = emitDropsFrom(loopStack[$ - 1].bodyDropDepth);
                    return drops.length ? drops ~ "\n    break;"d : "    break;"d;
                }
                return "    break;"d;
            }
            case NodeKind.ContinueStmt:
            {
                if (loopStack.length > 0)
                {
                    dstring drops = emitDropsFrom(loopStack[$ - 1].bodyDropDepth);
                    if (loopStack[$ - 1].hasContinueTarget)
                    {
                        loopStack[$ - 1].usedContinue = true;
                        dstring jump = formatD("    goto %s;", loopStack[$ - 1].continueLabel);
                        return drops.length ? drops ~ "\n"d ~ jump : jump;
                    }
                    return drops.length ? drops ~ "\n    continue;"d : "    continue;"d;
                }
                return "    continue;"d;
            }
            default:
            {
                dstring e = compileNativeExpr(node, pre);
                dstring stmt = formatD("    (void)(%s);", e);
                return pre.length ? pre.join("\n") ~ "\n"d ~ stmt : stmt;
            }
        }
    }

    private dstring compileNativeIf(IfStmt branch)
    {
        if (branch is null)
            return ""d;
        if (branch.expr is null)
        {
            pushDropScope();
            dstring[] bodyLines;
            foreach (Node st; branch.body)
                bodyLines ~= compileNativeStmt(st);
            dstring drops = emitDropsFrom(dropScopes.length - 1);
            if (drops.length)
                bodyLines ~= drops;
            popDropScope();
            return "{\n"d ~ bodyLines.join("\n") ~ "\n}"d;
        }
        dstring[] pre;
        dstring cond = compileNativeExpr(branch.expr, pre);
        pushDropScope();
        dstring[] thenLines;
        foreach (Node st; branch.body)
            thenLines ~= compileNativeStmt(st);
        dstring drops = emitDropsFrom(dropScopes.length - 1);
        if (drops.length)
            thenLines ~= drops;
        popDropScope();
        dstring res = (pre.length ? pre.join("\n") ~ "\n"d : ""d)
            ~ formatD("    if (!!(%s)) {\n%s\n    }", cond, thenLines.join("\n"));
        if (branch._else !is null)
            res ~= " else "d ~ compileNativeIf(branch._else);
        return res;
    }

    void addExtraDef(dstring defCode)
    {
        fnDefs ~= defCode;
    }

    dstring emitTypePreamble() const
    {
        dstring outStr = ""d;
        if (emittedMathInclude)
            outStr ~= "#include <math.h>\n"d;
        if (typeDecls.length)
            outStr ~= typeDecls.join("\n") ~ "\n"d;
        return outStr;
    }

    dstring emitPrototypes() const
    {
        if (!protoDecls.length)
            return ""d;
        return protoDecls.join("\n") ~ "\n"d;
    }

    dstring emitPreamble() const
    {
        return emitTypePreamble() ~ emitPrototypes();
    }

    dstring emitDefinitions() const
    {
        if (!fnDefs.length)
            return ""d;
        return "\n"d ~ fnDefs.join("\n") ~ "\n"d;
    }
}
