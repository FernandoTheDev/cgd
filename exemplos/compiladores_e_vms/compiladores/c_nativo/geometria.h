#ifndef GEOMETRIA_H
#define GEOMETRIA_H

#define FATOR_ESCALA 2
#define TAM_VETOR 5

enum Operacao { OP_SOMA = 1, OP_DIFF = 2, OP_AREA = 3 };

struct Ponto {
    int x;
    int y;
};

typedef struct Ponto Ponto2D;

struct Retangulo {
    Ponto2D origem;
    int largura;
    int altura;
};

union Registro {
    int inteiro;
    long alias_long;
};

int calcular_area(struct Retangulo *r);
void trocar(int *a, int *b);
void ordenar_ponteiro(int *base, int n);

#endif
