// Unidade de traducao 3: main.c
extern int escala(int x);
extern int soma_potencias(int n);
extern int mdc(int a, int b);

int main() {
    int s = soma_potencias(6);
    int g = mdc(84, 36);
    return escala(g) + s;
}
