// Mini-Rust — Programa valido verificado pelo Borrow Checker e executado na VM

fn tamanho_emprestado(s: &String) -> i64 {
    return len(s);
}

fn consumir(s: String) -> String {
    return s;
}

fn incrementar(x: &mut i64, delta: i64) -> i64 {
    *x = *x + delta;
    return *x;
}

fn main() -> i64 {
    // 1. Emprestimos imutaveis simultaneos (&s) dentro de um escopo lexical
    let texto: String = String::from("CGD+Rust");
    {
        let r1: &String = &texto;
        let r2: &String = &texto;
        println!(tamanho_emprestado(r1) + tamanho_emprestado(r2));
    }
    // Apos o bloco, r1 e r2 expiraram: agora podemos mover 'texto' com seguranca!
    let movido: String = consumir(texto);
    println!(movido);

    // 2. Emprestimo mutavel (&mut) e liberacao apos escopo
    let mut contador: i64 = 10;
    {
        let ref_mut: &mut i64 = &mut contador;
        incrementar(ref_mut, 32);
    }
    // ref_mut expirou: podemos ler e alterar contador novamente
    contador = contador + 8;
    println!(contador);

    // 3. Tipos Copy (i64) nao movem posse
    let a: i64 = 7;
    let b: i64 = a;
    println!(a * b);
    return 0;
}
