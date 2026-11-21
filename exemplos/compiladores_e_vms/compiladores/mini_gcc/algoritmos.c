// Unidade de traducao 2: algoritmos.c
extern int potencia(int base, int exp);

int soma_potencias(int n) {
    int acc = 0;
    int i = 0;
    while (i < n) {
        acc = acc + potencia(2, i);
        i = i + 1;
    }
    return acc;
}

int mdc(int a, int b) {
    while (b != 0) {
        int r = a % b;
        a = b;
        b = r;
    }
    return a;
}
