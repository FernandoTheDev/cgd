// MiniLang — Programa tipado compilado e otimizado em 5 fases pelo compilador em Delegua/CGD

fn potencia(base: int, exp: int): int {
    var res: int = 1;
    var i: int = 0;
    while (i < exp) {
        res = res * base;
        i = i + 1;
    }
    return res;
}

fn fib(n: int): int {
    if (n <= 1) {
        return n;
    }
    return fib(n - 1) + fib(n - 2);
}

fn eh_par(x: int): bool {
    return (x % 2) == 0;
}

fn soma_impares(limite: int): int {
    var acc: int = 0;
    var k: int = 1;
    while (k <= limite) {
        if (!eh_par(k)) {
            acc = acc + k;
        }
        k = k + 1;
    }
    return acc;
}

fn main(): int {
    // Expressao dobravel em tempo de compilacao (Constant Folding + identidade + 0)
    var constante: int = (2 + 3) * (10 - 4) + 0;
    print(constante);

    // Ramo morto eliminado pelo otimizador de AST
    if (false) {
        print(99999);
    } else {
        print(potencia(2, 10));
    }

    print(fib(10));
    print(soma_impares(15));
    print(eh_par(42));
    return 0;
}
