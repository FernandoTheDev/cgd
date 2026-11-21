# Compilador C99 Nativo em Delégua/CGD

Compilador C99 modular escrito inteiramente em Delégua e compilado pelo CGD, direcionado a Linux x86-64 (System V AMD64 ABI), com dois backends nativos:

1. **Backend 1 (`-S`)**: gera Assembly x86-64 (sintaxe Intel).
2. **Backend 2 (padrão)**: gera código de máquina x86-64 e executável ELF64 dinâmico diretamente (sem GCC, Clang, NASM ou `ld`), com segmentos separados `PT_LOAD` `R E` e `R W`, Section Headers completos e vínculo dinâmico à `libc.so.6` oficial (e `libm.so.6` via `-lm`).

## Estrutura dos Módulos

- `c_nativo.delegua`: driver CLI (`-I`, `-D`, `-l`, `-o`, `-S`, `-E`, `-O0`, `-O1`, multi-arquivo `.c`) e auto-teste padrão.
- `preproc.delegua`: pré-processador C99 real (fases 1–4, trigraphs, `#include`, macros objeto/função/variádicas, `#`, `##`, hide-set, `#if`/`#elif`/`#else`/`defined`, `#line`, `#error`, `#pragma once`, `_Pragma`).
- `tipos.delegua`: enums (`TokC99`, `NoKind`, `OpBin`, `OpUn`, `OpIR`, `TipoBase`), sistema de tipos LP64 e codificação IEEE-754 pura em Delégua.
- `lexer.delegua`: analisador léxico C99 com tabelas em dicionário O(1) e concatenação de literais de string.
- `parser.delegua`: parser recursivo descendente C99 (structs, unions, enums, typedefs, ponteiros de função, inicializadores designados, literais compostos, VLAs, `<stdarg.h>`).
- `sema.delegua`: análise semântica e cálculo de layout LP64 (alinhamento/padding).
- `ir_ssa.delegua`: lowering AST → CFG + IR SSA tipada, otimizador SSA e verificador de invariantes.
- `backend_asm.delegua`: emissor Assembly x86-64.
- `backend_elf.delegua`: emissor direto de código de máquina x86-64 + escritor ELF64 dinâmico.
- `include/`: 17 headers C99 reais (`stdio.h`, `stdlib.h`, `string.h`, `stdarg.h`, `stdint.h`, `stddef.h`, `stdbool.h`, `limits.h`, `math.h`, `time.h`, `ctype.h`, `assert.h`, `iso646.h`, `inttypes.h`, `errno.h`, `float.h`, `signal.h`).
- `testes_c99.py`: suíte diferencial comparando `stdout` e código de saída contra `gcc -std=c99` (`-O0` e `-O1`), testes negativos, multi-TU e auditoria ELF64 com `readelf`/`ldd`.
- `ARQUITETURA.md`: especificação técnica detalhada e matriz honesta de conformidade C99.

## Como Compilar e Usar

Na raiz do repositório CGD:

```sh
./cgd exemplos/compiladores_e_vms/compiladores/c_nativo/c_nativo.delegua -s out/c99cc

# Auto-teste integrado (compila e executa programa.c)
cd exemplos/compiladores_e_vms/compiladores/c_nativo && ../../../../out/c99cc

# Uso como compilador C99 CLI
./out/c99cc -O1 meu_programa.c -lm -o meu_binario
./out/c99cc -S meu_programa.c -o meu_programa.s
./out/c99cc -E -DFOO=42 meu_programa.c

# Suíte diferencial contra gcc -std=c99 (52 verificações)
python3 exemplos/compiladores_e_vms/compiladores/c_nativo/testes_c99.py
```
