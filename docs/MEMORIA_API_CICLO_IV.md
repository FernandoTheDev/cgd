# Biblioteca Padrão `cgd:memoria` — Especificação, Segurança e Benchmarks (Ciclo IV)

Data: 21/11/2026  
Arquivos: `bibliotecas/memoria.delegua`, `vendor/delegua-runtime/src/memoria_rt.c`, `vendor/delegua-runtime/src/bytes_interno.h`, `testes/memoria.py`.

---

## 1. Motivação e Princípios de Design

A auditoria CGD × DCC mostrou que compiladores e ferramentas de sistemas escritos em Delégua sofrem com dois problemas distintos quando dependem exclusivamente do heap gerenciado pelo Boehm GC:
1. Estruturas temporárias de alta rotatividade (mapas de constantes/cópias na IR SSA, bitsets de vivacidade, tabelas de trabalho por função) geram gigabytes de *churn* no GC e múltiplos ciclos *stop-the-world*.
2. Aplicações não dispunham de controle fino, portável e seguro sobre limiares de coleta (`coletarSeAcima`), telemetria detalhada do GC/SO (`RSS`, `HWM`, `PSS`, tempo total de GC) ou buffers binários imutáveis *zero-copy*.

**Princípios invioláveis adotados na `cgd:memoria`:**
- **Zero ponteiros crus expostos ao usuário Delégua** (nenhum `malloc`/`free` inseguro).
- **Prevenção determinística contra *use-after-free*, *use-after-reset* e *double-free***.
- **Separação rigorosa**: memória nativa das arenas (`malloc` fora do GC) nunca armazena ponteiros para objetos gerenciados pelo Boehm GC — apenas dados escalares/binários (`uint8_t`, `int64_t`), eliminando qualquer risco de objetos GC ocultos ou vazamento de raiz.
- **Compatibilidade com `rotina`**: `Arena`, `FatiaBytes` e `FatiaInt64` têm primitivas `paralelo = verdadeiro` para uso isolado dentro de workers, sem permitir compartilhamento de arenas mutáveis entre threads (`clonar` e transferência inter-thread bloqueados).

---

## 2. Superfície da API (`cgd:memoria`)

### 2.1. `Memoria` (Controle do Boehm GC e Telemetria)

| Método | Contrato |
|---|---|
| `Memoria.estatisticas(): dicionario` | Retorna `rssBytes`, `hwmBytes`, `pssBytes`, `heapBytes`, `livresBytes`, `desmapeadosBytes`, `alocadosBytes`, `emUsoBytes`, `ciclosGC`, `tempoTotalGCMs`, `divisorEspacoLivre`, `gcParalelo`. |
| `Memoria.sistema(): dicionario` | Retorna `cpusLogicas`, `cpusAfinidade`, `cpusCgroup`, `cpusEfetivas`, `totalBytes`, `disponivelBytes`, `limiteCgroupBytes`, `usoCgroupBytes`, `efetivaDisponivelBytes`, `limiteProcessos`, `pressao`. |
| `Memoria.coletar(desmapear: logico = falso)` | Executa `GC_gcollect()`; se `desmapear == verdadeiro`, chama `GC_unmap_gap()` / devolução de páginas ao SO. |
| `Memoria.coletarSeAcima(limiteHeapBytes, desmapear): logico` | Coleta somente se `GC_get_heap_size() >= limiteHeapBytes`, evitando coletas redundantes em fases pequenas. |
| `Memoria.definirDivisorEspacoLivre(divisor)` / `obterDivisorEspacoLivre()` | Ajusta `GC_set_free_space_divisor` com validação de faixa segura `[1, 32]`. |
| `Memoria.definirFrequenciaColetaCompleta(freq)` | Ajusta `GC_set_full_freq` com validação `[1, 100]`. |
| `Memoria.expandirHeap(bytes): logico` | Pré-expande o heap GC (`GC_expand_hp`) com limite máximo de segurança por chamada (`<= 1 GiB`). |
| `Memoria.criarArena(capInicial, limiteMax)` | Instancia `Arena` nativa com limite rígido anti-OOM. |
| `Memoria.criarBuffer(capInicial)` / `congelarBytes(buf)` | Criação reservada e congelamento imutável *zero-copy* sobre `cgd:bytes.Bytes`. |
| `Memoria.criarPoolBuffers(capPadrao, maxLivres)` | Pool reutilizável de buffers `Bytes` com limpeza determinística. |
| `Memoria.criarEscopo()` | Escopo RAII (`EscopoMemoria`) que libera todas as arenas e buffers registrados em ordem LIFO. |

### 2.2. `Arena`, `FatiaBytes` e `FatiaInt64` (Segurança por Geração de 64 Bits)

Cada `Arena` mantém internamente (`memoria_rt.c`):
- Lista encadeada de blocos nativos (`malloc` fora do GC), alocador linear (*bump pointer*) alinhado em 8 bytes e teto rígido `limiteMaximo` (padrão `64 MiB`).
- Contador monotônico **`uint64_t generation`** (iniciado em `1`).
- Flag `alive` (`1` ativa, `0` liberada) + **finalizador GC** (`GC_register_finalizer_no_order`) garantindo liberação automática dos chunks nativos mesmo se o usuário esquecer de chamar `arena.liberar()`.

Toda `FatiaBytes` e `FatiaInt64` captura `(arena_ptr, captured_generation, data_ptr, len, cap)`:
- **Em toda leitura/escrita**: valida `arena->alive && slice->generation == arena->generation` e *bounds check* `0 <= idx < len`.
- **`arena.limpar()`**: reseta o *bump pointer* em $O(1)$ (reutilizando os blocos já alocados sem `malloc`/`free`) e **incrementa `arena->generation++`**, invalidando instantaneamente todas as fatias emitidas antes da limpeza (*anti-use-after-reset*).
- **`arena.liberar()`**: libera todos os blocos nativos, marca `alive = 0` e incrementa `generation++` (idempotente — *anti-double-free* e *anti-use-after-free*).
- **`fatia.valida()`**: permite consulta explícita de validade sem lançar exceção.
- **`fatia.paraBytes()` / `fatia.paraBytesCongelado()`**: materializa os bytes válidos para `Bytes` gerenciado ou congelado *zero-copy*.

### 2.3. `PoolBuffers` e `EscopoMemoria`

- **`PoolBuffers`**: mantém até `maxLivres` buffers `Bytes` pré-alocados (`adquirir()`, `devolver(buf)`, `esvaziar()`, `estatisticas()`), evitando realocações repetidas em pipelines de compilação/I/O.
- **`EscopoMemoria`**: agrupa arenas e buffers criados dentro de uma fase (`criarArena`, `registrarArena`, `registrarBuffer`, `relatorio()`, `encerrar(coletarGC, desmapear)` + `destrutor()`), oferecendo contabilidade delta de `alocadosBytes`, `ciclosGC` e `rssBytes`.

---

## 3. Validação e Benchmarks Reais

### 3.1. Regressões (`testes/memoria.py` — 9/9 aprovadas com e sem `-o`)
- Telemetria `Memoria.estatisticas()` e `Memoria.sistema()` com invariantes numéricos válidos.
- `coletar`, `coletarSeAcima`, `definirDivisorEspacoLivre` (e rejeição de divisores inválidos `0`/`999`).
- `Arena` + `FatiaBytes` + `FatiaInt64`: escrita/leitura, invalidação determinística após `limpar()` (*use-after-reset*) e `liberar()` (*use-after-free*), idempotência de `liberar()`, limite anti-OOM e *bounds checking*.
- `PoolBuffers` (reutilização comprovada via `estatisticas()`) e `EscopoMemoria` (liberação LIFO em `encerrar()`).
- Uso de `Arena` + `FatiaBytes` + `FatiaInt64` dentro de `rotina` paralela (auditado por `E3402`) e bloqueio estático/runtime de transferência direta de `Arena` entre threads.
- Validação sob **ASan + UBSan** (`testes/assincronismo.py` e `vendor/delegua-runtime/tests/run.sh`): 0 vazamentos, 0 UAFs, 0 UBs.

### 3.2. Benchmark Comparativo (`07_arena_vs_bytes_vs_vetor_vs_dict`, 100 rodadas × 16.384 elementos)

| Estrutura | Tempo (mediana) | Alocação GC Total | Redução de Churn GC |
|---|---:|---:|---:|
| `inteiro[]` (vetor gerenciado) | `54,35 ms` | `61.467 KiB` (`60,0 MiB`) | baseline |
| `dicionario` (subset 2k chaves/rodada) | `15,98 ms` | `17.909 KiB` (`17,5 MiB`) | — |
| `cgd:bytes.Bytes` (`GC_MALLOC_ATOMIC`) | `77,11 ms` | `392 KiB` | **157× menos churn** |
| **`cgd:memoria.Arena` (`FatiaInt64`)** | **`76,86 ms`** | **`10 KiB`** | **6.147× menos churn!** |

**Impacto direto no DCC Ciclo V**: substituir dicionários `texto(reg)` por `Arena` (`FatiaBytes` + `FatiaInt64`) em `ir_opt.delegua` e `ir_verify.delegua`, combinado com despacho $O(1)$ de opcodes, derrubou `opt+verify` em `frozen_dcc.c` de **`3.611 ms` para `838 ms` (`4,31×` mais rápido)** com virtualmente zero pressão no Boehm GC.
