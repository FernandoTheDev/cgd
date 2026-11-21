# Auditoria Técnica Profunda — Ciclo II (Prompt Mestre V)

**Data:** 21/11/2026  
**Revisões base analisadas:** CGD `9038032bfd35e4094e40d33eedc6a6e84b0302b3` / `vendor/delegua-runtime` `fdd0463bc6b9f4cf06f2ada1f7b9f37663314aea`  
**Alvos de validação reais:** DCC v0.1.0 (`out/dcc_v010`, commit `25f3609`) e DCC v0.2.0 (`out/dcc_v020`, commit `6116502`), sem alterações em `/home/fernandodev/dcc`.  
**Toolchain medido:** GCC `16.2.1`, Clang `22.1.8`, TinyCC `0.9.28rc` (`/usr/local/sbin/tcc`), LDC `1.42.0`, DMD `v2.111.0`, Linux `x86_64`.

---

## 1. Sumário Executivo

O Ciclo II realizou uma segunda auditoria completa sobre compilador D (`src/`), runtime C (`vendor/delegua-runtime/src/`), coletor de lixo (Boehm GC), bibliotecas padrão, interoperabilidade C99/TCC/DCC e sistema de validação.

Em relação ao estado Pós-Ciclo I, o Ciclo II entregou reduções substanciais adicionais sem perda de semântica:

- **DCC v0.1.0 (`hello_libc.c`)**:
  - Código C emitido caiu de `37.829` linhas (`4,26 MB`) para **`30.042` linhas (`3,45 MB` / `3.620.677 B`)** (**-20,6%** vs Pós-Ciclo I; **-46,8%** linhas e **-60,5%** bytes vs Pré-Ciclo I `56.479` linhas / `9,16 MB`).
  - Declarações `delegua_value cgd_tmp_*` caíram de `10.052` (e `29.751` no Pré-Ciclo I) para **`7.917`**.
  - Execução compilando `hello_libc.c`: de `682,0 ms` (Pós-Ciclo I GCC) / `1.549,3 ms` (Pré-Ciclo I GCC) para **`420,9 ms` (GCC `-O2`)** e **`362,3 ms` (Clang `-O2`)** (**3,68x** em GCC e **4,28x** em Clang sobre o baseline inicial).
- **DCC v0.2.0 (`hello_libc.c`)**:
  - Código C caiu de `51.617` linhas (`5.733.858 B`) para **`40.734` linhas (`4.900.245 B`)** (**-21,1%** linhas).
  - Execução compilando `hello_libc.c`: **`290,7 ms` (GCC `-O2`)** e **`266,7 ms` (Clang `-O2`)**.
- **Correção crítica descoberta durante a auditoria (`AUD2-01`)**: `delegua_descr_promessa` e `delegua_descr_tarefa` compartilhavam e mutavam o descritor cacheado de `delegua_descr_array` (`d->kind = 4/5`), corrompendo verificações posteriores de `T[]` após uso de `Promessa<T>` no código gerado (manifestado em `stdlib_avancada.py` no servidor HTTP assíncrono).
- **Portabilidade C99 / TinyCC (`AUD2-04`)**: O CGD agora compila e executa programas com `--cc=/usr/local/sbin/tcc` sem erros de ABI TLS, `SIZE_MAX`, `__builtin_*` ou inicializadores compostos.

---

## 2. Reprodução do Baseline e Diagnóstico Empírico

Antes das mudanças do Ciclo II, a dissecação do C gerado pelo estado Pós-Ciclo I em `dcc v0.1.0` (`37.829` linhas / `4.257.562 B`) e do perfil `gprof` em `hello_libc.c` mostrou cinco gargalos estruturais dominantes:

1. **Declarações temporárias remanescentes**: `10.052` linhas `delegua_value cgd_tmp_*` (`37,0%` do arquivo C gerado) vindas de argumentos constantes/literais em `nodesToStr`, expressões `==`/`!=`/`!`, mapeamentos `MapLit` com chaves literais e `ConditionalExpr`/`IfStmt`.
2. **Importação e código morto em módulos**: `cli.delegua` importava `cgd:arquivos`, cujas funções não utilizadas `lerJson`/`gravarJson` arrastavam todo o módulo `cgd:json` (`1.253` linhas e `34` funções mortas), além de `2.316` linhas em branco e `504` `return` finais mortos após `ReturnStmt`.
3. **Despacho dinâmico evitável**: `delegua_chamar_membro` (`2.044.470` chamadas no `gprof`) em classes/módulos conhecidos, chamadas via `delegua_builtin` (`inteiro`: `43`, `escreva`: `38`, `texto`: `35`, `tupla`: `13`, `tamanho`: `9`, `real`: `3`, `clonar`: `1`), construtores passando por `delegua_chamar`/`delegua_chamar_membro` e checagens dinâmicas `delegua_assegurar_descr`/`conforme` (`1.591.790` chamadas no `gprof`).
4. **Custo residual no runtime C**: `rt_utf8_next` (`678.187` chamadas), `delegua_vetor_validar_elemento` (`2.036.607` chamadas) passando por `conforme`, `rt_chamar_metodo_padrao` (`1.988.967` chamadas), `delegua_instancia_de` (`526.847` chamadas) recomputando descritores/hashes, e `delegua_iterar` (`122.161` chamadas).
5. **Incompatibilidades C99/TCC**: ABI TLS (`__thread` vs `-pthread`), uso sem guarda de `__builtin_expect`/`__builtin_*_overflow`, `SIZE_MAX` em macro de aridade e lvalues/compostos estritos.

---

## 3. Auditoria das 13 Otimizações do Ciclo I (Critérios da Seção 3)

Cada otimização introduzida no Ciclo I foi reexaminada em implementação concreta sob os 10 critérios (custo residual, caminhos lentos, semântica, fragilidade, corrida, GC/FFI, efeitos colaterais, impacto real, GCC vs Clang e arquitetura alternativa):

| #   | Otimização do Ciclo I                         | Diagnóstico no Ciclo II                                                                                                                                                                                 | Status e Ação                                                                                                                 |
| --- | --------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| 1   | Cache TLS de indexação UTF-8                  | Caminhos com salto longo, retorno parcial e prefixo ASCII longo ainda recomeçavam ou avançavam 1-a-1; não mantinha amostra intermediária nem retrocesso bidirecional.                                   | **Evoluída (`AUD2-02`)**: `first_non_ascii`, retomada SWAR 64-bit, `mid_sample` e cursor bidirecional em `textos.c`.          |
| 2   | Fast-paths de operadores primitivos           | Mantiveram semântica e overflow exatos em GCC/Clang (`__builtin_*_overflow`), mas quebravam TCC por falta de guarda de compilador.                                                                      | **Endurecida (`AUD2-04`)**: `DELEGUA_LIKELY`/`DELEGUA_UNLIKELY` e guarda GCC/Clang explícita.                                 |
| 3   | Redução inicial de temporários                | Ainda materializava literais/puros em `nodesToStr`, chaves literais de `MapLit` e subexpressões únicas de operadores infalíveis (`==`, `!=`, `!`).                                                      | **Expandida (`AUD2-07`)**: inlining seguro condicionado a `isPureConstantNode` + `canChangeLocalSite`.                        |
| 4   | Eliminação inicial de `checked`               | Ainda usava `TypeSema` com perda (`inteiro` vs `numero`) sem aproveitar retorno de builtins, `MemberExpr` de classe fechada e indexação tipada.                                                         | **Expandida (`AUD2-07`)**: `effectiveTypeExpr`, `nodeMatchesExactType` em `TypeExprNamed` + atalhos `delegua_assegurar_*_em`. |
| 5   | Eliminação de `delegua_is_truthy`             | `isGuaranteedBoolNode` cobria apenas comparações binárias diretas, deixando `IfStmt`/`WhileStmt`/`ConditionalExpr` com `!cond` ou chamadas booleanas retornarem `delegua_is_truthy`.                    | **Expandida (`AUD2-07`)**: `compileCondition` com unwrapping de `!` e propagação de retorno `logico`.                         |
| 6   | Chamadas diretas iniciais                     | Só cobria `Identifier` livre e `Classe.metodo()` estático simples; não cobria módulos importados via `const`/`importar(...)`, `ClassDecl` como construtor ou builtins 1-arg.                            | **Expandida (`AUD2-06`)**: `resolveDirectCallee`, `resolveDirectConstructor` e atalhos builtin 1-arg.                         |
| 7   | Despacho de métodos em objetos                | `delegua_chamar_membro` fazia várias buscas em hashmaps (acessores, restrições, métodos, propriedades) mesmo em classes fechadas sem acessores; `semear_campos` usava `delegua_iterar` alocando tuplas. | **Refatorada (`AUD2-03`)**: `c->nomes_campos` sem tuplas e fast-path de 1 lookup em classes fechadas.                         |
| 8   | Literais estáticos (`create_text_lit`)        | Sem alocação no heap GC e sem risco de lifetime (`const char *` estático em `.rodata`), mantendo `.len` exato mesmo com NUL embutido.                                                                   | **Aprovada e mantida** sem fragilidades.                                                                                      |
| 9   | Singletons de descritores (`delegua_descr_*`) | `c->descr_propria` não era cacheado por classe e **havia bug latente** caso `delegua_descr_promessa`/`tarefa` usassem o cache de `delegua_descr_array`.                                                 | **Corrigida e expandida (`AUD2-01`)**: cache atômico separado para classe, array, promessa e tarefa.                          |
| 10  | Buffers de argumentos na stack                | Mantido seguro via `(delegua_value[]){...}` no bloco lexical; em TCC exigiu evitar uso de array literal como lvalue inválido.                                                                           | **Aprovada** (C99 composto dentro de chamadas).                                                                               |
| 11  | Mutexes de FFI                                | Protegem `dlopen`/`dlsym`/cache sem corrida em rotinas/threads; sem impacto em programas sem FFI.                                                                                                       | **Aprovada e mantida**.                                                                                                       |
| 12  | Simplificação de constantes e opt             | `opt/pass_manager.d` com ponto fixo preserva efeitos observáveis; custo de otimização no DCC ficou em apenas ~54–59 ms (`--tempo`).                                                                     | **Aprovada e mantida**.                                                                                                       |
| 13  | Eliminação de `volatile` fora de `try`        | Reduziu `volatile` de 1.667 para 67 em `dcc_v010`; requer manutenção estrita do invariant de escopo em `containsTryStmt` e `AsyncLowering`.                                                             | **Aprovada** (`67` restantes apenas em funções com `tente`/`pegue` ou estado `assincrono`).                                   |

---

## 4. Auditoria Completa dos 36 Componentes do Ecossistema

| #   | Componente                    | Local Real                                        | Situação Atual                                                                            | Achados / Oportunidades Ciclo II & III                                                                                           |
| --- | ----------------------------- | ------------------------------------------------- | ----------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| 1   | Lexer e Unicode               | `src/frontend/lexer/`                             | Rápido (< 0,1 ms no DCC main); literais hex/bin/oct/científicos validados                 | Sem gargalo                                                                                                                      |
| 2   | Parser                        | `src/frontend/parser/`                            | Descendente recursivo limpo; preserva posições precisas (`delegua_local`)                 | `parse_stmt` / `parse_expr` estáveis                                                                                             |
| 3   | AST                           | `src/frontend/parser/ast.d`                       | AST única compartilhada entre frontend, opt, lowering e backend                           | Sem `auto`, `childNodes` centralizado                                                                                            |
| 4   | Sistema de módulos            | `src/frontend/modules.d`                          | Carregamento estático com detecção de ciclo (~69–106 ms no DCC)                           | **AUD2-05**: módulos inalcançáveis agora podados no codegen e vínculo nativo                                                     |
| 5   | Resolução de símbolos         | `src/frontend/semantic/`                          | `collectGlobals` corrigido (`AUD2-09`) para não retravessar `ModuleUnit`s                 | `importVisited` compartilhado reduziu varredura redundante                                                                       |
| 6   | Sistema de tipos              | `src/frontend/type_*.d`                           | Dual (`TypeSema` + `TypeExpr`); atenção contínua a `TypeSemaBase.Int == "numero"`         | `codegen.d` consulta `TypeExpr` exato para `inteiro` vs `numero`                                                                 |
| 7   | Inferência e contratos        | `src/frontend/semantic/`                          | Propagação de `classRef` em `const` (`AUD2-06`) e `static_safety.d` ativos                | Oportunidade Ciclo III: fluxo intraprocedural por bloco básico (unboxing)                                                        |
| 8   | Passes semânticos             | `src/frontend/semantic/`                          | ~176 ms no DCC v0.1.0, ~216 ms no v0.2.0 (`--tempo`)                                      | Bem dimensionado                                                                                                                 |
| 9   | CTFE                          | `src/ctfe/`                                       | `@puro` restrito e determinístico; regressões com literais expandidos                     | Validado em `expansao.py` com `-Werror`                                                                                          |
| 10  | Lowering AST                  | `src/middle/`                                     | Baixo custo (~2,6–3,4 ms no DCC); desaçucaramento limpo                                   | `async_ir.d` cobre suspensão completa                                                                                            |
| 11  | IR e Fluxo de controle        | `src/middle/async_ir.d`, `src/frontend/flow.d`    | SSA/CFG completo apenas em `assincrono`; pipeline principal ainda é AST->C                | Oportunidade Ciclo III: CFG + SSA leve pré-C para eliminar boxing em loops                                                       |
| 12  | Otimizadores                  | `src/opt/`                                        | Ponto fixo em ~53–59 ms no DCC (`pass_manager.d`, `dead_code.d`, etc.)                    | Poderia absorver propagação interprocedural de leitura/efeitos                                                                   |
| 13  | Geração de C                  | `src/backend/c/codegen.d`                         | ~249–408 ms no DCC; **AUD2-05/06/07/08** reduziram C gerado em ~21%                       | Maior alavanca futura: modularizar emissão C em múltiplas TUs (`GCC -O2` no DCC v0.1.0 leva 261s num único `.c` vs 11s no Clang) |
| 14  | Temporários                   | `src/backend/c/codegen.d`                         | `cgd_tmp_*` caiu para `7.917` (DCC v0.1.0) e `10.949` (v0.2.0)                            | Restante decorre da ordem de `delegua_local_atual` em subexpressões falíveis                                                     |
| 15  | Funções e chamadas            | `src/backend/c/codegen.d`, `objetos.c`            | `delegua_chamar_direto` (`528` em v0.1.0 / `609` em v0.2.0) e builtins 1-arg              | Convenção unificada `sz argc, delegua_value *argv` simplifica closures, mas força pack na stack                                  |
| 16  | Objetos                       | `vendor/delegua-runtime/src/objetos.c`            | `semear_campos` sem tuplas; acesso rápido em classes fechadas                             | Oportunidade Ciclo III: inline caching / índice fixo de campo em classes fechadas                                                |
| 17  | Classes, herança, interfaces  | `objetos.c`, `codegen.d`                          | `classesWithSubclasses` protege devirtualização semântica                                 | **AUD2-01** corrigido em descritores compostos                                                                                   |
| 18  | Enums / Generics / Structs    | `src/frontend/`, `objetos.c`                      | Enums numéricos CTFE zeram lookup em runtime; interfaces verificadas no boot              | Estável                                                                                                                          |
| 19  | Closures e funções como valor | `codegen.d`, `objetos.c`                          | Sem captura de mutáveis por segurança; `delegua_funcao_cache` em slot estático            | Seguro conforme contrato CGD                                                                                                     |
| 20  | Exceções e localizações       | `valores.c`, `delegua_rt.h`, `diagnostics/`       | Ponteiro estático `&cgd_source_sites[i]` + atalhos `*_em`; custo zero no caminho rápido   | Mantida precisão exata de linha/coluna                                                                                           |
| 21  | Corrotinas e async            | `async_codegen.d`, `assincrono*.c`                | Reactor epoll + keep-alive HTTP + tarefas; validado com ASan/UBSan/TSan                   | Bug `delegua_descr_promessa` corrigido (`AUD2-01`)                                                                               |
| 22  | Garbage Collector             | Boehm GC (`bdw-gc`)                               | ~1,0 GiB alocado total / 147 MiB heap máx (v0.1.0); ~561 MiB / 75 MiB (v0.2.0)            | ~18–32 ms totais de coleta; pressão vem de strings intermediárias e vetores/objetos curtos                                       |
| 23  | Memória e ABI de Valor        | `delegua_rt.h`                                    | Struct de 24 bytes por valor (`type` + padding + union `8B`/`16B`)                        | Ver Seção 6 abaixo                                                                                                               |
| 24  | Runtime C                     | `vendor/delegua-runtime/src/`                     | 26.060 linhas totais em C/H (incluindo `unicode_tables.h`)                                | Compila limpo com `-Wall -Wextra -Werror`                                                                                        |
| 25  | Strings e coleções            | `textos.c`, `colecoes.c`                          | Prefixo ASCII SWAR, cursor bidirecional UTF-8, hash máscara `2^k - 1`, cursor de iterador | Ganho expressivo em `array_ops` (-28% a -35%) e `dict_ops` (-22% a -35%)                                                         |
| 26  | Biblioteca padrão             | `bibliotecas/*.delegua`, `~/.delegua/cgd`         | Sincronizada e coberta por `stdlib.py`, `stdlib_avancada.py`, `bibliotecas.py`            | Tipos explícitos verificados por `verificar_tipos.py`                                                                            |
| 27  | `cgd:nativo` e FFI            | `src/backend/c/foreign.d`, `nativas.c`            | Pruned por alcançabilidade; `_exit` corrigido para protótipo POSIX (`AUD2-04`)            | Mutexes preservados                                                                                                              |
| 28  | Sistema de pacotes            | `pacotes` / carregamento local                    | Resolvido via `ModuleLoader`                                                              | Sem pendências críticas                                                                                                          |
| 29  | CLI, diagnósticos e LSP       | `src/cli.d`, `src/diagnostics/`, `src/lsp/`       | `--tempo`, `--emitir-c`, `--diagnosticos=json`, LSP com tokens semânticos                 | Coberto por `driver.py` e `lsp.py`                                                                                               |
| 30  | Formatador                    | `src/frontend/formatter.d`, `scripts/formatar.py` | Quatro espaços contratuais para Delégua; formatadores próprios por linguagem              | Validado em modo `--check`                                                                                                       |
| 31  | Testes                        | `testes/` (`unit`, `*.py`, runtime `run.sh`)      | 10 módulos unitários (DMD/LDC2) + 14 suítes Python + C runtime/sanitizadores              | Coberturas do Ciclo II adicionadas                                                                                               |
| 32  | Benchmarks                    | `scripts/benchmark_suite.py`                      | Expandido com `min/median/max`, DCC v0.1.0 + v0.2.0, `--tempo`, métricas C e GC           | Resultados em `out/bench_ciclo2_*.json`                                                                                          |
| 33  | Build                         | `build-runtime`, `dub.sdl`, `driver/toolchain.d`  | Argumentos sem shell; suporte validado para GCC, Clang e TinyCC                           | Reproduzível                                                                                                                     |
| 34  | Portabilidade                 | Linux x86_64 (`GCC`, `Clang`, `TCC`)              | Guardas de intrínsecos, TLS slot compatível com TCC e C99 estrito                         | Arquiteturas cruzadas preparadas via flags `--target`/`--sysroot`                                                                |
| 35  | Segurança                     | `static_safety.d`, `validation.d`, `objetos.c`    | Capturas bloqueadas, limites de recursão/AST, contratos de tipo em runtime/CTFE           | Preservação integral de ordem e efeitos (`v[i] = i++`)                                                                           |
| 36  | Documentação e continuidade   | `docs/*.md`, `docs/linguagem.json`                | Referência web + guias técnicos + `AUDITORIA_CICLO_II.md` + `PERFORMANCE_CICLO_II.md`     | `CONTINUIDADE.md` atualizado                                                                                                     |

---

## 5. Avaliação da Arquitetura da IR e Pipeline (Seção 4)

Hoje, o CGD possui duas infraestruturas separadas:

1. O pipeline principal: `AST -> Passes Semânticos -> opt/* (ponto fixo na AST) -> middle/lowering.d (AST) -> BackendC (emissão direta C99)`.
2. A IR especializada de corrotinas (`middle/async_ir.d`): blocos básicos e slots persistentes exclusivos para funções `assincrono`.

**Conclusão técnica:** A ausência de uma IR de três endereços com blocos básicos (CFG + SSA) no caminho síncrono principal é a razão estrutural pela qual:

- Toda subexpressão falível precisa atualizar `delegua_local_atual` antes de avaliar e materializar resultados em `delegua_value cgd_tmp_*`, dificultando a eliminação global de cópias de structs de 24 bytes;
- GCC `-O2` gasta **261,2 s** no arquivo monolítico `dcc_v010.c` (`30.042` linhas / `1.180` funções), enquanto Clang `-O2` compila o mesmo arquivo em **11,0 s** (~23,7x diferença), porque declarações repetidas e macros inline de `delegua_value` ampliam os passes intraprocedurais do GCC num único translation unit;
- Unboxing automático de variáveis locais `inteiro`/`real`/`logico` (transformando `delegua_value` 24B em `i64`/`double`/`bool` nativos em registradores quando a variável não escapa para coleções dinâmicas ou `qualquer`) exige análise de **liveness + escape + SSA** no frontend/middle-end antes da emissão C.

---

## 6. Análise de Representação de Valores (`delegua_value`) e Boehm GC (Seções 7 e 8)

### Layout atual vs alternativas

- `delegua_value` atualmente ocupa **24 bytes** (`enum delegua_type type` de 4 bytes + 4 bytes de padding + `union` de 16 bytes por causa de `struct { const char *ptr; sz len; } text`).
- Por ser > 16 bytes, pela ABI System V AMD64 (`x86_64`), **todo `delegua_value` passado em `(delegua_value[]){...}` vai para memória/stack** e todo retorno é copiado via ponteiro oculto (`sret`), impedindo passagem puramente em 1 ou 2 registradores para chamadas não-inlined!
- **Comparação arquitetural:**
  - _NaN-boxing (64 bits = 8 bytes)_ exigiria tags em ponteiros de 48 bits, conversão em todo acesso a texto literal com tamanho separado (`slice` precisaria alocar cabeçalho de 16 bytes no heap GC em vez de carregar `(ptr, len)` por valor) e perderia precisão/faixa de inteiros de 64 bits completos (`i64`) sem promoção automática para heap. Como o CGD garante `inteiro` de 64 bits com verificação de overflow e strings fatiáveis sem copiar bytes, NaN-boxing trocaria tempo de CPU aritmético por alocações no heap de strings.
  - _Caminho superior recomendado para o Ciclo III:_ **manter `delegua_value` de 24 bytes na fronteira dinâmica/FII**, porém emitir **variáveis e assinaturas C unboxed (`i64`, `double`, `bool`)** para funções/loops monomórficos onde tipos concretos (`inteiro`, `real`, `logico`) são provados e não escapam como `qualquer`.

### Perfil do Coletor Boehm GC (`GC_PRINT_STATS=1`)

Medição direta executando o DCC compilado sobre `examples/hello_libc.c`:

- **DCC v0.1.0**: `19` coletas (GCC) / `21` (Clang), `1.016,1 MB` (GCC) alocados cumulativamente, `881,5 MB` liberados, heap máximo `147.536 KiB` (~144 MiB), tempo total em GC completo = **`31,73 ms`** (~7,5% dos `420,9 ms` totais).
- **DCC v0.2.0**: `20` coletas, `560,8 MB` (GCC) alocados cumulativamente, heap máximo `75.284 KiB` (~73,5 MiB), tempo total em GC completo = **`18,71 ms`** (~6,4% dos `290,7 ms` totais).

**Interpretação:** O GC em si custa menos de 8% do tempo de execução, porém a taxa de alocação (~560 MB a ~1 GB para compilar um arquivo C simples!) revela que o maior ganho remanescente no runtime/codegen virá de reduzir alocações temporárias (concatenações curtas, `dicionario` de instâncias via slots indexados por índice de campo em classes fechadas, e `buscar_cstr` internado).

---

## 7. Catálogo Consolidado de Achados do Ciclo II (`AUD2-01` .. `AUD2-09`)

- **`AUD2-01` [Crítico — Runtime / `objetos.c`]**: Mutação acidental de cache compartilhado entre `delegua_descr_array` e `delegua_descr_promessa`/`delegua_descr_tarefa`. **Corrigido** com `promise_of_this`/`task_of_this` + `descr_unary_cached` e regressões em C e Delégua.
- **`AUD2-02` [Alto — Runtime / `textos.c`]**: Scans UTF-8 unidirecionais e re-varredura sem aproveitamento de prefixos ASCII. **Corrigido** com SWAR 64-bit, `first_non_ascii`, `mid_sample` e cursor bidirecional.
- **`AUD2-03` [Alto — Runtime / `colecoes.c`, `objetos.c`, `biblioteca.c`, `adicionais.c`]**: Tuplas com capacidade superdimensionada, hash double-lookup no rehash, `semear_campos` via `delegua_iterar`, múltiplos lookups em classes fechadas e despacho lento em métodos padrão/conversões. **Corrigido**.
- **`AUD2-04` [Médio — Portabilidade / `delegua_rt.h`, `valores.c`, `codegen.d`, `foreign.d`]**: Macros GCC-only e `SIZE_MAX` incompatíveis com TinyCC. **Corrigido** e validado com `cgd --cc=/usr/local/sbin/tcc`.
- **`AUD2-05` [Alto — Backend C & Driver / `codegen.d`, `compile.d`]**: Importação e emissão de módulos/funções/classes mortos (`cgd:json` via `arquivos.delegua`). **Corrigido** via `computeReachability` + poda de `nativeLibraries`.
- **`AUD2-06` [Alto — Backend C & Semântica / `codegen.d`, `analyzer.d`]**: Chamadas diretas restritas; ausência de atalho para módulos, construtores (`delegua_instanciar`) e builtins 1-arg (`delegua_para_texto`, `delegua_tamanho_val`, `delegua_conv_inteiro`, `delegua_conv_real`, `delegua_clonar`, `delegua_destruir`, `delegua_para_tupla`, `delegua_leia`). **Corrigido**, incluindo correção da dupla avaliação em builtins com side-effects (`leia`).
- **`AUD2-07` [Alto — Backend C / `codegen.d`]**: `cgd_tmp_*`, `checked` e `delegua_is_truthy` em expressões de fluxo, `MapLit`, `ConditionalExpr`, `nodesToStr` e `return` morto em funções. **Corrigido**.
- **`AUD2-08` [Alto — Segurança Semântica / `codegen.d`]**: Ordem de avaliação entre lado esquerdo indexado e mutação no RHS (`v[i] = i++`). **Corrigido** via `resolveLValue(node, rhs)` + regressão em `casos_linguagem.py`.
- **`AUD2-09` [Médio — Front-end & Utils / `routine_validation.d`, `utils.d`, `compile.d`]**: Retravessia quadrática em `collectGlobals`, recálculo de `cName`/`cString` e ausência de medição isolada de carregamento de módulos no `--tempo`. **Corrigido**.
