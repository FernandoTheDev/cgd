#!/usr/bin/env python3
"""Suite diferencial de conformidade ISO C99 para o compilador nativo em Delegua/CGD.

Compara saida padrao (stdout) e codigo de saida (exit code) de cada programa compilado
pelo compilador C99 nativo (-O0 e -O1) contra gcc -std=c99, alem de validar testes
negativos, compilacao multi-arquivo (multi-TU), backend assembly (-S) e estrutura ELF64.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

RAIZ_C_NATIVO = Path(__file__).resolve().parent
RAIZ_REPO = RAIZ_C_NATIVO.parents[3]
COMPILADOR_BIN = RAIZ_REPO / "out" / "c99cc"
CGD_BIN = RAIZ_REPO / "cgd"


def garantir_compilador() -> None:
    if COMPILADOR_BIN.exists():
        return
    COMPILADOR_BIN.parent.mkdir(parents=True, exist_ok=True)
    res = subprocess.run(
        [str(CGD_BIN), str(RAIZ_C_NATIVO / "c_nativo.delegua"), "-s", str(COMPILADOR_BIN)],
        cwd=str(RAIZ_REPO),
        capture_output=True,
        text=True,
        check=False,
    )
    if res.returncode != 0:
        raise RuntimeError(f"Falha ao compilar c_nativo.delegua:\n{res.stdout}\n{res.stderr}")


def rodar_binario(caminho: Path) -> tuple[int, str]:
    res = subprocess.run([str(caminho)], capture_output=True, text=True, timeout=10, check=False)
    return res.returncode, res.stdout


CASOS_DIFERENCIAIS: list[tuple[str, str, list[str]]] = [
    (
        "pp_trigraphs_splice_comentarios",
        r"""
??=include <stdio.h>
??=define VALOR \
    (10 + \
     32)
int main(void) ??<
    int arr??(2??) = ??< VALOR, 5 ??>; /* comentario
       multilinha */
    // comentario linha com "string falsa"
    printf("%d %d\n", arr??(0??), arr??(1??));
    return arr??(0??) + arr??(1??);
??>
""",
        [],
    ),
    (
        "pp_macros_func_variadicas_hash_paste",
        r"""
#include <stdio.h>
#define SOMA(a, b) ((a) + (b))
#define STR(x) #x
#define COLAR(a, b) a##b
#define LOG(fmt, ...) printf(fmt, __VA_ARGS__)
int main(void) {
    int SELF_REF = 7;
#define SELF_REF SELF_REF + 1
    int r = SELF_REF; // hide-set impede recursao infinita -> vira SELF_REF + 1 -> 8
    int COLAR(num_, 1) = SOMA(3, 4);
    LOG("%s=%d r=%d\n", STR(hello world), num_1, r);
    return num_1 + r;
}
""",
        [],
    ),
    (
        "pp_condicionais_defined_cli",
        r"""
#include <stdio.h>
#define VERSAO 2
#if defined(FLAG_CLI) && (VERSAO * 10 + 5 == 25) && !defined(INEXISTENTE)
int pick(void) { return VAL_CLI + 1; }
#elif VERSAO == 1
int pick(void) { return 99; }
#else
int pick(void) { return 0; }
#endif
#undef VERSAO
#ifdef VERSAO
int extra(void) { return 100; }
#else
int extra(void) { return 7; }
#endif
#if NAO_DEFINIDA == 0
int zcheck(void) { return 3; }
#endif
int main(void) {
    printf("%d %d %d %ld\n", pick(), extra(), zcheck(), (long)__STDC_VERSION__);
    return pick() + extra() + zcheck();
}
""",
        ["-DFLAG_CLI", "-DVAL_CLI=20"],
    ),
    (
        "pp_line_predefinidas_pragma",
        r"""
#include <stdio.h>
#include <string.h>
_Pragma("unused")
int main(void) {
#line 500 "virtual.c"
    int ln = __LINE__;
    const char *fn = __FILE__;
    printf("%s:%d stdc=%d\n", fn, ln, __STDC__);
    return (strcmp(fn, "virtual.c") == 0 && ln == 500) ? 42 : 1;
}
""",
        [],
    ),
    (
        "headers_stdint_limits_stdbool_iso646",
        r"""
#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <limits.h>
#include <iso646.h>
int main(void) {
    int8_t a = -5;
    uint8_t b = 250;
    int16_t c = -300;
    uint16_t d = 60000;
    int32_t e = -100000;
    uint32_t f = 3000000000U;
    int64_t g = -5000000000LL;
    uint64_t h = 5000000000ULL;
    bool ok = (a < 0) and (b == 250) and (not false);
    bool coerced = 42;
    printf("%d %u %d %u %d %u %ld %lu %d %d %d\n",
           (int)a, (unsigned)b, (int)c, (unsigned)d, e, f,
           (long)g, (unsigned long)h, (int)ok, (int)coerced, CHAR_BIT);
    return (int)ok + (int)coerced + (int)sizeof(int8_t) + (int)sizeof(int16_t) + (int)sizeof(int32_t) + (int)sizeof(int64_t);
}
""",
        [],
    ),
    (
        "headers_ctype_string_stdlib_assert",
        r"""
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <assert.h>
int main(void) {
    assert(isdigit('7') != 0);
    assert(isalpha('Z') != 0);
    assert(isspace(' ') != 0);
    char buf[32];
    memset(buf, 0, 32);
    strcpy(buf, "delegua");
    buf[0] = (char)toupper(buf[0]);
    char *p = strchr(buf, 'g');
    int idx = (int)(p - buf);
    char *sub = strstr(buf, "gua");
    int n = atoi("-123");
    int *arr = calloc(4, sizeof(int));
    arr[2] = 99;
    arr = realloc(arr, 8 * sizeof(int));
    arr[7] = 11;
    char out[64];
    snprintf(out, 64, "%s:%d:%s:%d:%d", buf, idx, sub, abs(n), arr[2] + arr[7]);
    puts(out);
    free(arr);
    return (int)strlen(out);
}
""",
        [],
    ),
    (
        "tipos_signed_unsigned_casts_shifts",
        r"""
#include <stdio.h>
int main(void) {
    signed char sc = (signed char)200;
    unsigned char uc = (unsigned char)-1;
    int neg = -1;
    unsigned int u = 1U;
    int cmp_u = ((unsigned int)neg > u) ? 1 : 0;
    int cmp_s = (neg < 1) ? 1 : 0;
    unsigned int udiv = 4000000000U / 1000000000U;
    unsigned int umod = 4000000003U % 1000000000U;
    int sdiv = -17 / 5;
    int smod = -17 % 5;
    int ashr = (-16) >> 2;
    unsigned int lshr = 0x80000000U >> 31;
    printf("%d %u %d %d %u %u %d %d %d %u\n",
           (int)sc, (unsigned)uc, cmp_u, cmp_s, udiv, umod, sdiv, smod, ashr, lshr);
    return (int)(udiv + umod + lshr + cmp_u + cmp_s);
}
""",
        [],
    ),
    (
        "lp64_structs_padding_offsetof_unions",
        r"""
#include <stdio.h>
#include <stddef.h>
struct Mistura {
    char a;
    int b;
    char c;
    double d;
    short e;
};
union U {
    unsigned int u32;
    unsigned char bytes[4];
};
int main(void) {
    struct Mistura m = { .a = 'X', .b = 1234, .c = 'Y', .d = 2.5, .e = -7 };
    union U u;
    u.u32 = 0x04030201U;
    printf("sz=%lu off=%lu,%lu,%lu,%lu,%lu vals=%c,%d,%c,%.1f,%d le=%u,%u,%u,%u\n",
           (unsigned long)sizeof(struct Mistura),
           (unsigned long)offsetof(struct Mistura, a),
           (unsigned long)offsetof(struct Mistura, b),
           (unsigned long)offsetof(struct Mistura, c),
           (unsigned long)offsetof(struct Mistura, d),
           (unsigned long)offsetof(struct Mistura, e),
           m.a, m.b, m.c, m.d, (int)m.e,
           (unsigned)u.bytes[0], (unsigned)u.bytes[1], (unsigned)u.bytes[2], (unsigned)u.bytes[3]);
    return (int)sizeof(struct Mistura);
}
""",
        [],
    ),
    (
        "arrays_multidim_e_inicializadores_designados",
        r"""
#include <stdio.h>
int main(void) {
    int mat[3][4] = {
        { 1, 2, 3, 4 },
        { 5, 6, 7, 8 },
        { 9, 10, 11, 12 }
    };
    int esparso[6] = { [4] = 40, [1] = 10, 20 };
    int soma = 0;
    for (int i = 0; i < 3; i++) {
        for (int j = 0; j < 4; j++) {
            soma += mat[i][j];
        }
    }
    int soma_esp = 0;
    for (int i = 0; i < 6; i++) {
        soma_esp += esparso[i];
    }
    printf("soma=%d esp=%d,%d,%d,%d,%d,%d\n",
           soma, esparso[0], esparso[1], esparso[2], esparso[3], esparso[4], esparso[5]);
    return soma + soma_esp;
}
""",
        [],
    ),
    (
        "ponto_flutuante_ieee754_double_float",
        r"""
#include <stdio.h>
double g_pi = 3.14159265;
float g_f = 1.5f;

double hipotenusa_quad(double a, double b) {
    return a * a + b * b;
}

double misto(int n, double x) {
    return (double)n * x - 0.25;
}

int main(void) {
    float f = 2.25f;
    double d = -4.5;
    double neg = -d;
    double h = hipotenusa_quad(3, 4);
    double m = misto(5, 1.5);
    int c1 = (h == 25.0) ? 1 : 0;
    int c2 = (d < f) ? 1 : 0;
    int c3 = (neg > 4.0) ? 1 : 0;
    int trunc = (int)(g_pi * 10.0);
    printf("pi=%.4f gf=%.2f f=%.2f h=%.1f m=%.2f cmp=%d%d%d tr=%d\n",
           g_pi, (double)g_f, (double)f, h, m, c1, c2, c3, trunc);
    return trunc + c1 + c2 + c3;
}
""",
        [],
    ),
    (
        "fluxo_controle_goto_switch_fallthrough_shortcircuit",
        r"""
#include <stdio.h>
int efeitos = 0;
int inc_efeito(int ret) {
    efeitos++;
    return ret;
}

int main(void) {
    // Short-circuit && e ||
    int a = 0 && inc_efeito(1);
    int b = 1 || inc_efeito(1);
    int c = 1 && inc_efeito(1);
    int d = 0 || inc_efeito(0);

    // Switch com fallthrough intencional
    int sw = 0;
    for (int i = 0; i < 4; i++) {
        switch (i) {
        case 0:
            sw += 1;
            break;
        case 1:
        case 2:
            sw += 10;
            break;
        default:
            sw += 100;
            break;
        }
    }

    // Goto para frente e para tras + operador virgula
    int acc = 0;
    int k = 0;
loop_inicio:
    if (k >= 5) goto loop_fim;
    acc += (k++, k * 2);
    goto loop_inicio;
loop_fim:
    printf("sc=%d,%d,%d,%d ef=%d sw=%d acc=%d\n", a, b, c, d, efeitos, sw, acc);
    return efeitos + sw + acc;
}
""",
        [],
    ),
    (
        "abi_mais_de_6_args_e_mistos_pilha",
        r"""
#include <stdio.h>
int soma10(int a1, int a2, int a3, int a4, int a5, int a6, int a7, int a8, int a9, int a10) {
    return a1 * 1 + a2 * 2 + a3 * 3 + a4 * 4 + a5 * 5 +
           a6 * 6 + a7 * 7 + a8 * 8 + a9 * 9 + a10 * 10;
}

double mistura_abi(int i1, double d1, int i2, double d2, int i3, int i4, int i5, int i6, int i7, double d3) {
    return (double)(i1 + i2 + i3 + i4 + i5 + i6 + i7) + d1 + d2 + d3;
}

int main(void) {
    int s = soma10(1, 2, 3, 4, 5, 6, 7, 8, 9, 10); // sum(i^2, 1..10) = 385
    double m = mistura_abi(1, 0.5, 2, 1.5, 3, 4, 5, 6, 7, 2.0); // 28 + 4.0 = 32.0
    printf("s=%d m=%.1f\n", s, m);
    return (s % 200) + (int)m;
}
""",
        [],
    ),
    (
        "ponteiros_funcao_e_qsort_libc",
        r"""
#include <stdio.h>
#include <stdlib.h>

int cmp_int_asc(const void *pa, const void *pb) {
    int a = *(const int *)pa;
    int b = *(const int *)pb;
    if (a < b) return -1;
    if (a > b) return 1;
    return 0;
}

int dobro(int x) { return x * 2; }
int triplo(int x) { return x * 3; }

int aplicar(int (*fn)(int), int v) {
    return fn(v);
}

int main(void) {
    int v[6] = { 42, -5, 19, 0, 7, 3 };
    qsort(v, 6, sizeof(int), cmp_int_asc);
    int r1 = aplicar(dobro, 11);
    int r2 = aplicar(triplo, 7);
    printf("%d %d %d %d %d %d | %d %d\n", v[0], v[1], v[2], v[3], v[4], v[5], r1, r2);
    return r1 + r2 + v[5];
}
""",
        [],
    ),
    (
        "recursao_fib_e_globais_data_bss",
        r"""
#include <stdio.h>
int g_calls;
int g_base = 100;
int g_arr[4] = { 3, 6, 9, 12 };

int fib(int n) {
    g_calls++;
    if (n <= 1) return n;
    return fib(n - 1) + fib(n - 2);
}

int main(void) {
    int f10 = fib(10); // 55
    int s = g_base + g_arr[0] + g_arr[3]; // 115
    printf("fib10=%d calls=%d s=%d\n", f10, g_calls, s);
    return (f10 + s) % 250;
}
""",
        [],
    ),
    (
        "ponteiros_operadores_compostos_inc_dec",
        r"""
#include <stdio.h>
int main(void) {
    int xs[5] = { 10, 20, 30, 40, 50 };
    int *p = xs;
    int a = *p++;       // 10, p -> xs[1]
    int b = *++p;       // 30, p -> xs[2]
    int c = (*p)++;     // 30, xs[2] -> 31
    int d = ++(*p);     // 32, xs[2] -> 32
    long diff = (&xs[4]) - (&xs[1]); // 3
    int m = 60;
    m += 10; m -= 6; m *= 2; m /= 4; m %= 25;
    m |= 8; m &= 15; m ^= 3; m <<= 1; m >>= 1;
    printf("%d %d %d %d %ld %d %d\n", a, b, c, d, diff, xs[2], m);
    return a + b + (int)diff + m;
}
""",
        [],
    ),
    (
        "c99_copia_struct_e_literais_compostos",
        r"""
#include <stdio.h>
struct Vetor3 {
    int x;
    int y;
    int z;
};

int soma_ptr(const struct Vetor3 *v) {
    return v->x + v->y + v->z;
}

int main(void) {
    struct Vetor3 a = { .x = 10, .y = 20, .z = 30 };
    struct Vetor3 b;
    b = a;
    b.y = 99;
    struct Vetor3 c = (struct Vetor3){ .x = 1, .y = 2, .z = 3 };
    int direta = ((struct Vetor3){ 4, 5, 6 }).z;
    int via_ptr = soma_ptr(&(struct Vetor3){ 7, 8, 9 });
    int arr_cl = (int[]){ 11, 22, 33 }[2];
    printf("a=%d,%d,%d b=%d,%d,%d c=%d,%d,%d d=%d p=%d arr=%d\n",
           a.x, a.y, a.z, b.x, b.y, b.z, c.x, c.y, c.z, direta, via_ptr, arr_cl);
    return a.y + b.y + c.z + direta + via_ptr + arr_cl;
}
""",
        [],
    ),
    (
        "c99_static_locais_e_func",
        r"""
#include <stdio.h>
#include <string.h>

int proximo_id(void) {
    static int contador = 10;
    static int zerado;
    zerado += 2;
    contador++;
    return contador + zerado;
}

const char *nome_desta_funcao(void) {
    return __func__;
}

int main(void) {
    int r1 = proximo_id(); // 11 + 2 = 13
    int r2 = proximo_id(); // 12 + 4 = 16
    int r3 = proximo_id(); // 13 + 6 = 19
    printf("%d %d %d %s %s\n", r1, r2, r3, nome_desta_funcao(), __func__);
    return r1 + r2 + r3 + (int)strlen(nome_desta_funcao());
}
""",
        [],
    ),
    (
        "c99_arrays_inferidos_e_strings_char",
        r"""
#include <stdio.h>
#include <string.h>

int g_nums[] = { 2, 4, 6, 8 };
char g_str[] = "delegua";

int main(void) {
    char loc[] = "c99!";
    char fixo[10] = "ok";
    int esp[] = { [4] = 50, [1] = 10 };
    printf("%s %s %s sz=%lu,%lu,%lu,%lu,%lu g=%d esp=%d\n",
           g_str, loc, fixo,
           (unsigned long)sizeof(g_nums),
           (unsigned long)sizeof(g_str),
           (unsigned long)sizeof(loc),
           (unsigned long)sizeof(fixo),
           (unsigned long)sizeof(esp),
           g_nums[3], esp[4] + esp[1]);
    return (int)(sizeof(g_str) + sizeof(loc) + sizeof(esp)) + esp[4];
}
""",
        [],
    ),
    (
        "c99_vla_e_sizeof_dinamico",
        r"""
#include <stdio.h>

int somar_vla(int n) {
    int v[n];
    for (int i = 0; i < n; i++) {
        v[i] = (i + 1) * 3;
    }
    int total = 0;
    for (int i = 0; i < n; i++) {
        total += v[i];
    }
    size_t sz = sizeof(v);
    printf("n=%d sz=%lu total=%d\n", n, (unsigned long)sz, total);
    return total + (int)sz;
}

int main(void) {
    int a = somar_vla(5);  // total=45, sz=20 -> 65
    int b = somar_vla(9);  // total=135, sz=36 -> 171
    return (a + b) % 250;
}
""",
        [],
    ),
    (
        "c99_libm_dinamica_e_time",
        r"""
#include <stdio.h>
#include <math.h>
#include <time.h>

int main(void) {
    double s = sqrt(81.0);
    double p = pow(2.0, 5.0);
    double fl = floor(3.9);
    double cl = ceil(3.1);
    double fa = fabs(-12.5);
    double dt = difftime(250, 200);
    time_t agora = time(NULL);
    int tempo_ok = (agora > 1000000000L) ? 1 : 0;
    printf("s=%.1f p=%.1f fl=%.1f cl=%.1f fa=%.1f dt=%.1f tok=%d\n",
           s, p, fl, cl, fa, dt, tempo_ok);
    return (int)(s + p + fl + cl + fa + dt) + tempo_ok;
}
""",
        ["-lm"],
    ),
    (
        "c99_stdarg_variadicas_vacopy_e_vsnprintf_glibc",
        r"""
#include <stdio.h>
#include <stdarg.h>

int somar_inteiros(int n, ...) {
    va_list ap;
    va_list copia;
    va_start(ap, n);
    va_copy(copia, ap);
    int s1 = 0;
    for (int i = 0; i < n; i++) {
        s1 += va_arg(ap, int);
    }
    int primeiro = va_arg(copia, int);
    va_end(copia);
    va_end(ap);
    return s1 + primeiro;
}

double somar_reais(int n, ...) {
    va_list ap;
    va_start(ap, n);
    double total = 0.0;
    for (int i = 0; i < n; i++) {
        total += va_arg(ap, double);
    }
    va_end(ap);
    return total;
}

int meu_formatar(char *buf, size_t tam, const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    int n = vsnprintf(buf, tam, fmt, ap);
    va_end(ap);
    return n;
}

int main(void) {
    // 8 argumentos variadicos -> testa GP regs (rsi..r9) + overflow_arg_area na pilha!
    int si = somar_inteiros(8, 10, 20, 30, 40, 50, 60, 70, 80); // 360 + 10 = 370
    double sd = somar_reais(4, 1.5, 2.25, 3.25, 4.0); // 11.0
    char out[128];
    int len = meu_formatar(out, 128, "glibc-vsnprintf:%s:%d:%.2f", "OK", si, sd);
    printf("%s (len=%d)\n", out, len);
    return (si % 200) + (int)sd + len;
}
""",
        [],
    ),
    (
        "c99_struct_por_valor_abi",
        r"""
#include <stdio.h>

struct Ponto2D {
    int x;
    int y;
};

struct Ponto2D somar_pontos(struct Ponto2D a, struct Ponto2D b) {
    struct Ponto2D r = { .x = a.x + b.x, .y = a.y + b.y };
    return r;
}

int main(void) {
    struct Ponto2D p1 = { 3, 7 };
    struct Ponto2D p2 = { 10, 20 };
    struct Ponto2D s = somar_pontos(p1, p2);
    struct Ponto2D encadeado = somar_pontos(s, (struct Ponto2D){ 5, 11 });
    int x_direto = somar_pontos(p1, encadeado).x;
    printf("s=(%d,%d) enc=(%d,%d) xd=%d\n", s.x, s.y, encadeado.x, encadeado.y, x_direto);
    return s.x + s.y + encadeado.x + encadeado.y + x_direto;
}
""",
        [],
    ),
]

CASOS_NEGATIVOS: list[tuple[str, str, str]] = [
    (
        "pp_diretiva_error",
        '#error "abortado pelo usuario"\nint main(void) { return 0; }\n',
        "#error",
    ),
    ("pp_if_sem_endif", "#if 1\nint main(void) { return 0; }\n", "#endif"),
    ("sema_var_nao_declarada", "int main(void) { return nao_existe; }\n", "nao declarado"),
    (
        "sema_campo_inexistente",
        "struct A { int x; }; int main(void) { struct A a; return a.y; }\n",
        "nao existe",
    ),
    ("sema_desref_invalida", "int main(void) { int x = 5; return *x; }\n", "desreferencia"),
    (
        "sema_goto_label_inexistente",
        "int main(void) { goto sumiu; return 0; }\n",
        "label indefinido",
    ),
]


def rodar_testes_diferenciais(tmp: Path) -> int:
    falhas = 0
    for nome, codigo, flags_extra in CASOS_DIFERENCIAIS:
        arq_c = tmp / f"{nome}.c"
        arq_c.write_text(codigo, encoding="utf-8")

        bin_gcc = tmp / f"{nome}_gcc"
        res_gcc = subprocess.run(
            ["gcc", "-std=c99", "-O0", *flags_extra, str(arq_c), "-o", str(bin_gcc)],
            capture_output=True,
            text=True,
            check=False,
        )
        if res_gcc.returncode != 0:
            print(f"[FALHA GCC] {nome}: {res_gcc.stderr}")
            falhas += 1
            continue
        ec_gcc, out_gcc = rodar_binario(bin_gcc)

        for opt in ("-O0", "-O1"):
            bin_c99 = tmp / f"{nome}_c99_{opt[1:]}"
            res_c99 = subprocess.run(
                [str(COMPILADOR_BIN), opt, *flags_extra, str(arq_c), "-o", str(bin_c99)],
                cwd=str(RAIZ_C_NATIVO),
                capture_output=True,
                text=True,
                check=False,
            )
            if res_c99.returncode != 0:
                print(f"[FALHA COMPILACAO] {nome} ({opt}):\n{res_c99.stdout}\n{res_c99.stderr}")
                falhas += 1
                continue
            ec_c99, out_c99 = rodar_binario(bin_c99)
            if ec_c99 != ec_gcc or out_c99 != out_gcc:
                print(f"[DIVERGENCIA] {nome} ({opt}):")
                print(f"  GCC: exit={ec_gcc} stdout={out_gcc!r}")
                print(f"  C99: exit={ec_c99} stdout={out_c99!r}")
                falhas += 1
            else:
                print(f"[OK] {nome} ({opt}) -> exit={ec_c99}")
    return falhas


def rodar_teste_multi_tu(tmp: Path) -> int:
    inc_dir = tmp / "meus_headers"
    inc_dir.mkdir(exist_ok=True)
    (inc_dir / "matematica.h").write_text(
        "#pragma once\nextern int g_fator;\nint multiplicar_fator(int x);\n",
        encoding="utf-8",
    )
    (tmp / "mod_a.c").write_text(
        '#include "matematica.h"\nint g_fator = 6;\nint multiplicar_fator(int x) { return x * g_fator; }\n',
        encoding="utf-8",
    )
    (tmp / "mod_b.c").write_text(
        '#include <stdio.h>\n#include "matematica.h"\nint main(void) { int r = multiplicar_fator(7); printf("multi=%d\\n", r); return r; }\n',
        encoding="utf-8",
    )

    bin_gcc = tmp / "multi_gcc"
    subprocess.run(
        [
            "gcc",
            "-std=c99",
            "-I",
            str(inc_dir),
            str(tmp / "mod_a.c"),
            str(tmp / "mod_b.c"),
            "-o",
            str(bin_gcc),
        ],
        check=True,
    )
    ec_gcc, out_gcc = rodar_binario(bin_gcc)

    bin_c99 = tmp / "multi_c99"
    res = subprocess.run(
        [
            str(COMPILADOR_BIN),
            "-I",
            str(inc_dir),
            str(tmp / "mod_a.c"),
            str(tmp / "mod_b.c"),
            "-o",
            str(bin_c99),
        ],
        cwd=str(RAIZ_C_NATIVO),
        capture_output=True,
        text=True,
        check=False,
    )
    if res.returncode != 0:
        print(f"[FALHA MULTI-TU] {res.stdout}\n{res.stderr}")
        return 1
    ec_c99, out_c99 = rodar_binario(bin_c99)
    if ec_c99 != ec_gcc or out_c99 != out_gcc:
        print(f"[DIVERGENCIA MULTI-TU] GCC=({ec_gcc},{out_gcc!r}) vs C99=({ec_c99},{out_c99!r})")
        return 1
    print(f"[OK] multi_tu_e_flag_I -> exit={ec_c99}")
    return 0


def rodar_testes_negativos(tmp: Path) -> int:
    falhas = 0
    for nome, codigo, trecho_esperado in CASOS_NEGATIVOS:
        arq_c = tmp / f"neg_{nome}.c"
        arq_c.write_text(codigo, encoding="utf-8")
        bin_out = tmp / f"neg_{nome}.elf"
        res = subprocess.run(
            [str(COMPILADOR_BIN), str(arq_c), "-o", str(bin_out)],
            cwd=str(RAIZ_C_NATIVO),
            capture_output=True,
            text=True,
            check=False,
        )
        combinado = (res.stdout + "\n" + res.stderr).lower()
        if res.returncode == 0 or trecho_esperado.lower() not in combinado:
            print(
                f"[FALHA NEGATIVO] {nome}: rc={res.returncode} esperado={trecho_esperado!r} saida={combinado!r}"
            )
            falhas += 1
        else:
            print(f"[OK] negativo:{nome}")
    return falhas


def rodar_auditoria_elf_e_asm(tmp: Path) -> int:
    asm_out = tmp / "prog.s"
    res_s = subprocess.run(
        [str(COMPILADOR_BIN), "-S", str(RAIZ_C_NATIVO / "programa.c"), "-o", str(asm_out)],
        cwd=str(RAIZ_C_NATIVO),
        capture_output=True,
        text=True,
        check=False,
    )
    if res_s.returncode != 0 or not asm_out.exists():
        print(f"[FALHA ASM -S] {res_s.stdout}\n{res_s.stderr}")
        return 1
    asm_txt = asm_out.read_text(encoding="utf-8")
    for obrig in (
        "section .rodata",
        "section .data",
        "section .bss",
        "section .text",
        "extern printf",
    ):
        if obrig not in asm_txt:
            print(f"[FALHA ASM -S] faltou '{obrig}'")
            return 1

    elf_out = tmp / "prog.elf"
    res_e = subprocess.run(
        [str(COMPILADOR_BIN), str(RAIZ_C_NATIVO / "programa.c"), "-o", str(elf_out)],
        cwd=str(RAIZ_C_NATIVO),
        capture_output=True,
        text=True,
        check=False,
    )
    if res_e.returncode != 0:
        print(f"[FALHA ELF] {res_e.stdout}\n{res_e.stderr}")
        return 1

    env_c = dict(os.environ)
    env_c["LC_ALL"] = "C"
    r_ph = subprocess.run(
        ["readelf", "-W", "-l", str(elf_out)], capture_output=True, text=True, env=env_c, check=True
    ).stdout
    r_sh = subprocess.run(
        ["readelf", "-W", "-S", str(elf_out)], capture_output=True, text=True, env=env_c, check=True
    ).stdout
    r_ldd = subprocess.run(
        ["ldd", str(elf_out)], capture_output=True, text=True, env=env_c, check=True
    ).stdout

    if "RWE" in r_ph:
        print("[FALHA ELF] Segmento RWE inseguro encontrado!")
        return 1
    for sec in (
        ".interp",
        ".dynstr",
        ".dynsym",
        ".rela.dyn",
        ".rodata",
        ".text",
        ".dynamic",
        ".got",
        ".data",
        ".bss",
        ".shstrtab",
    ):
        if sec not in r_sh:
            print(f"[FALHA ELF] Secao '{sec}' ausente em readelf -S")
            return 1
    if "libc.so.6" not in r_ldd:
        print(f"[FALHA ELF] libc.so.6 ausente em ldd:\n{r_ldd}")
        return 1

    print("[OK] auditoria_elf_e_asm (PT_LOAD RX+RW, 13 sections, ldd libc.so.6, -S)")
    return 0


def main() -> int:
    garantir_compilador()
    tmp = Path(tempfile.mkdtemp(prefix="c99_suite_"))
    try:
        falhas = 0
        falhas += rodar_testes_diferenciais(tmp)
        falhas += rodar_teste_multi_tu(tmp)
        falhas += rodar_testes_negativos(tmp)
        falhas += rodar_auditoria_elf_e_asm(tmp)
        total = len(CASOS_DIFERENCIAIS) * 2 + 1 + len(CASOS_NEGATIVOS) + 1
        print(f"\nResumo C99: {total - falhas}/{total} verificacoes aprovadas, {falhas} falhas.")
        return 1 if falhas > 0 else 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
