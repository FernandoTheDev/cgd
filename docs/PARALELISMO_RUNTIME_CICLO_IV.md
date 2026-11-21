# Evolução do Runtime Paralelo e Thread-Safety — CGD 0.9.0 (Ciclo IV)

Data: 21/11/2026

---

## 1. Resumo das Evoluções Implementadas

Todas as mudanças foram projetadas para fortalecer correção concorrente, eliminar cópias desnecessárias em cargas binárias e oferecer paralelismo adaptativo sem saturar a máquina do usuário nem enfraquecer o isolamento de rotinas.

### 1.1. `Bytes` Congelado *Zero-Copy* (`bytes_interno.h`, `bytes_rt.c`, `rotinas_transferencia.{h,c}`, `bibliotecas/bytes.delegua`)
- Criada estrutura `rt_shared_bytes` alocada fora do Boehm GC (`malloc`/`free`) com `refcount` atômico (`acquire`/`release`) e `immutable = 1`.
- Novo método `Bytes.congelar()` promove o buffer atual para `rt_shared_bytes` (ou cria uma vista compartilhada imutável com finalizador GC que chama `rt_shared_bytes_release`).
- Operações mutáveis (`definir`, `anexar*`, `limpar`, `reservar`, `liberar`) sobre um `Bytes` congelado falham deterministicamente com erro explícito.
- Novas primitivas binárias de baixo custo: `ehCongelado()`, `capacidade()`, `limpar()`, `liberar()`, `reservar(n)`, `lerU16LE()`, `lerU32LE()`, `lerU64LE()`, `definirU64LE()`, `anexarBytesFatia()`, `anexarPreenchimento()`, `lerCString()`.
- Em `rotinas_transferencia.c`:
  - Limite de transferência binária/texto elevado de `16 MiB` para **`64 MiB`**.
  - Adicionados `RT_TRANSFER_BYTES` (cópia exclusiva para buffers mutáveis) e **`RT_TRANSFER_IMMUTABLE_BYTES` (*zero-copy* via retain/release atômico)** para buffers congelados.
  - Compilação isolada de `tests/rotinas_pool.c` (TSan sem GC) preservada com `#if !defined(DELEGUA_NO_GC)`.

### 1.2. Detecção Confiável de Recursos e Política Conservadora (`sistema_posix.c`, `interno.h`, `bibliotecas/sistema.delegua`)
- Implementado `rt_detectar_recursos(rt_sistema_recursos *)` sem depender apenas de `nproc`:
  - `sysconf(_SC_NPROCESSORS_ONLN)` (CPUs lógicas).
  - `sched_getaffinity(0, ...)` via `CPU_COUNT` (afinidade real de CPU, respeitando `taskset`).
  - **Cgroups v2** (`/proc/self/cgroup` subindo hierarquia para `cpu.max`, `memory.max`, `memory.current`) com fallback para **Cgroups v1** (`cpu.cfs_quota_us`/`cpu.cfs_period_us`, `memory.limit_in_bytes`, `memory.usage_in_bytes`).
  - `/proc/meminfo` (`MemTotal`, `MemAvailable`) e `getrlimit(RLIMIT_NPROC)`.
  - Cálculo de `cpus_efetivas = min(logicas, afinidade, cgroup)`, `mem_efetiva_disponivel_bytes` e índice de `pressao_memoria` (`0.0..1.0`).
- Política conservadora `rt_workers_recomendados(mem_por_tarefa_bytes)`:
  - `<= 2` CPUs efetivas → `1` worker; `<= 4` → `2` workers; `> 4` → `cpus_efetivas / 2` (teto automático `8`).
  - Redução automática para `1` worker se RAM disponível `< 768 MiB` ou pressão `>= 0,88`, ou para `<= 2` se `< 1,5 GiB` ou pressão `>= 0,78`.
  - Limite adicional `orcamento_mem / mem_por_tarefa_bytes` quando o chamador informa custo estimado por tarefa.
- Exposto em Delégua como `Sistema.recursos()`, `Memoria.sistema()` e `Rotinas.recursos()` / `Rotinas.workersRecomendados(memBytes)`.

### 1.3. Pool de Rotinas Configurável e Telemetria (`rotinas_pool.{h,c}`, `rotinas_reactor.c`, `bibliotecas/assincrono.delegua`)
- Alocação de slots do pool alterada para varredura circular $O(1)$ amortizado (`next_slot_hint`).
- Adicionada estrutura `rt_pool_stats` (workers configurados, capacidade da fila, pendentes, ativas, total submetidas/concluídas/falhas/canceladas, tempos acumulados de fila e execução em nanossegundos).
- Pool inicializado com `rt_workers_recomendados(0)` no lugar da constante fixa `4`.
- Nova classe `Rotinas` em `cgd:assincrono`: `Rotinas.configurar(workers, capacidade)`, `Rotinas.workersRecomendados(memBytes)`, `Rotinas.estatisticas()`, `Rotinas.recursos()`.

### 1.4. Pool Limitado de Subprocessos (`processo_posix.c`, `bibliotecas/processo.delegua`)
- Implementada `delegua_ffi_sistemaExecutarLote(tarefas, maxConcorrencia)` usando `posix_spawnp` + pipes `O_NONBLOCK` + multiplexação por `poll()` com backpressure estrito (`<= maxConcorrencia` filhos ativos simultaneamente), timeout individual por tarefa, limite de captura e retorno **estritamente na ordem `0..N-1`**.
- Exposta em `cgd:processo` como `Processo.executarLote(tarefas, maxConcorrencia)` — base do paralelismo multi-TU isolado do DCC Ciclo V.

### 1.5. Correções Reais de Thread-Safety e Performance no Runtime & Compilador D
1. **Data race em `delegua_funcao_cache` (`objetos.c`)**: acesso concorrente não sincronizado a `slot->type` corrigido com `func_cache_mutex` e `DELEGUA_ATOMIC_LOAD_INT`/`STORE_INT`.
2. **Hardening de Inline Caches (`objetos.c`)**: `DELEGUA_ATOMIC_LOAD_PTR` em `cached->layout_klass` e `cached->klass` nas fast-paths de `delegua_prop_ic`, `delegua_def_ic` e `delegua_chamar_ic`.
3. **Destravamento de IC para classes fechadas com campos privados (`objetos.c`)**: `Bytes`, `Arena`, `FatiaBytes` e `FatiaInt64` antes tinham `fast_fields = false` por causa de `privado { _recurso }`; agora usam IC monomórfico thread-safe com verificação inline de nível de acesso (`acesso`), dobrando a velocidade de métodos de `Bytes` e `Arena`.
4. **Inicialização thread-safe de módulos (`modulos.c` + `src/backend/c/codegen.d`)**: `compileModule` agora usa `DELEGUA_ATOMIC_LOAD_INT`/`STORE_INT` + `delegua_mod_lock`/`unlock` (`PTHREAD_MUTEX_RECURSIVE`), eliminando corrida quando dois workers importam o mesmo módulo puro pela primeira vez.
5. **Contrato estático `paralelo = verdadeiro` (`ast.d`, `foreign.d`, `routine_validation.d`)**:
   - Aceito **exclusivamente** em `@definicao(biblioteca = "cgd-runtime", abi = "delegua")` — FFI externo C e operações de I/O (`Bytes.lerArquivo`/`gravarArquivo`) permanecem rejeitados com `E3402`.
   - `routine_validation.d` passa a permitir `ImportExpr` de módulos puros (sem variáveis globais mutáveis nem efeitos top-level) e instanciação de classes exportadas de módulos (`right.classRef`) com auditoria recursiva de inicializadores e construtores.
   - Compatibilidade estrita `-std=c99 -pedantic -Werror` com glibc 2.43+ (`(strrchr)` e `(memchr)` parentetizados contra expansão `_Generic` C11).

---

## 2. Validação sob Sanitizadores e Regressões

Todos os testes abaixo foram executados após a versão final de todos os arquivos C, D e Delégua:
- `vendor/delegua-runtime/tests/run.sh`: **APROVADO** (GCC, Clang, runtime C + async C + caminhos de erro).
- `python3 testes/assincronismo.py`: **APROVADO** em Clang, GCC `-O2`, **ASan + UBSan** e **TSan** (0 data races reportadas).
- `dub test --compiler=dmd --config=unittest` e `dub test --compiler=ldc2 --config=unittest`: **10/10 módulos aprovados**.
- `testes/memoria.py` (**9/9**), `testes/rotinas.py` (**15/15**), `testes/driver.py` (**26/26**), `testes/stdlib.py` (**122/122**), `testes/integracao.py` (**439/439**), `testes/async_linguagem.py` (**30/30**), `testes/bibliotecas.py` (**342/342**), `testes/exemplos.py` (**155 exemplos / 310 verificações / 0 falhas**).
- TinyCC `0.9.28rc`: compilação completa do DCC Ciclo V em **`1,36 s`** com saída `.o` bit-a-bit idêntica a GCC e Clang.
