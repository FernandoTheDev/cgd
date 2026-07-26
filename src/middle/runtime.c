#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <stddef.h>
#include <stdint.h>
#include <assert.h>
#include <stdio.h>

#define INIT_CAP 32
#define THRESOLD 128

typedef struct GCOBJ GCOBJ;
typedef struct GCFrame GCFrame;

static GCOBJ *gc_object = NULL;
static size_t gc_objects = 0;
static size_t gc_bytes = 0;
static size_t gc_thresold = 512;
static GCFrame *gc_frame = NULL;

void gc_collect(void);
GCOBJ *gcobj_create();
GCOBJ *gcobj_create_string(const char *ptr, size_t len);

// GC ////////////////////////////////////////////////////////////////////

enum GCOBJKind
{
    GCOBJKind_String,
    GCOBJKind_Array,
};

typedef enum GCOBJKind GCOBJKind;

struct GCOBJ
{
    GCOBJKind kind;     // 4
    bool mark;          // 4
    struct GCOBJ *next; // 8
    union
    { // 24
        struct
        {
            const char *ptr; // 8
            size_t length;   // 8
            bool owned;      // 4
            // 4 de padding
        } string; // 24
        struct
        {
            struct GCOBJ **slots; // 8
            size_t size, cap;     // 16
        } array;
    };
};

struct GCFrame
{
    GCOBJ **slots;
    size_t size, cap;
    struct GCFrame *prev;
};

GCFrame gcframe_create()
{
    GCOBJ **slots = calloc(1, sizeof(GCOBJ *) * INIT_CAP);
    assert(slots != NULL);
    return (GCFrame){.slots = slots, .size = 0, .cap = INIT_CAP, .prev = gc_frame};
}

void gcframe_realloc(GCFrame *fr)
{
    fr->cap *= 2;
    GCOBJ **tmp = realloc(fr->slots, sizeof(GCOBJ *) * fr->cap);
    fr->slots = tmp;
}

#define GCFRAME_PUSH()                    \
    GCFrame _gc_frame = gcframe_create(); \
    gc_frame = &_gc_frame;

#define GCFRAME_POP()            \
    if (gc_frame->slots != NULL) \
        free(gc_frame->slots);   \
    gc_frame = _gc_frame.prev;

#define GCFRAME_ADD(obj)                 \
    if (_gc_frame.size == _gc_frame.cap) \
        gcframe_realloc(&_gc_frame);     \
    _gc_frame.slots[_gc_frame.size++] = (obj);

#define GCFRAMEG_ADD(obj)                 \
    if (gc_frame->size == gc_frame->cap) \
        gcframe_realloc(gc_frame);     \
    gc_frame->slots[gc_frame->size++] = (obj);

#define CGDCHECKSTR(val)                         \
    do {                                         \
        if ((val).type == CGD_ValueType_String) { \
            GCFRAME_ADD((val).s.obj);            \
        }                                        \
    } while (0)

#define GCFRAME_GET(idx) \
    _gc_frame.slots[(idx)];

GCOBJ *gcobj_create()
{
    if (gc_bytes >= gc_thresold)
    {
        gc_collect();
        gc_thresold = gc_bytes * 2;
        if (gc_thresold < THRESOLD)
            gc_thresold = THRESOLD;
    }
    GCOBJ *obj = calloc(1, sizeof(GCOBJ));
    assert(obj != NULL);
    gc_objects++;
    return obj;
}

GCOBJ *gcobj_create_string(const char *str, size_t size)
{
    GCOBJ *obj = gcobj_create();
    assert(obj != NULL);
    assert(str != NULL);

    obj->kind = GCOBJKind_String;
    obj->mark = false;
    obj->next = gc_object;
    obj->string.ptr = str;
    obj->string.length = size;
    obj->string.owned = false;

    gc_object = obj;
    gc_bytes += size;
    return obj;
}

GCOBJ *gcobj_string_concat(GCOBJ* left, GCOBJ* right) {
    GCOBJ *obj = gcobj_create();
    assert(obj != NULL);
    assert(left != NULL);
    assert(right != NULL);

    obj->kind = GCOBJKind_String;
    obj->mark = false;
    obj->next = gc_object;

    size_t len = left->string.length + right->string.length + 1;
    char* ptr = calloc(1, len);
    memcpy(ptr, left->string.ptr, left->string.length);
    memcpy(ptr+left->string.length, right->string.ptr, right->string.length);
    ptr[len - 1] = '\0';
    
    obj->string.ptr = ptr;
    obj->string.length = len;
    obj->string.owned = true;

    gc_object = obj;
    gc_bytes += len;
    return obj;
}

GCOBJ *gcobj_create_array()
{
    GCOBJ *obj = gcobj_create();
    assert(obj != NULL);

    obj->kind = GCOBJKind_Array;
    obj->mark = false;
    obj->next = gc_object;

    size_t size = sizeof(GCOBJ *) * INIT_CAP;
    GCOBJ **ptr = calloc(1, size);
    assert(ptr != NULL);

    obj->array.cap = INIT_CAP;
    obj->array.size = 0;
    obj->array.slots = ptr;

    gc_object = obj;
    gc_bytes += size;
    return obj;
}

void gc_mark_object(GCOBJ *obj)
{
    assert(obj != NULL);
    obj->mark = true;

    if (obj->kind == GCOBJKind_String)
        return;

    if (obj->kind == GCOBJKind_Array)
        for (size_t i = 0; i < obj->array.size; i++)
            gc_mark_object(obj->array.slots[i]);
}

// frames e objetos
void gc_mark(void)
{
    GCFrame *f = gc_frame;
    while (f)
    {
        for (size_t i = 0; i < f->size; i++)
            gc_mark_object(f->slots[i]);
        f = f->prev;
    }
}

bool gc_sweep_object(GCOBJ *obj)
{
    assert(obj != NULL);
    // printf("%d\n", obj->mark);

    if (obj->mark)
    {
        obj->mark = false; // reseta
        return false;
    }

    gc_objects--;

    if (obj->kind == GCOBJKind_String)
    {
        gc_bytes -= obj->string.length;
        if (obj->string.owned)
            free((void *)obj->string.ptr);
        free(obj);
        return true;
    }

    if (obj->kind == GCOBJKind_Array)
    {
        gc_bytes -= obj->array.cap * sizeof(GCOBJ *);
        free(obj->array.slots);
        free(obj);
        return true;
    }

    return false;
}

// objetos
void gc_sweep(void)
{
    GCOBJ **obj = &gc_object;
    while (*obj)
    {
        GCOBJ *next = (*obj)->next;
        if (gc_sweep_object(*obj))
            *obj = next; // remove da lista, obj continua apontando pro mesmo slot
        else
            obj = &(*obj)->next; // avança de fato
    }
}

void gc_collect(void)
{
    gc_mark();
    gc_sweep();
}

void gc_shutdown(void)
{
    while (gc_object)
    {
        GCOBJ *obj = gc_object->next;
        gc_sweep_object(gc_object);
        gc_object = obj;
    }
}

// RUNTIME ///////////////////////////////////////////////////////////////

void __cgd_erro_interno(char *msg)
{
    printf("CGD RUNTIME ERRO: %s\n", msg);
    exit(1);
}

typedef struct CGD_String
{
    GCOBJ *obj;
} CGD_String;

typedef struct CGD_Int
{
    long val;
} CGD_Int;

typedef struct CGD_Double
{
    double val;
} CGD_Double;

typedef struct CGD_Bool
{
    int val;
} CGD_Bool;

typedef enum CGD_ValueType
{
    CGD_ValueType_Bool,
    CGD_ValueType_Int,
    CGD_ValueType_Double,
    CGD_ValueType_String,
} CGD_ValueType;

typedef struct CGD_Value
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
    v.s.obj = gcobj_create_string(ptr, strlen(ptr));
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
    if (l.type == CGD_ValueType_Bool)
        __cgd_erro_interno("Nao foi possivel somar esses tipos.");

    if (l.type == CGD_ValueType_String && r.type == CGD_ValueType_String)
    {
        GCOBJ *concat = gcobj_string_concat(l.s.obj, r.s.obj);
        GCFRAMEG_ADD(concat);   // protege o resultado ANTES de strlen/gcobj_create_string
        return cgd_str(concat->string.ptr);
    }

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

    if (t == CGD_ValueType_String)
    {
        if (l.s.obj->string.length != r.s.obj->string.length)
        {
            val.b.val = false;
            return val;
        }

        val.b.val = strcmp(l.s.obj->string.ptr, r.s.obj->string.ptr) == 0;
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
        printf("%s\n", v.s.obj->string.ptr);
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
    // CGD_Value str1 = cgd_str("Fernando");
    // CGD_Value str2 = __cgd_binary_op_add(str1, cgd_str("Dev"));
    // CGD_Value str3 = cgd_str("FernandoDev");
    // cgd_escreva(__cgd_binary_op_ee(str2, str3));
    cgd_main();
    gc_shutdown();
    return 0;
}
