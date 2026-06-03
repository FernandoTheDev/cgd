#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>

void __cgd_erro_interno(char *msg)
{
    printf("CGD RUNTIME ERRO: %s\n", msg);
    exit(1);
}

typedef struct _CGD_String CGD_String;
typedef struct _CGD_Int CGD_Int;
typedef struct _CGD_Double CGD_Double;
typedef struct _CGD_Bool CGD_Bool;

typedef struct _CGD_Value CGD_Value;
typedef enum _CGD_ValueKind CGD_ValueKind;

typedef struct _CGD_String
{
    char *ptr;
    size_t len;
} CGD_String;

typedef struct _CGD_Int
{
    long val;
} CGD_Int;

typedef struct _CGD_Double
{
    double val;
} CGD_Double;

typedef struct _CGD_Bool
{
    int val;
} CGD_Bool;

typedef enum _CGD_ValueType
{
    CGD_ValueType_Bool,
    CGD_ValueType_Int,
    CGD_ValueType_Double,
    CGD_ValueType_String,
} CGD_ValueType;

typedef struct _CGD_Value
{
    CGD_ValueType type;
    union
    {
        CGD_Int i;
        CGD_String s;
        CGD_Double d;
        CGD_Bool b;
    };
} CGD_Value;

static inline CGD_Value cgd_int(long val)
{
    CGD_Value v;
    v.type = CGD_ValueType_Int;
    v.i.val = val;
    return v;
}

static inline CGD_Value cgd_double(double val)
{
    CGD_Value v;
    v.type = CGD_ValueType_Double;
    v.d.val = val;
    return v;
}

static inline CGD_Value cgd_str(const char *ptr)
{
    CGD_Value v;
    v.type = CGD_ValueType_String;
    v.s.ptr = (char *)ptr;
    v.s.len = strlen(ptr);
    return v;
}

static inline CGD_ValueType __cgd_maior_tipo(CGD_ValueType l, CGD_ValueType r)
{
    return l > r ? l : r;
}

int __cgd_is_truthy(CGD_Value val)
{
    switch (val.type)
    {
    case CGD_ValueType_Bool:
        return (bool)val.b.val;
    case CGD_ValueType_Double:
        return (bool)val.d.val;
    case CGD_ValueType_Int:
        return (bool)val.i.val;
    case CGD_ValueType_String:
        return false;
    default:
        return false;
    }
}

CGD_Value __cgd_cast(CGD_Value from, CGD_ValueType to)
{
    if (from.type == to)
        return from;

    CGD_ValueType fromType = from.type;
    // assume que o cast dará certo, se der erro o sistema irá falhar em runtime
    from.type = to;

    switch (fromType)
    {
    case CGD_ValueType_Int:
        switch (to)
        {
        case CGD_ValueType_Double:
            from.d.val = (double)from.i.val;
            break;
        case CGD_ValueType_Bool:
            from.b.val = from.i.val == 0 ? 0 : 1;
            break;
        default:
            __cgd_erro_interno("Erro ao realizar cast de um inteiro.");
            break;
        }
        break;
    case CGD_ValueType_Double:
        switch (to)
        {
        case CGD_ValueType_Int:
            from.i.val = (long)from.d.val;
            break;
        case CGD_ValueType_Bool:
            from.b.val = from.d.val == 0.0 ? 0 : 1;
            break;
        default:
            __cgd_erro_interno("Erro ao realizar cast de um inteiro.");
            break;
        }
        break;
    case CGD_ValueType_Bool:
        switch (to)
        {
        case CGD_ValueType_Int:
            from.i.val = (long)from.b.val;
            break;
        case CGD_ValueType_Double:
            from.d.val = (double)from.b.val;
            break;
        default:
            __cgd_erro_interno("Erro ao realizar cast de um inteiro.");
            break;
        }
        break;
    default:
        __cgd_erro_interno("Erro ao realizar cast.");
        break;
    }
    return from;
}

CGD_Value __cgd_binary_op_add(CGD_Value l, CGD_Value r)
{
    if (l.type == CGD_ValueType_Bool || l.type == CGD_ValueType_String)
        __cgd_erro_interno("Nao foi possivel somar esses tipos.");

    // se os tipos forem diferentes faz cast manual pra fast path
    CGD_ValueType t = l.type;
    if (l.type != r.type)
    {
        t = __cgd_maior_tipo(l.type, r.type);
        if (l.type != t)
            l = __cgd_cast(l, t);
        if (r.type != t)
            r = __cgd_cast(r, t);
    }

    CGD_Value val = (CGD_Value){.type = t};

    if (t == CGD_ValueType_Double)
    {
        val.d.val = l.d.val + r.d.val;
        return val;
    }

    if (t == CGD_ValueType_Int)
    {
        val.i.val = l.i.val + r.i.val;
        return val;
    }

    __cgd_erro_interno("Erro na função de soma.");
    return val;
}

CGD_Value __cgd_binary_op_mul(CGD_Value l, CGD_Value r)
{
    if (l.type == CGD_ValueType_Bool || l.type == CGD_ValueType_String)
        __cgd_erro_interno("Nao foi possivel operar com esses tipos.");

    // se os tipos forem diferentes faz cast manual pra fast path
    CGD_ValueType t = l.type;
    if (l.type != r.type)
    {
        t = __cgd_maior_tipo(l.type, r.type);
        if (l.type != t)
            l = __cgd_cast(l, t);
        if (r.type != t)
            r = __cgd_cast(r, t);
    }

    CGD_Value val = (CGD_Value){.type = t};

    if (t == CGD_ValueType_Double)
    {
        val.d.val = l.d.val * r.d.val;
        return val;
    }

    if (t == CGD_ValueType_Int)
    {
        val.i.val = l.i.val * r.i.val;
        return val;
    }

    __cgd_erro_interno("Erro na função de mul.");
    return val;
}

CGD_Value __cgd_binary_op_minus(CGD_Value l, CGD_Value r)
{
    if (l.type == CGD_ValueType_Bool || l.type == CGD_ValueType_String)
        __cgd_erro_interno("Nao foi possivel operar com esses tipos.");

    // se os tipos forem diferentes faz cast manual pra fast path
    CGD_ValueType t = l.type;
    if (l.type != r.type)
    {
        t = __cgd_maior_tipo(l.type, r.type);
        if (l.type != t)
            l = __cgd_cast(l, t);
        if (r.type != t)
            r = __cgd_cast(r, t);
    }

    CGD_Value val = (CGD_Value){.type = t};

    if (t == CGD_ValueType_Double)
    {
        val.d.val = l.d.val - r.d.val;
        return val;
    }

    if (t == CGD_ValueType_Int)
    {
        val.i.val = l.i.val - r.i.val;
        return val;
    }

    __cgd_erro_interno("Erro na função de sub.");
    return val;
}

CGD_Value __cgd_binary_op_ee(CGD_Value l, CGD_Value r)
{
    // se os tipos forem diferentes faz cast manual pra fast path
    CGD_ValueType t = l.type;
    if (l.type != r.type)
    {
        t = __cgd_maior_tipo(l.type, r.type);
        if (l.type != t)
            l = __cgd_cast(l, t);
        if (r.type != t)
            r = __cgd_cast(r, t);
    }

    CGD_Value val = (CGD_Value){.type = CGD_ValueType_Bool, .b.val = 0};

    if (t == CGD_ValueType_Double)
    {
        val.b.val = (bool)(l.d.val == r.d.val);
        return val;
    }

    if (t == CGD_ValueType_Int)
    {
        val.b.val = (bool)(l.i.val == r.i.val);
        return val;
    }

    if (t == CGD_ValueType_Bool)
    {
        val.b.val = l.b.val == r.b.val;
        return val;
    }

    __cgd_erro_interno("Erro na função de ==.");
    return val;
}

CGD_Value __cgd_binary_op_lt(CGD_Value l, CGD_Value r, int equals)
{
    if (l.type == CGD_ValueType_Bool || l.type == CGD_ValueType_String)
        __cgd_erro_interno("Nao foi possivel operar com esses tipos.");

    // se os tipos forem diferentes faz cast manual pra fast path
    CGD_ValueType t = l.type;
    if (l.type != r.type)
    {
        t = __cgd_maior_tipo(l.type, r.type);
        if (l.type != t)
            l = __cgd_cast(l, t);
        if (r.type != t)
            r = __cgd_cast(r, t);
    }

    CGD_Value val = (CGD_Value){.type = CGD_ValueType_Bool, .b.val = 0};

    if (t == CGD_ValueType_Double)
    {
        if (equals)
            val.b.val = (bool)(l.d.val <= r.d.val);
        else
            val.b.val = (bool)(l.d.val < r.d.val);
        return val;
    }

    if (t == CGD_ValueType_Int)
    {
        if (equals)
            val.b.val = (bool)(l.i.val <= r.i.val);
        else
            val.b.val = (bool)(l.i.val < r.i.val);
        return val;
    }

    if (t == CGD_ValueType_Bool)
    {
        if (equals)
            val.b.val = l.b.val <= r.b.val;
        else
            val.b.val = l.b.val < r.b.val;
        return val;
    }

    __cgd_erro_interno("Erro na função de < | <=.");
    return val;
}

CGD_Value __cgd_binary_op_gt(CGD_Value l, CGD_Value r, int equals)
{
    if (l.type == CGD_ValueType_Bool || l.type == CGD_ValueType_String)
        __cgd_erro_interno("Nao foi possivel operar com esses tipos.");

    // se os tipos forem diferentes faz cast manual pra fast path
    CGD_ValueType t = l.type;
    if (l.type != r.type)
    {
        t = __cgd_maior_tipo(l.type, r.type);
        if (l.type != t)
            l = __cgd_cast(l, t);
        if (r.type != t)
            r = __cgd_cast(r, t);
    }

    CGD_Value val = (CGD_Value){.type = CGD_ValueType_Bool, .b.val = 0};

    if (t == CGD_ValueType_Double)
    {
        if (equals)
            val.b.val = (bool)(l.d.val >= r.d.val);
        else
            val.b.val = (bool)(l.d.val > r.d.val);
        return val;
    }

    if (t == CGD_ValueType_Int)
    {
        if (equals)
            val.b.val = (bool)(l.i.val >= r.i.val);
        else
            val.b.val = (bool)(l.i.val > r.i.val);
        return val;
    }

    if (t == CGD_ValueType_Bool)
    {
        if (equals)
            val.b.val = l.b.val >= r.b.val;
        else
            val.b.val = l.b.val > r.b.val;
        return val;
    }

    __cgd_erro_interno("Erro na função de > | >=.");
    return val;
}

void cgd_escreva(CGD_Value v)
{
    switch (v.type)
    {
    case CGD_ValueType_Int:
        printf("%ld\n", v.i.val);
        break;
    case CGD_ValueType_Double:
        printf("%g\n", v.d.val);
        break;
    case CGD_ValueType_String:
        printf("%.*s\n", (int)v.s.len, v.s.ptr);
        break;
    case CGD_ValueType_Bool:
        printf("%s\n", v.b.val ? "verdadeiro" : "falso");
        break;
    }
}

int main(int argc, char **argv);
void cgd_main(void);

int main(int argc, char **argv)
{
    cgd_main();
    return 0;
}
