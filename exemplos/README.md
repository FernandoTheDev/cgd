# Exemplos executáveis

Cada arquivo possui um contrato de teste na primeira linha. Rode todos com
`python3 testes/exemplos.py`: cada exemplo é compilado com e sem otimização,
sem ignorar arquivos. Esse runner reconhece os contratos atuais, incluindo a
entrada padrão dos exemplos interativos e a fase de compilação.

```sh
mkdir -p out
./cgd exemplos/linguagem/14_classes.delegua -s out/classes
./out/classes
```

## Percurso pela linguagem

| Exemplo                                                                        | Recurso                                |
| ------------------------------------------------------------------------------ | -------------------------------------- |
| [01_tipos.delegua](linguagem/01_tipos.delegua)                                 | Tipos e valores                        |
| [02_operadores.delegua](linguagem/02_operadores.delegua)                       | Operadores                             |
| [03_atribuicoes.delegua](linguagem/03_atribuicoes.delegua)                     | Atribuições múltiplas                  |
| [04_condicionais.delegua](linguagem/04_condicionais.delegua)                   | Condicionais e escolha                 |
| [05_lacos.delegua](linguagem/05_lacos.delegua)                                 | Laços e controle                       |
| [06_lacos_resultado.delegua](linguagem/06_lacos_resultado.delegua)             | Laços como expressões                  |
| [07_funcoes.delegua](linguagem/07_funcoes.delegua)                             | Parâmetros padrão e variáveis          |
| [08_funcoes_valores.delegua](linguagem/08_funcoes_valores.delegua)             | Funções como valores e callbacks       |
| [09_vetores.delegua](linguagem/09_vetores.delegua)                             | Métodos de vetores                     |
| [10_compreensao_fatias.delegua](linguagem/10_compreensao_fatias.delegua)       | Compreensão e fatias                   |
| [11_dicionarios.delegua](linguagem/11_dicionarios.delegua)                     | Dicionários e desestruturação          |
| [12_tuplas.delegua](linguagem/12_tuplas.delegua)                               | Tuplas e contratos                     |
| [13_texto_unicode.delegua](linguagem/13_texto_unicode.delegua)                 | Texto e Unicode                        |
| [14_classes.delegua](linguagem/14_classes.delegua)                             | Classes                                |
| [15_heranca.delegua](linguagem/15_heranca.delegua)                             | Herança e métodos ligados              |
| [16_privacidade_acessores.delegua](linguagem/16_privacidade_acessores.delegua) | Privacidade e acessores                |
| [17_excecoes.delegua](linguagem/17_excecoes.delegua)                           | Exceções                               |
| [18_finalmente_retorno.delegua](linguagem/18_finalmente_retorno.delegua)       | Finalmente em retornos e laços         |
| [19_excecoes_tipadas.delegua](linguagem/19_excecoes_tipadas.delegua)           | Exceções tipadas                       |
| [20_clonagem.delegua](linguagem/20_clonagem.delegua)                           | Clonagem e ciclos                      |
| [21_biblioteca.delegua](linguagem/21_biblioteca.delegua)                       | Biblioteca nativa                      |
| [22_contratos_aliases.delegua](linguagem/22_contratos_aliases.delegua)         | Contratos através de aliases           |
| [23_decoradores.delegua](linguagem/23_decoradores.delegua)                     | Decoradores                            |
| [24_assercoes.delegua](linguagem/24_assercoes.delegua)                         | Asserções                              |
| [25_escopos.delegua](linguagem/25_escopos.delegua)                             | Escopos e funções internas sem captura |
| [26_ctfe.delegua](linguagem/26_ctfe.delegua)                                   | Avaliação em compilação                |
| [27_entrada.delegua](linguagem/27_entrada.delegua)                             | Entrada padrão                         |

| [28_metodos_texto.delegua](linguagem/28_metodos_texto.delegua) | Métodos de texto |
| [29_metodos_numero.delegua](linguagem/29_metodos_numero.delegua) | Métodos de número |
| [30_metodos_vetor.delegua](linguagem/30_metodos_vetor.delegua) | Métodos de vetor |
| [31_metodos_dicionario.delegua](linguagem/31_metodos_dicionario.delegua) | Métodos de dicionário |
| [32_objeto_e_metodos.delegua](linguagem/32_objeto_e_metodos.delegua) | Métodos de Objeto |
| [33_aleatoriedade.delegua](linguagem/33_aleatoriedade.delegua) | Intervalos de aleatoriedade |
| [34_lacos_variantes.delegua](linguagem/34_lacos_variantes.delegua) | Variações de laços |
| [35_bits_e_atribuicoes.delegua](linguagem/35_bits_e_atribuicoes.delegua) | Bits e atribuições |

## Os próximos passos

Depois dos fundamentos, experimente [destrutores](linguagem/36_destrutores.delegua),
[dicionário.obter](linguagem/37_dicionario_obter.delegua),
[interfaces, classes abstratas e arrows](linguagem/38_contratos.delegua),
[valores padrão](linguagem/39_inicializacao.delegua) e
[enums em diferentes escopos](linguagem/40_enums_escopos.delegua).

Para tarefas do dia a dia, há exemplos de [textos](bibliotecas/textos.delegua),
[estatística](bibliotecas/estatistica.delegua), [caminhos](bibliotecas/caminhos.delegua)
e [coleções](bibliotecas/colecoes.delegua). São programas pequenos: rode, mude uma
entrada e veja o que acontece antes de partir para a calculadora ou o MiniJS.

## Módulos

[Importação](modulos/01_importacao.delegua) usa a
[biblioteca local](modulos/lib/calculos.delegua). O caminho de importação é
relativo à fonte que o declara. A biblioteca também possui contrato e é validada
como unidade independente.

## Exemplos de falhas esperadas

Os arquivos em [seguranca/](seguranca/) são exemplos de proteção do compilador ou
do runtime: capturas, FFI, importação dinâmica, privacidade, contrato indireto,
imutabilidade de tuplas e overflow. Não devem encerrar com sucesso.

## Contratos

- `//! texto`: exige compilação bem-sucedida, status 0 e a saída indicada; `\n` representa nova linha.
- `//# N`: exige o status N na compilação ou execução, para compatibilidade com o catálogo histórico.
- `//? fase: compilacao` ou `execucao`: fixa a fase validada. Em `compilacao`, não executa o binário.
- `//? erro: trecho`: exige que o diagnóstico contenha o trecho.
- `//? saida: expressão`: valida uma expressão regular multilinha na saída.
- `//? ausente: expressão`: rejeita uma expressão regular nos diagnósticos e saída.
- `//? diretorio: fonte`: executa a partir da pasta do exemplo, para fixtures relativas.
- `//? entrada: Ada\n`: fornece a entrada padrão, preservando testes reproduzíveis.
- `//$`: marcador histórico de otimização; o runner Python testa os dois modos independentemente dele.

Os exemplos históricos na raiz e em `ctfe/` continuam fazendo parte da suíte.
Nenhum exemplo demonstra carregamento nativo arbitrário como recurso permitido.

## Engenharia do compilador

Os exemplos em `compilador/` mostram contratos que os passes devem preservar:

| Exemplo                                                          | Contrato                                           |
| ---------------------------------------------------------------- | -------------------------------------------------- |
| [Constantes e escopos](compilador/01_constantes_escopos.delegua) | Propagação pela identidade da declaração           |
| [Efeitos](compilador/02_efeitos.delegua)                         | Chamadas observáveis não desaparecem               |
| [Fluxo](compilador/03_fluxo.delegua)                             | Aviso de código morto e preservação de finalmente  |
| [Curto-circuito](compilador/04_curto_circuito.delegua)           | Ramos descartados não executam                     |
| [Diagnósticos](compilador/05_diagnosticos.delegua)               | Recuperação de mais de um erro                     |
| [Sugestão](compilador/06_sugestao.delegua)                       | Sugestão de símbolo existente                      |
| [Métodos e padrões](compilador/07_metodos_e_padroes.delegua)     | Travessia de métodos, lambdas e padrões            |
| [Módulos](compilador/08_otimizacao_modulos.delegua)              | Inicialização única com referências compartilhadas |

Experimente `./cgd exemplo.delegua --verificar --diagnosticos=json` para análise
sem gerar executável, ou `--emitir-c -o -s out/exemplo` para inspecionar o C.

As regressões [CTFE e escopos](compilador/09_ctfe_fluxo_escopos.delegua),
[CTFE e exceção tratável](compilador/10_ctfe_excecao.delegua) e
[CTFE e contrato de tipo](compilador/11_ctfe_contrato.delegua) mostram que avaliar
em compilação deve preservar o mesmo comportamento da execução nativa.

Os exemplos [divisão estática](compilador/12_divisao_estatica.delegua) e
[índice Unicode](compilador/13_indice_unicode.delegua) falham antes de gerar C,
com E3101 e E3103. [Falha tratada](compilador/14_falha_tratada.delegua) demonstra
um aviso W3101 em região com pegue, preservando o tratamento em execução.

Exemplos de destruição, dicionários e I/O, já incluídos na validação:

- [Destrutores explícitos](linguagem/36_destrutores.delegua)
- [Métodos de dicionário](linguagem/37_dicionario_obter.delegua)
- [Navegação de JSON](bibliotecas/json_navegacao.delegua)
- [Classe Arquivo](bibliotecas/arquivos.delegua)

I/O real e ClienteHTTP/RespostaHTTP têm contratos isolados em `testes/expansao.py`,
com arquivos temporários e servidor HTTP de loopback.

`perceptron2` exige os 24 checks internos sem falhas; `perceptron3` exige 8/8
acertos. `minigpt` preserva o treinamento de 150 épocas: a matriz valida apenas
compilação/vínculo desse experimento longo, sem afirmar validação de seu treino.

## Calculadora, VMs, interpretadores e compiladores

[Calculadora](calculadora.delegua) implementa lexer, parser, compilação para bytecode
e VM de expressões, com saída exata 90/15/25.
[MiniJS](minijs/jsvm.delegua) usa [programa.js](minijs/programa.js) como fixture:
fibonacci, funções, vetores, objetos, laços e escopos têm saída exata verificada.
É um programa didático em Delégua; não habilita integração JS ou compatibilidade
ECMAScript no compilador. O contrato `diretorio: fonte` mantém o caminho relativo
válido também ao testar cópias formatadas.

Projetos maiores reunidos em [compiladores_e_vms/](compiladores_e_vms/README.md),
organizados entre `compiladores/` e `interpretadores/`:

| Projeto                                                                               | Categoria     | O que implementa                                                                                                                          |
| ------------------------------------------------------------------------------------- | ------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| [C99 Nativo (ASM + ELF64)](compiladores_e_vms/compiladores/c_nativo/c_nativo.delegua) | Compilador    | Projeto modular (7 arquivos): Lexer, Parser, Semântica, CFG/SSA + otimizador, **Backend Assembly x86_64** e **Backend ELF64 nativo**      |
| [Mini-LLVM](compiladores_e_vms/compiladores/mini_llvm/mini_llvm.delegua)              | Compilador    | IR SSA (`.ll`), verificador SSA, ConstProp/Folding, DCE, CFG reachability, alocador de registradores Linear Scan e executor com nós `phi` |
| [Mini-GCC + Linker](compiladores_e_vms/compiladores/mini_gcc/mini_gcc.delegua)        | Compilador    | Pré-processador `#define`, compilação paralela de 3 arquivos `.c` -> `.obj` via `rotina`/`Tarefa<texto>`, Linker estático e VM            |
| [Mini-Clang C++](compiladores_e_vms/compiladores/mini_clang_cpp/mini_clang.delegua)   | Compilador    | `namespace`, sobrecarga com Itanium Name Mangling (`_Z...`), classes, herança, lowering com `this` e `cout <<`                            |
| [Mini-Rust + Borrow](compiladores_e_vms/compiladores/mini_rust/mini_rust.delegua)     | Compilador    | Ownership/Move, `let mut`, `&T`/`&mut T`, lifetimes lexicais, Borrow Checker (`E0382`/`E0596`/`E0502`/`E0499`/`E0506`) e VM               |
| [MiniLang (5 fases)](compiladores_e_vms/compiladores/minipascal/compilador.delegua)   | Compilador    | Lexer, parser com AST polimórfica (`classe abstrata`), verificador de tipos, otimizador (folding/DCE) e VM                                |
| [CPU Mini-RISC](compiladores_e_vms/compiladores/riscv_vm/vm.delegua)                  | Compilador/VM | Emulador de CPU de 16 registradores (`zero`/`sp`/`lr`), RAM, pilha e assembler de 2 passes (MDC, fatorial recursivo e Bubble Sort)        |
| [Brainfuck Otim.](compiladores_e_vms/compiladores/brainfuck/bf_compilador.delegua)    | Compilador/VM | RLE, peephole (`Zerar` e `Transferir` em O(1)), resolução de saltos e VM de fita de bytes                                                 |
| [MiniLisp](compiladores_e_vms/interpretadores/minilisp/lisp.delegua)                  | Interpretador | Scheme com S-expressions, ambientes léxicos, closures mutáveis (`set!`), currying, `map`/`filter`/`foldl` e Quicksort funcional           |
| [MiniForth](compiladores_e_vms/interpretadores/miniforth/forth.delegua)               | Interpretador | Linguagem concatenativa threaded-code com `: ... ;`, `RECURSE`, `IF/ELSE/THEN`, `BEGIN/WHILE/REPEAT`, `DO/LOOP/I` e `VARIABLE`            |
| [Regex PikeVM](compiladores_e_vms/interpretadores/regex_vm/regex_vm.delegua)          | Interpretador | Parser de regex -> bytecode NFA de Thompson -> PikeVM em tempo linear O(n·m), imune a backtracking exponencial                            |

## Ferramentas de sistema

Comece por [Processo](bibliotecas/processo.delegua) e [Ambiente](bibliotecas/ambiente.delegua).
Os exemplos de [Sistema](bibliotecas/sistema.delegua), [Tempo](bibliotecas/tempo.delegua)
e [IO](bibliotecas/io.delegua) cobrem a base. Depois experimente
[CLI](bibliotecas/cli.delegua), [Logger](bibliotecas/log.delegua) e
[Algoritmos](bibliotecas/algoritmos.delegua). APIs, dependências e erros estão
no [guia de sistema](../docs/stdlib-sistema.md).

### Servidor HTTP

[servidor/http.delegua](servidor/http.delegua) cria rotas locais, responde JSON,
captura parâmetros e encerra por uma rota do exemplo. O contrato do catálogo
verifica compilação; `python3 testes/servidor.py` valida a comunicação real.

## Assincronismo, rotinas paralelas, mixins e bibliotecas avançadas

- [Assincronismo e Promessas](linguagem/41_assincronismo.delegua)
- [Rotinas paralelas e Canal](linguagem/42_rotinas.delegua)
- [Campos estáticos, mescla e envelopes em métodos](linguagem/43_estaticos_mescla.delegua)
- [Bytes, Cripto, Compressão, SQLite e DataHora](bibliotecas/bytes_cripto_sqlite.delegua)
