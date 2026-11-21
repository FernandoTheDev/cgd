# Auditoria Técnica Completa do CGD (Compilador Geral Delégua) e Runtime C

**Data da auditoria:** 21/11/2026  
**Versão inicial auditada:** CGD v0.9.0 (`commit 9038032`, submódulo `vendor/delegua-runtime` em `fdd0463`)  
**Plataforma validada:** Linux x86_64 (DMD / LDC2, Clang 22, GCC 16, Boehm GC)

---

## 1. Resumo Executivo e Estado Inicial

Esta auditoria inspecionou integralmente o compilador **CGD**, seu frontend, sistema de tipos, passes semânticos, CTFE, otimizador, lowering, gerador de código C99, runtime nativo em C (`vendor/delegua-runtime`), integração com o Boehm GC, FFI, biblioteca padrão (`bibliotecas/` e `~/.delegua/cgd`), ferramentas (formatador, diagnósticos, LSP) e suítes de testes.

Como estudo de caso principal para geração de código e desempenho em aplicações reais complexas, utilizamos o **DCC 0.1.0 (Delégua C Compiler)** — um compilador C99 completo escrito inteiramente em Delégua.

### 1.1 Medições Quantitativas de Baseline (DCC 0.1.0)

Compilando `src/main.delegua` do DCC 0.1.0 com o CGD v0.9.0 antes das otimizações:

| Métrica                                                 | Sem `-o` (`noopt`)         | Com `-o` (`opt`)           | Observação                                           |
| ------------------------------------------------------- | -------------------------- | -------------------------- | ---------------------------------------------------- |
| **Total de linhas C geradas**                           | 56.679 linhas              | 56.479 linhas              | `-o` reduziu apenas 200 linhas (0,35%)               |
| **Linhas não vazias**                                   | 54.813 linhas              | 54.613 linhas              | 96,7% de densidade                                   |
| **Tamanho total do arquivo C**                          | 9.227.338 bytes (8,80 MiB) | 9.155.945 bytes (8,73 MiB) | Média de 162 bytes/linha                             |
| **Bytes na Linha 3 (`cgd_source_sites[]`)**             | 3.720.114 bytes            | 3.713.928 bytes            | **40,6% de todo o arquivo C está em 1 única linha!** |
| **Declarações de variáveis do usuário**                 | 2.925 (`volatile`)         | 2.925 (`volatile`)         | Todas marcadas `volatile` + `(void)&var;`            |
| **Declarações de temporários (`cgd_tmp_*`, `t*`)**      | 29.914 linhas              | 29.751 linhas              | **52,7% de todas as linhas do arquivo C!**           |
| — Temporários copiando identificador (`tmp = var`)      | 12.238 linhas              | 12.169 linhas              | **21,5% de todas as linhas do arquivo C!**           |
| — Temporários copiando `isto` (`tmp = isto`)            | 3.328 linhas               | 3.328 linhas               | `isto` é imutável, mas copiado a cada acesso         |
| — Temporários copiando literal de texto                 | 2.035 linhas               | 2.027 linhas               | `tmp = create_text_len(...)`                         |
| — Temporários copiando `delegua_funcao_cache`           | 482 linhas                 | 482 linhas                 | Materializados apenas para `delegua_chamar`          |
| — Temporários de `delegua_propriedade_em`               | 8.412 linhas               | 8.390 linhas               | Leituras de campos e métodos                         |
| **Atribuições de localização (`delegua_local_atual=`)** | 24.482                     | 24.311                     | Presentes em cada subexpressão                       |
| **Verificações de contrato (`delegua_assegurar_*`)**    | 4.961                      | 4.961                      | Cada uma chama `delegua_descr_*` em runtime          |
| **Construtores de descritor (`delegua_descr_*`)**       | 5.828                      | 5.828                      | Cada chamada aloca `delegua_tipo` no GC!             |
| **Tempo de emissão C (`./cgd --emitir-c`)**             | 762,7 ms                   | 813,2 ms                   | Rápido no frontend/codegen D                         |
| **Tempo de compilação C (`gcc -O0`)**                   | 6.711,4 ms                 | —                          | 6,71 segundos                                        |
| **Tempo de compilação C (`gcc -O2`)**                   | —                          | **29.374,3 ms**            | **29,37 segundos!**                                  |
| **Tempo de compilação C (`clang -O2`)**                 | —                          | **12.125,9 ms**            | **12,13 segundos!**                                  |
| **Tamanho do binário ELF64 (`gcc -O2`)**                | 5.227.488 bytes (`-O0`)    | 4.137.808 bytes (`-O2`)    | ~4,14 MB                                             |
| **Tempo de execução DCC compilando `hello_libc.c`**     | —                          | **1.624,3 ms**             | Inclui pré-processamento dos headers da glibc        |

---

## 2. Mapeamento dos 36 Componentes Auditados

1. **Lexer (`src/frontend/lexer/lexer.d`, `token.d`, `keywords.d`)**: Decodifica UTF-8 previamente validado (`std.utf.validate`), mas `lexNumer` reconhece apenas inteiros decimais e reais simples (`0..9` e `.`), sem suporte a `0x`, `0b`, `0o`, separadores `_`, notação científica `e`/`E`, hex-float `0x1.fp+3` ou comentários de bloco `/* ... */`.
2. **Parser (`src/frontend/parser/parser.d`, `parse_decl.d`, `parse_stmt.d`, `parse_expr.d`, `parse_type.d`)**: Pratt parser para expressões e descendente recursivo para declarações/comandos, com proteção de profundidade (`nesting >= 256` → `E1003`) e sincronização de erros. Quando o usuário usa uma palavra reservada (como `e`, `ou`, `em`, `de`) onde um identificador é esperado (ex.: `pegue (e: Excecao)`), emite apenas `Esperado nome da exceção.` sem informar que `e` é palavra reservada.
3. **AST (`src/frontend/parser/ast.d`)**: Hierarquia limpa baseada em `Node` com `type_expr` (anotação sintática) e `type_sema` (tipo semântico resolvido). `frontend/validation.d` impõe limite de profundidade (512) e nós (500.000) iterativamente antes dos passes recursivos.
4. **Sistema de Módulos (`src/frontend/modules.d`)**: Carregamento estático com resolução canônica (`realpath`), detecção de ciclos (`E2001`), orçamento de 4 MiB/arquivo e 64 MiB/grafo (`E2002`), e resolução dinâmica segura de `cgd:<modulo>` em `~/.delegua/cgd` e `bibliotecas/` com bloqueio de path traversal (`E2003`).
5. **Resolução de Símbolos (`src/frontend/semantic/context.d`, `symbol.d`, `declarations.d`)**: Escopos léxicos aninhados com detecção de captura de variáveis externas (`W4001` + `E4001`) e sugestões por distância de Levenshtein (`H3001`).
6. **Sistema de Tipos (`src/frontend/type_expr.d`, `type_sema.d`, `type_registry.d`, `type_resolver.d`)**: Suporta `inteiro`/`numero`, `real`, `logico`, `texto`, `vazio`, `qualquer`, `funcao`, `dicionario`, `tupla`, vetores `T[]`, classes, interfaces, `Promessa<T>` e `Tarefa<T>`.
7. **Inferência e Validação de Tipos (`src/frontend/semantic/analyzer.d`)**: Infere tipos de literais, expressões binárias/unárias, ternário, indexação de vetores tipados, chamadas de funções/métodos e `aguardar`.
8. **Passes Semânticos (`src/frontend/semantic/pipeline.d`, `static_safety.d`, `flow.d`, `contracts.d`, `routine_validation.d`, `async_validation.d`, `purity.d`)**: Pipeline determinístico cobrindo declarações, tipos, regras async (`E3301`–`E3307`), isolamento de rotinas (`E3401`–`E3404`), segurança estática (`E3101`–`E3112` com degradação para `W31xx` dentro de `tente`/`pegue`), pureza CTFE e fluxo (`W3001`/`W3002`).
9. **CTFE (`src/ctfe/`)**: VM própria com orçamento de passos para dobrar chamadas a funções livres e métodos estáticos marcados com `@puro` ou `//>puro` quando invocadas com argumentos constantes sob `-o`.
10. **Lowering de AST (`src/middle/lowering.d`, `async_lower.d`)**: Converte operadores binários e unários em chamadas `CallExpr` (`runtimeCall = true`) para `delegua_op_*` e reduz funções `assincrona` para máquinas de estados stackless (`async_ir.d`).
11. **Representação Intermediária (`src/middle/async_ir.d`, `src/middle/rewrite.d`)**: Funções assíncronas possuem CFG explícito com análise de vivacidade e arestas excepcionais; funções síncronas fazem lowering diretamente sobre a AST validada usando `AstRewriter`.
12. **Otimizadores (`src/opt/pass_manager.d`, `constant_folding.d`, `dead_code.d`)**: Busca ponto fixo em até 8 iterações combinando propagação de constantes tipadas, constant folding, CTFE e eliminação de código morto/ramos constantes. Falta dobrar operadores bit a bit (`&`, `|`, `^`, `<<`, `>>`), divisão inteira (`\`) e potência (`**`), além de simplificações algébricas seguras.
13. **Geração de C (`src/backend/c/codegen.d`, `utils.d`, `lvalue.d`, `descriptors.d`)**: Principal foco de volume de código; analisado em profundidade nos itens `AUD-02` a `AUD-08`.
14. **Gerenciamento de Temporários (`src/backend/c/codegen.d`)**: `materialize()` cria variáveis `cgd_tmp_N` para quase todo nó não-literal escalar, gerando 29.751 linhas de temporários no DCC.
15. **Geração de Funções e Chamadas (`src/backend/c/codegen.d`, `vendor/delegua-runtime/src/objetos.c`)**: Todas as chamadas passam por `delegua_funcao_cache` + `delegua_chamar` indireto, e chamadas de método passam por `delegua_propriedade_em` + `ligar` (alocando struct `funcao` e array `args` no GC a cada chamada).
16. **Representação de Objetos e Valores (`vendor/delegua-runtime/src/delegua_rt.h`, `objetos.c`)**: Tagged union `delegua_value` de 16 bytes (tag + union de 8/16 bytes; 24 bytes alinhados em x86_64 porque `text` tem `ptr` + `len` = 16 bytes + 8 bytes de tag). Objetos usam `hashmap` para campos.
17. **Classes, Herança, Mixins e Interfaces (`src/frontend/semantic/contracts.d`, `vendor/delegua-runtime/src/objetos.c`)**: Suporte completo a herança simples, `mescla` (mixins), `implementa` (interfaces), visibilidade (`publico`/`protegido`/`privado`), campos estáticos tipados, acessores `obter`/`definir`, construtores e destrutores idempotentes.
18. **Enums, Tuplas e Dicionários**: Enums numéricos congelados com resolução em compilação (`member.enumValue`); tuplas imutáveis de 2 a 10 elementos; dicionários com hash FNV-1a e encadeamento separado.
19. **Closures e Capturas**: Excluídas por contrato de segurança (`W4001`/`E4001`); funções anônimas e arrows sem captura funcionam como callbacks de primeira classe.
20. **Exceções (`vendor/delegua-runtime/src/excecoes.c`)**: Implementadas via pilha TLS de `delegua_try_frame` (`setjmp`/`longjmp`) com preservação da origem do erro e execução garantida de `finalmente`.
21. **Corrotinas e Rotinas Paralelas (`src/middle/async_lower.d`, `vendor/delegua-runtime/src/assincrono*.c`, `rotinas_*.c`)**: Corrotinas stackless cooperativas em reactor `epoll` na thread principal + pool de worker threads isoladas para `rotina` (`Tarefa<T>`) com transferência por cópia profunda de escalares/textos e `Canal` com backpressure.
22. **Garbage Collector e Memória (`vendor/delegua-runtime/src/delegua_rt.c`, `interno.h`)**: Boehm-Demers-Weiser GC (`GC_INIT`, `GC_allow_register_threads`, `GC_MALLOC`, `GC_MALLOC_ATOMIC`). A maior pressão sobre o GC vem de alocações efêmeras evitáveis no próprio runtime (`create_text` em buscas de propriedades e literais, `delegua_descr_*` em checagens de tipo, `ligar` e `args` em chamadas de método).
23. **Biblioteca Padrão (`bibliotecas/*.delegua` e `~/.delegua/cgd/*.delegua`)**: 24 módulos cobrindo arquivos, caminhos, bytes, processos, textos, coleções, algoritmos, JSON, criptografia, compressão, rede, HTTP/servidor, sockets TCP/UDP/DNS, SQLite, tempo, matemática, estatística, CLI, log, ambiente, sistema, assíncrono e nativo.
24. **FFI (`src/frontend/semantic/foreign.d`, `src/backend/c/foreign.d`, `vendor/delegua-runtime/src/ffi.c`)**: Classes `@definicao` com ABI C escalar ou ABI gerenciada `delegua`, com verificação de byte nulo em strings passadas para C.

---

## 3. Catálogo Detalhado de Problemas Auditados

### `AUD-01` — Lexer: Expansão de Literais Numéricos e Comentários de Bloco

- **Identificador:** `AUD-01`
- **Componente afetado:** `src/frontend/lexer/lexer.d`, `src/frontend/formatter.d`, `src/diagnostics/catalog.d`
- **Severidade:** Alta (Evolução de linguagem e qualidade de diagnósticos)
- **Sintoma:** O lexer reconhece apenas inteiros decimais simples e números reais no formato `d+.d+`, rejeitando hexadecimal (`0xFF`), binário (`0b1010`), octal (`0o755`), separadores de dígitos (`1_000_000`), notação científica (`1.25e-8`, `6.022e23`), hex-floats (`0x1.fp+3`) e comentários de bloco `/* ... */`. Além disso, entradas inválidas como `0xGG` são partidas em `Int(0)` + `Identifier("xGG")`, gerando erro sintático confuso no parser em vez de erro léxico `E1005`.
- **Causa raiz:** `Lexer.lexNumer` em `src/frontend/lexer/lexer.d:109-127` foi implementado originalmente apenas com `while (isNumeric(peek()) || peek() == '.')`.
- **Evidência técnica:** Linhas 109–213 de `src/frontend/lexer/lexer.d`.
- **Teste para reprodução:** Compilar `const x = 0xFF` ou `const y = 1_000_000` ou `const z = 1.25e-8` falha no parser/lexer.
- **Impacto:** Impede escrita natural de máscaras de bits, permissões octais, constantes científicas e grandes números legíveis em compiladores/VMs como o DCC; diagnósticos imprecisos para literais malformados.
- **Solução proposta:** Implementar máquina de estados linear $O(n)$ no lexer suportando `0x`/`0X`, `0b`/`0B`, `0o`/`0O`, separadores `_` validados (apenas entre dígitos válidos da base, nunca no início, fim, adjacentes a `.`, prefixo ou expoente, nem duplicados `__`), notação científica `e`/`E` (`[+-]?[0-9]+`), literais hex-float `0x<hex>[.<hex>]p[+-]<dec>` e comentários `/* ... */`, além de rejeitar sufixos alfanuméricos colados a números com `E1005`.
- **Alternativas consideradas:** Tratar prefixos no parser (descartado: quebra a separação léxica e permite espaços entre `0` e `xFF`).
- **Riscos da mudança:** Garantir que chamadas de método após literal como `10.formatar()` ou `3.14.formatar()` continuem funcionando (verificando se após `.` vem identificador de método e não dígito).
- **Prioridade:** Alta (Etapa 3)
- **Estado da implementação:** Implementado e Validado
- **Resultado após correção:** Todos os formatos (`0x`, `0b`, `0o`, `_`, `e`/`E`, hex-float `0x...p...`, `/* ... */`) suportados no lexer e no formatador, com diagnósticos `E1005` exatos para `0x`, `0b102`, `0o89`, `1__000`, `100_`, `1e+`, `0xGG`.

---

### `AUD-02` — Codegen C: Emissão Massiva de Variáveis Temporárias Redundantes

- **Identificador:** `AUD-02`
- **Componente afetado:** `src/backend/c/codegen.d`
- **Severidade:** Crítica (Volume de código C e tempo de compilação C)
- **Sintoma:** 52,7% de todas as linhas do C gerado para o DCC 0.1.0 (29.751 de 56.479 linhas) são declarações `delegua_value cgd_tmp_N = ...;`, das quais 12.169 são cópias diretas de identificadores (`cgd_tmp_N = var;`, incluindo 3.328 cópias de `isto`), 2.027 são cópias de literais de string e 482 são cópias de `delegua_funcao_cache`.
- **Causa raiz:** `BackendC.materialize(Node node)` (linhas 243–253) cria uma variável temporária para todo nó exceto `IntLit`, `DoubleLit`, `BoolLit` e `NullLit`, sem verificar se o nó já produziu um temporário fresco, se é um valor imutável (`isto`, `const`, literal de texto, referência a função/classe), ou se nenhum irmão subsequente na mesma expressão pode alterar aquela variável local.
- **Evidência técnica:** Em `out/dcc_v010_opt.c`, 29.751 linhas batem com `^\s*delegua_value\s+(cgd_tmp_|t\d+|...)`.
- **Teste para reprodução:** `./cgd -o --emitir-c out/dcc_v010/src/main.delegua -s out/dcc_base_opt`.
- **Impacto:** Infla o arquivo C em dezenas de milhares de linhas e sobrecarrega o parser e os passes SSA/SRA do GCC e do Clang.
- **Solução proposta:**
  1. Não materializar novo temporário quando a expressão compilada já é um temporário fresco ou valor imutável (`StringLit`, `FunctionExpr`, `Identifier` de `isto`, `const`, função ou classe).
  2. Em listas de argumentos e expressões binárias/indexação/membros, analisar com função estática `canMutateVar(Node subtree, dstring varName)` se algum irmão avaliado posteriormente pode modificar a variável local; caso não possa (o que ocorre em >99% dos casos, já que Delégua não tem closures nem aliasing de locais por ponteiro), usar o identificador C diretamente sem criar `cgd_tmp`.
  3. Em `VarDecl`, atribuir diretamente à variável declarada sem criar um `cgd_tmp` intermediário antes de `checked(...)`.
- **Alternativas consideradas:** Substituição textual pós-codegen (descartada: proibida pelos requisitos e arriscada para ordem de avaliação).
- **Riscos da mudança:** Expressões com efeitos colaterais como `escreva(i, i++)` ou `a[i++] = i` onde um irmão posterior modifica `i`: `canMutateVar` detecta qualquer `AssignStmt` ou `UnaryExpr(++ / --)` sobre `i` nos irmãos seguintes e força o snapshot temporário de `i`, preservando 100% da ordem de avaliação!
- **Prioridade:** Crítica (Etapa 5/6)
- **Estado da implementação:** Implementado e Validado
- **Resultado após correção:** Temporários no DCC reduzidos de **29.751 para 10.877 (-63,4%)**, cópias `cgd_tmp = var` reduzidas de **12.169 para 600 (-95,1%)**, cópias de `isto` reduzidas de **3.328 para 0 (-100,0%)**, e total de linhas C do DCC reduzido de **56.479 para 37.829 (-33,0% / -18.650 linhas)**.

---

### `AUD-03` — Codegen C: Explosão de Bytes em `cgd_source_sites[]`

- **Identificador:** `AUD-03`
- **Componente afetado:** `src/backend/c/codegen.d`
- **Severidade:** Crítica (Tamanho em bytes do C gerado e legibilidade)
- **Sintoma:** O arquivo C gerado para o DCC 0.1.0 tem 9,15 MB (9.155.945 bytes), sendo que **3,71 MB (40,6% do arquivo inteiro)** estão apenas na linha 3 (`cgd_source_sites[]`).
- **Causa raiz:** `location()` repete o literal completo do caminho do arquivo (`"/home/fernandodev/..."` codificado em octal por `cString`) dentro de cada uma das 19.767 structs de `cgd_source_sites[]`.
- **Evidência técnica:** `len(lines[2]) == 3713928` em `out/dcc_v010_opt.c` e `src/backend/c/codegen.d:687-712`.
- **Teste para reprodução:** Inspecionar linha 3 de `out/dcc_v010_opt.c`.
- **Impacto:** Aumenta o tamanho do código C emitido em ~3,43 MB apenas na tabela de localização, além de ~1,47 MB em temporários redundantes.
- **Solução proposta:** Em `location()`, deduplicar caminhos de arquivos em constantes estáticas `static const char cgd_file_N[] = ...;` e referenciá-las nos elementos `{cgd_file_N, line, col}` de `cgd_source_sites[]`, preservando `cString` e `cName` intactos em `src/backend/c/utils.d` para 100% de compatibilidade com os testes unitários existentes (`testes/unit/codegen.d`).
- **Alternativas consideradas:** Omitir `cgd_source_sites[]` com `-o` (descartado: perderia localização exata de erros de runtime em builds otimizados) ou alterar o formato de `cString`/`cName` (descartado: `testes/unit/codegen.d` valida o formato octal e hexadecimal de `utils.d`).
- **Riscos da mudança:** Zero risco semântico: o ponteiro `const char *arquivo` em `delegua_local` aponta para exatamente a mesma string C terminada em nulo.
- **Prioridade:** Crítica (Etapa 6)
- **Estado da implementação:** Implementado e Validado
- **Resultado após correção:** A tabela `cgd_source_sites[]` caiu de **3.713.928 bytes para 282.091 bytes (-92,4% / 13,2x menor)**, e o tamanho total do C gerado para o DCC caiu de **9.155.945 bytes (8,73 MiB) para 4.257.615 bytes (4,06 MiB) (-53,5% / -4,90 MB)**.

---

### `AUD-04` — Codegen C: Qualificador `volatile` em Variáveis Locais de Funções sem `setjmp`

- **Identificador:** `AUD-04`
- **Componente afetado:** `src/backend/c/codegen.d`
- **Severidade:** Crítica (Qualidade do C gerado e alocação em registradores pelo GCC/Clang)
- **Sintoma:** Todas as 1.667 declarações de variáveis locais e parâmetros no DCC são emitidas como `volatile delegua_value`, forçando escrita/leitura em memória stack em todas as funções síncronas.
- **Causa raiz:** Todas as variáveis locais e parâmetros são declarados como `volatile delegua_value` para satisfazer a regra de `setjmp` do C99, mesmo em funções que não possuem nenhum bloco `tente`/`pegue` (`TryStmt`).
- **Evidência técnica:** `src/backend/c/codegen.d:365, 372, 397, 851, 854`.
- **Teste para reprodução:** Compilar qualquer função com loop em `gcc -O2 -S` e observar spills/reloads forçados em cada acesso a variável local.
- **Impacto:** Impede alocação em registradores, SRA (Scalar Replacement of Aggregates), copy propagation e DCE pelo GCC/Clang.
- **Solução proposta:** Detectar por função síncrona se seu corpo contém `TryStmt` (`containsTryStmt(node)`). Emitir `volatile` e `(void)&var;` somente nas funções que efetivamente invocam `setjmp` (`TryStmt`), usando `delegua_value` e `(void)var;` nas demais.
- **Alternativas consideradas:** Remover `volatile` de todas as funções (descartado: causaria comportamento indefinido C99 quando uma variável local modificada dentro de `tente` é lida no `pegue`/`finalmente` após `longjmp`).
- **Riscos da mudança:** Funções sem `TryStmt` nunca chamam `setjmp`; se uma função interna lançar exceção, o `longjmp` salta diretamente para o frame da função ancestral que possui `TryStmt`, destruindo o frame da função sem `TryStmt` — portanto variáveis locais de funções sem `TryStmt` nunca são lidas após `longjmp`.
- **Prioridade:** Crítica (Etapa 6)
- **Estado da implementação:** Implementado e Validado
- **Resultado após correção:** Declarações `volatile delegua_value` no DCC caíram de **1.667 para 79 (-95,3%)**, permitindo alocação em registradores nas 250+ funções síncronas sem `TryStmt`.

---

### `AUD-05` — Runtime C e Codegen C: Alocação de `delegua_tipo` no GC a Cada Verificação de Tipo

- **Identificador:** `AUD-05`
- **Componente afetado:** `vendor/delegua-runtime/src/objetos.c`, `vendor/delegua-runtime/src/delegua_rt.h`, `src/backend/c/codegen.d`
- **Severidade:** Crítica (Pressão sobre o GC e overhead de chamadas/atribuições tipadas)
- **Sintoma:** Toda entrada de função tipada, declaração `var`, atribuição e `retorna` chama `delegua_assegurar_descr(v, delegua_descr_nome("..."))`. `delegua_descr_nome` chama `rt_alloc(1, sizeof(*d))` (`GC_MALLOC`), alocando milhões de structs `delegua_tipo` descartáveis no heap e executando cadeias de `strcmp` em `delegua_tipo_compativel`.
- **Causa raiz:** `delegua_descr_nome` em `vendor/delegua-runtime/src/objetos.c:639` aloca dinamicamente um novo `delegua_tipo` a cada chamada em vez de retornar descritores estáticos para tipos primitivos, e o codegen C não possui fast-path inline nem elide a checagem quando o nó já tem tipo garantido.
- **Evidência técnica:** 5.828 chamadas `delegua_descr_*` e 4.961 chamadas `delegua_assegurar_descr` estáticas no código C do DCC.
- **Teste para reprodução:** Loop de $10^6$ iterações atribuindo a `var soma: inteiro` aloca $10^6$ structs `delegua_tipo` no Boehm GC.
- **Impacto:** Enorme pressão sobre o Boehm GC e lentidão em loops e chamadas de funções tipadas.
- **Solução proposta:**
  1. Em `objetos.c`, retornar singletons estáticos imutáveis com tag numérica pré-resolvida em `delegua_descr_nome` para todos os tipos primitivos (`inteiro`, `real`, `numero`, `texto`, `logico`, `dicionario`, `funcao`, `tupla`, `vazio`, `nulo`, `qualquer`, `Objeto`).
  2. Em `delegua_rt.h`, fornecer helpers `static inline` (`delegua_assegurar_inteiro`, `delegua_assegurar_real`, `delegua_assegurar_texto`, `delegua_assegurar_logico`, `delegua_assegurar_dicionario`, `delegua_assegurar_funcao`, `delegua_assegurar_vazio`) que verificam `v.type` inline em 1 instrução e só chamam `delegua_assegurar_descr` no caminho de erro.
  3. Em `BackendC.checked()`, elidir a verificação quando o nó já produz comprovadamente aquele tipo exato (ex.: `IntLit` para `inteiro`/`numero`, `DoubleLit` para `real`/`numero`, `StringLit` para `texto`, `BoolLit` para `logico`, `NullLit` para `vazio`) e usar os helpers `static inline` para tipos primitivos.
- **Alternativas consideradas:** Remover verificações de tipo em runtime com `-o` (descartado: violaria contratos dinâmicos quando um valor vem de `qualquer`, dicionário ou JSON).
- **Riscos da mudança:** Zero risco semântico: quando `v.type` não corresponde ao tipo esperado, o helper inline delega para `delegua_assegurar_descr`, produzindo exatamente o mesmo diagnóstico e mensagem de erro.
- **Prioridade:** Crítica (Etapa 6/7)
- **Estado da implementação:** Implementado e Validado
- **Resultado após correção:** Zero alocações de `delegua_tipo` no GC para tipos primitivos e verificação inline em 1 comparação de tag.

---

### `AUD-06` — Runtime C: Alocação de Literais de String, Indexação UTF-8 $O(N^2)$ e `fatiar`/`juntar` Quadráticos

- **Identificador:** `AUD-06`
- **Componente afetado:** `vendor/delegua-runtime/src/delegua_rt.h`, `textos.c`, `colecoes.c`, `biblioteca.c`, `src/backend/c/codegen.d`
- **Severidade:** Crítica (Desempenho de processamento de texto, lexers e pré-processadores como o DCC)
- **Sintoma:** O DCC leva 1.624 ms para compilar um único arquivo `hello_libc.c` porque o pré-processador e o lexer indexam e fatiam strings de dezenas de milhares de caracteres.
- **Causa raiz:**
  1. `StringLit` emite `create_text_len("...", len)`, que chama `GC_MALLOC_ATOMIC` + `memcpy` toda vez que um literal de string é avaliado (ex.: `se (ch == " " ou ch == "\t")` aloca 2 strings no GC a cada caractere!).
  2. `delegua_obter(texto, i)` chama `rt_text_count(texto)` (varrendo a string inteira desde o byte 0!) e depois `rt_text_offset(texto, i)` (varrendo do byte 0 até `i`!) e depois aloca 2 bytes no GC para retornar um caractere de 1 byte!
  3. `delegua_intervalo` (chamado por `texto.fatiar(a, b)` e `texto[a:b]`) executa um loop caractere por caractere chamando `delegua_obter(v, i)` e `create_text_concat(out, item)` ($O(N^2)$ tempo e alocações!), mesmo quando `stride == 1`!
  4. `juntar` em `biblioteca.c` (`vetor.juntar(sep)`) chama `create_text_concat` em loop, copiando a string acumulada a cada elemento ($O(N^2)$ bytes alocados!).
- **Evidência técnica:** `vendor/delegua-runtime/src/delegua_rt.h:194`, `textos.c:67-80`, `colecoes.c:233-239, 379-391`, `biblioteca.c:342-353`.
- **Teste para reprodução:** Executar `out/dcc_bin_gcc_o2 out/dcc_v010/examples/hello_libc.c -o out/hello_libc_test` (1.624,3 ms).
- **Impacto:** Complexidade $O(N^2)$ de tempo e memória em qualquer operação de varredura, fatiamento ou junção de strings.
- **Solução proposta:**
  1. Adicionar `create_text_lit(const char *ptr, sz len)` em `delegua_rt.h` referenciando diretamente o literal imutável em `.rodata` sem `GC_MALLOC_ATOMIC`, e tabela estática para strings de 0 e 1 byte em `create_text_len`.
  2. Em `textos.c`, adicionar cache TLS de 8 entradas com detecção word-at-a-time (64 bits) de strings ASCII puras e cursor `(last_char_idx, last_byte_offset)` para strings UTF-8 multibyte, reduzindo `rt_text_count` e `rt_text_offset` sequencial ou aleatório em ASCII para **$O(1)$** sem perder a validação e semântica de codepoints UTF-8.
  3. Em `colecoes.c` (`delegua_intervalo`), quando `v.type == DELEGUA_T_TEXT` e `stride == 1`, fatiar diretamente o intervalo contíguo de bytes `[rt_text_offset(v, a), rt_text_offset(v, b))` em uma única chamada `create_text_len`.
  4. Em `biblioteca.c` (`juntar` e `concatenar`), calcular o tamanho total e escrever em um único buffer `GC_MALLOC_ATOMIC` ($O(N)$ linear).
- **Alternativas consideradas:** Alterar indexação de `texto` para bytes em vez de codepoints UTF-8 (descartado: quebraria a semântica Unicode contratada da linguagem Delégua).
- **Riscos da mudança:** `value.text.ptr` é estritamente `const char *` (imutável e nunca liberado manualmente em todo o runtime, verificado por auditoria completa de `grep -rn "text\.ptr"`).
- **Prioridade:** Crítica (Etapa 7)
- **Estado da implementação:** Implementado e Validado
- **Resultado após correção:** O microbenchmark `string_unicode_preproc` caiu de **22.916,00 ms para 9,75 ms (`gcc -O2`) / 9,26 ms (`clang -O2`) (~2.350x–2.475x mais rápido!)**, e o tempo do DCC compilando `hello_libc.c` (com todos os headers reais da glibc) caiu de **1.549,3 ms para 682,0 ms (2,27x mais rápido)**.

---

### `AUD-07` — Runtime C e Codegen C: Overhead e Alocações em Acesso a Propriedades e Chamadas de Funções/Métodos

- **Identificador:** `AUD-07`
- **Componente afetado:** `vendor/delegua-runtime/src/objetos.c`, `colecoes.c`, `biblioteca.c`, `modulos.c`, `src/backend/c/codegen.d`
- **Severidade:** Alta (Desempenho de orientação a objetos e chamadas)
- **Sintoma:** Cada leitura ou escrita de atributo (`isto.campo`) aloca 2 strings no GC (`create_text(name)`) e faz até 6 buscas na hash table; cada chamada de método (`obj.metodo(a, b)`) aloca um objeto `funcao` (`ligar`) e um array `args` no GC; chamadas a funções livres/estáticas conhecidas passam por `delegua_funcao_cache` e despacho indireto.
- **Causa raiz:** `delegua_propriedade_em`, `delegua_objeto_obter`, `delegua_definir_em` e `delegua_objeto_setar` usam `create_text(name)` (que aloca no GC) e chamam `delegua_map_contem` seguido de `delegua_map_obter`; `CallExpr` de método faz `delegua_propriedade_em` separado de `delegua_chamar`.
- **Evidência técnica:** `vendor/delegua-runtime/src/objetos.c:68-131, 435-519`.
- **Teste para reprodução:** Benchmark de acesso a campos e chamadas de métodos de instância.
- **Impacto:** Milhões de alocações temporárias no GC durante execução de programas orientados a objetos (como AST/IR do DCC).
- **Solução proposta:**
  1. Usar chave `DELEGUA_T_TEXT` na stack (`text_key_stack`) com hash FNV-1a calculado uma única vez para consultas em `objetos.c`, `modulos.c` e `biblioteca.c`, e lookup único de ponteiro `entry *` no `hashmap`.
  2. Em `delegua_chamar`, usar buffer na stack `delegua_value stack_args[16]` para funções ligadas com `argc < 15`, eliminando `rt_alloc` por chamada.
  3. Criar `delegua_chamar_membro(receiver, name, caller, argc, argv)` no runtime C e emiti-lo no `BackendC` quando `CallExpr.fn` é `MemberExpr`, despachando métodos de instância, estáticos, de módulo e métodos nativos de tipos primitivos (`vetor`, `texto`, `dicionario`) sem alocar `funcao` ligada (`ligar`) no GC!
  4. Criar `delegua_chamar_direto(fn, argc, argv)` `static inline` em `delegua_rt.h` e emiti-lo para chamadas a funções livres e métodos estáticos resolvidos em compilação que não possuam envelope de decorador.
- **Alternativas consideradas:** Substituir `hashmap` de objetos por vtables/offsets fixos (descartado: objetos Delégua suportam mixins dinâmicos, reflexão de campos, clonagem e `respondeA` sobre `o->campos`).
- **Riscos da mudança:** Funções com envelope de decorador (`fn.decorators` com `d.envelope !is null`) substituem o `_slot` em runtime; portanto `delegua_chamar_direto` só deve ser emitido quando a função alvo não possui decoradores de envelope.
- **Prioridade:** Alta (Etapa 6/7)
- **Estado da implementação:** Implementado e Validado
- **Resultado após correção:** Eliminadas 100% das alocações de chave e de `ligar`/`args` (para `argc < 16`) em acessos a propriedades e chamadas de métodos; `oop_fields_methods` caiu de **688,24 ms para 103,21 ms (`gcc -O2`, 6,67x) / 96,71 ms (`clang -O2`, 7,12x)** e `fn_calls` caiu de **365,67 ms para 30,34 ms (`gcc -O2`, 12,05x) / 25,55 ms (`clang -O2`, 14,31x)**.

---

### `AUD-08` — Runtime C, Otimizador e Codegen C: Fast-paths Inline para Operadores e Dobras Constantes Faltantes

- **Identificador:** `AUD-08`
- **Componente afetado:** `vendor/delegua-runtime/src/delegua_rt.h`, `operadores.c`, `src/frontend/semantic/constants.d`, `src/opt/constant_folding.d`, `src/backend/c/codegen.d`
- **Severidade:** Alta (Desempenho numérico e qualidade do otimizador `-o`)
- **Sintoma:** Loops numéricos simples (`para (var i: inteiro = 0; i < 100000; i++) { soma += i }`) executam chamadas de função externas ao módulo C (`delegua_op_lt`, `delegua_is_truthy`, `delegua_op_add`) a cada operação; além disso, expressões constantes com `&`, `|`, `^`, `<<`, `>>`, `\` e `**` não são dobradas em tempo de compilação pelo `-o`.
- **Causa raiz:**
  1. `delegua_is_truthy` e os operadores `delegua_op_*` estão apenas em `operadores.c`, sem fast-path `static inline` em `delegua_rt.h`.
  2. `foldBinary` em `src/frontend/semantic/constants.d` só trata `+`, `-`, `*`, `/`, `%` e relacionais, ignorando `BITAnd`, `BITOr`, `BITXor`, `BITSL`, `BITSR`, `IntDiv` (`\`) e `Pow` (`**`).
  3. Condições já booleanas (`==`, `!=`, `<`, `<=`, `>`, `>=`, `!`, `em`, `contem`) ainda passavam por `delegua_is_truthy(...)` em vez de acessar `.value.b1` diretamente.
- **Evidência técnica:** `src/frontend/semantic/constants.d:125-162`, `src/backend/c/codegen.d:527-544`, `vendor/delegua-runtime/src/operadores.c`.
- **Teste para reprodução:** Microbenchmark `int_loop` (2.000.000 iterações) e inspeção de `1 << 4` com `-o --emitir-c`.
- **Impacto:** Impede que GCC/Clang façam inlining e mantenham variáveis inteiras/booleanas em registradores sem chamadas externas em loops quentes.
- **Solução proposta:**
  1. Adicionar fast-paths `static inline` em `delegua_rt.h` para `delegua_is_truthy` e para o caso `DELEGUA_T_NUM` nos operadores aritméticos, relacionais, igualdade e bit a bit (delegando para `delegua_op_*` em `operadores.c` para outros tipos ou erro).
  2. Expandir `foldBinary` em `constants.d` para dobrar `&`, `|`, `^`, `<<` (0..63), `>>` (0..63), `\` (divisão inteira sem overflow/zero) e `**` (potência inteira exata dentro de `long.min..long.max`), e adicionar identidades algébricas seguras para inteiros em `src/opt/constant_folding.d`.
  3. Emitir `(<expr>).value.b1` diretamente via `truthyExpr` quando a condição já é comprovadamente booleana (`isGuaranteedBoolNode`).
- **Alternativas consideradas:** Mudar representação de variáveis locais tipadas de `delegua_value` para `int64_t` cru (descartado: exigiria boxing/unboxing complexo em fronteiras de chamadas, exceções, `qualquer` e argumentos variádicos; com `delegua_value` não-`volatile` + fast-path `static inline`, o próprio GCC/Clang aplica SRA em `-O2` mantendo `type` e `value.num` em registradores!).
- **Riscos da mudança:** Preservar rigorosamente a verificação de overflow (`__builtin_add_overflow`, `__builtin_sub_overflow`, `__builtin_mul_overflow`) no fast-path inline para que overflows inteiros continuem disparando `delegua_panic("Overflow inteiro.")` com a localização `delegua_local_atual` exata.
- **Prioridade:** Alta (Etapa 5/6/7)
- **Estado da implementação:** Implementado e Validado
- **Resultado após correção:** `int_loop` caiu de **397,68 ms para 57,21 ms (`gcc -O2`, 6,95x) / 43,77 ms (`clang -O2`, 9,09x)** e chamadas a `delegua_is_truthy` no DCC caíram de **2.029 para 253 (-87,5%)**.

---

### `AUD-09` — Parser e Diagnósticos: Mensagem Clara para Palavras Reservadas Usadas como Identificador

- **Identificador:** `AUD-09`
- **Componente afetado:** `src/frontend/parser/parser.d`
- **Severidade:** Média (Experiência do desenvolvedor e diagnósticos)
- **Sintoma:** Ao escrever `pegue (e: Excecao)` ou `var e = 1` ou `funcao f(ou: inteiro)`, o parser emite apenas `error[E1001]: Esperado nome da exceção.` (ou `Esperado nome de variável.`), sem esclarecer que `e` / `ou` / `em` / `de` é uma palavra reservada de Delégua.
- **Causa raiz:** `Parser.consume(TokenKind.Identifier, message)` verifica `tk.kind == TokenKind.Identifier` e emite `message` sem distinguir quando `tk` é uma keyword (`tk.kind <= TokenKind.Of && tk.value.s.length`).
- **Evidência técnica:** `src/frontend/parser/parser.d:116-130` e erro observado em `/home/fernandodev/dcc/src/lexer/lexer.delegua:48`.
- **Teste para reprodução:** `./cgd --verificar` em `tente {} pegue (e: Excecao) {}`.
- **Impacto:** Confunde programadores acostumados a usar `e` para `exception`/`error` em outras linguagens.
- **Solução proposta:** Em `Parser.consume`, quando `kind == TokenKind.Identifier` e `tk.kind <= TokenKind.Of && tk.value.s.length`, anexar nota explicativa à mensagem: `format("%s ('%s' é uma palavra reservada em Delégua; escolha outro identificador)", message, tk.value.s)`.
- **Alternativas consideradas:** Permitir `e` como identificador em `pegue (e)` (descartado: tornaria expressões dentro do bloco `pegue` ambíguas entre a variável `e` e o operador lógico `e`).
- **Riscos da mudança:** Preservar a mensagem original como prefixo garante 100% de compatibilidade com todos os testes que verificam substring da mensagem de `E1001`.
- **Prioridade:** Média (Etapa 2/16)
- **Estado da implementação:** Implementado e Validado
- **Resultado após correção:** O diagnóstico agora informa explicitamente quando uma palavra reservada como `'e'` é usada no lugar de um identificador.

---

### `AUD-10` — Biblioteca Padrão (`~/.delegua/cgd`): Reimportação Dinâmica em Métodos Quentes de `Bytes` e Demais Módulos

- **Identificador:** `AUD-10`
- **Componente afetado:** `bibliotecas/bytes.delegua`, `bibliotecas/arquivos.delegua`, `bibliotecas/cripto.delegua`, `bibliotecas/compressao.delegua`, `bibliotecas/sqlite.delegua` (e cópias instaladas em `~/.delegua/cgd/`)
- **Severidade:** Alta (Desempenho da biblioteca padrão)
- **Sintoma:** Cada chamada a `Bytes.obter(i)`, `Bytes.definir(i, v)`, `Bytes.tamanho()`, `Bytes.fatiar(...)`, etc., executa `var nativo: qualquer = importar("cgd:nativo").Primitivas` e faz despacho dinâmico em `nativo`. No DCC (que emite binários ELF64 e objetos `.o` byte a byte usando `cgd:bytes`), isso multiplica o custo de manipulação de buffers binários.
- **Causa raiz:** `bytes.delegua` importa `cgd:nativo` dinamicamente dentro de cada método em vez de declarar sua ponte `@definicao(biblioteca = "cgd-runtime", abi = "delegua")` com métodos `estatico` (como `assincrono.delegua` faz) ou usar métodos estáticos em `Primitivas`. Além disso, em `nativo.delegua`, os métodos de `Primitivas` não estavam marcados com `estatico` na declaração (embora `parse_decl.d:299` force `method.isStatic = isStatic || node.isForeign`).
- **Evidência técnica:** `bibliotecas/bytes.delegua:11-94`, `bibliotecas/nativo.delegua:1-186`.
- **Teste para reprodução:** Benchmark de leitura/escrita de 100.000 bytes via `cgd:bytes`.
- **Impacto:** Overhead de ~5x em operações byte a byte de `cgd:bytes`.
- **Solução proposta:** Declarar `@definicao(biblioteca = "cgd-runtime", abi = "delegua", prefixo = "delegua_ffi_") classe estrangeira PrimitivasBytes` diretamente em `bibliotecas/bytes.delegua` (e equivalente em `cripto.delegua`, `compressao.delegua`, `sqlite.delegua`) e sincronizar `~/.delegua/cgd/`. Combinado com `AUD-07` (`delegua_chamar_direto` para métodos de classes estrangeiras), toda chamada a `PrimitivasBytes.bytesObter(isto._recurso, indice)` torna-se uma chamada C direta sem busca em hash table!
- **Alternativas consideradas:** Manter `importar("cgd:nativo").Primitivas` em cada método (descartado: gera código C extra e lookup de módulo).
- **Riscos da mudança:** Zero incompatibilidade de API pública (`Bytes`, `Cripto`, `Compressao`, `SQLite`, `BancoSQLite` e `cgd:nativo.Primitivas` mantêm 100% das suas classes e assinaturas públicas).
- **Prioridade:** Alta (Etapa 9)
- **Estado da implementação:** Implementado e Validado
- **Resultado após correção:** Operações em `cgd:bytes` compilam para chamadas diretas às primitivas `delegua_ffi_bytes*` sem resolução de módulo/hash table por chamada.

---

### `AUD-11` — Runtime C (FFI / Concorrência): Proteção por Mutex na Lista Global de Bibliotecas Dinâmicas (`ffi.c`)

- **Identificador:** `AUD-11`
- **Componente afetado:** `vendor/delegua-runtime/src/ffi.c`
- **Severidade:** Média (Segurança e thread-safety)
- **Sintoma:** A lista ligada global `static biblioteca *bibliotecas;` e as chamadas a `dlerror()` em `vendor/delegua-runtime/src/ffi.c` não utilizam mutex.
- **Causa raiz:** `ffi.c` foi escrito antes da introdução do pool de threads de rotinas.
- **Evidência técnica:** `vendor/delegua-runtime/src/ffi.c:7-47`.
- **Teste para reprodução:** Inspeção de concorrência em `ffi.c`.
- **Impacto:** Potencial condição de corrida caso primitivas C internas usem `delegua_dlopen`/`delegua_close` concorrentemente.
- **Solução proposta:** Proteger `delegua_dlopen`, `delegua_dlsym_invoke` e `delegua_close` em `ffi.c` com `static pthread_mutex_t ffi_mutex = PTHREAD_MUTEX_INITIALIZER;` (bloqueando o mutex durante manipulação da lista `bibliotecas` e chamadas `dlopen`/`dlsym`/`dlclose`/`dlerror`, liberando-o antes de invocar a função nativa `fn` para permitir chamadas FFI reentrantes).
- **Alternativas consideradas:** Manter sem lock confiando apenas em `E3402` (descartado: defesa em profundidade no runtime é superior).
- **Riscos da mudança:** Destravar o mutex antes de `return fn(...)` evita qualquer deadlock se a função chamada abrir outra biblioteca.
- **Prioridade:** Média (Etapa 8)
- **Estado da implementação:** Implementado e Validado
- **Resultado após correção:** Tabela de bibliotecas FFI e `dlerror()` protegidos por `pthread_mutex_t` sem segurar o lock durante a execução da função externa.
