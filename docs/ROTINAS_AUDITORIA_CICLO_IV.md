# Auditoria Forense de Rotinas e Paralelismo Nativo — CGD 0.9.0 (Ciclo IV)

Data: 21/11/2026  
Ambiente: Linux x86-64 Fedora 44 (`7.2.5-200.fc44.x86_64`), Intel Core i5-11300H (4 núcleos físicos / 8 threads lógicas), 15 GiB RAM, Boehm GC (`bdw-gc`) 8.2.6, Clang 22.1.8, GCC 16.2.1, TinyCC 0.9.28rc.

---

## 1. Mapa de Arquivos Auditados

| Camada | Arquivos Principais | Papel |
|---|---|---|
| Frontend / Semântica | `src/frontend/semantic/routine_validation.d`, `src/frontend/semantic/analyzer.d`, `src/frontend/semantic/foreign.d` | Auditoria estática de pureza (`E3402`) e tipos transferíveis (`E3403`) em `rotina` |
| Backend C | `src/backend/c/codegen.d` | Geração de wrappers `cgd_rotina_*`, captura por valor e registro de tarefa |
| Pool de Workers | `vendor/delegua-runtime/src/rotinas_pool.{h,c}` | Pool nativo POSIX (`pthread`), fila circular FIFO, cancelamento, métricas |
| Transferência | `vendor/delegua-runtime/src/rotinas_transferencia.{h,c}`, `bytes_interno.h` | Serialização/isolamento de argumentos e retornos entre main thread e workers |
| Reator / Async | `vendor/delegua-runtime/src/rotinas_reactor.{h,c}`, `assincrono.c`, `assincrono_canal.c`, `assincrono_io.c` | Loop de eventos `epoll` + `eventfd`, `Promessa<T>`, `Tarefa<T>`, `Canal<T>` |
| Runtime / GC / Objetos | `vendor/delegua-runtime/src/objetos.c`, `modulos.c`, `excecoes.c`, `textos.c`, `colecoes.c`, `delegua_rt.{h,c}` | Thread-safety de ICs, cache de funções, módulos, TLS e Boehm GC |
| Stdlib Delégua | `bibliotecas/assincrono.delegua`, `algoritmos.delegua`, `bytes.delegua`, `memoria.delegua`, `sistema.delegua`, `processo.delegua` | Superfície de programação concorrente e controle de recursos |

---

## 2. Respostas com Evidência de Código às 25 Perguntas Obrigatórias (§4.1)

1. **Uma `rotina` realmente executa em uma thread nativa distinta?**  
   **Sim.** `rotinas_pool.c` cria threads nativas POSIX via `pthread_create(..., worker_main, pool)` quando o pool é inicializado (`rt_pool_iniciar` chamado por `rt_rotinas_iniciar` em `rotinas_reactor.c`). A função executa inteiramente fora da thread do loop de eventos.

2. **Existe um pool de threads persistente?**  
   **Sim.** O pool (`rt_rotinas_pool`) é inicializado sob demanda na primeira submissão de rotina (ou via `Rotinas.configurar(...)`) e mantido vivo até o encerramento do processo (`rt_rotinas_encerrar` em `delegua_async_encerrar`).

3. **Como o pool é dimensionado?**  
   - **Antes (Baseline Ciclo III)**: constante fixa `RT_ROTINAS_WORKERS_PADRAO = 4` e fila fixa `RT_ROTINAS_CAPACIDADE_PADRAO = 256` em `rotinas_reactor.c`.
   - **Depois (Ciclo IV)**: dimensionado dinamicamente por `rt_workers_recomendados(0)` em `sistema_posix.c` (respeitando `sched_getaffinity`, quotas cgroup v2/v1 `cpu.max` e memória disponível/cgroup) e configurável pela aplicação via `Rotinas.configurar(workers, capacidade)`.

4. **Quantos workers são criados?**  
   Na política conservadora padrão do Ciclo IV: `<= 2` CPUs efetivas → `1` worker; `<= 4` CPUs efetivas → `2` workers; `> 4` CPUs efetivas → `cpus_efetivas / 2` (limitado a `8` no automático, reduzido automaticamente sob pressão de memória `>= 78%` ou RAM disponível `< 1,5 GiB`). Nesta máquina (4 núcleos físicos / 8 threads lógicas, 15 GiB RAM): **4 workers** por padrão.

5. **É possível limitar o pool por aplicação?**  
   **Antes**: não havia API Delégua. **Ciclo IV**: **sim**, via `cgd:assincrono.Rotinas.configurar(workers, capacidade)` (capado com segurança em `[1, 32]` workers e `[16, 4096]` capacidade de fila). Se o pool já existir com número distinto de workers e sem tarefas pendentes, é drenado e reconfigurado com segurança.

6. **Existe fila de tarefas?**  
   **Sim.** Fila circular limitada (`pool->queue` com `q_head`, `q_tail`, `q_count`, `q_cap`) protegida por `pool->mutex` e `pool->cond` em `rotinas_pool.c`. Quando a fila atinge a capacidade máxima, `rt_pool_submeter` retorna erro controlado (backpressure, sem crescimento ilimitado de memória).

7. **Como funciona o escalonamento?**  
   FIFO estrito (`q_head` → `q_tail`) com acordamento via `pthread_cond_signal` e notificação de conclusão da thread worker para o reator principal via `eventfd(0, EFD_NONBLOCK | EFD_CLOEXEC | EFD_SEMAPHORE)` registrado no `epoll` (`rotinas_reactor.c`). O reator drena até 32 conclusões por ciclo de `epoll_wait`.

8. **Existem prioridades?**  
   **Não.** Todas as tarefas compartilham a mesma fila FIFO. A ausência de prioridades evita inanição (*starvation*) e mantém previsibilidade determinística.

9. **Há work stealing?**  
   **Não.** Como a fila central FIFO com mutex único já apresenta latência de submissão de apenas **3,86 µs/tarefa** (benchmark `01_spawn_small_tasks`, 2.000 tarefas em `7,60 ms`), work stealing adicionaria complexidade e contenção de cache sem benefício mensurável para cargas de granularidade média/grossa.

10. **Como uma rotina recebe seus argumentos?**  
    Na thread principal, `rt_transferir_valor` (`rotinas_transferencia.c`) empacota cada argumento em um `rt_transfer_slot` independente do heap GC da thread principal. O worker desserializa os argumentos em sua pilha (`rt_materializar_valor`), executa o corpo da rotina e empacota o valor de retorno ou exceção de volta em `rt_transfer_slot`.

11. **Quais dados são copiados?**  
    - **Baseline**: `nulo`, `logico`, `inteiro`, `real` (cópia por valor de 8 B) e `texto` (cópia dupla: `malloc` na submissão + `create_text` no GC do worker; e o inverso no retorno, até `16 MiB`).
    - **Ciclo IV**: limite elevado para `64 MiB`, adicionado `Bytes` mutável (cópia exclusiva via `RT_TRANSFER_BYTES`) e **`Bytes` congelado imutável (`RT_TRANSFER_IMMUTABLE_BYTES`) com transferência *zero-copy*** via contagem de referências atômica (`rt_shared_bytes` fora do GC).

12. **Quais objetos são rejeitados na transferência?**  
    Vetores (`T[]`), dicionários (`dicionario`), instâncias mutáveis de classes, funções/closures, promessas, canais e `Arena`/`Fatia*` continuam **estaticamente rejeitados com `E3403`** (`routine_validation.d`, validado por `testes/rotinas.py:233-240`) e bloqueados em runtime em `rt_transferir_valor`, preservando isolamento total contra *data races*.

13. **Qual o custo da cópia profunda?**  
    Medido no benchmark `03_transfer_text_roundtrip`: 10 *roundtrips* de `texto` de `4 MiB` levaram **`33,42 ms`** e alocaram **`80 MiB`** no Boehm GC (2 cópias ida + 2 cópias volta por chamada). Em contraste, 40 despachos (10×4 workers) de **`Bytes` congelado de `16 MiB`** no benchmark `06_bytes_frozen_zero_copy` levaram apenas **`0,011 ms` de transferência** e **`137 KiB`** de alocação GC total (**~3.000× menos custo de transferência**).

14. **Existem estruturas compartilhadas imutáveis?**  
    - **Antes**: apenas literais estáticos `.rodata`.
    - **Ciclo IV**: **sim** — `Bytes.congelar()` promove o buffer para `rt_shared_bytes` (`malloc` fora do GC, `immutable = 1`, `refcount` atômico `acquire/release`), imutável e compartilhável *zero-copy* entre N workers simultaneamente.

15. **Objetos `Bytes` podem ser transferidos eficientemente?**  
    **Sim (Ciclo IV).** Via `b.congelar().recursoInterno()` (ou `Bytes.deRecurso(raw)` no worker): custo $O(1)$ de um incremento atômico (`__atomic_add_fetch(..., __ATOMIC_RELAXED)`), zero cópia de bytes e zero varredura pelo Boehm GC.

16. **Há transferência por ownership?**  
    `Bytes` mutáveis transferidos são isolados por cópia exclusiva (`RT_TRANSFER_BYTES`), enquanto `Bytes` congelados usam propriedade compartilhada imutável (*Arc-pattern* em `rt_shared_bytes`), liberando o buffer nativo exatamente quando o último dono (worker ou thread principal) conclui ou é coletado pelo finalizador GC.

17. **O GC reconhece corretamente as threads?**  
    **Sim.** `rotinas_pool.c` invoca `GC_allow_register_threads()` na inicialização do pool e cada worker registra sua pilha com `GC_register_my_thread(&sb)` antes de executar qualquer código Delégua e desregistra com `GC_unregister_my_thread()` ao sair. Compilações isoladas sem GC (`tests/rotinas_pool.c` sob TSan) usam guardas `#if !defined(DELEGUA_NO_GC)`.

18. **Como erros são propagados?**  
    Cada worker possui pilha TLS própria de frames `setjmp`/`longjmp` (`DELEGUA_TLS` em `excecoes.c`). Exceções lançadas no worker são capturadas no wrapper `worker_main`, empacotadas em `rt_transfer_slot` (mensagem + código + origem), entregues ao reator principal e rejeitam a `Tarefa<T>` (`Promessa`) correspondente, sendo capturáveis via `tente { aguardar t } pegue (erro: Excecao)`.

19. **Como tarefas são canceladas?**  
    `tarefa.cancelar()` chama `rt_pool_cancelar(pool, id)`. Se a tarefa ainda estiver na fila (não iniciada), é marcada como `RT_TAREFA_CANCELADA` imediatamente sem executar. Se já estiver em execução no worker, o cancelamento é cooperativo (o resultado é descartado na entrega e a tarefa conclui como cancelada).

20. **Existe suporte a timeout?**  
    Via composição com `Temporizador` / `Promessa.corrida` no loop assíncrono (`cgd:assincrono`) e timeouts nativos em `Processo.executarLote` (`poll` com deadline monotônico). O pool de rotinas em si também coleta `tempoFilaNs` e `tempoExecNs` por tarefa para diagnóstico de saturação.

21. **Como o runtime evita deadlocks?**  
    - Ordem única de travamento (`pool->mutex` nunca é mantido durante execução de código Delégua ou chamadas ao GC).
    - `Canal<T>` (`assincrono_canal.c`) existe apenas na thread principal do loop de eventos (sem locks bloqueantes inter-thread).
    - `modulos.c` usa `PTHREAD_MUTEX_RECURSIVE` (`delegua_mod_lock`) para inicialização de módulos com dependências transitivas.
    - `objetos.c` mantém `func_cache_mutex` e `layout_mutex` estritamente em seções críticas folha (nunca chamando código do usuário sob lock).

22. **Qual o overhead para criar e executar uma rotina?**  
    Medido em `01_spawn_small_tasks` (2.000 tarefas pequenas em lotes): **`3,86 µs/tarefa`** (`7,60 ms` totais, `4.782 KiB` GC, `8,4 MiB` RSS).

23. **Como o pool reage quando existem centenas de tarefas?**  
    Submissões em lotes até a capacidade da fila (`256` padrão, configurável até `4096`) são drenadas de forma contínua sem explosão de threads (apenas `W` threads ativas). Acima da capacidade da fila, o runtime rejeita com erro determinístico de backpressure, impedindo *OOM* por enfileiramento ilimitado. No Ciclo IV, a alocação de slots passou de varredura linear para alocação circular $O(1)$ amortizado.

24. **Quais mecanismos garantem sincronização?**  
    - `pthread_mutex_t` + `pthread_cond_t` na fila do pool (`rotinas_pool.c`).
    - `eventfd` + `epoll` para entrega assíncrona ao loop principal (`rotinas_reactor.c`).
    - Atômicas `acquire`/`release` (`DELEGUA_ATOMIC_LOAD_PTR/STORE_PTR`, `DELEGUA_ATOMIC_LOAD_INT/STORE_INT`) em inline caches (`objetos.c`), cache de funções (`delegua_funcao_cache`), inicialização de módulos (`codegen.d` + `modulos.c`) e refcount de `rt_shared_bytes` (`bytes_rt.c`).
    - TLS (`__thread`) para frames de exceção, `delegua_call_depth`, `delegua_local_atual`, cache UTF-8 (`textos.c`) e cursor de mapa (`colecoes.c`). *(Nota: TinyCC define `DELEGUA_TLS` vazio; execução concorrente de rotinas é suportada em GCC/Clang com TLS nativo.)*

25. **Como classes e inline caches interagem com threads?**  
    - **Achado crítico auditado e corrigido no Ciclo IV**:
      1. `delegua_funcao_cache` em `objetos.c` apresentava uma *data race* real (leitura/escrita sem sincronização de `slot->type`); corrigido com `func_cache_mutex` + carga/escrita atômica `acquire`/`release`.
      2. `delegua_prop_ic` / `delegua_def_ic` / `delegua_chamar_ic` foram endurecidos com `DELEGUA_ATOMIC_LOAD_PTR` em `cached->layout_klass` e `cached->klass`.
      3. Classes fechadas com campos `privado` (como `Bytes`, `Arena`, `FatiaBytes`, `FatiaInt64`) antes desabilitavam inline caching (`fast_fields = false`); no Ciclo IV o IC foi destravado para classes fechadas sem acessores checando o nível de acesso em $O(1)$ inline — mantendo segurança total e dobrando a velocidade de `Bytes`/`Arena`.

---

## 3. Evidência Experimental (Microbenchmarks de Rotinas)

Script: `scripts/bench_rotinas_memoria.py` (3 repetições sequenciais, `clang -O2`, dados em `out/bench_rotinas_baseline.json` e `out/bench_rotinas_ciclo4_ic.json`):

| Benchmark | Baseline | Ciclo IV | Observação |
|---|---:|---:|---|
| `01_spawn_small_tasks` (2.000 tarefas) | `7,77 ms` (`3,89 µs/t`) | `7,60 ms` (`3,86 µs/t`) | Overhead mínimo; RSS `8,4 MiB` |
| `02_cpu_bound_seq_vs_par` (seq vs 4w) | `1141 → 312 ms` (`3,66×`) | `1121 → 292 ms` (`3,84×`) | Escalabilidade próxima ao linear em 4 núcleos físicos |
| `03_transfer_text_roundtrip` (4 MiB × 10) | `33,85 ms` (`80 MiB` GC) | `33,42 ms` (`80 MiB` GC) | Confirma custo de cópia profunda em `texto` |
| `04_channel_throughput` (10.000 msgs) | `13,08 ms` (`1,31 µs/msg`) | `12,61 ms` (`1,26 µs/msg`) | Canal single-thread no event loop |
| `05_gc_concurrent_alloc` (4w alocando) | `102,8 → 52,0 ms` (`1,98×`) | `99,3 → 51,1 ms` (`1,94×`) | **Contenção real do Boehm GC sob alocação intensiva** |
| `06_bytes_frozen_zero_copy` (16 MiB × 4w) | *(não existia)* | **`76,9 → 19,6 ms` (`3,92×`)** | **`transfer_ms=0,011 ms`**, apenas `137 KiB` GC |
| `08_workers_1_2_4_8_scaling` | *(não existia)* | `w1=535 w2=290 w4=194 w8=115 ms` | Speedup `1,84×` (2w), `2,76×` (4w), **`4,67×` (8w)** |

**Conclusão arquitetural da auditoria**: o runtime de rotinas do CGD é excelente para computação CPU-bound e processamento sobre `BytesCongelado` + `Arena` (escala `3,8×–4,7×` com `< 40 MiB` RSS), mas **não é adequado para clonar grafos AST/IR mutáveis gigantes** nem para múltiplas threads alocando centenas de MiB simultaneamente no mesmo heap Boehm GC (`1,94×` de teto por contenção de lock/STW do GC). Essa constatação guiou diretamente o design híbrido do DCC Ciclo V.
