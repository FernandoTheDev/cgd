# Relatório de Performance — CGD 0.9.0 (Ciclo IV)

Data: 21/11/2026  
Script reproduzível: `scripts/bench_rotinas_memoria.py` (3 repetições sequenciais por cenário, `clang -O2`, dados brutos em `out/bench_rotinas_baseline.json` e `out/bench_rotinas_ciclo4_ic.json`).

---

## 1. Comparação Baseline vs Ciclo IV (Rotinas, Zero-Copy e `cgd:memoria`)

| Cenário | Baseline (mediana) | Ciclo IV (mediana) | Pico RSS (Ciclo IV) | Destaque |
|---|---:|---:|---:|---|
| `01_spawn_small_tasks` (2.000 tarefas) | `7,77 ms` (`3,89 µs/t`) | **`7,60 ms`** (`3,86 µs/t`) | `8.408 KB` | Submissão circular $O(1)$ sem regressão |
| `02_cpu_bound_seq_vs_par` (4 workers) | `307,36 ms` (`3,66×`) | **`297,49 ms`** (`3,84×`) | `7.648 KB` | Speedup `3,84×` em 4 núcleos físicos |
| `03_transfer_text_roundtrip` (4 MiB × 10) | `33,85 ms` (`80 MiB` GC) | `33,42 ms` (`80 MiB` GC) | `49.676 KB` | Custo de cópia profunda preservado como referência |
| `04_channel_throughput` (10.000 msgs) | `13,08 ms` (`1,31 µs/msg`) | **`12,61 ms`** (`1,26 µs/msg`) | `8.372 KB` | Event loop single-thread estável |
| `05_gc_concurrent_alloc` (4w alocando GC) | `52,01 ms` (`1,98×`) | `51,07 ms` (`1,94×`) | `8.520 KB` | Limite real de contenção do Boehm GC documentado |
| `06_bytes_frozen_zero_copy` (16 MiB × 4w) | *(novo)* | **`19,79 ms`** (`3,92×` vs `76,92 ms` seq) | `40.520 KB` | **`transfer_ms = 0,011 ms`**, apenas **`137 KiB` GC** |
| `07_arena_vs_bytes_vs_vetor_vs_dict` | *(novo)* | Arena **`76,98 ms`** (`10 KiB` GC) vs Vetor `54,35 ms` (`61.467 KiB` GC) | `11.460 KB` | **6.147× menos alocação no GC** |
| `08_workers_1_2_4_8_scaling` | *(novo)* | `w1=535,4` → `w2=290,5` → `w4=194,2` → `w8=114,6 ms` | `7.816 KB` | **`1,84×` (2w), `2,76×` (4w), `4,67×` (8w)** |

---

## 2. Impacto do Destravamento do Inline Cache em Classes com Campos Privados (`objetos.c`)

Durante o benchmark `07_arena_vs_bytes_vs_vetor_vs_dict`, a instrumentação revelou que `Bytes`, `Arena`, `FatiaBytes` e `FatiaInt64` não utilizavam os caminhos rápidos `delegua_prop_ic`/`delegua_def_ic`/`delegua_chamar_ic` porque possuíam `privado { _recurso }` (o que marcava `has_restricted = true` e desabilitava `fast_fields`).

Após habilitar IC monomórfico com verificação inline de nível de acesso em `objetos.c` (e remover `assincrona` desnecessária do harness síncrono do benchmark `07`):
- `Arena FatiaInt64` (1,64M acessos): **`286 ms` → `76,86 ms` (`3,72×` mais rápido)**, alocação GC de `187 MiB` → **`10 KiB`**.
- `Bytes` (1,64M acessos): **`290 ms` → `77,11 ms` (`3,76×` mais rápido)**, alocação GC **`392 KiB`**.
- Benefício direto no **DCC Ciclo V**: `codegen` (que chama milhões de `Bytes.anexarByte/U32LE/U64LE`) caiu de `1.420 ms` para **`928 ms` (`-34,6%`)**, e o linker `Bytes` para 300 `.o` caiu de `200 ms` para **`30 ms` (`6,7×` mais rápido)**!

---

## 3. Escalabilidade de Workers (`08_workers_1_2_4_8_scaling`)

Carga: 16 tarefas CPU-bound puras (sem contenção de GC), variando `Rotinas.configurar(W, 128)` no mesmo processo (Intel Core i5-11300H, 4 físicos / 8 SMT):

| Workers | Tempo (ms) | Speedup vs 1w | Eficiência por núcleo físico | Pico RSS |
|---:|---:|---:|---:|---:|
| 1 | `535,39 ms` | `1,00×` | 100% | `7,8 MiB` |
| 2 | `290,49 ms` | `1,84×` | 92% | `7,8 MiB` |
| 4 | `194,21 ms` | `2,76×` | 69% | `7,8 MiB` |
| 8 (SMT) | `114,60 ms` | **`4,67×`** | 117% (ganho real de HT) | `7,8 MiB` |

---

## 4. Comparativo de Transferência: `texto` vs `Bytes` Congelado

| Modo de Transferência | Payload | Despachos | Tempo de Transferência | Alocação GC |
|---|---:|---:|---:|---:|
| `texto` (cópia profunda) | `4 MiB` | 10 roundtrips | `33,42 ms` | `80.000 KiB` |
| **`Bytes` congelado (*zero-copy*)** | **`16 MiB` (4× maior)** | **40 despachos (4× mais)** | **`0,011 ms`** | **`137 KiB`** |

O `Bytes` congelado resolve definitivamente o gargalo de transferência de buffers binários entre thread principal e workers sem comprometer a imutabilidade nem a segurança do Boehm GC.
