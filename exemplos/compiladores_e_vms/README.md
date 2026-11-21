# Compiladores, Toolchains, Interpretadores e VMs em Delégua (CGD)

Coleção de projetos de médio e grande porte escritos em Delégua e compilados
nativamente pelo CGD para demonstrar estabilidade, desempenho, tipagem,
polimorfismo (`classe abstrata`), exceções tipadas, `rotina`/`Tarefa<T>` e
engenharia de compiladores real.

Todos os projetos possuem contratos executáveis (`//!` e `//?`) e são validados
com e sem otimização (`-o`) por `python3 testes/exemplos.py`.

## Compiladores, Linkers, Assemblers e Infraestruturas (`compiladores/`)

| Projeto                                                                         | Entrada                                                                                                                                        | Destaques técnicos                                                                                                                                                                                                       |
| ------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| [Compilador C99 Nativo (ASM + ELF64)](compiladores/c_nativo/c_nativo.delegua)   | [programa.c](compiladores/c_nativo/programa.c)                                                                                                 | Projeto modular em 7 arquivos: Lexer C99, Parser, Semântica, Lowering AST→CFG/SSA + ConstProp/CFG/DCE, **Backend 1 (Assembly x86_64)** e **Backend 2 (Código de Máquina x86_64 + ELF64 executado nativamente no Linux)** |
| [Mini-LLVM](compiladores/mini_llvm/mini_llvm.delegua)                           | [programa.ll](compiladores/mini_llvm/programa.ll)                                                                                              | Parser de IR SSA (`.ll`), verificador SSA, Constant Propagation/Folding, DCE, eliminação de blocos mortos no CFG, alocador de registradores Linear Scan e executor com nós `phi`                                         |
| [Mini-GCC + Linker Paralelo](compiladores/mini_gcc/mini_gcc.delegua)            | [main.c](compiladores/mini_gcc/main.c), [matematica.c](compiladores/mini_gcc/matematica.c), [algoritmos.c](compiladores/mini_gcc/algoritmos.c) | Pré-processador `#define`, compilação paralela real de 3 unidades `.c` -> `.obj` em worker threads via `rotina`/`Tarefa<texto>` + `assincrona`/`aguardar`, Linker estático com tabela global de símbolos/relocações e VM |
| [Mini-Clang C++](compiladores/mini_clang_cpp/mini_clang.delegua)                | [programa.cpp](compiladores/mini_clang_cpp/programa.cpp)                                                                                       | `namespace` (`::`), sobrecarga de funções com Itanium Name Mangling (`_Z...`), classes, construtores, herança pública, lowering de métodos com `this` e `cout <<`                                                        |
| [Mini-Rust + Borrow Checker](compiladores/mini_rust/mini_rust.delegua)          | [programa.rs](compiladores/mini_rust/programa.rs)                                                                                              | Ownership/Move (`String` vs `Copy` `i64`), `let mut`, `&T` vs `&mut T`, liberação lexical de lifetimes (`{ ... }`), validação de `E0382`, `E0596`, `E0502`, `E0499`, `E0506` e execução na VM com referências mutáveis   |
| [Compilador MiniLang (5 fases)](compiladores/minipascal/compilador.delegua)     | [programa.ml](compiladores/minipascal/programa.ml)                                                                                             | Lexer, parser com AST polimórfica (`classe abstrata Expr`/`Stmt`), verificador de tipos estático, otimizador (folding + DCE), gerador de bytecode e VM                                                                   |
| [CPU Mini-RISC + Assembler](compiladores/riscv_vm/vm.delegua)                   | [programa.asm](compiladores/riscv_vm/programa.asm)                                                                                             | Emulador de CPU de 16 registradores (`zero`/`sp`/`lr`), RAM, `PUSH`/`POP`, `CALL`/`RET` e montador de 2 passes executando MDC, fatorial recursivo e Bubble Sort in-place                                                 |
| [Compilador Brainfuck Otimizador](compiladores/brainfuck/bf_compilador.delegua) | embutidos                                                                                                                                      | Pipeline multi-passe: RLE, peephole (`Zerar` e `Transferir` em O(1)), resolução de saltos e VM de fita de bytes                                                                                                          |

## Interpretadores e Autômatos (`interpretadores/`)

| Projeto                                                              | Entrada                                                | Destaques técnicos                                                                                                                                                 |
| -------------------------------------------------------------------- | ------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| [MiniLisp (Scheme)](interpretadores/minilisp/lisp.delegua)           | [programa.scm](interpretadores/minilisp/programa.scm)  | S-expressions, ambientes léxicos encadeados, closures de primeira classe com `set!`, `let*`, `cond`, currying, `map`/`filter`/`foldl` e Quicksort funcional        |
| [MiniForth](interpretadores/miniforth/forth.delegua)                 | [programa.fth](interpretadores/miniforth/programa.fth) | Linguagem concatenativa com compilação threaded-code (`: ... ;`), backpatching de `IF/ELSE/THEN`, `BEGIN/WHILE/REPEAT`, `DO/LOOP/I`, `RECURSE`, `VARIABLE` e `.""` |
| [Motor de Regex (PikeVM)](interpretadores/regex_vm/regex_vm.delegua) | embutidos                                              | Parser de regex -> AST polimórfica -> bytecode NFA de Thompson -> PikeVM em tempo linear O(n·m), imune a backtracking exponencial                                  |

## Como executar todos

```sh
python3 testes/exemplos.py --examples-dir "$(pwd)/exemplos/compiladores_e_vms"
```
