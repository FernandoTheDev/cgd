# Auditoria de Memória do Runtime CGD — Ciclo III

**Data:** 21/11/2026  
**Escopo:** `vendor/delegua-runtime/src/{delegua_rt.h,objetos.c,colecoes.c,biblioteca.c,bytes_rt.c,sistema_posix.c}` + interação com Boehm-Demers-Weiser GC (`libgc`) sob carga extrema do DCC 0.2.0.

---

## 1. Diagnóstico Forense do Consumo de Memória Pré-Ciclo III

Usando a nova instrumentação [`Sistema.memoria()`](file:///home/fernandodev/cgd/bibliotecas/sistema.delegua) (que consulta `/proc/self/status`, `/proc/self/smaps_rollup` e `GC_get_*` diretamente no processo), medimos a execução do DCC 0.2.0 compilando `frozen_dcc.c` (5,05 MiB, 865.315 tokens, 442.449 nós AST, 803.990 instruções SSA) **antes** das otimizações de memória do Ciclo III:

- **Pico RSS**: `6.252 MiB` (com `-fmem-report`) a `6.404 MiB` (`6.715.172 KB` no baseline sem telemetria) em Clang `-O2`, chegando a **`7.118.316 KB` (6,79 GiB)** em GCC `-O0`.
- **Alocações cumulativas no Boehm GC (`gc_total`)**: **`12.150 MiB` (~11,9 GiB)** para compilar um único arquivo C de 5,05 MiB (amplificação de **2.460×** sobre o tamanho da entrada!).

### 1.1. Anatomia do Desperdício no Runtime CGD

| Estrutura do Runtime | Layout Ciclo II (Antes) | Custo Real por Instância | Custo em 1M Instâncias | Layout Ciclo III (Depois) | Redução |
| --- | --- | ---: | ---: | ---: | ---: |
| **Objeto com 8 campos** (`TokenC99`) | `objeto` + `hashmap` + `buckets[16]` + `8 × entry(64B)` + `origem_erro` | ~**1.430 B** (13 allocs GC) | ~**1,36 GiB** | `32 B + 8 × 24 B` = **224 B** (1 alloc GC) | **6,4× menor** |
| **Objeto com 18 campos** (`NoAST`) | `objeto` + `hashmap` + `buckets[32]` + `18 × entry(64B)` + `origem_erro` | ~**2.880 B** (23 allocs GC) | ~**2,75 GiB** | `32 B + 18 × 24 B` = **464 B** (1 alloc GC) | **6,2× menor** |
| **Vetor vazio `[]`** (`NoAST.filhos` em folha) | `vetor` (32 B) + `8 × 24 B` (`values`) | **224 B** (2 allocs GC) | **214 MiB** | **32 B** (1 alloc GC, `values=NULL`) | **7,0× menor** |
| **Dicionário vazio `{}`** | `hashmap` (32 B) + `buckets` (64–128 B) | **96–160 B** (2 allocs GC) | **92–153 MiB** | **32 B** (1 alloc GC, `buckets=NULL`) | **3–5× menor** |
| **Buffer binário de 17,8 MB** | `inteiro[]` (`24 B/byte`, geométrico 2×, varrido pelo GC!) | **427–854 MiB** live (~1,6 GiB alloc) | — | `Bytes` (`GC_MALLOC_ATOMIC`, 1 B/byte) = **17–32 MiB** | **~25× menor** |

---

## 2. Arquitetura de Memória Implementada no Runtime (Ciclo III)

### 2.1. Objetos de Slots Fixos Inline (`objetos.c`)
- **Descritor de classe (`struct classe`)**:
  - Na primeira instanciação (ou via `finalizar_layout` protegido por `layout_mutex`), a classe compila a hierarquia completa (superclasses + mixins + campos próprios) em um array plano `campo_slot *slots_layout` de tamanho `num_slots`, acompanhado de uma tabela hash aberta (`slot_hash_idx`) com fator de carga ≤ 50% para lookups dinâmicos em $O(1)$.
  - Cada `campo_slot` armazena: nome, índice no array `slots[]`, `fast_check` (tag de tipo primitivo para validação rápida sem `delegua_conforme`), flags de restrição/acessor e `layout_klass` (ponteiro para a classe detentora, usado para validação de IC).
  - `ctor_cache` memoriza o construtor efetivo, evitando busca na cadeia de protótipos a cada `delegua_instanciar`.
- **Instância (`struct objeto`)**:
  - Cabeçalho de 32 bytes: `classe *klass`, `hashmap *campos_extra` (`NULL` para classes fechadas), `struct origem_erro *origem_erro` (`NULL` até erro), `u32 num_slots` e `delegua_value slots[]` (FAM).
  - Alocação única: `GC_MALLOC(sizeof(struct objeto) + num_slots * sizeof(delegua_value))`.
  - Como `DELEGUA_T_NULO == 0`, o zeroing garantido por `GC_MALLOC` inicializa todos os slots sem nenhum loop `semear_campos` e sem nenhuma alocação auxiliar.
- **Invalidação segura**: se um campo/acessor/restrição for adicionado dinamicamente a uma classe após instanciações anteriores, `invalidar_layout_classe` limpa `layout_klass` dos slots antigos (invalidando todos os ICs apontando para eles) e promove instâncias pré-existentes de forma transparente via `campos_extra`.

### 2.2. Coleções Vazias Preguiçosas e Liberação Explícita (`colecoes.c`, `biblioteca.c`)
- `create_vetor()` e `create_map()` inicializam `cap = 0`, `size = 0`, `values = NULL` / `buckets = NULL`.
- `VETOR_INIT_CAP` foi reduzido de `8` para `4` (vetores pequenos como listas de 1–3 argumentos ou filhos de nós binários da AST passam de 192 B para 96 B).
- `vetor.limpar()` e `dicionario.limpar()` zeram `size`, `cap` e atribuem `NULL` ao ponteiro de dados interno, quebrando instantaneamente a retenção de ponteiros pelo Boehm GC mesmo quando o objeto contêiner ainda reside em algum registrador ou slot de pilha.

### 2.3. `cgd:bytes.Bytes` em Memória Atômica (`bytes_rt.c`)
- Todas as alocações do buffer interno de `Bytes` usam **`GC_MALLOC_ATOMIC`**:
  - O Boehm GC **não varre** o conteúdo do buffer procurando falsos ponteiros (crucial para código de máquina x86-64 e tabelas ELF que contêm sequências arbitrárias de 8 bytes!).
  - O crescimento geométrico (`bytes_garantir_cap`) evita realocações quadráticas ao emitir buffers de 17–22 MiB sem fragmentar o heap GC.
  - `gravarArquivo` / `lerArquivo` fazem `fwrite`/`fread` direto do ponteiro `unsigned char *data`, eliminando cópias em texto Base64 e processos auxiliares.

### 2.4. Interação com o Boehm GC Conservador (Lição Arquitetural)
A investigação forense no DCC revelou dois comportamentos críticos do Boehm GC que todo programador e compilador sobre o runtime CGD deve conhecer:
1. **Retenção por pilha conservadora (`cgd_tmp_*` e `volatile`)**: em funções grandes com `tente/pegue`, o CGD marca locais como `volatile` (exigido por `setjmp`/`longjmp`). Mesmo após `tokens = nulo`, cópias residuais em `cgd_tmp_*` ou *compound literals* no frame da função continuam mantendo o grafo inteiro vivo até o retorno da função. Além disso, o Clang `-O2` pode fazer *inline* de funções auxiliares de volta no caller.
2. **Coleta sob demanda após picos de fase**: quando o heap GC já cresceu para ~800 MiB, o limiar adaptativo do Boehm GC pode atrasar coletas em fases subsequentes com menor pressão de alocação. Combinar **isolamento de frame + `.limpar()` + `Sistema.coletarGC(verdadeiro)`** em fronteiras de grandes fases derrubou o RSS final em mais de 330 MiB adicionais.

---

## 3. Impacto Medido no Perfil de Memória (DCC `frozen_dcc.c`, `clang -O2`)

| Fase | RSS Antes (MiB) | RSS Depois (MiB) | Redução RSS | GC Alloc Cumulativo Antes (MiB) | GC Alloc Cumulativo Depois (MiB) |
| --- | ---: | ---: | ---: | ---: | ---: |
| `PREPROCESS_END` | `95` | `195` *(hwm 226)* | *(menos ciclos GC: 157→35)* | `3.502` | **`2.081`** (-40,6%) |
| `LEX_END` | `1.274` | **`398`** | **-68,8%** | `5.382` | **`2.575`** (-52,2%) |
| `PARSE_END` | `3.060` | **`834`** | **-72,7%** | `7.463` | **`3.107`** (-58,4%) |
| `SEMA_END` | `3.155` | **`834`** | **-73,6%** | `7.800` | **`3.216`** (-58,8%) |
| `IR_END` | `4.488` | **`870`** | **-80,6%** | `9.592` | **`3.652`** (-61,9%) |
| `OPT_END` | `4.488` | **`870`** | **-80,6%** | `9.922` | **`3.654`** (-63,2%) |
| `CODEGEN_END` | `6.048` | **`923`** | **-84,7%** | `11.678` | **`3.830`** (-67,2%) |
| `ELF_END` (Pico) | `6.098` *(6.404 s/ report)* | **`950`** *(mediana 933)* | **-85,8%** | `12.150` | **`3.863`** (-68,2%) |

---

## 4. Segurança de Memória Validada

- **ASan + UBSan** sobre o runtime C + `testes/stdlib.py` (122 contratos) + `testes/linguagem_nova.py` + `tests/runtime.c`: **0 leaks fatais/UAF/buffer-overflow/UB** (incluindo o caso limite `memmove` em vetor vazio e invalidação dinâmica de layout).
- **TSan** (`testes/assincronismo.py`): **0 data races** nos caches atômicos de descritores, `layout_mutex` e ponteiros atômicos de IC.
