// Unidade de traducao 1: matematica.c
#define FATOR_BASE 10

int potencia(int base, int exp) {
    int res = 1;
    int i = 0;
    while (i < exp) {
        res = res * base;
        i = i + 1;
    }
    return res;
}

int escala(int x) { return x * FATOR_BASE; }
