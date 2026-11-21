# Benchmark e Análise de Desempenho — Ciclo II

**Data:** 21/11/2026  
**Artefatos reproduzíveis:**

- `scripts/benchmark_suite.py`
- `out/bench_ciclo2_gcc.json`
- `out/bench_ciclo2_clang.json`

**Ambiente de medição:**

- Arquitetura/OS: Linux `x86_64`
- GCC `16.2.1`, Clang `22.1.8`, TinyCC `0.9.28rc` (`/usr/local/sbin/tcc`)
- CGD compilado com LDC `1.42.0` (`dub build --compiler=ldc2 --build=release`)
- Flags de execução: `-o` ativo no CGD (`-O2` no compilador C), warmup + 5 repetições com mediana reportada em ms (`min` e `max` registrados nos JSONs).

---

## 1. Aplicação Real: DCC v0.1.0 (`out/dcc_v010`, commit `25f3609`)

### 1.1 Evolução Pré-Ciclo I -> Pós-Ciclo I -> Pós-Ciclo II

| Métrica                      |        Pré-Ciclo I (GCC) | Pós-Ciclo I (GCC) |                Pós-Ciclo II (GCC) | Pós-Ciclo I (Clang) |              Pós-Ciclo II (Clang) |      Ganho Total (Ciclo II vs Baseline) |
| ---------------------------- | -----------------------: | ----------------: | --------------------------------: | ------------------: | --------------------------------: | --------------------------------------: |
| Linhas C emitidas            |                 `56.479` |          `37.829` |                      **`30.042`** |            `37.829` |                      **`30.042`** |        **-46,8%** (`-20,6%` vs Ciclo I) |
| Tamanho do C emitido         |            `9.156.614 B` |     `4.257.615 B` |                 **`3.620.677 B`** |       `4.257.615 B` |                 **`3.620.677 B`** |        **-60,5%** (`-15,0%` vs Ciclo I) |
| Tamanho do binário ELF       |            `4.137.808 B` |     `3.859.264 B` |                 **`3.528.152 B`** |       `3.592.600 B` |                 **`3.290.264 B`** |            **-14,7% GCC / -8,4% Clang** |
| Declarações `cgd_tmp_*`      | `29.751` (cgd_tmp total) |    `10.052` decls |                 **`7.917` decls** |      `10.052` decls |                 **`7.917` decls** |          **-21,2%** de decls vs Ciclo I |
| Variáveis `volatile`         |                  `1.667` |              `79` |                          **`67`** |                `79` |                          **`67`** |                              **-96,0%** |
| Chamadas `delegua_is_truthy` |                  `2.029` |             `253` |                         **`198`** |               `253` |                         **`198`** |                              **-90,2%** |
| Compilar `hello_libc.c`      |            `1.549,34 ms` |       `682,03 ms` | **`420,93 ms`** (`406,5`–`432,2`) |         `692,94 ms` | **`362,26 ms`** (`357,7`–`372,2`) | **3,68x GCC / 4,28x Clang vs Baseline** |

### 1.2 Métricas adicionais do C emitido no DCC v0.1.0 (Pós-Ciclo II)

- Funções de usuário emitidas (`cgd_user_*`): `1.180` (vs `34` funções mortas só em `cgd:json` removidas com a poda interprocedimental).
- Chamadas diretas estáticas (`delegua_chamar_direto`): `528` sites.
- Instanciações diretas (`delegua_instanciar`): `342` sites.
- Chamadas dinâmicas de membro (`delegua_chamar_membro`): `3.216` sites.
- Checagens de contrato (`delegua_assegurar_*`): `2.204` sites.
- Tempo total do build C (`--cc=clang -O2`): **`11.000,64 ms` (`11,0 s`)** vs GCC `-O2`: `261.172,38 ms`.

---

## 2. Aplicação Real: DCC v0.2.0 (`out/dcc_v020`, commit `6116502`)

O DCC v0.2.0 amplia o compilador C99 com IEEE-754 float32/NaN/Inf, structs/arrays/globals avançados, linker `.a`/weak/strong e diagnósticos expandidos.

| Métrica                                  | Antes do Ciclo II |                Pós-Ciclo II (GCC) |              Pós-Ciclo II (Clang) | Variação                      |
| ---------------------------------------- | ----------------: | --------------------------------: | --------------------------------: | ----------------------------- |
| Linhas C emitidas                        |          `51.617` |                      **`40.734`** |                      **`40.734`** | **-21,1%** (`-10.883` linhas) |
| Tamanho do C emitido                     |     `5.733.858 B` |                 **`4.900.245 B`** |                 **`4.900.245 B`** | **-14,5%** (`-833.613 B`)     |
| Tamanho do binário ELF                   |               N/M |                     `4.501.040 B` |                     `4.156.976 B` | —                             |
| Declarações `cgd_tmp_*`                  |               N/M |                          `10.949` |                          `10.949` | —                             |
| `volatile` / `delegua_is_truthy`         |               N/M |                     `163` / `357` |                     `163` / `357` | —                             |
| Diretas (`chamar_direto` / `instanciar`) |               N/M |                     `609` / `232` |                     `609` / `232` | —                             |
| Compilar `hello_libc.c`                  |               N/M | **`290,74 ms`** (`259,8`–`319,0`) | **`266,70 ms`** (`263,2`–`275,0`) | —                             |
| Tempo de build C (`-O2`)                 |               N/M |                    `37.363,07 ms` |                **`15.607,98 ms`** | Clang **2,39x** mais rápido   |

---

## 3. Fases do Compilador CGD (`cgd -o -t --emitir-c`)

Tempos medidos durante o benchmark no carregamento, análise, otimização e codegen C:

| Fase (`--tempo`)          |       DCC v0.1.0 (ms) |       DCC v0.2.0 (ms) |
| ------------------------- | --------------------: | --------------------: |
| Lendo arquivo             |     `0,011` – `0,041` |     `0,013` – `0,039` |
| Geração de tokens + AST   |     `0,085` – `0,110` |     `0,083` – `0,099` |
| Carregamento de módulos   |   `68,634` – `80,588` |  `88,205` – `105,539` |
| Análise semântica         | `154,274` – `175,736` | `216,111` – `223,521` |
| Otimização até ponto fixo |   `51,297` – `58,644` |   `53,113` – `54,448` |
| Lowering da AST           |     `2,523` – `2,958` |     `3,414` – `3,452` |
| Geração de código C       | `248,909` – `407,646` | `355,066` – `369,513` |
| Escrita do `.c`           |     `0,976` – `1,027` |     `1,314` – `1,371` |

---

## 4. Microbenchmarks (`scripts/benchmark_suite.py`)

### 4.1 Tempo de execução (mediana em ms — menor é melhor)

| Microbenchmark           | Pré-Ciclo I (GCC) | Pós-Ciclo I (GCC) |      Pós-Ciclo II (GCC) | Pós-Ciclo I (Clang) | Pós-Ciclo II (Clang) | Variação Ciclo II vs Ciclo I (GCC / Clang)            |
| ------------------------ | ----------------: | ----------------: | ----------------------: | ------------------: | -------------------: | ----------------------------------------------------- |
| `int_loop`               |          `397,68` |           `57,21` |                 `58,84` |             `43,77` |          **`42,47`** | `+2,8%` / `-3,0%`                                     |
| `float_loop`             |          `233,72` |           `96,72` | `132,79` (`103,97` min) |             `87,70` |          **`86,31`** | ruído max GCC / `-1,6%`                               |
| `fn_calls`               |          `365,67` |           `30,34` |                 `31,09` |             `25,55` |              `25,64` | estável (`~30` / `~25 ms`)                            |
| `oop_fields_methods`     |          `688,24` |          `103,21` |             **`84,56`** |             `96,71` |          **`75,00`** | **`-18,1%` / `-22,4%`** (**8,1x–9,2x** vs baseline)   |
| `array_ops`              |          `115,42` |           `40,95` |             **`29,58`** |             `38,60` |          **`25,18`** | **`-27,8%` / `-34,8%`**                               |
| `dict_ops`               |          `114,68` |           `69,95` |             **`54,82`** |             `71,73` |          **`46,38`** | **`-21,6%` / `-35,3%`**                               |
| `string_unicode_preproc` |       `22.916,00` |            `9,75` |              **`9,39`** |              `9,26` |           **`8,50`** | **`-3,7%` / `-8,2%`** (**~2.696x** Clang vs baseline) |
| `stdlib_bytes_json`      |          `244,47` |           `53,05` |             **`43,65`** |             `52,45` |          **`40,55`** | **`-17,7%` / `-22,7%`**                               |

### 4.2 Tamanho de código C nos microbenchmarks

| Microbenchmark           | Pré-Ciclo I (linhas / B) | Pós-Ciclo I (linhas / B) |                             Pós-Ciclo II (linhas / B) |
| ------------------------ | -----------------------: | -----------------------: | ----------------------------------------------------: |
| `int_loop`               |           `34` / `4.132` |           `28` / `2.063` |                                    **`25` / `1.978`** |
| `float_loop`             |           `37` / `4.743` |           `29` / `2.263` |                                    **`26` / `2.113`** |
| `fn_calls`               |           `50` / `5.438` |           `40` / `2.360` |                                    **`35` / `2.126`** |
| `oop_fields_methods`     |         `109` / `14.634` |           `94` / `7.578` |                                    **`82` / `6.799`** |
| `array_ops`              |           `63` / `8.130` |           `46` / `3.591` |                                    **`39` / `3.407`** |
| `dict_ops`               |           `66` / `8.726` |           `52` / `3.855` |                                    **`43` / `3.531`** |
| `string_unicode_preproc` |         `120` / `17.505` |           `86` / `7.438` |                                    **`71` / `6.411`** |
| `stdlib_bytes_json`      |      `3.867` / `467.529` |      `3.255` / `327.582` | **`1.515` / `150.320`** (**-54,1% bytes vs Ciclo I**) |

---

## 5. Perfil `gprof` e Estatísticas de GC

### 5.1 Perfil `gprof` Pós-Ciclo II (`dcc_v010`, Clang `-O2 -pg` compilando `hello_libc.c`)

O tempo total amostrado em CPU caiu para `0,15 s` na parte instrumentada (`cgd_user_*` e runtime):

- Principais consumidores remanescentes observados: `buscar_cstr` (`20,0%`), `conforme` (`13,3%`), `delegua_chamar_membro`, `adicionar`, `delegua_op_eq`, `delegua_op_in`, `juntar`, `rt_chamar_metodo_padrao`, `rt_hash_cstr` e `utf8_sample` (~`6,7%` cada na amostragem residual).
- Indica exatamente onde focar um eventual **Ciclo III**: slots de campos por índice em classes fechadas (reduzindo `buscar_cstr`), unboxing local de `inteiro`/`real`/`logico` (reduzindo chamadas a `conforme` e `cgd_tmp`) e otimizações de concatenação (`juntar`/`+`).

### 5.2 Boehm GC (`GC_PRINT_STATS=1`) compilando `hello_libc.c`

| Indicador GC      |  DCC v0.1.0 (GCC) | DCC v0.1.0 (Clang) | DCC v0.2.0 (GCC) | DCC v0.2.0 (Clang) |
| ----------------- | ----------------: | -----------------: | ---------------: | -----------------: |
| Coletas completas |              `19` |               `21` |             `20` |               `20` |
| Total alocado     | `1.016.091.168 B` |  `1.055.907.296 B` |  `560.779.600 B` |    `543.557.424 B` |
| Total liberado    |   `881.515.824 B` |    `983.264.240 B` |  `527.382.512 B` |    `463.099.248 B` |
| Heap máximo       |     `147.536 KiB` |      `133.664 KiB` |     `75.284 KiB` |       `74.260 KiB` |
| Tempo total de GC |       `31,727 ms` |        `25,795 ms` |      `18,707 ms` |        `19,025 ms` |

---

## 6. Comandos de Reprodução

```sh
./build-runtime
dub build --compiler=ldc2 --build=release
python3 scripts/benchmark_suite.py --cc=gcc --json-out=out/bench_ciclo2_gcc.json
python3 scripts/benchmark_suite.py --cc=clang --json-out=out/bench_ciclo2_clang.json
./cgd --cc=/usr/local/sbin/tcc -o -s out/tcc_cli_bin out/tcc_smoke.delegua
CGD=/home/fernandodev/cgd/cgd bash out/dcc_v010/bootstrap/verify.sh
CGD=/home/fernandodev/cgd/cgd bash out/dcc_v020/bootstrap/verify.sh
```
