# Arquitetura do Compilador C99 Nativo em Delégua/CGD

Este documento descreve a arquitetura interna, os contratos de ABI/ELF64, a matriz de conformidade ISO/IEC 9899:1999 (C99) e as limitações reais ainda abertas do compilador C99 localizado em `exemplos/compiladores_e_vms/compiladores/c_nativo/`.

## 1. Pipeline de Compilação

O compilador é integralmente escrito em Delégua e compilado para binário nativo pelo CGD, sem invocar GCC, Clang, NASM ou `ld` como backend:

```text
Fonte .c + headers (.h)
   │
   ▼  preproc.delegua (Fases 1–4 ISO C99)
Tokens de pré-processamento, trigraphs, junção de linhas, comentários,
#include real (-I), macros objeto/função/variádicas (__VA_ARGS__), #, ##,
hide-set, #if/#elif/#else/#endif/defined, #undef, #line, #error, #pragma once, _Pragma
   │
   ▼  lexer.delegua (Fases 5–6)
Tokens tipados (enum TokC99 + dicionários O(1)), literais hex/oct/dec/float/char,
concatenação de strings adjacentes
   │
   ▼  parser.delegua
AST C99 (enum NoKind): especificadores/qualificadores, typedef, struct/union/enum,
ponteiros de função, arrays multidimensionais, VLAs, inicializadores designados,
literais compostos, __builtin_va_start / __builtin_va_arg, casts, sizeof, goto/labels
   │
   ▼  sema.delegua
Análise semântica + cálculo de layout LP64 (alinhamento/padding reais),
resolução de escopos, __func__, verificação de labels/goto e assinaturas
   │
   ▼  ir_ssa.delegua
Lowering AST -> ModuloSSA (CFG + IR SSA tipada com 1/2/4/8B, signed/unsigned,
IEEE-754 float/double, globais .data/.bss, Alloca 16B, va_list SysV AMD64)
+ Otimizador (-O1: ConstProp/Folding, Simplificação Algébrica, CopyProp, CFG, DCE)
+ Verificador estrutural de invariantes (verificarModuloSSA)
   │
   ├──► backend_asm.delegua (-S)   ──► Assembly x86-64 Intel (System V AMD64 ABI)
   └──► backend_elf.delegua (padrão) ─► Código de máquina x86-64 + ELF64 Dinâmico
```

## 2. Modelo de Dados LP64 e System V AMD64 ABI

| Tipo C99                                | Largura (bytes)         | Alinhamento (bytes) | Observações                                                   |
| --------------------------------------- | ----------------------- | ------------------- | ------------------------------------------------------------- |
| `_Bool`, `char`, `signed/unsigned char` | 1                       | 1                   | Extensão `movsx`/`movzx`; `_Bool` normalizado via `ToBool`    |
| `short`, `unsigned short`               | 2                       | 2                   | `movsx`/`movzx`                                               |
| `int`, `unsigned int`                   | 4                       | 4                   | `movsxd` (signed) / `mov eax, [rax]` (unsigned)               |
| `long`, `long long`, ponteiros          | 8                       | 8                   | Aritmética 64-bit                                             |
| `float`                                 | 4                       | 4                   | Armazenado em 32-bit IEEE-754 (`movss`/`cvtss2sd`/`cvtsd2ss`) |
| `double`                                | 8                       | 8                   | SSE2 escalar 64-bit (`movsd`/`addsd`/`ucomisd`)               |
| `struct` / `union`                      | Alinhado ao maior campo | Máximo dos campos   | Padding interno e final conforme System V AMD64               |

### Convenção de Chamada (System V AMD64)

- **Inteiros e ponteiros**: `rdi`, `rsi`, `rdx`, `rcx`, `r8`, `r9`; argumentos excedentes empilhados da direita para a esquerda mantendo `rsp` alinhado em 16 bytes antes de `call`, lidos pelo callee em `[rbp + 16 + k*8]`.
- **Ponto flutuante**: `xmm0`..`xmm7` (e `mov eax, numXmm` antes da chamada para funções variádicas).
- **Retornos**: `rax` (inteiros, ponteiros e `struct`/`union` ≤ 8 bytes), `xmm0` (`float`/`double`).
- **`va_list` (`<stdarg.h>`)**: layout binário idêntico à System V AMD64 ABI (`gp_offset`, `fp_offset`, `overflow_arg_area`, `reg_save_area`) com área de salvamento de 176 bytes (6 GP + 8 XMM espaçados de 16 bytes), compatível diretamente com `vprintf`/`vsnprintf` da `libc.so.6`.
- **VLAs (`Alloca`)**: alocação dinâmica alinhada em 16 bytes na pilha (`add rax, 15; and rax, -16; sub rsp, rax; mov rax, rsp`), preservando o frame via `rbp` e liberada automaticamente no epílogo `mov rsp, rbp`.

## 3. Layout do Executável ELF64 Nativo (`backend_elf.delegua`)

O backend binário gera um executável ELF64 dinâmico sem segmentos `RWE` (W^X respeitado):

- **Program Headers (5)**:
  1. `PT_PHDR` (`R`)
  2. `PT_INTERP` (`R`) — `/lib64/ld-linux-x86-64.so.2`
  3. `PT_LOAD #1` (`R E`, alinhado a `0x1000`, base `0x400000`) — ELF header, Phdrs, `.interp`, `.dynstr`, `.dynsym`, `.hash`, `.rela.dyn`, `.rodata`, `.text`
  4. `PT_LOAD #2` (`R W`, alinhado em página seguinte `0x1000`) — `.dynamic`, `.got`, `.data`, `.bss` (`p_memsz = p_filesz + bssSize`)
  5. `PT_DYNAMIC` (`R W`) — entradas `DT_NEEDED` (`libc.so.6` + bibliotecas via `-l`, ex. `-lm` -> `libm.so.6`)
- **Section Headers (13)**: `NULL`, `.interp`, `.dynstr`, `.dynsym`, `.hash`, `.rela.dyn`, `.rodata`, `.text`, `.dynamic`, `.got`, `.data`, `.bss`, `.shstrtab`.
- **Relocações**: `R_X86_64_GLOB_DAT` em `.rela.dyn` resolvidas pelo carregador dinâmico do sistema na `.got`.

## 4. Distribuição Própria de Headers C99 (`include/`)

Nenhum header é simulado ou codificado dentro do pré-processador. Todos os `#include <...>` leem e analisam declarações reais dos arquivos em `include/`:

- `stddef.h`, `stdint.h`, `stdbool.h`, `limits.h`, `iso646.h`, `float.h`, `inttypes.h`, `errno.h`, `assert.h`, `ctype.h`, `string.h`, `stdlib.h`, `stdio.h`, `stdarg.h`, `math.h`, `time.h`, `signal.h`.

## 5. Matriz Honesta de Conformidade ISO C99

### Implementado e Validado Diferencialmente contra `gcc -std=c99` (`-O0` e `-O1`)

- Pré-processador C99 real: fases 1–4, trigraphs, line splicing, comentários, `#include "..."` / `<...>` com `-I`, `-D`, macros objeto/função/variádicas (`__VA_ARGS__`), `#`, `##`, hide-set contra recursão infinita, `#if`/`#elif`/`#else`/`#endif`/`#ifdef`/`#ifndef`/`#undef`/`defined`, `#error`, `#line`, `#pragma once`, `_Pragma`, `__FILE__`, `__LINE__`, `__DATE__`, `__TIME__`, `__STDC__`, `__STDC_VERSION__`.
- Tipos escalares LP64 reais (`_Bool`, `char`, `short`, `int`, `long`, `long long`, `signed`/`unsigned`, `float`, `double`), promoções inteiras, conversões aritméticas usuais e casts explícitos.
- `struct`, `union`, `enum`, `typedef`, alinhamento e padding LP64, `offsetof`, `sizeof` em tipos e expressões, cópia de structs/unions e passagem/retorno por valor de structs ≤ 8 bytes.
- Ponteiros multinível, aritmética e diferença de ponteiros, ponteiros para funções, chamadas indiretas e callbacks nativos para `qsort` da `libc.so.6`.
- Arrays multidimensionais, arrays com tamanho inferido (`int a[] = ...`, `char s[] = "..."`), inicializadores designados (`.campo`, `[idx]`), literais compostos (`(Tipo){ ... }`) e VLAs com `sizeof` dinâmico em tempo de execução.
- Variáveis globais (`.data`/`.bss`), variáveis locais `static`, compilação multi-TU (`a.c b.c`) com `extern`, identificador predefinido `__func__`.
- Controle de fluxo completo (`if`/`else`, `while`, `do-while`, `for` C99, `switch`/`case`/`default` com fallthrough, `break`, `continue`, `goto`/labels), curto-circuito (`&&`, `||`), ternário `?:`, vírgula `,`, pré/pós `++`/`--` e todas as atribuições compostas.
- Funções variádicas definidas em C via `<stdarg.h>` (`va_list`, `va_start`, `va_arg`, `va_copy`, `va_end`) com interoperabilidade binária com `vsnprintf`/`vprintf` da `libc.so.6`.
- Vínculo dinâmico com `libc.so.6` e bibliotecas adicionais (`-lm` -> `libm.so.6`).

### Pendências Reais para Conformidade C99 Integral (Ainda Não Implementadas)

O compilador **não** declara conformidade 100% ISO/IEC 9899:1999 enquanto permanecerem pendentes os itens abaixo:

- Bit-fields em `struct` (`unsigned x : 3;`).
- `struct`/`union` por valor maiores que 8 bytes (9–16 bytes em `rax:rdx` e > 16 bytes via ponteiro oculto `sret`/memória na ABI System V AMD64).
- `_Complex`, `_Imaginary` e `long double` (x87 80-bit).
- Literais hexadecimais de ponto flutuante (`0x1.fp+3`), strings/chars largos (`L"..."`, `L'a'`), UCNs (`\uXXXX`).
- Escopo de `typedef` em bloco interno e inicialização de globais com endereços simbólicos (relocações de dados em `.data`, ex.: `const char *g = "abc";`).
- Qualificação estrita `const`/`volatile`/`restrict` na verificação de compatibilidade de tipos e diagnóstico completo de conversões de ponteiros incompatíveis.
- Modo de compatibilidade GNU para consumir diretamente os headers da `/usr/include` da glibc (`__attribute__`, `__extension__`, `asm`, `__builtin_*` da glibc).
- Alocação de registradores por grafo de interferência/linear scan, promoção `mem2reg` com nós `phi` e emissão de objetos relocáveis `.o` (`ET_REL`) com linker próprio.
