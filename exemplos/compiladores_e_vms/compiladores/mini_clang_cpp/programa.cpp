// Mini-Clang C++ — Programa C++ compilado com name mangling, classes, heranca e cout

namespace mat {
    int somar(int a, int b) {
        return a + b;
    }

    int somar(int a, int b, int c) {
        return a + b + c;
    }
}

class Forma {
public:
    int escala;

    Forma(int s) {
        this->escala = s;
    }

    int fator() {
        return this->escala;
    }
};

class Retangulo : public Forma {
public:
    int largura;
    int altura;

    Retangulo(int l, int a, int s) {
        this->escala = s;
        this->largura = l;
        this->altura = a;
    }

    int area() {
        return this->largura * this->altura * this->fator();
    }
};

int main() {
    int x = mat::somar(10, 20);
    int y = mat::somar(1, 2, 3);
    cout << "mat::somar(10,20) = " << x << endl;
    cout << "mat::somar(1,2,3) = " << y << endl;

    Retangulo r = Retangulo(5, 4, 3);
    cout << "Retangulo.area() = " << r.area() << endl;
    cout << "Retangulo.fator() herdado = " << r.fator() << endl;
    return 0;
}
