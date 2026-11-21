#include "geometria.h"
#include <limits.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define SOMA_QUAD(a, b) (((a) * (a)) + ((b) * (b)))
#define STR_LIT(x) #x
#define JUNTAR_ID(a, b) a##b

int g_contador_data = 10;
int g_acumulador_bss;

void trocar(int *a, int *b) {
    int tmp = *a;
    *a = *b;
    *b = tmp;
}

int calcular_area(struct Retangulo *r) {
    return (r->largura * r->altura) + r->origem.x + r->origem.y;
}

void ordenar_ponteiro(int *base, int n) {
    for (int i = 0; i < n - 1; i++) {
        for (int j = 0; j < n - 1 - i; j++) {
            int *p1 = base + j;
            int *p2 = base + j + 1;
            if (*p1 > *p2) {
                trocar(p1, p2);
            }
        }
    }
}

int aplicar_op(int op, int a, int b) {
    int res = 0;
    switch (op) {
    case OP_SOMA:
        res = a + b;
        break;
    case OP_DIFF:
        res = a - b;
        break;
    case OP_AREA:
        res = a * b;
        break;
    default:
        res = 1;
        break;
    }
    return res;
}

int somar_callback(int x, int y) { return x + y; }

int main(void) {
    // 1. Struct aninhada com inicializador designado C99 + typedef + ponteiro (->)
    struct Retangulo ret = {.origem = {.x = 3, .y = 4}, .largura = 6, .altura = 5};
    int area = calcular_area(&ret); // 37

    // 2. Union: zera 8 bytes e grava 4 bytes (LP64)
    union Registro reg;
    reg.alias_long = 0;
    reg.inteiro = 14;
    long lido_union = reg.alias_long; // 14

    // 3. Ponteiro para ponteiro (int **) + do-while
    int valor = 10;
    int *pv = &valor;
    int **ppv = &pv;
    int passos = 0;
    do {
        **ppv = **ppv + 3;
        passos++;
    } while (passos < 4);
    // valor = 22

    // 4. Array local + ordenacao por ponteiros + indexacao
    int dados[TAM_VETOR] = {9, 2, 7, 1, 5};
    ordenar_ponteiro(dados, TAM_VETOR);
    int extremos = dados[0] + dados[4]; // 1 + 9 = 10

    // 5. LP64 real: sizeof(struct Retangulo) = 16, sizeof(union Registro) = 8 -> 24
    int tamanhos = (int)(sizeof(struct Retangulo) + sizeof(union Registro));

    // 6. switch + enum + macros (#, ##, funcional) + ramo morto no CFG
    int JUNTAR_ID(var_, colada) = SOMA_QUAD(2, 3);     // 13
    int sw = aplicar_op(OP_AREA, 5, 4) * FATOR_ESCALA; // 40
    int morto = 0;
    if (0) {
        morto = 200;
    }

    // 7. Globais (.data e .bss) + ponteiro de funcao + double IEEE-754 + bool
    g_acumulador_bss = g_contador_data + 5; // 15
    int (*fp)(int, int) = somar_callback;
    int cb = fp(g_acumulador_bss, var_colada); // 28
    double media = (area + cb) / 2.0;          // 32.50
    bool ok = media > 30.0;

    // 8. Stdlib oficial da libc.so.6 via headers reais C99
    char *buf = malloc(64);
    strcpy(buf, STR_LIT(CGD));
    strcat(buf, "-C99");
    size_t tam = strlen(buf);
    int cmp = strcmp(buf, "CGD-C99");
    int num_abs = abs(-15);

    puts("ELF64 dinamico C99 linkado a libc.so.6 oficial!");
    printf("Area=%d Heap=%s Len=%lu Cmp=%d Abs=%d Media=%.2f Ok=%d\n", area, buf,
           (unsigned long)tam, cmp, num_abs, media, (int)ok);
    free(buf);

    // 37 + 14 + 22 + 10 + 24 + 40 + 28 + 0 = 175
    return area + (int)lido_union + valor + extremos + tamanhos + sw + cb + morto;
}
