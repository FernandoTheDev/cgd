# Auditoria Técnica e Especificação Arquitetural — Gerenciamento Híbrido de Memória & CGD-GC

## 1. Escopo e Estado Inicial Auditado

Esta auditoria cobre integralmente o compilador CGD (`src/`), o runtime C99 (`vendor/delegua-runtime/`), as bibliotecas padrão (`bibliotecas/`), as pontes opcionais (`bridges/`) e a aplicação real de referência DCC (`/home/fernandodev/dcc`, 13.223 linhas de Delégua).

### 1.1. Ambiente de Baseline Congelado (`out/baseline_a/`)

- **Sistema Operacional / Kernel**: Linux Fedora 44 `7.2.5-200.fc44.x86_64` (`x86_64`)
- **CPU**: 11th Gen Intel Core i5-11300H @ 3.10GHz (4 núcleos físicos / 8 threads lógicas, L2 5 MiB, L3 8 MiB)
- **RAM**: 15 GiB
- **Toolchains**:
  - `clang 22.1.8`
  - `gcc 16.2.1`
  - `ldc2 1.42.0` (DMD FE `2.112.1` / LLVM `20.1.8`)
  - `dmd 2.111.0`
  - `tcc 0.9.28rc`
- **Commits de Origem**:
  - `cgd`: `ef68db3` + árvore de trabalho do Prompt Mestre X preservada intacta (`out/baseline_a/cgd` SHA-256 `802456aadd2c0bf4d4ab30a2e9b96a78346e1ada5e9b0256d95411a806e12e8e`)
  - `vendor/delegua-runtime`: `2310cd1` + árvore de trabalho preservada (`out/baseline_a/lib/libdelegua_rt.o` SHA-256 `e29f1023aed3a2ea71a2df4711d53c91e10ac642f9c70667f79f6d855b1171f9`)
  - `dcc`: `59aae9a` (`out/baseline_a/frozen_dcc.c`, 7.416.984 bytes, SHA-256 `401e0b7ef4fa890ea37f315c1074dff3b922b711d711d711930a77b8391dce845764`)

---

## 2. Mapeamento Integral do Uso Atual de Memória e Boehm GC

### 2.1. Sítios de Alocação, Realocação, Finalização e Controle

| Módulo | Operações Boehm / Nativo | Papel e Propriedades |
| --- | --- | --- |
| `src/delegua_rt.h` | `GC_MALLOC_ATOMIC` (`create_text_len`, `create_text_concat`), `GC_MALLOC` (`create_vetor`, `program_create`) | Textos >= 2 bytes alocados como folha atômica; literais usam `.rodata` (`create_text_lit`); textos de 0/1 byte usam estáticos (`""` / `delegua_single_byte_strs`). |
| `src/delegua_rt.c` | `GC_INIT()`, `GC_allow_register_threads()` | Inicialização na thread principal antes de `delegua_main()` e `rt_async_program_finish()`. |
| `src/interno.h` | `rt_alloc(count, size)` -> `GC_MALLOC` | Alocador genérico zero-initialized usado para metadados, objetos, mapas, promessas e descritores. |
| `src/objetos.c` | `GC_MALLOC` (`alocar_objeto`), `GC_MALLOC_ATOMIC` (`slot_hash_idx`), `rt_alloc` (`classe`, `funcao`, `delegua_tipo`, `delegua_restricao`, `campo_slot`, `metodo_ic_entry`, `delegua_local`) | Instâncias `objeto` têm cabeçalho de 32 B + array flexível `delegua_value slots[]`. Destrutores Delégua (`delegua_destruir`) são **explícitos e síncronos**, nunca chamados pelo GC. |
| `src/colecoes.c` | `GC_MALLOC` / `GC_REALLOC` (`d->values`), `rt_alloc` (`hashmap`, `buckets`, `entry`, `rt_clone_entry`), `GC_MALLOC_ATOMIC` (`delegua_intervalo`) | Vetores/tuplas usam `delegua_vetor_data`; mapas usam encadeamento separado (`hashmap` -> `entry**` -> `entry`). |
| `src/biblioteca.c`, `src/nativas.c`, `src/cripto.c`, `src/regex_posix.c`, `src/http_servidor.c` | `GC_MALLOC_ATOMIC`, `GC_REALLOC` | Construção de textos, fatiamento, leitura de linha, hex/bcrypt, respostas HTTP e regex. |
| `src/textos.c` | `GC_get_gc_no()`, `rt_alloc` | Cache UTF-8 TLS de 8 slots usa o contador de ciclos de coleta (`gc_no`) + amostras de conteúdo para detectar reutilização de endereços. |
| `src/bytes_rt.c`, `src/bytes_interno.h` | `GC_MALLOC_ATOMIC`, `GC_register_finalizer_no_order`, `malloc`/`free` (`rt_shared_bytes`) | `Bytes` mutável usa buffer atômico GC; `Bytes.congelar()` usa `rt_shared_bytes` fora do GC com refcount atômico e finalizador no wrapper `rt_bytes`. |
| `src/memoria_rt.c`, `src/sistema_posix.c` | `GC_get_*`, `GC_gcollect*`, `GC_set_*`, `GC_expand_hp`, `GC_register_finalizer_no_order`, `malloc`/`free` (`rt_arena_chunk`) | Telemetria de memória e `Arena` fora do GC com geração de 64 bits anti-UAF e finalizador de segurança. |
| `src/assincrono*.c` | `rt_alloc`, `GC_REALLOC` (`timers`, `operation->bytes`), `GC_register_finalizer_no_order` (`rt_canal`) | Event loop cooperativo na thread principal; `loops`, `program_loop`, `current_task`, `watches`, `timers` e `operations` atuam como raízes estáticas em C. |
| `src/rotinas_*.c` | `GC_register_my_thread`, `GC_unregister_my_thread`, `calloc`/`free` (`rt_pool`, `rt_transfer_packet`) | Workers paralelos executam funções isoladas; argumentos e retornos atravessam threads por cópia serializada (`rt_transfer_packet`) ou `rt_shared_bytes` zero-copy, sem compartilhar objetos mutáveis entre heaps de threads. |
| `src/rede.c`, `src/sockets_posix.c`, `src/sqlite_rt.c`, `src/ffi.c`, `src/gpu_rt.c`, `bridges/*.c` | `rt_alloc`, `GC_REALLOC`, `GC_register_finalizer_no_order` | Recursos externos (`CURL*`, file descriptors, `sqlite3*`, `dlopen`, `GClosure`) usam fechamento explícito + finalizador idempotente de segurança. |

### 2.2. Dependências Implícitas do Coletor Conservativo e Mitigações Arquiteturais

1. **Temporários `delegua_value` e ponteiros locais C na stack e em registradores**:
   - O C gerado e as 35 unidades do runtime mantêm valores intermediários (`objeto*`, `classe*`, `delegua_value`, compound literals `(delegua_value[]){...}`) em variáveis automáticas e registradores C através de chamadas que alocam.
   - **Solução**: Heap e raízes globais 100% precisas combinadas com: (a) frames de raízes explícitos (`cgd_gc_root_frame`) integrados ao unwinding de `delegua_try_frame` (`setjmp`/`longjmp`), e (b) **Stack Root Pinning** validado contra o Radix Map de 2 níveis + bitmap `alloc_bits` das regiões. Qualquer palavra na stack/registradores de uma thread em safepoint que aponte para um objeto ativo na heap gerenciada marca e fixa (`PIN`) apenas aquele objeto durante o ciclo atual, garantindo segurança total sob `-O0/-O1/-O2/-O3/LTO` em Clang, GCC e TinyCC sem varrer conservativamente a heap nem `.data`/`.bss`.
2. **Desenrolamento não-local via `setjmp`/`longjmp` (`delegua_tentar` / `delegua_falhar`)**:
   - Exceções saltam múltiplos frames C.
   - **Solução**: `delegua_try_frame` salva o topo da cadeia TLS `cgd_gc_root_top` em `delegua_tentar()` e restaura-o deterministicamente antes de `longjmp` em `delegua_falhar()`, impedindo root frames pendentes ou corrompidos.
3. **Ponteiros para `.rodata` e estáticos em `DELEGUA_T_TEXT` e `delegua_tipo`**:
   - `create_text_lit`, `""`, `delegua_single_byte_strs` e `static_descr_*` não pertencem à heap dinâmica.
   - **Solução**: O Radix Map de 2 níveis identifica em 2 acessos $O(1)$ se um endereço pertence a uma região `CGD-GC` ou `cgd_gc_large_obj`; ponteiros estáticos retornam `0` imediatamente e são ignorados sem custo nem corrupção.
4. **Chamadas bloqueantes POSIX/FFI (`epoll_wait`, `poll`, `curl_easy_perform`, `pthread_cond_wait`, `fgets`)**:
   - Uma thread bloqueada no kernel não pode atrasar safepoints de outras threads.
   - **Solução**: Regiões bloqueantes envolvidas por `cgd_gc_enter_blocking()` / `cgd_gc_leave_blocking()`, publicando o snapshot de registradores/stack da thread e permitindo coleta imediata sem esperar o fim da syscall.
5. **Invalidação da cache UTF-8 em `textos.c`**:
   - `utf8_cache_get` usa `GC_get_gc_no()` para detectar reciclagem de endereço.
   - **Solução**: `cgd_gc_cycle_count()` incrementa monotonicamente a cada coleta (menor ou maior), preservando exatamente a invariante de invalidação da cache TLS.

### 2.3. Infraestrutura Existente no Compilador (`src/`) Reaproveitada e Generalizada

- `src/frontend/semantic/value_types.d`, `native_validation.d`, `ownership.d` e `src/backend/c/native_codegen.d` já implementam tipos escalares C, structs `@pilha`, containers nativos com RAII e verificação de ownership/borrows explícitos.
- **Lacunas atacadas nesta evolução**:
  1. Funções e métodos sem `@nativo` explícito sempre compilam para `delegua_value (sz argc, delegua_value *argv)` com boxing/unboxing e despacho por array na stack, mesmo quando 100% escalares/numéricos.
  2. Não há análise interprocedural de escape/efeitos para promover automaticamente alocações locais seguras para a stack, scalar replacement ou liberação determinística.
  3. `TupleLit` e `tupla([...])` alocam um vetor intermediário mutável antes de converter em tupla; `ArrayLit` cresce incrementalmente (`0 -> 4 -> 8 -> 16...`) em vez de reservar a capacidade estática conhecida.
  4. O runtime ainda depende de `bdw-gc` (`libgc.so`), sofrendo com varredura conservativa de arrays de `delegua_value` de 24 bytes e cabeçalhos/metadados genéricos.

---

## 3. Pesquisa Arquitetural Crítica e Seleção para o CGD

| Arquitetura Avaliada | Pontos Fortes | Limitações no Contexto C99 / CGD | Decisão Adotada |
| --- | --- | --- | --- |
| **G1 / ZGC / Shenandoah (JVM)** | Baixíssima pausa em heaps multi-GB com relocação concorrente | Exigem read barriers em cada load de ponteiro ou colored pointers/remap virtual + stack maps exatos do JIT | Rejeitado copiar read barriers em C99 (alto overhead em código gerado C e incompatível com ponteiros diretos em `delegua_rt.h`). |
| **Go GC (Tricolor Mark-Sweep + Spans sem Header)** | Zero header por objeto, side bitmaps cache-friendly, baixa latência, spans segregados por classe de tamanho | Não geracional: revarre toda a heap antiga em cargas de compiladores com grande AST viva (como o DCC) | **Adotado o layout de regiões segregadas com side-bitmaps (0 B de header por objeto <= 16 KiB)**, mas combinado com gerações! |
| **Immix / Mark-Region + Oilpan / Mono SGen** | Regiões fixas, bump + reciclagem por bitmap, compatível com conservative stack pinning + precise heap, geracional com card table | Evacuação exige respeitar objetos fixados pela stack | **Selecionado como base central do CGD-GC**: Mark-Region Geracional Preciso com TLABs, Card Marking (512 B), Stack Pinning seletivo, Parallel Marking e Lazy/Incremental Bitmap Sweeping. |
| **Gerenciamento Determinístico / Escape Analysis (JVM EA / Rust / Swift SIL)** | Elimina completamente o custo de GC onde o lifetime é local | Não resolve grafos cíclicos/dinâmicos que escapam | **Integrado na camada híbrida do compilador** (Interprocedural Escape Analysis + ANS + Stack Promotion + Scalar Replacement + Deterministic Release). |

---

## 4. Invariantes Formais da Arquitetura

1. **Invariante de Alcançabilidade Precisa (I1)**: Todo objeto gerenciado alcançável a partir do conjunto união `Roots = GlobalRoots ∪ ThreadStackRoots ∪ ExplicitRootFrames ∪ ExternalHandles ∪ PendingFinalizerSubgraphs` permanece marcado e alocado ao término de qualquer coleta completa.
2. **Invariante Intergeracional (I2)**: Para todo objeto `O` em uma região `CGD_GEN_OLD` (ou no `LOS` marcado como `OLD`) que contenha referência para um objeto `Y` em uma região `CGD_GEN_YOUNG`, o card correspondente de 512 bytes em `O->region->card_table` (ou `O->remembered` no `LOS`) está marcado (`!= 0`) antes do próximo safepoint de coleta menor.
3. **Invariante Tricolor Concorrente/Incremental (I3 — Write Barrier)**: Durante uma fase de marcação incremental/concorrente ativa, nenhuma mutação `container.field = ref` pode esconder um objeto branco único sem registrá-lo no buffer de marcação (`Incremental Update / Yuasa SATB hybrid`).
4. **Invariante de Safepoint e Exceções (I4)**: Toda thread registrada encontra-se ou em `THREAD_RUNNING` (respondendo cooperativamente a `cgd_gc_safepoint_flag`), ou em `THREAD_AT_SAFEPOINT` / `THREAD_BLOCKED_SAFE` com seu contexto `jmp_buf` e `stack_top` publicados; todo `longjmp` por `delegua_falhar` restaura `cgd_gc_root_top` ao nível salvo no `delegua_try_frame`.
5. **Invariante de Domínios Híbridos (I5)**: Nenhum objeto na heap gerenciada pode armazenar ponteiro para objeto `StackAllocated` ou `DeterministicOwned` (garantido estaticamente pela condição necessária `escapes == false`). Inversamente, objetos `StackAllocated` que contenham `delegua_value` residem na pilha ativa da thread e têm suas referências para a heap gerenciada rastreadas durante todo o seu tempo de vida.
6. **Invariante de Finalização Segura (I6)**: Finalizadores são executados no máximo uma vez por instância, sempre **fora** do mutex interno do coletor, e o subgrafo referenciado pelo objeto finalizável permanece vivo até o retorno do finalizador.
