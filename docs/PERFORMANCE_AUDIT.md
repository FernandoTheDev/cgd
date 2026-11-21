# Auditoria de Desempenho e Geração de Código — CGD (`PERFORMANCE_AUDIT.md`)

Data: 21/11/2026
Plataforma validada: Linux x86_64 (`LDC2`, `DMD`, `GCC -O2`, `Clang -O2`, Boehm GC)
Caso de estudo principal: **DCC 0.1.0 (Delégua C Compiler)** + suíte reproduzível de microbenchmarks (`scripts/benchmark_suite.py`)

---

## 1. Resumo Executivo

A auditoria empírica do código C gerado pelo CGD para o **DCC 0.1.0** (12 módulos `.delegua` + bibliotecas padrão) revelou que o arquivo C inicial possuía **56.479 linhas** e **9.155.945 bytes (8,73 MiB)**, levando **29,42 s** para compilar com `gcc -O2` e **1.549,3 ms** para o binário do DCC compilar `examples/hello_libc.c` (processando os cabeçalhos reais da glibc em `/usr/include`).

Após as otimizações implementadas no frontend (`lexer`, `parser`, `semantic/constants`), otimizador (`opt/constant_folding`), backend C (`backend/c/codegen.d`), runtime C (`vendor/delegua-runtime`) e biblioteca padrão (`bibliotecas/bytes.delegua`), mantendo 100% da semântica e dos contratos da linguagem:

- **Volume de C gerado para o DCC 0.1.0**:
  - Linhas de C: **56.479 → 37.829 (-33,0% / -18.650 linhas)**
  - Bytes de C: **9.155.945 B (8,73 MiB) → 4.257.615 B (4,06 MiB) (-53,5% / -4,90 MB)**
  - Tabela `cgd_source_sites[]`: **3.713.928 B → 282.091 B (-92,4% / 13,2x menor)**
  - Temporários `cgd_tmp_*`: **29.751 → 10.877 (-63,4% / -18.874 temporários)**
  - Cópias redundantes de identificadores (`cgd_tmp = var`): **12.169 → 600 (-95,1%)**
  - Cópias redundantes de `isto` (`cgd_tmp = isto`): **3.328 → 0 (-100,0%)**
  - Declarações `volatile delegua_value`: **1.667 → 79 (-95,3%)**
  - Chamadas a `delegua_is_truthy`: **2.029 → 253 (-87,5%)**
- **Desempenho do DCC 0.1.0 compilando `hello_libc.c` (com headers reais da glibc)**:
  - Tempo de execução (`gcc -O2`): **1.549,3 ms → 682,0 ms (2,27x mais rápido / -56,0%)**
  - Tempo de execução (`clang -O2`): **1.549,3 ms → 692,9 ms (2,24x mais rápido / -55,3%)**
  - Tamanho do binário final do DCC: **4.137.808 B → 3.859.264 B (`gcc -O2`, -6,7%)** e **3.592.600 B (`clang -O2`, -13,2%)**
- **Desempenho dos Microbenchmarks (`gcc -O2` / `clang -O2`)**:
  - `string_unicode_preproc`: **22.916,00 ms → 9,75 ms (`gcc -O2`) / 9,26 ms (`clang -O2`) (~2.350x–2.475x mais rápido)**
  - `fn_calls`: **365,67 ms → 30,34 ms (`gcc -O2`, 12,05x) / 25,55 ms (`clang -O2`, 14,31x)**
  - `int_loop`: **397,68 ms → 57,21 ms (`gcc -O2`, 6,95x) / 43,77 ms (`clang -O2`, 9,09x)**
  - `oop_fields_methods`: **688,24 ms → 103,21 ms (`gcc -O2`, 6,67x) / 96,71 ms (`clang -O2`, 7,12x)**
  - `stdlib_bytes_json`: **244,47 ms → 53,05 ms (`gcc -O2`, 4,61x) / 52,45 ms (`clang -O2`, 4,66x)**
  - `array_ops`: **115,42 ms → 40,95 ms (`gcc -O2`, 2,82x) / 38,60 ms (`clang -O2`, 2,99x)**
  - `float_loop`: **233,72 ms → 96,72 ms (`gcc -O2`, 2,42x) / 87,70 ms (`clang -O2`, 2,67x)**
  - `dict_ops`: **114,68 ms → 69,95 ms (`gcc -O2`, 1,64x) / 71,73 ms (`clang -O2`, 1,60x)**

---

## 2. Tabela Consolidada de Gargalos Identificados e Ganhos Medidos

| Gargalo                                                                                  | Componente                                                                                     | Causa raiz                                                                                                                                                                            | Evidência (Antes)                                                                                                                    | Correção aplicada                                                                                                                                                                    | Ganho medido (Depois)                                                                                                                                 |
| :--------------------------------------------------------------------------------------- | :--------------------------------------------------------------------------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | :----------------------------------------------------------------------------------------------------------------------------------- | :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | :---------------------------------------------------------------------------------------------------------------------------------------------------- |
| **AUD-02**: Inflação da tabela `cgd_source_sites[]`                                      | `backend/c/codegen.d`                                                                          | O caminho absoluto completo do arquivo codificado em octal era repetido inline em cada um dos 19.767 descritores de localização.                                                      | Linha 3 do C do DCC tinha **3.713.928 bytes** (40,6% de todo o `.c`).                                                                | Deduplicação de nomes de arquivo em `static const char cgd_file_N[]` referenciados nos descritores.                                                                                  | `cgd_source_sites[]` caiu para **282.091 bytes (-92,4% / -3,43 MB)**.                                                                                 |
| **AUD-03**: Explosão de temporários `cgd_tmp_*`                                          | `backend/c/codegen.d`                                                                          | `materialize()` criava `delegua_value cgd_tmp_N` para todo `Identifier` (`isto`, `const`, variáveis locais sem mutação), `StringLit`, `FunctionExpr` e temporários já materializados. | **29.751** declarações `cgd_tmp_*` no DCC (52,7% das linhas), incluindo **12.169** cópias de variáveis e **3.328** cópias de `isto`. | `isAlreadyMaterializedNode`, `isImmutableIdentifier`, análise `canMutateVar`/`siblingsCanMutateVar` e proteção de autossombreamento `currentDeclaringVar`.                           | `cgd_tmp_*` caiu para **10.877 (-63,4%)**; cópias de `isto` caíram para **0 (-100%)**; cópias de identificadores caíram **95,1%**.                    |
| **AUD-04**: `volatile delegua_value` universal                                           | `backend/c/codegen.d`                                                                          | Toda variável local e parâmetro era declarado `volatile delegua_value`, forçando escrita/leitura em pilha em todas as funções.                                                        | **1.667** variáveis `volatile` em 258 funções do DCC, mesmo sem `tente/pegue`.                                                       | Análise `containsTryStmt`: `volatile` e `(void)&var;` restritos às funções que possuem `TryStmt`.                                                                                    | Variáveis `volatile` no DCC caíram de **1.667 para 79 (-95,3%)**.                                                                                     |
| **AUD-05**: Alocações GC e `ligar` em despacho de métodos e campos                       | `vendor/delegua-runtime` (`objetos.c`, `biblioteca.c`, `colecoes.c`) + `codegen.d`             | Toda chamada `obj.m()` alocava closure `ligar` no GC; toda leitura/escrita de campo alocava `create_text` no GC; todo `delegua_descr_nome` alocava struct no GC.                      | `oop_fields_methods`: **688,24 ms**; milhares de alocações efêmeras no GC por segundo.                                               | `delegua_chamar_membro`, `rt_chamar_metodo_padrao`, `rt_map_try_get_cstr`, buffer `stack_args[16]`, singletons estáticos `delegua_tipo` com `fast_tag`.                              | `oop_fields_methods`: **103,21 ms (`gcc`) / 96,71 ms (`clang`) (~6,7x–7,1x mais rápido)**.                                                            |
| **AUD-06**: Indexação e fatiamento UTF-8 $O(N^2)$ + alocação por literal e por caractere | `vendor/delegua-runtime` (`textos.c`, `valores.c`, `colecoes.c`, `biblioteca.c`) + `codegen.d` | `texto[i]` e `texto.fatiar(a, b)` varriam o UTF-8 desde o byte 0 a cada chamada; `create_text` alocava no GC para literais e strings de 1 byte; `juntar` concatenava em $O(N^2)$.     | `string_unicode_preproc`: **22.916,00 ms**; DCC compilando `hello_libc.c`: **1.549,3 ms**.                                           | Cache TLS de 8 slots com detecção ASCII 64-bit e cursor sequencial; `create_text_lit` zero-alloc; tabela estática `delegua_single_byte_strs[256]`; fatia contígua e `juntar` $O(N)$. | `string_unicode_preproc`: **9,75 ms (`gcc`) / 9,26 ms (`clang`) (~2.350x–2.475x mais rápido)**; DCC `hello_libc.c`: **682,0 ms (2,27x mais rápido)**. |
| **AUD-07**: Chamadas indiretas, checks redundantes de tipo e `delegua_is_truthy`         | `backend/c/codegen.d` + `delegua_rt.h`                                                         | Funções livres/estáticas conhecidas usavam `delegua_chamar`; `checked()` e `delegua_is_truthy` eram emitidos mesmo quando o tipo estático já estava provado.                          | `fn_calls`: **365,67 ms**; `int_loop`: **397,68 ms**; **2.029** chamadas a `delegua_is_truthy` no DCC.                               | `delegua_chamar_direto`, fast-paths `static inline` para inteiros, `nodeMatchesExactType` estendido e `truthyExpr` (`(.value.b1)`).                                                  | `fn_calls`: **30,34 ms (`gcc`, 12,05x) / 25,55 ms (`clang`, 14,31x)**; `int_loop`: **57,21 ms (`gcc`, 6,95x) / 43,77 ms (`clang`, 9,09x)**.           |
| **AUD-10**: Indireção dinâmica repetida em `cgd:bytes`                                   | `bibliotecas/bytes.delegua`                                                                    | Cada `obter`/`definir` reexecutava `importar("cgd:nativo").Primitivas` e despachava método dinâmico.                                                                                  | `stdlib_bytes_json`: **244,47 ms** (3.867 linhas / 467.529 B de C).                                                                  | Classe estrangeira direta `@definicao` `PrimitivasBytes` em `bibliotecas/bytes.delegua`.                                                                                             | `stdlib_bytes_json`: **53,05 ms (4,61x mais rápido)**; C gerado reduzido para **3.255 linhas / 327.582 B (-29,9%)**.                                  |

---

## 3. Comparativo Quantitativo Completo — Microbenchmarks

Todas as medições abaixo são a mediana de 3 execuções consecutivas após compilação com `./cgd -o` (`scripts/benchmark_suite.py`).

| Microbenchmark                                          | Execução Antes (`gcc -O2`) | Execução Depois (`gcc -O2`) | Execução Depois (`clang -O2`) | Speedup (`gcc` / `clang`) | Linhas C (Antes → Depois) |     Bytes C (Antes → Depois) |
| :------------------------------------------------------ | -------------------------: | --------------------------: | ----------------------------: | ------------------------: | ------------------------: | ---------------------------: |
| `int_loop` (2M iterações bitwise/soma)                  |                  397,68 ms |                **57,21 ms** |                  **43,77 ms** |         **6,95x / 9,09x** |          34 → 28 (-17,6%) |     4.132 → 2.063 B (-50,1%) |
| `float_loop` (1M iterações `real`)                      |                  233,72 ms |                **96,72 ms** |                  **87,70 ms** |         **2,42x / 2,67x** |          37 → 29 (-21,6%) |     4.743 → 2.263 B (-52,3%) |
| `fn_calls` (1M chamadas de função tipada)               |                  365,67 ms |                **30,34 ms** |                  **25,55 ms** |       **12,05x / 14,31x** |          50 → 40 (-20,0%) |     5.438 → 2.360 B (-56,6%) |
| `oop_fields_methods` (400k chamadas de método + campos) |                  688,24 ms |               **103,21 ms** |                  **96,71 ms** |         **6,67x / 7,12x** |         109 → 94 (-13,8%) |    14.634 → 7.578 B (-48,2%) |
| `array_ops` (200k push + 200k index/update)             |                  115,42 ms |                **40,95 ms** |                  **38,60 ms** |         **2,82x / 2,99x** |          63 → 46 (-27,0%) |     8.130 → 3.591 B (-55,8%) |
| `dict_ops` (50k escritas + 100k leituras)               |                  114,68 ms |                **69,95 ms** |                  **71,73 ms** |         **1,64x / 1,60x** |          66 → 52 (-21,2%) |     8.726 → 3.855 B (-55,8%) |
| `string_unicode_preproc` (115 KB UTF-8 scan + slice)    |               22.916,00 ms |                 **9,75 ms** |                   **9,26 ms** |       **2.350x / 2.475x** |         120 → 86 (-28,3%) |    17.505 → 7.438 B (-57,5%) |
| `stdlib_bytes_json` (50k byte ops + 400 objetos JSON)   |                  244,47 ms |                **53,05 ms** |                  **52,45 ms** |         **4,61x / 4,66x** |    3.867 → 3.255 (-15,8%) | 467.529 → 327.582 B (-29,9%) |

---

## 4. Comparativo Quantitativo Completo — Estudo de Caso DCC 0.1.0

| Métrica (DCC 0.1.0 — 12 módulos `.delegua`)              |       Antes (Baseline) |         Depois (Otimizado) |                         Variação |
| :------------------------------------------------------- | ---------------------: | -------------------------: | -------------------------------: |
| **Linhas de código C geradas (`-o`)**                    |                 56.479 |                 **37.829** |      **-33,0% (-18.650 linhas)** |
| **Tamanho do arquivo C gerado (`-o`)**                   | 9.155.945 B (8,73 MiB) | **4.257.615 B (4,06 MiB)** |            **-53,5% (-4,90 MB)** |
| **Tamanho da tabela `cgd_source_sites[]`**               |            3.713.928 B |              **282.091 B** |         **-92,4% (13,2x menor)** |
| **Declarações de temporários `cgd_tmp_*`**               |                 29.751 |                 **10.877** | **-63,4% (-18.874 temporários)** |
| **Cópias `cgd_tmp = <identificador>`**                   |                 12.169 |                    **600** |                       **-95,1%** |
| **Cópias `cgd_tmp = isto`**                              |                  3.328 |                      **0** |                      **-100,0%** |
| **Declarações `volatile delegua_value`**                 |                  1.667 |                     **79** |                       **-95,3%** |
| **Chamadas a `delegua_is_truthy`**                       |                  2.029 |                    **253** |                       **-87,5%** |
| **Tempo de emissão C (`./cgd -o --emitir-c`)**           |               812,7 ms |               **692,1 ms** |                       **-14,8%** |
| **Tempo de compilação total (`gcc -O2`)**                |            29.423,7 ms |            **28.790,0 ms** |                        **-2,2%** |
| **Tempo de compilação total (`clang -O2`)**              |            12.125,9 ms |            **11.965,7 ms** |                        **-1,3%** |
| **Tamanho do binário DCC (`gcc -O2`)**                   |            4.137.808 B |            **3.859.264 B** |            **-6,7% (-278,5 KB)** |
| **Tamanho do binário DCC (`clang -O2`)**                 | 4.137.808 B (ref. GCC) |            **3.592.600 B** |           **-13,2% (-545,2 KB)** |
| **Tempo do DCC compilando `hello_libc.c` (`gcc -O2`)**   |             1.549,3 ms |               **682,0 ms** |   **2,27x mais rápido (-56,0%)** |
| **Tempo do DCC compilando `hello_libc.c` (`clang -O2`)** |             1.549,3 ms |               **692,9 ms** |   **2,24x mais rápido (-55,3%)** |

---

## 5. Comandos para Reprodução

```sh
# 1. Recompilar runtime C e compilador CGD em modo release
./build-runtime
dub build --compiler=ldc2 --build=release

# 2. Executar a suíte de benchmarks com GCC e Clang
python3 scripts/benchmark_suite.py --cc=gcc --output out/bench_optimized_gcc.json
python3 scripts/benchmark_suite.py --cc=clang --output out/bench_optimized_clang.json

# 3. Inspecionar os relatórios JSON gerados
cat out/bench_optimized_gcc.json
cat out/bench_optimized_clang.json
```
