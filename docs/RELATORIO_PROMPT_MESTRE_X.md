# Relatório Técnico — Prompt Mestre X (Revisão Definitiva)

**Data**: 23/11/2026  
**Escopo**: Evolução estrutural do CGD (Compilador Geral Delégua) com CTFE inteligente expandido, compilação condicional estrutural (`@quando`), código nativo C99 direto (`@nativo`), 23 tipos escalares C, classes por valor na pilha (`@pilha` / alias `@valor`), ownership/empréstimos/escapes/lifetimes/RAII inferidos automaticamente, operadores personalizados (`@operador`), 8 containers nativos, fronteira gerenciado ↔ nativo segura, bibliotecas GPU/Tensores/ML (`cgd.computacao.{gpu,tensores,ml}` + `@gpu`), gerador de documentação automática (`cgd documentar`), integração LSP/DAP/VS Code e suíte massiva de testes extremos.

---

## 1. Diretriz Arquitetural Central Cumprida

- **Zero novas palavras-chave reservadas**: `git diff src/frontend/lexer/keywords.d` = **0 linhas alteradas**. Nenhuma keyword como `comptime`, `emprestado`, `mover`, `ownership`, `borrow`, `unsafe`, `stack`, `ref` ou `mut` foi adicionada ao lexer, parser ou gramática da extensão VS Code.
- **Reutilização da infraestrutura existente**: CTFE existente em `src/ctfe/` foi preservado e expandido; o sistema de decoradores `@...` foi estendido retrocompatibilmente (`@quando`, `@nativo`, `@pilha`/`@valor`, `@operador`, `@gpu`); e toda a análise de ownership/empréstimos/lifetimes/escapes e RAII é inferida estaticamente pelo compilador.
- **Sem `auto` em D**: 0 ocorrências de inferência `auto` nos módulos D adicionados.
- **Compatibilidade retroativa preservada**: classes gerenciadas GC, `destruir()` idempotente legado em objetos gerenciados, exceções, rotinas paralelas, bibliotecas padrão, exemplos e compilação/conformidade do DCC preservados integralmente.

---

## 2. Entrega por Marco (Marcos A–K)

### Marco A — Auditoria e Especificação Formal
- Criado [docs/ESPECIFICACAO_NATIVA_X.md](ESPECIFICACAO_NATIVA_X.md) com auditoria completa do CTFE existente, modelo de compilação condicional, tabela dos tipos C, layout `@pilha`, análise de ownership/RAII, operadores, containers nativos, fronteira GC e catálogo de diagnósticos `E3501`–`E3951`.

### Marco B — CTFE Expandido e Compilação Condicional Estrutural
- **Arquivos criados/modificados**: `src/driver/target_info.d` (novo), `src/frontend/conditional.d` (novo), `src/diagnostics/catalog.d`, `src/driver/args.d`, `src/cli.d`, `src/frontend/parser/{parser,parse_decl,ast}.d`, `src/frontend/modules.d`, `src/driver/compile.d`, `src/ctfe/vm/cgd_vm.d`, `src/ctfe/context.d`, `src/ctfe/compile.d`, `src/frontend/semantic/purity.d`, `src/opt/constant_folding.d`.
- **Recursos entregues**:
  - `TargetInfo` separando estritamente **alvo** (`--target`, `--cc`, `-o`, `--recurso=<nome>`) de **host**.
  - Pré-passe estrutural `frontend/conditional.d` avaliando `@quando(...)`, `Compilacao.{sistemaOperacional,arquitetura,tamanhoPonteiro,abi,compiladorC,modo,temRecurso}` e ramos `se` constantes **antes** do carregamento de módulos e análise semântica — declarações/imports/FFIs inativos não exigem símbolos ou bibliotecas da plataforma ausente.
  - Expansão da VM CTFE existente: cache de memoização (`memoCache`), tabelas/vetores constantes (`CGDTypeKind.Vetor`) com indexação, curto-circuito `e`/`ou`, `**`, `?:`, `para`, `fazer-enquanto`, `sustar`, `continua`, `escolha`.
  - Códigos diagnósticos: `E3501`, `E3502`, `E3503`.

### Marco C — Tipos C Explícitos e Código Nativo `@nativo` sem Fallback Silencioso
- **Arquivos criados/modificados**: `src/frontend/semantic/native_validation.d` (novo), `src/backend/c/native_codegen.d` (novo), `src/frontend/type_sema.d`, `src/frontend/type_registry.d`, `src/frontend/semantic/declarations.d`, `src/frontend/semantic/foreign.d`, `src/backend/c/foreign.d`, `src/backend/c/codegen.d`.
- **Recursos entregues**:
  - **23 tipos escalares C**: `ci8`, `cu8`, `ci16`, `cu16`, `ci32`, `cu32`, `ci64`, `cu64`, `cchar`, `cschar`, `cuchar`, `cshort`, `cushort`, `cint`, `cuint`, `clong`, `culong`, `csize`, `cf32`, `cf64`, `cfloat`, `cdouble`, `cbool`, com casts explícitos tipados.
  - Emissão C99 direta (`static <c_type> cgd_nat_<id>(...)`) sem `delegua_value`, sem `delegua_op_*` e sem `GC_MALLOC`, validada contra Clang, GCC e TinyCC (zero GNU statement expressions).
  - Intrínsecos matemáticos diretos via `<math.h>` (`Matematica.raiz`/`raizQuadrada`, `seno`, `cosseno`, `absoluto`, `piso`, `teto`, `exponencial`, etc.).
  - Rejeição explícita de conversões implícitas inseguras (narrowing, troca de sinal, float→int: `E3604`), chamadas gerenciadas (`E3603`), tipos incompatíveis (`E3602`) e operações dinâmicas (`E3601`).

### Marco D — Classes por Valor na Pilha (`@pilha` / alias `@valor`)
- **Arquivos criados/modificados**: `src/frontend/semantic/value_types.d` (novo), `src/backend/c/native_codegen.d`, `src/backend/c/codegen.d`, `vendor/delegua-runtime/src/{delegua_rt.h,objetos.c}`.
- **Recursos entregues**:
  - `@pilha` (canônico) e `@valor` (alias compatível) compilados para `typedef struct cgd_val_<id>` C99 com layout estático plano, preferência por pilha e cópia por valor independente (inclusive ao atribuir ou passar argumentos em código gerenciado via `delegua_clonar`).
  - Construtor posicional automático quando `construtor` explícito não é declarado.
  - Inferência automática de `isTrivialCopy` vs `hasNonTrivialDrop`, com rejeição de herança/interfaces/abstratas (`E3701`), campos dinâmicos GC (`E3702`) e ciclos/recursão de layout (`E3703`).

### Marco E — Ownership, Empréstimos, Escapes, Lifetimes e RAII Inferidos
- **Arquivos criados/modificados**: `src/frontend/semantic/ownership.d` (novo), `src/backend/c/native_codegen.d`, `src/frontend/parser/ast.d`, `src/frontend/semantic/analyzer.d`.
- **Recursos entregues**:
  - Inferência automática de `ParamMode` (`ReadBorrow`, `MutBorrow`, `Consume`) sem anotações manuais de borrow/lifetime.
  - Análise sensível ao fluxo de controle (`se`/`senao` com reconhecimento de ramos terminais `alwaysTerminates`, `para`, `enquanto`, `fazer`, `para cada`, `escolha`, `tente`/`pegue`/`finalmente`, NLL — liberação automática de empréstimos de visões após último uso no bloco).
  - RAII determinístico em C99 com emissão de drops em retornos, `sustar`, `continua` e saídas de escopo, com zeragem pós-move para prevenir double-free.
  - Diagnósticos completos: `E3801` (use-after-move), `E3802` (use-after-free), `E3803` (cópia implícita proibida), `E3804` (retorno de visão pendurada), `E3805` (conflito de empréstimo/mutação em iteração/aliasing `f(v, v)`), `E3806` (escape inseguro de visão por escopo/struct/coleção), `E3807` (double-free em recursos nativos), `E3808` (uso sem inicialização explícita em `@nativo`), `E3809` (bounds/capacidade negativa constante).

### Marco F — Operadores Personalizados (`@operador`)
- **Arquivos criados/modificados**: `src/frontend/semantic/operators.d` (novo), `src/frontend/semantic/analyzer.d`, `src/middle/lowering.d`, `src/backend/c/native_codegen.d`, `src/backend/c/codegen.d`.
- **Recursos entregues**:
  - Suporte completo a todos os 16 operadores: `+`, `-`, `*`, `/`, `%`, `==`, `!=`, `<`, `<=`, `>`, `>=`, `[]`, `[]=`, `unario-`, `unario+`, `unario!`.
  - Funciona em `@pilha` (emissão C direta sem boxing) e em classes gerenciadas (com herança, sobrescrita e visibilidade).
  - Despacho comutativo seguro (`2.0 * v`, `10 + obj`) preservando ordem de avaliação esquerda→direita e avaliação única dos operandos.
  - Prioridade preservada para tipos primitivos; validações `E3901`–`E3906`.

### Marco G — Containers Nativos
- **Arquivos modificados**: `src/frontend/type_expr.d`, `src/frontend/parser/{parse_type,parse_expr}.d`, `src/frontend/type_resolver.d`, `src/frontend/semantic/static_safety.d`, `src/backend/c/native_codegen.d`, `src/backend/c/codegen.d`.
- **Recursos entregues**: 8 containers especializados em C99 (com checagem de limites e overflow): `VetorNativo<T>`, `MapaNativo<K, V>`, `FatiaNativa<T>`, `StringNativa`, `VisaoTexto`, `ResultadoNativo<T, E>`, `OpcionalNativo<T>`, `MatrizNativa<T>`, com suporte de ponte também no lado gerenciado (`paraVetor`, `paraTexto`, `paraDicionario`).

### Marco H — Fronteira Gerenciado ↔ Nativo e ABI
- **Recursos entregues**: `@pilha` como campo de classes gerenciadas, thunks automáticos `delegua_value ↔ tipos C / @pilha / containers nativos`, `delegua_instanciar_sem_construtor` no runtime, FFI C explícita acessível também de dentro de `@nativo` (`LibM.fmaC`, `LibC.absC`), e interoperabilidade transparente com bibliotecas padrão (ex.: `cgd.json`).

### Marco I — GPU, Tensores, Machine Learning e `@gpu`
- **Arquivos criados**:
  - `vendor/delegua-runtime/src/gpu_rt.c` (descoberta real de dispositivos Vulkan via `dlopen("libvulkan.so.1")` + backend nativo CPU C99, buffers alinhados fora do GC para `cf32`/`cf64`/`ci32`/`ci64`, kernels binários/unários/ativações/matmul/redução/produto escalar com medição monotônica em ns; compilado com `-std=c99 -Wall -Wextra -Werror -pedantic -Wconversion -Wshadow`).
  - `src/frontend/semantic/gpu_validation.d` (validação de kernels `@gpu`, código `E3951`).
  - `bibliotecas/computacao/gpu.delegua` (`cgd.computacao.gpu`), `bibliotecas/computacao/tensores.delegua` (`cgd.computacao.tensores`), `bibliotecas/computacao/ml.delegua` (`cgd.computacao.ml` com ativações `@nativo`, MSE/BCE/Softmax, SGD/Adam, `RegressaoLinear`, `RegressaoLogistica`, `Perceptron`, `MLP` com serialização/desserialização JSON).

### Marco J — Documentação Automática, LSP, DAP e Extensão VS Code
- **Gerador de Documentação (`src/driver/docgen.d`)**: `cgd documentar [--bibliotecas] [--formato markdown|html] [--saida dir] [--validar]` extrai declarações, `///`, anotações, contratos de memória e valida exemplos executáveis ````delegua```` (validados **40 módulos** em Markdown e HTML com **3/3 exemplos executáveis sem falhas**).
- **LSP (`src/lsp/{completion,server}.d`)**: completion de decoradores `@`, 23 tipos C, 8 containers nativos, `Compilacao.*`, membros de containers nativos após `.`, hover enriquecido com contratos de memória/ownership, Go to Definition de `a + b` → `@operador("+")`, Find References de `@operador("+")` → `a + b`, diagnósticos `E35xx`–`E3951` e respeito a `@quando`.
- **DAP (`src/dap/server.d` + `#line` em `native_codegen.d`/`codegen.d`)**: breakpoints exatos em funções `@nativo`, `stackTrace` legível (`calcularNativo [@nativo]`), inspeção de escalares C sem boxing, expansão de campos de structs `@pilha` e elementos de `VetorNativo`, tratamento honesto de `<optimized out>`.
- **Extensão VS Code**: `extensao-vscode/syntaxes/delegua.tmLanguage.json` e `extensao-vscode/snippets/delegua.json` atualizados sem nenhuma keyword proibida.

### Marco K — 5 Projetos de Exemplo, Testes Extremos e Regressão Total
- **5 Exemplos Grandes Criados e Validados**:
  1. `exemplos/nativo/algebra_vetorial/algebra_vetorial.delegua` (`Vetor2`, `Vetor3`, `Matriz3x3`, `Quaternion` com `@pilha` + `@operador` + `@nativo`).
  2. `exemplos/algoritmos/raytracer/fontes/nativo.delegua` (comparação diferencial contra `principal.delegua` e C99 manual).
  3. `exemplos/jogos/xadrez/fontes/perft_nativo.delegua` (variante nativa preservando engine principal; `perft(1..4) = 20, 400, 8902, 197281`).
  4. `exemplos/computacao/ml_demo/ml_demo.delegua` (Tensor matmul, Regressão Linear com Adam, MLP resolvendo XOR + serialização JSON).
  5. `exemplos/computacao/gpu_demo/gpu_demo.delegua` (descoberta real de 4 dispositivos CPU + Vulkan NVIDIA GTX 1650 / Intel Iris Xe / llvmpipe, buffers, operações, produto escalar e matmul).
- **Suítes Novas Criadas**:
  - `testes/prompt_mestre_x.py`: **314 casos independentes** (contabilizados 1 vez cada).
  - `testes/prompt_mestre_x_ide.py`: **15 casos independentes** (8 LSP + 4 DAP + 3 VS Code).
  - `testes/prompt_mestre_x_extremo.py`: Matriz ABI (Clang/GCC/TinyCC × `-O0`/`-o`), ASan+UBSan (5 cargas incluindo 1.500 ciclos de RAII), oráculo diferencial aleatório (1.100 ops) e fuzzing sintático/semântico (250 programas).

---

## 3. Evidências Quantitativas Reais

### 3.1 Contagem de Testes Novos Independentes

| Área | Meta Mínima | Aprovados / Total |
| :--- | :---: | :---: |
| 1. CTFE e Compilação Condicional | 45 | **46 / 46** |
| 2. `@nativo` e Tipos C | 45 | **46 / 46** |
| 3. `@pilha` / `@valor` e Cópia por Valor | 45 | **46 / 46** |
| 4. Ownership, Escapes e Lifetimes Inferidos | 60 | **62 / 62** |
| 5. Operadores Personalizados (`@operador`) | 45 | **46 / 46** |
| 6. Containers Nativos | 25 | **28 / 28** |
| 7. Interoperabilidade e ABI | 20 | **22 / 22** |
| 8. GPU, Tensores, ML, `@gpu` e `cgd documentar` | 15 | **18 / 18** |
| 9. IDE (LSP + DAP + VS Code) | — | **15 / 15** |
| **Total de casos independentes novos** | **300+** | **329 / 329 (100%)** |

### 3.2 Benchmarks Reais Medidos (Linux x86_64, `-o` / `-O2`)

| Carga | Resultado / Correção | Tempo Medido | Razão vs Baseline |
| :--- | :--- | :---: | :---: |
| Ray Tracer Gerenciado (`principal.delegua`) | `pixels=14400 acertos=6522 checksum=17445089` | **36–37 ms** | 1,0× (baseline) |
| Ray Tracer `@nativo` + `@pilha` + `@operador` (Clang `-o`) | `pixels=14400 acertos=6522 checksum=17445089` | **0,400–0,419 ms** | **~90× mais rápido** |
| Ray Tracer `@nativo` (GCC `-o`) | `pixels=14400 acertos=6522 checksum=17445089` | **0,390 ms** | **~92× mais rápido** |
| Ray Tracer C99 Manual (`clang -O2`) | `pixels=14400 acertos=6522 checksum=17445089` | **0,395–0,447 ms** | **Paridade ~1,0× com C99** |
| Xadrez `perft_nativo.delegua` (`perft(1..4)`) | `20 / 400 / 8902 / 197281` | **8,41–8,85 ms** (`perft(4)`) | 0 boxing/GC em 8 funções `cgd_nat_` |
| Auditoria de C gerado (`raytracer_nativo`, `perft_nativo`, `algebra_vetorial`) | 34 funções `cgd_nat_` inspecionadas | — | **0 ocorrências** de `delegua_value`, `delegua_op_*` ou `GC_MALLOC` |

### 3.3 Validação Extrema e Regressões Executadas

- **Matriz ABI (`testes/prompt_mestre_x_extremo.py`)**: `clang -O0`, `clang -o`, `gcc -O0`, `gcc -o`, `tcc -O0` produziram saída idêntica (`ABI_RES=891189`); Ray Tracer Clang vs GCC idêntico.
- **ASan + UBSan**: `stress_raii` (1.500 ciclos RAII), `raytracer nativo`, `xadrez perft nativo`, `algebra vetorial` e `gpu_demo` executados com `-fsanitize=address,undefined` — **0 erros de memória, 0 UAF, 0 OOB, 0 UB**.
- **TSan**: `testes/assincronismo.py` — pool isolado aprovado em ThreadSanitizer + núcleo async/rotinas em Clang, GCC e ASan/UBSan.
- **Oráculo Diferencial Aleatório**: **1.100 operações aleatórias** sobre `VetorNativo<ci64>` e `MapaNativo<ci32, ci64>` idênticas ao oráculo Python (`ORACULO=61707`).
- **Fuzzing Sintático/Semântico**: **250 programas aleatórios** em 0,58s — **0 crashes/segfaults/ICE** (63 válidos, 187 rejeitados com diagnósticos limpos).
- **Runtime C**: `(cd vendor/delegua-runtime && ./tests/run.sh)` — 100% aprovado (`libdelegua_rt.o`, `gpu_rt.c` sob `-Werror -pedantic -Wconversion -Wshadow`).
- **Unittests D e Builds**: `dub test --compiler=dmd --config=unittest` (10/10), `dub test --compiler=ldc2 --config=unittest` (10/10), `dub build --compiler=ldc2 --build=release` (OK).
- **Suítes de Regressão CGD (em LDC2 release)**:
  - `testes/driver.py`: 26/26
  - `testes/integracao.py`: 439/439
  - `testes/bibliotecas.py`: 342/342
  - `testes/stdlib.py`: 122/122
  - `testes/memoria.py`: 9/9
  - `testes/rotinas.py`: 15/15
  - `testes/assincronismo.py`: OK (Clang, GCC, ASan/UBSan, TSan)
  - `testes/lsp.py`: OK
  - `testes/dap.py`: 3/3 cenários OK
  - `testes/exemplos.py`: **158 exemplos, 324 verificações, 0 falhas, nenhum arquivo ignorado**
- **Regressão DCC (`/home/fernandodev/dcc`)**: compilado do zero com o novo `cgd` (LDC2 release); `verify.sh` smoke fora da árvore `DCC-OK`, **`86/86` verificações C99/ABI/linker vs GCC+Clang aprovadas** e `test_unidades` aprovado. (Observação: `tests/test_examples.py::test_programas` possui 4 arquivos extras pré-existentes no repositório do DCC fora da lista `CASOS`, não relacionado ao CGD.)

---

## 4. Bugs Reais Encontrados e Corrigidos Durante a Validação

1. **Ordem de protótipos `_box`/`_unbox`/`_drop` para containers de `@pilha`** (`src/backend/c/native_codegen.d`): protótipos movidos para `typeDecls` logo após o `typedef struct`, corrigindo compilação de `VetorNativo<Esfera>` e `VetorNativo<LanceNativo>`.
2. **Chamadas a funções `@nativo` retornando containers nativos** (`src/backend/c/native_codegen.d`): `compileNativeCall` capturava chamadas como `criarTabuleiroInicial()` como construtor de container por não checar `id.functionRef is null`.
3. **Loop infinito com `continua` em `para (...)` nativo + vazamento RAII em `sustar`/`continua`** (`src/backend/c/native_codegen.d`): adicionada pilha `LoopContext` com rótulo `continueLabel` antes de `stepStr` e emissão determinística de drops do corpo do loop antes de `break`/`goto`.
4. **Warnings `-Wparentheses-equality` no Clang** (`src/backend/c/native_codegen.d`): condição normalizada com `if (!!(...))`, zerando warnings em todos os exemplos.
5. **Validação de exemplos em `cgd documentar --validar`** (`src/driver/docgen.d`): arquivo temporário gravado em disco com limpeza `scope(exit)` antes de invocar `ModuleLoader.load`.
6. **Tipos C `cchar`, `cschar`, `cuchar` e `Matematica.raizQuadrada`** (`type_sema.d`, `type_registry.d`, `declarations.d`, `foreign.d`, `native_validation.d`, `native_codegen.d`, `codegen.d`, `lsp/completion.d`, `delegua.tmLanguage.json`): cobertura completa dos tipos char da ABI C e alias matemático.
7. **Sobrescrita de `@operador` em herança e validação de aridade de `+` unário** (`src/frontend/semantic/operators.d`): `findClassOperators` agora respeita overrides por assinatura na cadeia de herança e `normalizeOperatorSymbol` não converte `@operador("+")` com 0 argumentos em unário.
8. **`@operador("[]=")` em `@nativo`** (`src/frontend/semantic/native_validation.d`): `AssignStmt` com `resolvedIndexSetOperator` não é mais rejeitado como indexação de coleção gerenciada.
9. **Refinamentos de ownership (NLL, ramos terminais, escape em retorno de struct, `E3808` e `destruir()` legado)** (`src/frontend/semantic/ownership.d`, `src/frontend/parser/ast.d`, `src/frontend/semantic/analyzer.d`):
   - NLL (`expireDeadViewBorrows`) em blocos e corpos de loops;
   - `alwaysTerminates` em `analyzeIf` evitando contaminação de estado pós-`if` quando `then` sempre retorna;
   - `lackedExplicitInit` preservando defaults tipados gerenciados enquanto exige inicialização explícita (`E3808`) em `@nativo`;
   - detecção de `E3806` ao retornar struct `@pilha` contendo visão local;
   - preservação de `destruir()` idempotente para classes gerenciadas GC (`exemplos/linguagem/36_destrutores.delegua`).
10. **Cópia por valor de parâmetros `@pilha` e uso de containers nativos em código gerenciado** (`src/backend/c/codegen.d`): clonagem no prólogo de funções gerenciadas e mapeamento gerenciado de `VetorNativo`/`MapaNativo`/`StringNativa`.
11. **Precisão de `#line` para DAP/GDB dentro de `@nativo`** (`src/backend/c/native_codegen.d`, `src/backend/c/codegen.d`): emissão de `#line` em `compileNativeStmt` e reset `#line 1 "<cgd-runtime-init>"` antes de thunks e `delegua_main`, garantindo parada exata em `calcularNativo [@nativo]`.

---

## 5. Limitações Conhecidas e Fronteiras Explícitas

- **Execução GPU**: a descoberta real de dispositivos Vulkan (`libvulkan.so.1`) está operacional (identificando GPUs físicas como NVIDIA GTX 1650 / Intel Iris Xe além de llvmpipe), enquanto a execução de compute kernels atualmente despacha pelo backend nativo CPU C99 auditável (`EventGPU.fallbackCpu = verdadeiro`, zero silenciamento). O próximo passo natural é compilar kernels `@gpu` para SPIR-V e despachá-los em `VkQueue` quando o dispositivo selecionado for Vulkan.
- **Bibliotecas instaladas em `~/.delegua/cgd`**: se existir uma instalação prévia do CGD em `~/.delegua/cgd`, ela tem precedência sobre `./bibliotecas/` quando `CGD_LIBS_DIR` não está definida; executar `./instalar --no-build` sincroniza os novos módulos `cgd.computacao.{gpu,tensores,ml}` e `cgd.tempo` no diretório do usuário.
- **Plataforma validada**: Linux x86_64 (Clang, GCC, TinyCC). A simulação de alvos cruzados (`--target=x86_64-pc-windows-msvc`, `aarch64-apple-darwin`, `i686-unknown-linux-gnu`) foi validada via `--emitir-c`; compilação/linkagem nativa cruzada requer sysroot e runtime compilado para o alvo.
