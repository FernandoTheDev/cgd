# Arquitetura do CGD

O CGD gera um executável nativo a partir de uma unidade fonte Delégua e de seu
grafo de módulos. O frontend é escrito em D; o runtime e a saída intermediária
usam C99. DMD e LDC2 compilam o mesmo frontend.

## Passes

1. **Lexer** — reconhece palavras-chave, operadores, literais, escapes e posições.
2. **Parser** — produz nós de declarações, expressões, tipos, classes e controle de fluxo.
3. **Módulos** — resolve caminhos literais de `.delegua`, canonicaliza caminhos,
   reutiliza módulos e diagnostica ciclos antes da geração de código.
4. **Semântica** — registra símbolos, resolve tipos e herança, valida chamadas,
   retornos, constantes e escopos; bloqueia capturas de ambientes externos.
5. **CTFE e otimização** — com `-o`, propaga constantes adequadas e tenta executar
   funções `//>puro` em uma VM de compilação limitada. Limites de instruções ou
   recursão preservam a chamada para execução nativa.
6. **Lowering** — converte operações em chamadas explícitas do runtime e prepara
   a representação usada pelo backend.
7. **Backend C** — emite callbacks, descritores de tipos, valores de classes,
   inicializadores de módulos e o corpo de `delegua_main`.
8. **Driver** — grava o `.c` e chama Clang/GCC/TCC por vetor de argumentos,
   vinculando `libdelegua_rt.o`, Boehm GC e bibliotecas nativas necessárias.

## Mapa do repositório

| Caminho | Responsabilidade |
| --- | --- |
| `src/frontend/lexer/` | Tokens e posições |
| `src/frontend/parser/` | AST, expressões, declarações e tipos |
| `src/frontend/semantic/` | Símbolos, escopos e análise semântica |
| `src/frontend/modules.d` | Grafo de importação de fontes |
| `src/ctfe/` | Análise de pureza, bytecode e VM de compilação |
| `src/opt/` | Otimizações da AST |
| `src/middle/` | Lowering |
| `src/backend/c/` | Emissão C99 e destinos de atribuição |
| `src/driver/` | CLI, arquivos, tempos e chamada ao compilador C |
| `src/errors.d` | Diagnósticos com severidade e posição |
| `vendor/delegua-runtime/` | Runtime C e seus próprios testes |
| `testes/unit/` | Testes unitários de D |
| `testes/integracao.py` | Semântica observável, erros e segurança |
| `testes/exemplos.py` | Validação de todo o catálogo de exemplos |
| `scripts/validar.py` | Matriz de compiladores e modos de build |
| `docs/` | Documentação e website estático |

## ABI dos valores e chamadas

Um `delegua_value` contém uma etiqueta de tipo e os dados correspondentes.
Valores de texto, coleções, instâncias e funções referenciam memória gerenciada
pelo GC. A linguagem não permite fabricar etiquetas, ponteiros ou callbacks C.

Funções são callbacks com quantidade de argumentos e um vetor de valores. O
runtime verifica a faixa de aridade antes de chamar o callback. Parâmetros
padrão são avaliados no chamado, após os parâmetros anteriores. Parâmetros
variáveis recebem um vetor próprio. Métodos ligados guardam um receptor
explícito; não apontam para variáveis da pilha de uma função encerrada.

Nomes internos de funções e módulos são separados dos identificadores que o
programa pode declarar. Textos e caminhos são escapados na emissão C. Os
argumentos são materializados na ordem da fonte para preservar efeitos
colaterais, inclusive em chamadas aninhadas e índices modificáveis.

## Tipos e objetos

Descritores preservam a identidade das classes, inclusive quando duas classes
com o mesmo nome vêm de módulos distintos. Contratos estruturais de vetores e
tuplas validam seus elementos. Vetores tipados conservam restrições de escrita
através de aliases; um alias `qualquer` não remove uma restrição já instalada.

Classes possuem um estágio de criação das identidades e outro de registro dos
campos/métodos. Isso permite campos que referenciam classes declaradas depois.
Acessos privados/protegidos usam a classe lexical do método como identidade,
e não o nome textual da classe. Getters e setters executam callbacks validados.

## Exceções e limpeza

O runtime mantém frames de exceção gerenciados pelo GC. O C gerado usa `setjmp`
e `longjmp` com variáveis do programa preservadas conforme as regras de C.
`retorna`, `sustar` e `continua` emitem a limpeza dos frames que abandonam e os
blocos `finalmente` correspondentes. Uma exceção disparada por um `finalmente`
substitui a transferência de controle anterior.

O estado de recursão de chamadas também é restaurado ao tratar uma exceção.
Erros de operações do runtime tornam-se exceções `Excecao`, com a propriedade
`mensagem`. Sem tratador, o processo termina com status 1 e diagnóstico.

## Módulos e metadados

Cada módulo é compilado em seu próprio contexto de símbolos. Seu inicializador
é executado uma vez, expõe uma tabela de exportações e detecta reentrada. Se a
inicialização falhar, o estado permite uma nova tentativa posterior. A tabela
de exportações é protegida contra substituição; objetos exportados continuam
possuindo sua própria mutabilidade.

Decoradores de dados ficam registrados como metadados. Envelopes de funções
livres são aplicados na inicialização das funções do programa. Envelopes que
exigem capturar o parâmetro recebido em uma função interna são bloqueados pela
mesma regra de upvalues. A extensão `decoradores(valor)` consulta cópias dos
metadados de funções, classes e propriedades.
