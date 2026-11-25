# Relatório Técnico — Correção Definitiva do CGD-GC (Strings Heap de 1 Byte), Fortalecimento do HeapVerifier e Evolução do FFI C

## 1. Resumo Executivo

Durante o desenvolvimento e validação de estresse do projeto **LinConEs Nativo** (`~/lincones`) sobre o **CGD v0.10.0**, dois defeitos fundamentais de infraestrutura foram expostos e diagnosticados até a causa raiz:

1. **Coleta prematura e corrupção de strings heap de 1 byte no CGD-GC (`text.len >= 2U`)**: seis pontos do runtime nativo ignoravam valores `DELEGUA_T_TEXT` com `len < 2`, assumindo incorretamente que toda string de 1 byte residiria na tabela estática `delegua_single_byte_strs[256][2]`. Strings de 1 byte alocadas dinamicamente no heap (ex.: concatenação `"" + ch` no lexador para identificadores de 1 caractere como `"k"` e `"v"`) não eram marcadas pelo coletor, não passavam pela barreira de escrita intergeracional e eram ignoradas pelo `HeapVerifier`, sendo recicladas prematuramente sob pressão de alocação.
2. **Conflito de cabeçalhos C e ausência de ponteiro opaco no FFI C**: o gerador C emitia declarações `extern` incompatíveis com `<stdio.h>` / `<stdlib.h>` / `<string.h>` usando `uint64_t` em vez de `void *`, impedindo o uso direto de `fopen`, `fclose`, `fseek`, `fread`, `fwrite`, `malloc`, `free` etc., e o linker não aceitava bibliotecas compartilhadas por soname versionado (`:libmariadb.so.3`) ou caminho absoluto.

Todas as causas raiz foram corrigidas preservando integralmente o **CGD-GC** como coletor padrão, o backend **C99**, a arquitetura híbrida de memória (ANS, escape analysis, alocação em stack, liberação determinística, fusão de coleções, desvirtualização) e o **Boehm** como referência diferencial opcional.

---

## 2. Parte I — Causa Raiz e Correção do CGD-GC

### 2.1 Diagnóstico Experimental

- **Caso reproduzível preservado**: `~/lincones/reproducoes/cgd_gc_fuzz_pressao.delegua` (400 iterações de fuzzing sintático seguidas de 150 operações no `MotorProprio` com colunas `"k"` e `"v"`).
- **Manifestação pré-correção**: falhava de forma determinística no `CGD-GC` (mesmo com `--opcoes-memoria=nenhuma`), produzindo `Texto UTF-8 incompleto`, `Coluna duplicada '\x00'` ou `Coluna '0' não existe`, enquanto o mesmo programa passava em `Boehm`.
- **Análise do runtime**: funções como `delegua_text_concat` / construtores dinâmicos podem produzir `DELEGUA_T_TEXT` com `len == 1` cujo ponteiro reside em uma região gerenciada pelo `CGD-GC`. Porém, 6 verificações assumiam `len >= 2U` como proxy para "alocado no heap":
  1. `vendor/delegua-runtime/src/delegua_rt.h` (`cgd_gc_write_barrier_val`)
  2. `vendor/delegua-runtime/src/gc/gc_collector.c` (`mark_delegua_value`)
  3. `vendor/delegua-runtime/src/gc/gc_collector.c` (`CGD_GC_KIND_VALUE_ARRAY`)
  4. `vendor/delegua-runtime/src/gc/gc_verifier.c` (validação de handles `DELEGUA_T_TEXT`)
  5. `vendor/delegua-runtime/src/colecoes.c` (`rt_gc_trace_map_entry`)
  6. `vendor/delegua-runtime/src/objetos.c` (`trace_val_helper`)

### 2.2 Correção Implementada

- Removida a guarda incorreta `len >= 2U` nos 6 pontos acima, passando a verificar apenas `ptr != NULL`.
- A filtragem de ponteiros estáticos (incluindo `delegua_single_byte_strs[256][2]` e literais de texto) já é realizada em `O(1)` por `cgd_gc_radix_lookup(ptr) == 0` no coletor e na barreira de escrita — eliminando qualquer necessidade de heurística por comprimento.
- **Fortalecimento do `HeapVerifier`** (`vendor/delegua-runtime/src/gc/gc_allocator.c`): removido o atalho que forçava `do_full = true` em todos os ciclos no perfil `CGD_GC_PROFILE=verify`. Agora `verify` executa coletas **minor** e **major** reais e valida todas as invariantes (inclusive referências `OLD → YOUNG` e integridade de `DELEGUA_T_TEXT` de 1 byte) após cada ciclo.

### 2.3 Contrato de Rastreamento e Barreira de Escrita

- Todo valor `DELEGUA_T_TEXT` com `ptr != NULL` **deve** ser entregue ao marcador (`cgd_gc_mark_ptr`), à barreira de escrita (`cgd_gc_write_barrier_val`) e ao verificador (`cgd_gc_verify_heap_locked`), independentemente de `len`.
- Ponteiros fora de regiões `CGD-GC` (literais C, tabela estática de 1 byte) são descartados com segurança e custo `O(1)` via `cgd_gc_radix_lookup`.

---

## 3. Parte II — Correção do FFI C

### 3.1 Melhorias no Compilador (`src/`)

- **Novo tipo opaco `cponteiro`** (`src/frontend/type_registry.d`, `src/frontend/semantic/foreign.d`, `src/backend/c/descriptors.d`, `src/backend/c/foreign.d`): mapeado para `void *` na ABI C, com conversão explícita `(void *)(intptr_t)` / `(int64_t)(intptr_t)` no wrapper gerado.
- **Resolução de conflitos com cabeçalhos padrão C** (`src/frontend/parser/ast.d`, `src/frontend/semantic/foreign.d`, `src/backend/c/foreign.d`):
  - Suporte ao metadado `@definicao(declarado = verdadeiro)` em métodos estrangeiros para omitir a redeclaração `extern` quando o símbolo já vem de cabeçalho incluído.
  - Detecção automática de símbolos da biblioteca padrão C já declarados por `<stdio.h>`, `<stdlib.h>` e `<string.h>` (`fopen`, `fclose`, `fseek`, `ftell`, `fgetc`, `fputc`, `fflush`, `fread`, `fwrite`, `malloc`, `calloc`, `realloc`, `free`, `memcpy`, `memmove`, `memset`, `remove`, `rename`, etc.), evitando conflitos de protótipo em GCC e Clang.
- **Bibliotecas compartilhadas por soname versionado e caminho absoluto** (`src/frontend/semantic/foreign.d`, `src/driver/compile.d`):
  - `@definicao(biblioteca = ":libmariadb.so.3", abi = "c")` gera `-l:libmariadb.so.3` no linker.
  - Caminhos absolutos `.so` são aceitos e passados diretamente ao linker.

---

## 4. Validação e Testes Permanentes de Regressão

| Suíte / Verificação | Resultado |
|---|---|
| `~/lincones/reproducoes/cgd_gc_fuzz_pressao.delegua` (6 perfis: `balanced`, `low_mem`, `throughput`, `low_latency`, `stress`, `verify`; GCC `-O2` e Clang `-O2`) | **PASSOU (6/6 × 2 compiladores)** |
| `python3 testes/gc_hibrido.py` (inclui novo `test_one_byte_heap_strings_and_intergenerational`) | **PASSOU** |
| `python3 testes/memoria.py` | **PASSOU (9/9)** |
| `python3 testes/ffi_stdio_e_soname.py` (GCC e Clang `-o`, `cponteiro`, `<stdio.h>` 4 KiB roundtrip, `:libmariadb.so.3`) | **PASSOU** |
| `dub test --compiler=ldc2` | **PASSOU (10 módulos)** |
| `~/dcc/bootstrap/verify.sh` (regressão externa) | **PASSOU (86/86)** |
| ASan + UBSan + `CGD_GC_PROFILE=verify` em `cgd_gc_fuzz_pressao.delegua` e `overflow_e_ordenacao_externa_teste.delegua` | **PASSOU (0 erros)** |
| Fuzzing intensificado 10× no LinConEs (12.000 parses + 4.500 ops em 3 sementes: `balanced`, `low_mem`, `verify`, `boehm`) | **PASSOU (4/4)** |
