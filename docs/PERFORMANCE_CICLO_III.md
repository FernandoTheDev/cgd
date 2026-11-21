# Relatório de Performance do CGD — Ciclo III

**Data:** 21/11/2026  
**CGD:** `0.9.0` (compilado com LDC `1.42.0` `--build=release`)  
**Compiladores C avaliados:** Clang `22.1.8`, GCC `16.2.1`, TinyCC `0.9.28rc`  
**Hardware:** Intel Core i5-11300H (8 threads), 15 GiB RAM, Linux `7.2.5-200.fc44.x86_64`  
**Dados brutos JSON:**
- Ciclo II (baseline): [`out/bench_ciclo2_clang.json`](file:///home/fernandodev/cgd/out/bench_ciclo2_clang.json), [`out/bench_ciclo2_gcc.json`](file:///home/fernandodev/cgd/out/bench_ciclo2_gcc.json)
- Ciclo III (atual): [`out/bench_ciclo3_clang.json`](file:///home/fernandodev/cgd/out/bench_ciclo3_clang.json), [`out/bench_ciclo3_gcc.json`](file:///home/fernandodev/cgd/out/bench_ciclo3_gcc.json)

---

## 1. Metodologia

- Execução **estritamente sequencial** por meio de [`scripts/benchmark_suite.py`](file:///home/fernandodev/cgd/scripts/benchmark_suite.py) (1 *warmup* + 5 execuções cronometradas por benchmark, reportando `min / mediana / max`).
- Os 8 microbenchmarks são idênticos aos do Ciclo II para comparação direta.
- Para o aplicativo real **DCC 0.2.0**, são comparados:
  - Compilação de `examples/hello_libc.c` (headers reais da `glibc`, 5 repetições após *warmup*) + telemetria `GC_PRINT_STATS=1`.
  - Auto-compilação completa sobre entrada congelada (`frozen_dcc.c`, 5,05 MiB) nos relatórios cruzados do DCC ([`PERFORMANCE_CICLO_IV.md`](file:///home/fernandodev/dcc/docs/PERFORMANCE_CICLO_IV.md)).

---

## 2. Microbenchmarks — Ciclo II vs. Ciclo III

### 2.1. Backend `clang -O2`

| Microbenchmark | Ciclo II Mediana (ms) | Ciclo III Mediana (ms) | Ciclo III (min / max) | Ganho |
| --- | ---: | ---: | --- | ---: |
| `int_loop` | `42,47` | `42,60` | `42,18 / 42,96` | `1,00×` (estável) |
| `float_loop` | `86,31` | **`70,02`** | `69,35 / 70,87` | **`1,23×`** (-18,9%) |
| `fn_calls` | `25,64` | **`24,92`** | `24,56 / 25,38` | **`1,03×`** (-2,8%) |
| `oop_fields_methods` | `75,00` | **`24,20`** | `23,88 / 25,04` | **`3,10×`** (-67,7%) |
| `array_ops` | `25,18` | **`22,83`** | `20,97 / 23,42` | **`1,10×`** (-9,3%) |
| `dict_ops` | `46,38` | **`36,60`** | `36,24 / 36,97` | **`1,27×`** (-21,1%) |
| `string_unicode_preproc` | `8,50` | **`6,77`** | `6,70 / 6,97` | **`1,26×`** (-20,4%) |
| `stdlib_bytes_json` | `40,55` | **`19,57`** | `18,60 / 19,76` | **`2,07×`** (-51,7%) |

### 2.2. Backend `gcc -O2`

| Microbenchmark | Ciclo II Mediana (ms) | Ciclo III Mediana (ms) | Ciclo III (min / max) | Ganho |
| --- | ---: | ---: | --- | ---: |
| `int_loop` | `58,84` | `60,53` | `58,74 / 68,82` | `0,97×` (ruído CPU) |
| `float_loop` | `132,79` | **`85,13`** | `83,51 / 88,18` | **`1,56×`** (-35,9%) |
| `fn_calls` | `31,09` | **`30,30`** | `29,49 / 30,42` | **`1,03×`** (-2,5%) |
| `oop_fields_methods` | `84,56` | **`29,72`** | `29,37 / 31,89` | **`2,85×`** (-64,9%) |
| `array_ops` | `29,58` | **`25,00`** | `23,81 / 25,18` | **`1,18×`** (-15,5%) |
| `dict_ops` | `54,82` | **`39,43`** | `36,88 / 41,78` | **`1,39×`** (-28,1%) |
| `string_unicode_preproc` | `9,39` | **`7,41`** | `7,23 / 8,00` | **`1,27×`** (-21,1%) |
| `stdlib_bytes_json` | `43,65` | **`19,07`** | `19,00 / 19,70` | **`2,29×`** (-56,3%) |

### Análise dos Ganhos
- **`oop_fields_methods` (`3,10×` em Clang, `2,85×` em GCC)**: efeito combinado de slots inline (`o->slots[idx]`), inline caching monomórfico (`delegua_prop_ic`/`delegua_def_ic`/`delegua_chamar_ic`), checagem inline `validar_slot_valor` e compilação do runtime em `-O2`.
- **`stdlib_bytes_json` (`2,07×` em Clang, `2,29×` em GCC)**: beneficia-se simultaneamente do runtime em `-O2`, checagens FFI inline em `foreign.d` (eliminando `delegua_assegurar_descr` + `delegua_descr_nome` em 100.000 chamadas `definir`/`obter` de `Bytes`) e ICs sobre os 126 callsites de método + 75 acessos de propriedade.
- **`float_loop`, `dict_ops`, `string_unicode_preproc`, `array_ops` (`1,10×–1,56×`)**: ganho direto da otimização `-O2` de `libdelegua_rt.o` e do `delegua_chamar_ic` sobre métodos nativos.

---

## 3. Aplicação Real — DCC 0.2.0 (`examples/hello_libc.c`)

Nota metodológica: no Ciclo III o próprio código-fonte do DCC 0.2.0 também evoluiu (adição de `-fmem-report`, `CallInfoSSA`, `Bytes` no lexer/codegen/ELF e tracking de `RAX`), elevando o número de funções emitidas de `1.574` para `1.642`.

| Métrica (DCC 0.2.0) | Ciclo II (`clang -O2`) | Ciclo III (`clang -O2`) | Ciclo II (`gcc -O2`) | Ciclo III (`gcc -O2`) |
| --- | ---: | ---: | ---: | ---: |
| Emissão C (`cgd -o --emitir-c`) | `934,75 ms` | `993,13 ms` | `983,72 ms` | `987,90 ms` |
| Build completo (`cgd -o`) | `15,61 s` | `17,64 s` | `37,36 s` | `40,94 s` |
| Linhas C geradas | `40.734` | `42.915` | `40.734` | `42.915` |
| Volume C gerado | `4.900.245 B` | `5.255.575 B` | `4.900.245 B` | `5.255.575 B` |
| Tamanho binário DCC | `4.156.976 B` | `4.658.896 B` | `4.501.040 B` | `5.015.320 B` |
| `delegua_chamar_membro` | `4.324` | **`0`** | `4.324` | **`0`** |
| `delegua_chamar_ic` | `0` | **`4.479`** | `0` | **`4.479`** |
| `delegua_prop_ic` / `delegua_def_ic` | `0 / 0` | **`7.311 / 781`** | `0 / 0` | **`7.311 / 781`** |
| **`hello_libc.c` mediana** | `266,70 ms` | **`168,46 ms` (-36,8%)** | `290,74 ms` | **`168,08 ms` (-42,2%)** |
| `hello_libc.c` (min / max) | `263,2 / 275,0 ms` | `164,7 / 171,4 ms` | `259,8 / 319,0 ms` | `157,8 / 184,5 ms` |
| Ciclos GC (`hello_libc.c`) | `20` | **`11` (-45%)** | `20` | **`11` (-45%)** |
| Tempo total de GC (`complete_gc_ms`) | `19,03 ms` | **`11,42 ms` (-40%)** | `18,71 ms` | **`12,16 ms` (-35%)** |
| Alocação GC total (`hello_libc.c`) | `543,56 MB` | **`461,54 MB` (-15,1%)** | `560,78 MB` | **`521,80 MB` (-7,0%)** |

---

## 4. Contribuição Isolada das Otimizações de Performance na Carga Pesada (`frozen_dcc.c`)

Na auto-compilação da entrada congelada `frozen_dcc.c` (5,05 MiB, ~865k tokens, `clang -O2`), cada intervenção do CGD teve seu efeito medido individualmente:

| Etapa (CGD + DCC) | Tempo Total | Delta vs. Anterior | Fator vs. Baseline |
| --- | ---: | ---: | ---: |
| Baseline Ciclo II (`libdelegua_rt.o -O0`, objetos em `hashmap`) | `29,94 s` | — | `1,00×` |
| + CGD Slots Fixos Inline (`objetos.c`) | `21,09 s` | `-8,85 s (-29,6%)` | `1,42×` |
| + CGD Coleções Vazias Preguiçosas + `Bytes` crescível + Isolamento GC | `20,63 s` | `-0,46 s` | `1,45×` |
| + **CGD Runtime em `-O2`** (`vendor/delegua-runtime/build`) | **`11,68 s`** | **`-8,95 s (-43,4%)`** | **`2,56×`** |
| + **CGD Inline Caching Monomórfico** (`prop_ic`/`def_ic`/`chamar_ic`) | **`9,71 s`** | **`-1,97 s (-16,9%)`** | **`3,08×`** |
| + **CGD FFI Fast-Check + Slot Type-Check Inline** + Preproc/IR DCC | **`8,93 s`** | **`-0,78 s (-8,0%)`** | **`3,35×`** |
| + DCC Intra-Block RAX Tracking (mediana 3 reps finais) | **`8,56 s`** | **`-0,37 s (-4,1%)`** | **`3,50×`** |

---

## 5. Trade-offs Registrados

- **Tempo de build C (`-O2`)**: a introdução de `cgd_ic[]` (12.571 ponteiros estáticos) e o crescimento natural do código do DCC elevaram o build de `15,6 s → 17,6 s` em Clang (`-O2`) e `37,4 s → 40,9 s` em GCC (`-O2`). Em contrapartida, o build em `-O0` permanece extremamente rápido (`1,03 s` em TinyCC, `2,32 s` em Clang, `6,82 s` em GCC) e o tempo de execução caiu até **3,50×**.
- **Tamanho de `libdelegua_rt.o`**: passou a `1,7 MB` compilado em `-O2` (com informações de debug/símbolos padrão de relocável).
