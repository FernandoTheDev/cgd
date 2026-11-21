# Terceira Auditoria Técnica Profunda do CGD (Ciclo III — Integração CGD × DCC)

**Data:** 21/11/2026  
**Versão do CGD:** `0.9.0` (branch `dev`, commit base `9038032` + modificações acumuladas dos Ciclos I–III)  
**Submódulo do runtime C:** `vendor/delegua-runtime` (branch `dev`, commit base `fdd0463` + Ciclos I–III)  
**Carga real de engenharia cruzada:** DCC `0.2.0` (`/home/fernandodev/dcc`, branch `master`, commit base `686efc3`)  
**Ambiente:** Linux `7.2.5-200.fc44.x86_64`, Intel Core i5-11300H (8 threads), 15 GiB RAM; LDC `1.42.0`, DMD `v2.111.0`, GCC `16.2.1`, Clang `22.1.8`, TinyCC `0.9.28rc`.

---

## 1. Sumário Executivo

Enquanto os Ciclos I e II reduziram drasticamente o volume de código C gerado, os temporários `cgd_tmp_*`, a indexação UTF-8 e as chamadas dinâmicas via poda interprocedimental, a execução de cargas reais de escala industrial — em especial a auto-compilação do **DCC 0.2.0** (~865 mil tokens, 442 mil nós AST, 804 mil instruções SSA) — expôs **quatro gargalos estruturais no runtime C e no codegen do CGD** que dominavam tanto o consumo de memória (6,4–7,1 GiB de RSS) quanto o tempo de CPU:

1. **Instâncias de classe apoiadas por `hashmap` completo**: cada objeto Delégua (`objeto`) alocava `struct objeto` + `struct hashmap` + tabela `buckets` + $F$ nós de entrada de 64 B para cada campo, resultando em 13–33 alocações GC e 864–2.880 bytes por instância.
2. **Alocação imediata de buffers em coleções vazias**: `create_vetor()` e `create_map()` alocavam buffers/buckets imediatamente mesmo quando o vetor/mapa jamais recebia elementos (ex.: 222.090 nós folha da AST do DCC).
3. **Runtime C compilado em `-O0`**: `vendor/delegua-runtime/build` compilava `libdelegua_rt.o` sem nenhuma flag de otimização (`-O2`), penalizando cada acesso a propriedade, método, string, vetor e mapa mesmo quando o programa do usuário era compilado com `cgd -o`.
4. **Despacho dinâmico sem Inline Caching e verificações FFI fora de linha**: leituras/escritas de campos (`delegua_prop`/`delegua_def`), chamadas de método (`delegua_chamar_membro`) e wrappers FFI (`delegua_assegurar_descr(..., delegua_descr_nome(...))`) pagavam buscas repetitivas em tabelas hash e chamadas de função não-inline em laços quentes.

O Ciclo III resolveu essas quatro causas raiz preservando 100% da semântica dinâmica de Delégua, a segurança de threads/GC e a compatibilidade com GCC, Clang e TinyCC (C99).

### Resultados Principais no CGD

| Indicador | Ciclo II (Antes) | Ciclo III (Depois) | Ganho |
| --- | ---: | ---: | ---: |
| `oop_fields_methods` (`clang -O2`) | `75,00 ms` | **`24,20 ms`** | **3,10× mais rápido** |
| `oop_fields_methods` (`gcc -O2`) | `84,56 ms` | **`29,72 ms`** | **2,85× mais rápido** |
| `stdlib_bytes_json` (`clang -O2`) | `40,55 ms` | **`19,57 ms`** | **2,07× mais rápido** |
| `stdlib_bytes_json` (`gcc -O2`) | `43,65 ms` | **`19,07 ms`** | **2,29× mais rápido** |
| DCC 0.2.0 compilando `hello_libc.c` (`clang -O2`) | `266,70 ms` | **`168,46 ms`** | **1,58× mais rápido (-36,8%)** |
| DCC 0.2.0 compilando `hello_libc.c` (`gcc -O2`) | `290,74 ms` | **`168,08 ms`** | **1,73× mais rápido (-42,2%)** |
| DCC 0.2.0 auto-compilando `frozen_dcc.c` (`clang -O2`, tempo) | `29,94 s` | **`8,56 s`** (mediana) | **3,50× mais rápido** |
| DCC 0.2.0 auto-compilando `frozen_dcc.c` (`clang -O2`, pico RSS) | `6.715.172 KB` (6,40 GiB) | **`955.216 KB`** (0,91 GiB) | **7,03× menos memória (-85,8%)** |
| Chamadas `delegua_chamar_membro` no C gerado do DCC 0.2.0 | `4.324` | **`0`** (`4.479` ICs) | **100% migrado para IC** |

---

## 2. Catálogo de Achados e Intervenções (Ciclo III)

### CGD-III-01 — Instâncias de Classe com Slots Fixos Inline (`objetos.c`, `delegua_rt.h`)
- **Causa raiz**: `delegua_instanciar` alocava `objeto` + `hashmap` (`campos`) + `buckets` + 1 `entry` (64 B) por campo durante `semear_campos`, além de sempre alocar estrutura `origem_erro`.
- **Intervenção**:
  - `struct classe` ganhou descritor de layout plano (`campo_slot *slots_layout`, `sz num_slots`, tabela hash aberta `slot_hash_idx`/`slot_hash_cap`, `bool layout_finalizado`, `bool layout_sem_acessores_restritos`, cache `ctor_cache`, e contador `layout_versao`).
  - `struct objeto` passou a ser um cabeçalho compacto de 32 bytes com *flexible array member* `delegua_value slots[]`. `delegua_instanciar` realiza **uma única alocação `GC_MALLOC(sizeof(objeto) + num_slots * sizeof(delegua_value))`**. Como `DELEGUA_T_NULO == 0`, o zero-fill do GC já inicializa todos os campos para `nulo`, eliminando completamente `semear_campos`.
  - `origem_erro` foi movido para alocação preguiçosa (`struct origem_erro *`), e campos dinâmicos extras em classes não-fechadas caem sob demanda em `hashmap *campos_extra` (`NULL` no caso comum).
  - Finalização e invalidação de layout são protegidas por `pthread_mutex_t layout_mutex` e cargas/armazenamentos atômicos, preservando herança, mixins, propriedades com acessores/restrições, `clonar()`, inspeção reflexiva e extensão dinâmica de classe pós-instanciação.
- **Impacto isolado no DCC (`frozen_dcc.c`)**: Pico RSS caiu de **6.252 MiB → 3.319 MiB (-49,4%)**, alocações totais no GC caíram de **12.150 → 8.521 MiB**, e o tempo caiu de **29,94 s → 21,09 s**.

### CGD-III-02 — Vetores e Dicionários Vazios Preguiçosos + `VETOR_INIT_CAP = 4` (`colecoes.c`, `biblioteca.c`, `delegua_rt.h`)
- **Causa raiz**: `create_vetor()` alocava `8 × 24 B = 192 B` e `create_map()` alocava `buckets` imediatamente, desperdiçando centenas de MiB em nós folha com coleções vazias.
- **Intervenção**:
  - `create_vetor()` e `create_map()` alocam apenas o cabeçalho (32 B) com `values = NULL`/`buckets = NULL`, `cap = 0`, `size = 0`.
  - `VETOR_INIT_CAP` reduzido de `8` para `4`.
  - Guardas de `NULL`/vazio adicionadas em `delegua_vetor_empilhar`, `delegua_vetor_inserir`, `delegua_vetor_remover` (evitando UB em `memmove(NULL, ...)`), `delegua_map_set`, `delegua_map_get`, `delegua_map_delete`, `delegua_map_limpar` e `delegua_map_chaves`.
  - Adicionado método nativo `vetor.limpar()` (em `biblioteca.c` e `src/frontend/semantic/native_methods.d`) e atualizado `dicionario.limpar()` (`delegua_map_limpar`) para soltar o ponteiro interno (`values = NULL`/`buckets = NULL`, `cap = 0`), permitindo liberação determinística pelo GC sem retenção residual.
- **Impacto isolado no DCC (`frozen_dcc.c`)**: Pico RSS caiu de **3.319 → 3.009 MiB** (`PARSE_END`: `989 → 821 MiB`).

### CGD-III-03 — `cgd:bytes` Crescível em `GC_MALLOC_ATOMIC` e I/O Binário Direto (`bytes_rt.c`, `bibliotecas/bytes.delegua`)
- **Causa raiz**: `Bytes` possuía apenas tamanho fixo; aplicações precisavam usar `inteiro[]` (24 B por byte, varrido pelo GC como ponteiro) para acumular buffers binários e `base64 -d` via subprocesso para gravar arquivos binários.
- **Intervenção**:
  - `struct delegua_bytes` recebeu campo `sz cap` com crescimento geométrico em `GC_MALLOC_ATOMIC` (invisível ao scanner de ponteiros do Boehm GC).
  - Novas primitivas: `criarReservado(cap)`, `anexarByte(b)`, `anexarU16LE(v)`, `anexarU32LE(v)`, `anexarU64LE(v)`, `definirU32LE(pos, v)`, `anexarBytes(outro)`, `anexarVetor(vec)`, `anexarZeros(n)`, `anexarTexto(txt)`, `fatiarTexto(inicio, fim)`, `gravarArquivo(caminho)` e `lerArquivo(caminho)`.
  - Validação rigorosa de limites/overflow e segurança sob ASan/UBSan.
- **Impacto no DCC**: eliminou >1,6 GiB de alocações em `EmissorX86_64.code` e `elf_obj.delegua` e eliminou o subprocesso `/bin/sh -c "exec base64 -d"`.

### CGD-III-04 — Telemetria de Memória e Controle de GC (`sistema_posix.c`, `bibliotecas/nativo.delegua`, `bibliotecas/sistema.delegua`)
- **Intervenção**:
  - `Sistema.memoria()`: retorna dicionário com `rss_bytes`, `hwm_bytes` (`/proc/self/status`), `pss_bytes` (`/proc/self/smaps_rollup`), `gc_heap_bytes`, `gc_free_bytes`, `gc_unmapped_bytes`, `gc_memory_use_bytes`, `gc_total_bytes` e `gc_cycles` (API Boehm GC).
  - `Sistema.coletarGC(desmapear)`: aciona `GC_gcollect()` ou `GC_gcollect_and_unmap()`.
- **Uso**: habilitou o modo `-fmem-report` do DCC e o controle determinístico de memória em compilações grandes (>20k tokens).

### CGD-III-05 — Otimização `-O2` na Compilação do Runtime (`vendor/delegua-runtime/build`)
- **Causa raiz**: `vendor/delegua-runtime/build` invocava `$CC` sem flag de otimização (`-O0` implícito), mantendo todo `libdelegua_rt.o` sem inlining, sem propagação de constantes e com *spills* de pilha em cada chamada do runtime.
- **Intervenção**: adicionado `RT_OPT=${RT_OPT:--O2}` em `CFLAGS`, permitindo sobrescrita limpa em builds com sanitizadores (`RT_OPT="-O1 -g -fno-omit-frame-pointer"`).
- **Impacto isolado no DCC (`frozen_dcc.c`)**: tempo total caiu de **20,63 s → 11,68 s (1,77× mais rápido em uma única mudança!)**.

### CGD-III-06 — Inline Caching Monomórfico Thread-Safe (`objetos.c`, `delegua_rt.h`, `codegen.d`, `lvalue.d`)
- **Causa raiz**: mesmo com slots fixos em `objeto`, cada `obj.campo` e `obj.metodo(...)` ainda fazia lookup por hash de string no descritor da classe ou tabela de métodos.
- **Intervenção**:
  - `codegen.d` e `lvalue.d` alocam um vetor estático `static const void *cgd_ic[N];` por unidade de tradução e emitem `delegua_prop_ic`, `delegua_def_ic` e `delegua_chamar_ic` com `&cgd_ic[slot]` (mantendo deduplicação em `ic_metodos` no runtime e preservação estrita de ordem de avaliação).
  - `delegua_prop_ic` e `delegua_def_ic` cacheiam um ponteiro atômico para `campo_slot` (que armazena `layout_klass` para invalidação em $O(1)$ caso a classe seja alterada dinamicamente); no acerto monomórfico, o acesso vira **uma comparação de ponteiro + indexação direta `o->slots[s->index]`**.
  - `delegua_def_ic` valida tipos primitivos inline via `campo_slot.fast_check` (`validar_slot_valor`) antes de cair para `delegua_conforme`.
  - `delegua_chamar_ic` cacheia a entrada `(classe, metodo)` para instâncias ou o ponteiro de método nativo para coleções/strings, reduzindo chamadas de método em `oop_fields_methods` em 3,1×.
  - Guardas `DELEGUA_ATOMIC_LOAD_PTR` / `DELEGUA_ATOMIC_STORE_PTR` garantem compatibilidade C99/TinyCC (onde `__atomic_load_n` não existe).
- **Impacto isolado no DCC (`frozen_dcc.c`)**: tempo caiu de **11,68 s → 9,71 s** (`parse`: `-27%`, `ir`: `-26%`, `codegen`: `-15%`).

### CGD-III-07 — Checagem Inline de Primitivos em Wrappers FFI (`src/backend/c/foreign.d`)
- **Causa raiz**: `foreign.d` gerava `delegua_assegurar_descr(expr, delegua_descr_nome("inteiro"), ...)` em cada argumento de função `@definicao` (incluindo `Bytes.obter`, `Bytes.definir`, `Bytes.anexarByte`), pagando duas chamadas de função por argumento.
- **Intervenção**: mapeamento direto para `delegua_assegurar_inteiro_em`, `delegua_assegurar_real_em`, `delegua_assegurar_texto_em` e `delegua_assegurar_logico_em` (funções `static inline` em `delegua_rt.h`), preservando mensagens de erro e contratos de tipo.
- **Impacto**: acelerou `Bytes.obter`/`anexarByte` e reduziu `stdlib_bytes_json` e o `LEX`/`PREPROCESS` do DCC.

---

## 3. Inventário de Arquivos Modificados no Ciclo III

| Camada | Arquivo | Natureza da Mudança |
| --- | --- | --- |
| Runtime C (build) | `vendor/delegua-runtime/build` | `RT_OPT=${RT_OPT:--O2}` padrão em `CFLAGS` |
| Runtime C (core) | `vendor/delegua-runtime/src/delegua_rt.h` | `struct objeto` com `slots[]`, protótipos `*_ic`, macros atômicas C99/TCC, API `Bytes` crescível e `Sistema.memoria`/`coletarGC` |
| Runtime C (objetos) | `vendor/delegua-runtime/src/objetos.c` | Layout plano por slots, `finalizar_layout` thread-safe, invalidação de IC, `delegua_prop_ic`/`def_ic`/`chamar_ic`, `validar_slot_valor` |
| Runtime C (coleções) | `vendor/delegua-runtime/src/colecoes.c`, `biblioteca.c`, `interno.h` | `VETOR_INIT_CAP=4`, vetores/mapas vazios preguiçosos, `vetor.limpar()`, `delegua_map_limpar` liberando `buckets`, guarda `memmove` |
| Runtime C (bytes) | `vendor/delegua-runtime/src/bytes_rt.c` | Buffer `cap` em `GC_MALLOC_ATOMIC`, anexação LE/bloco/texto, `fatiarTexto`, I/O binário direto em arquivo |
| Runtime C (sistema) | `vendor/delegua-runtime/src/sistema_posix.c` | `delegua_ffi_sistemaMemoria` (`/proc` + Boehm GC) e `delegua_ffi_sistemaColetarGC` |
| Runtime C (testes) | `vendor/delegua-runtime/tests/runtime.c` | +51 linhas testando slots inline, herança, `clonar`, IC monomórfico/polimórfico, invalidação pós-instanciação, coleções vazias e `limpar()` |
| Stdlib Delégua | `bibliotecas/bytes.delegua`, `nativo.delegua`, `sistema.delegua` | Bindings `@definicao` das novas primitivas de `Bytes` e `Sistema` |
| Compilador D | `src/backend/c/codegen.d`, `lvalue.d`, `foreign.d` | Emissão de `cgd_ic[]`, chamadas `*_ic`, fast-path inline de checagem de primitivos FFI |
| Compilador D | `src/frontend/semantic/native_methods.d` | Registro semântico do método nativo `vetor.limpar(): nulo` |
| Testes/Benchmarks | `testes/stdlib.py`, `scripts/benchmark_suite.py` | +4 contratos stdlib (`Bytes` crescível/I/O, `Sistema.memoria`/`coletarGC`, `vetor.limpar()`); métricas IC em `benchmark_suite.py` |

---

## 4. Validação Executada

Todas as verificações abaixo foram executadas integralmente após a consolidação das alterações (sem pular falhas):

- **Runtime C nativo**: `./build-runtime` e `(cd vendor/delegua-runtime && ./tests/run.sh)` — **APROVADO** (incluindo núcleo async C, caminhos de erro e novas regressões de slots/IC/coleções).
- **Testes unitários em D**:
  - `dub test --compiler=dmd --config=unittest` — **10/10 módulos aprovados**.
  - `dub test --compiler=ldc2 --config=unittest` — **10/10 módulos aprovados**.
- **Suíte completa de integração e bibliotecas**:
  - `testes/driver.py` (26 verificações) — **APROVADO**.
  - `testes/integracao.py` (439 verificações) — **APROVADO**.
  - `testes/expansao.py`, `testes/enums.py` — **APROVADO**.
  - `testes/bibliotecas.py` (342 verificações) — **APROVADO**.
  - `testes/stdlib.py` (122 contratos em ambos os modos) — **APROVADO**.
  - `testes/stdlib_avancada.py` (11), `testes/linguagem_nova.py` (8), `testes/rotinas.py` (15), `testes/async_linguagem.py` (30), `testes/lsp.py` — **APROVADO**.
  - `testes/assincronismo.py` (Clang, GCC, ASan/UBSan e TSan) — **APROVADO**.
  - `testes/exemplos.py` (155 programas, 310 verificações, 0 falhas) — **APROVADO**.
- **Sanitizadores (ASan + UBSan)**:
  - Runtime compilado com `-O1 -g -fsanitize=address,undefined` validado com `./tests/run.sh`, `testes/stdlib.py` (122 contratos) e `testes/linguagem_nova.py` (8 verificações) — **0 erros ASan/UBSan**. (Runtime normal `-O2` restaurado e reinstalado em seguida.)
- **Portabilidade TinyCC (`tcc 0.9.28rc`)**:
  - Smoke de classe + slots + IC + `Bytes` compilado com `cgd --cc=/usr/local/sbin/tcc` (`TCC-OK:42`) e compilação/execução completa do DCC 0.2.0 com `tcc` (3 repetições em Modo A, `.o` bit-a-bit idêntico a GCC e Clang) — **APROVADO**.

---

## 5. Limitações Honestas e Próximas Oportunidades no CGD

1. **Inline Caching ainda é monomórfico (1 entrada)**: locais polimórficos (ex.: AST/IR com múltiplas subclasses no mesmo callsite) sofrem sobrescrita de cache (miss → lookup). Um PIC de 2–4 entradas ou despacho direto estático para receptores de classe fechada conhecida em tempo de compilação traria novo ganho.
2. **Alocação de `delegua_value` em `inteiro[]` (24 B/elemento)**: vetores tipados `inteiro[]` ou `real[]` continuam armazenando `delegua_value` genérico (24 B) em vez de vetores *unboxed* (`int64_t[]`/`double[]`). Embora `cgd:bytes.Bytes` resolva buffers binários, coleções numéricas tipadas ainda têm margem de 3× em memória e cache.
3. **Retenção conservadora por pilha no Boehm GC**: funções com `tente/pegue` mantêm variáveis `volatile` e temporários `cgd_tmp_*` no stack frame até o retorno da função, podendo reter grafos grandes se fases não forem isoladas em subfunções. Zeragem explícita de slots temporários mortos em escopos longos ou separação automática de blocos grandes ajudaria aplicações intensivas em memória.
4. **Crescimento do binário por `cgd_ic[]`**: no DCC 0.2.0, `cgd_ic` adicionou ~12,5k ponteiros estáticos (~100 KiB em `.bss`) e elevou ligeiramente o volume C gerado (42.915 linhas / 5,26 MiB, também incluindo as novas funções do DCC). Compactar nomes de chamadas IC ou usar macros curtas em `delegua_rt.h` pode reduzir o tamanho do `.c` intermediário e acelerar a compilação em GCC/Clang.
