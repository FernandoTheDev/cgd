# Arquitetura de Gerenciamento Híbrido de Memória e Coletor de Lixo (`CGD-GC`)

Este documento descreve a arquitetura integrada de gerenciamento de memória do **CGD (Compilador Geral Delégua)** e de seu runtime C99 (`vendor/delegua-runtime`), projetada especificamente para o modelo de execução, o sistema de tipos e o código C99 gerado pelo compilador.

## 1. Princípio Fundamental: Cooperatividade Híbrida

Em vez de tratar toda alocação como heap gerenciada indiferenciada, o CGD combina **quatro domínios de armazenamento complementares**, escolhidos automaticamente pelo compilador por meio de análise interprocedimental de ponto fixo (`src/frontend/semantic/interprocedural.d`):

1. **Especialização Nativa Automática (ANS)** (`src/middle/ans.d`): funções Delégua normais (sem `@nativo`) cujas assinaturas e corpos operam exclusivamente sobre escalares concretos (`inteiro`/`longo`, `real`/`decimal`, `logico`/`booleano`, `vazio`) são especializadas em funções C99 `static cgd_ans_<fn>(...)` operando em registradores escalares (`i64`, `f64`, `bool`) sem *boxing* de `delegua_value`, preservando 100% da semântica observável da linguagem (overflow assinado de 64 bits verificado via `__builtin_*_overflow`, divisão/módulo por zero, faixa de deslocamento `0..63`, limite de recursão `delegua_call_depth >= 1024` e *safepoints* cooperativos amortizados em laços).
2. **Alocação Automática em Stack (`StorageDomain.StackLocal`)**: instâncias de classes fechadas (sem subclasses, sem destrutor, sem acessores customizados, `<= 32` slots) cuja análise conservadora prova que não escapam do escopo são alocadas em buffer alinhado na stack C e inicializadas via `delegua_init_stack_objeto()`, sem nenhuma alocação na heap GC.
3. **Liberação Determinística na Heap (`StorageDomain.DeterministicHeap`)**: coleções locais (vetores/tuplas) com *ownership* exclusivo provado dentro de blocos livres de exceções recebem liberação determinística `cgd_gc_free_det_value()` na saída normal do bloco e antes de `return`/`break`/`continue`, reciclando slots em $O(1)$ sem *lock* diretamente no *free-list* da TLAB da thread atual.
4. **Coletor Especializado `CGD-GC` (`StorageDomain.ManagedHeap`)**: objetos que escapam, possuem ciclos, cruzam fronteiras assíncronas/paralelas ou têm tempo de vida dinâmico são gerenciados pelo `CGD-GC` nativo do runtime, eliminando a dependência obrigatória do Boehm GC (`libgc` / `bdw-gc`).

O Boehm GC permanece disponível como *backend* selecionável de referência científica (`--gc=boehm` ou `CGD_GC_BACKEND=boehm`, vinculado a `libdelegua_rt_boehm.o`).

## 2. Arquitetura Interna do `CGD-GC`

O coletor reside em `vendor/delegua-runtime/src/gc/` e é composto por módulos focados:

| Módulo | Responsabilidade |
| :--- | :--- |
| `cgd_gc.h` / `cgd_gc_internal.h` | API pública e estruturas internas (`cgd_gc_region`, `cgd_gc_tlab_bin`, `cgd_gc_thread`, `cgd_gc_large_obj`). |
| `gc_platform.c` | Abstração POSIX (`mmap`/`munmap`/`madvise(MADV_DONTNEED)`) e relógio monotônico em nanossegundos. |
| `gc_radix.c` | Mapa Radix de 2 níveis (espaço de endereços virtual de 48 bits, granularidade de 64 KiB) com resolução $O(1)$ *lock-free* de qualquer ponteiro para sua região ou objeto grande (LOS). |
| `gc_regions.c` | Regiões *slab* alinhadas a 64 KiB com **cabeçalho de 0 bytes por objeto**, 24 classes de tamanho (`16 B .. 16384 B`), *bitmaps* `alloc_bits`/`mark_bits`/`pin_bits`, tabela de *cards* de 512 B, *lazy sweep* por região e *Large Object Space* (LOS `> 16 KiB`). |
| `gc_allocator.c` | Alocador rápido por thread (TLAB com *bump pointer* + *free-list* local sem *locks*), realocação *in-place* dentro da mesma classe, liberação determinística $O(1)$ sem *lock* e barreiras de escrita geracionais. |
| `gc_roots_threads.c` | Registro de threads, protocolo cooperativo de *safepoint* e regiões bloqueantes (`cgd_gc_enter_blocking`/`cgd_gc_leave_blocking`), *root frames* compatíveis com `setjmp`/`longjmp`, *handles* opacos FFI e *pinning*. |
| `gc_collector.c` | Coletor preciso na heap (rastreamento por `cgd_gc_kind_t` e `delegua_value.type`), *stack root pinning* validado contra Radix Map + `alloc_bits` (com suporte nativo ao *fake stack* do AddressSanitizer), coleta menor geracional (*nursery* + *card table* + *LOS remembered set* + promoção $O(1)$), marcação paralela por *workers* em heaps grandes, finalizadores executados fora do *lock* global e política adaptativa de orçamento. |
| `gc_verifier.c` | Verificador de integridade de heap (`cgd_gc_verify_heap`), executado automaticamente ao final de todo ciclo no perfil `CGD_GC_PROFILE=verify`. |
| `gc_runtime_bridge.c` | Ponte de rastreamento preciso entre o GC e os subsistemas do runtime (`objetos.c`, `colecoes.c`, `excecoes.c`, `assincrono*.c`, `rotinas_reactor.c`, `ffi.c`). |
| `gc_boehm_compat.c` | Adaptador de compatibilidade compilado apenas quando `CGD_GC_BACKEND_BOEHM=1`. |

## 3. Integração Compilador ↔ Runtime

- **Raízes globais precisas**: `BackendC` emite `cgd_gc_scan_generated_roots()` varrendo todos os descritores de classes, módulos, *slots* de funções e entradas de *inline cache* (`cgd_ic[N]`), registrado uma única vez no início de `delegua_main()`.
- **Safepoints cooperativos**: laços gerados (`WhileStmt`, `ForStmt`, `DoStmt`, `EachStmt` e laços ANS) emitem verificação amortizada de *safepoint* a cada 1024 iterações (`if (DELEGUA_UNLIKELY((++sp & 1023U) == 0U)) cgd_gc_safepoint();`), mantendo *overhead* próximo de zero no caminho quente e garantindo paradas rápidas em aplicações multithread.
- **Fusão de coleções e desvirtualização**:
  - Literais de tupla `(a, b, ...)` e `tupla([a, b, ...])` com 2..10 elementos são emitidos diretamente como `create_tupla(N, ...)` sem vetor temporário.
  - Literais de vetor com `> 4` elementos usam `create_vetor_cap(N)` evitando realocações iniciais.
  - Chamadas a métodos de classes fechadas sem subclasses/decoradores são desvirtualizadas para `delegua_chamar_metodo_fn()`.
- **Frames assíncronos geracionais**: a suspensão de tarefas em `assincrono.c` e o *scanner* `rt_gc_scan_assincrono` marcam `cgd_gc_dirty_object(task->frame)` garantindo que atribuições diretas no *frame* promovido à geração `OLD` nunca percam referências `OLD -> YOUNG`.

## 4. Opções de CLI, Perfis e Observabilidade

### Opções do compilador (`cgd`)
- `--gc=cgd` (padrão, zero dependência de `libgc`) ou `--gc=boehm` (referência).
- `--opcoes-memoria=padrao|nenhuma|ans,stack,det,fusao,devirt,safepoints` (ou `CGD_MEM_OPTS`).
- `--relatorio-memoria` (resumo textual das otimizações e decisões de memória aplicadas).
- `--relatorio-memoria-json=<arquivo.json>` (relatório estruturado em JSON).

### Variáveis de ambiente em tempo de execução
- `CGD_GC_PROFILE=balanced|low_mem|throughput|low_latency|stress|verify`
- `CGD_GC_STATS=1` (imprime resumo de ciclos, alocações, liberações determinísticas, memória viva/reservada/comprometida e pausas `p99`/`max` ao encerrar).
- Biblioteca padrão `cgd:memoria` (`Memoria.estatisticas()`): expõe `backendGC`, `ciclosGC`, `coletasMenores`, `coletasMaiores`, `pausaP50Us`, `pausaP95Us`, `pausaP99Us`, `pausaMaxUs`, `liberadosDeterministicos`, `barreirasEscrita`, `cardsSujosVarredos`, `taxaSobrevivencia`, `fragmentacao`, entre outros.
