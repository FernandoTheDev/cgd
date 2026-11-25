# Especificação Arquitetural — Prompt Mestre X (Revisão Definitiva)

> **Diretriz central:** Evoluir a inteligência do compilador CGD sem poluir a sintaxe da Delégua. Zero novas palavras-chave reservadas; contratos explícitos via anotações (`@puro`, `@quando`, `@nativo`, `@pilha`, `@operador`, `@gpu`) e inferência estática de ownership, empréstimos, escapes e lifetimes.

## 1. Auditoria da Base Existente (Marco A)

### 1.1 Infraestrutura de CTFE
- **Análise de pureza (`src/frontend/semantic/purity.d`)**: valida funções livres e métodos estáticos marcados com `@puro` (ou `//>puro`, flag `CTFEFlags.Pure`). Rejeita envelopes de decorador, acesso a variáveis externas (`E3201`) e chamadas a funções não puras.
- **Compilador de bytecode CTFE (`src/ctfe/compile.d`, `src/ctfe/prepare.d`)**: traduz AST de funções puras em instruções `VMInstruction` (`LoadParam`, `Load`, `Store`, `Validate`, `Push`, `Jmp`, `Jz`, `Jnz`, aritmética, bitwise, comparação, `Call`, `Ret`, `Halt`, `Drop`).
- **Máquina Virtual (`src/ctfe/vm/cgd_vm.d`, `src/ctfe/context.d`)**: executa bytecode com tipos `Inteiro`, `Real`, `Logico`, `Texto`, proteção contra overflow (`core.checkedint`), divisão por zero, recursão máxima (`depth < 128`), orçamento de instruções (`10_000_000`), limite de slots ativos (`100_000`), pilha (`16_384`) e texto (`1 MiB`).
- **Otimizador (`src/opt/constant_folding.d`, `src/opt/dead_code.d`, `src/opt/pass_manager.d`)**: itera dobramento de constantes + avaliação `evaluatePureCall` + remoção de código morto até ponto fixo (máximo 8 iterações).
- **Lacunas identificadas**:
  1. Falta memoização/cache de chamadas puras em `CTFEContext`.
  2. Falta suporte em `PureFunctionAnalysis`/`CTFECompile`/`cgd_vm` a operadores `e`, `ou`, `**`, ternário `?:`, laços `para`/`faca`, `sustar`/`continua`, `escolha`/`caso`, `const` literais externas de módulo e tabelas constantes (`ArrayLit` + indexação).
  3. Não existe API pura de inspeção do alvo (`Compilacao.*`) nem compilação condicional estrutural (`@quando(...)`) executada antes do carregamento de módulos e da análise semântica.

### 1.2 Sistema de Anotações e Parser
- `parseDecorators()` (`src/frontend/parser/parser.d`) aceita `@nome` e `@nome(chave = expr, ...)`, armazenando `Decorator(name, keys, values, envelope)` em qualquer `Node` e `ClassField`.
- **Extensão compatível**: permitir argumentos posicionais em decoradores (`@quando(expr)`, `@operador("+")`) usando `key = ""d` quando o argumento não segue a forma `ident = expr`, mantendo 100% de retrocompatibilidade com `@definicao(...)`, `@puro` e decoradores do usuário.

### 1.3 Sistema de Tipos e Backend C
- `TypeExpr` (`Named`, `Array`, `Tuple`, `Promise`, `Task`) e `TypeSema` (`Builtin`, `Array`, `Tuple`, `Class`, `Promise`, `Task`) já suportam tipos parametrizados (`Promessa<T>`, `Tarefa<T>`) e tipos qualificados por módulo.
- `BackendC` (`src/backend/c/codegen.d`) emite C99 sobre `delegua_value`, já possui análise de alcançabilidade interprocedimental (`computeReachability`), despacho direto (`delegua_chamar_direto`), inline caching (`cgd_ic[]`) e elisão de temporários.
- `CToolchain` (`src/driver/toolchain.d`) já recebe `--target`, `--cc`, `--sysroot`, `--cflag`, `--ldflag` e invoca o compilador C por `argv` sem shell.

---

## 2. Contrato das Anotações (Zero Novas Keywords)

| Anotação | Alvo | Semântica |
| --- | --- | --- |
| `@puro` | Função livre / método estático | Elegível para avaliação em compilação (CTFE), independente de `@nativo`. |
| `@quando(expr)` | Função, classe, método, constante, `var`, `importar` | Inclusão condicional estrutural avaliada sobre `TargetInfo` antes do carregamento de módulos e da semântica. Código inativo não gera dependências de símbolos nem de linkagem. |
| `@nativo` | Função livre / método | Geração C99 direta em tipos primitivos C e structs `@pilha`, sem `delegua_value`, sem boxing e sem GC nas operações internas. Sem fallback silencioso. |
| `@pilha` (alias `@valor`) | `classe` | Tipo com semântica de valor e layout C `typedef struct`, sem alocação individual obrigatória no GC. Cópia independente para triviais; controle de ownership para não-triviais. |
| `@operador("op")` | Método de classe (`@pilha` ou gerenciada) | Define sobrecarga tipada para operadores `+`, `-`, `*`, `/`, `%`, `==`, `!=`, `<`, `<=`, `>`, `>=`, `[]`, `[]=`, `unario-`, `unario+`, `unario!`. |
| `@gpu` | Função numérica | Marca kernel verificável em subconjunto numérico para execução via `cgd.computacao.gpu` (CPU ou Vulkan compute). |

---

## 3. Catálogo de Códigos de Diagnóstico Novos

- **CTFE e Compilação Condicional (`E35xx`)**:
  - `E3501`: Condição de `@quando(...)` não é constante avaliável em tempo de compilação.
  - `E3502`: Argumento inválido em `@quando(...)` (exige exatamente 1 expressão lógica constante).
  - `E3503`: Consulta de compilação desconhecida ou inválida em `Compilacao.*`.
- **Código Nativo e Tipos C (`E36xx`)**:
  - `E3601`: Operação ou expressão incompatível com `@nativo` (sem fallback silencioso).
  - `E3602`: Tipo incompatível com região `@nativo` (ex.: `qualquer`, objeto gerenciado sem fronteira).
  - `E3603`: Chamada a função/método não-`@nativo` ou de runtime GC proibida dentro de `@nativo`.
  - `E3604`: Conversão implícita potencialmente insegura entre tipos C (perda de precisão/largura ou troca de sinal).
  - `E3605`: Anotação `@nativo` usada em alvo inválido (ex.: `assincrona`, envelope de decorador, classe abstrata).
- **Tipos de Valor `@pilha` (`E37xx`)**:
  - `E3701`: Classe `@pilha` incompatível com herança (`herda`), `abstrata`, `interface`, `mescla` ou `estrangeira`.
  - `E3702`: Campo de classe `@pilha` exige tipo concreto com layout estático conhecido.
  - `E3703`: Recursão infinita de layout detectada em tipo `@pilha`.
  - `E3704`: Acessor dinâmico ou campo `qualquer` não permitido em `@pilha`.
- **Ownership, Empréstimos e Lifetimes Inferidos (`E38xx`)**:
  - `E3801`: Uso de valor após transferência de ownership (use-after-move).
  - `E3802`: Uso de recurso nativo após liberação explícita (use-after-free).
  - `E3803`: Cópia implícita proibida de tipo proprietário não-trivial (use `.clonar()` quando disponível).
  - `E3804`: Retorno de visão ou referência pendurada (`VisaoTexto`/`FatiaNativa`) vinculada a recurso local.
  - `E3805`: Conflito de empréstimo mutável / aliasing ativo (ex.: mutação ou realocação com visão ativa).
  - `E3806`: Escape inseguro de recurso ou visão por closure ou campo gerenciado.
  - `E3807`: Liberação/destruição duplicada demonstrável (double-free).
  - `E3808`: Leitura de variável ou recurso nativo antes da inicialização completa.
  - `E3809`: Acesso fora dos limites ou overflow de capacidade demonstrável em container nativo.
- **Operadores Personalizados (`E39xx`)**:
  - `E3901`: Operador desconhecido ou não suportado em `@operador(...)`.
  - `E3902`: Assinatura/aridade inválida para o operador declarado.
  - `E3903`: Método `@operador` inacessível pela visibilidade no ponto de uso.
  - `E3904`: Definição duplicada ou resolução ambígua de operador personalizado.
  - `E3905`: Tipo de retorno inválido para operador relacional/igualdade (exige `logico`/`cbool`).
  - `E3906`: Operador personalizado incompatível com contexto `@nativo`.
- **GPU (`E395x`)**:
  - `E3951`: Recurso incompatível com kernel `@gpu`.

---

## 4. Modelo de Memória, Tipos e Interoperabilidade

### 4.1 Tipos C Primitivos
| Tipo Delégua | Tipo C99 | Categoria |
| --- | --- | --- |
| `ci8`, `ci16`, `ci32`, `ci64` | `int8_t`, `int16_t`, `int32_t`, `int64_t` | Inteiro fixo com sinal |
| `cu8`, `cu16`, `cu32`, `cu64` | `uint8_t`, `uint16_t`, `uint32_t`, `uint64_t` | Inteiro fixo sem sinal |
| `cshort`, `cint`, `clong` | `short`, `int`, `long` | Inteiro ABI com sinal |
| `cushort`, `cuint`, `culong`, `csize` | `unsigned short`, `unsigned int`, `unsigned long`, `size_t` | Inteiro ABI sem sinal |
| `cf32`, `cfloat` | `float` | Ponto flutuante 32 bits |
| `cf64`, `cdouble` | `double` | Ponto flutuante 64 bits |
| `cbool` | `bool` | Booleano C99 |

### 4.2 Classificação de Ownership Inferido
1. **`Copy` (Trivial)**: primitivos C, `inteiro`, `real`, `logico`, e classes `@pilha` cujos campos são todos `Copy` e que não declaram `destrutor()`.
2. **`Owned` (Proprietário / Não-trivial)**: `VetorNativo<T>`, `MapaNativo<K, V>`, `StringNativa`, `MatrizNativa<T>`, e classes `@pilha` com `destrutor()` ou com pelo menos um campo `Owned`. Possuem destruição determinística automática (RAII) no fim do escopo, respeitando transferências por retorno/atribuição/consumo.
3. **`BorrowedView` (Visão Emprestada)**: `FatiaNativa<T>`, `VisaoTexto`. Ligadas estaticamente ao dono de origem; impedem mutação/realocação/liberação do dono enquanto vivas e não podem escapar do escopo do dono.

### 4.3 Fronteira Gerenciado ↔ Nativo
- `@pilha` dentro de classe gerenciada: copiado por valor na leitura e escrita, sem compartilhar ponteiro mutável interno.
- Conversões explícitas de containers (`paraTexto()`, `paraVetor()`, `paraDicionario()`, `StringNativa.criar(...)`) com custo documentado.
- Funções `@nativo` expõem símbolo C direto (`cgd_nat_*`) para chamadores nativos e thunk gerenciado (`cgd_fn_*`) para chamadores Delégua comuns.
