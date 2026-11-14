# Arquitetura do CGD

O CGD gera um executável nativo a partir de uma unidade fonte Delégua e de seu
grafo de módulos. O frontend é escrito em D; o runtime e a saída intermediária
usam C99. DMD e LDC2 compilam o mesmo frontend.

## Passes

1. **Lexer** — valida UTF-8 e reconhece palavras-chave, operadores, literais, escapes e posições. Tabelas imutáveis são compartilhadas entre lexers.
2. **Parser** — produz a AST e recupera erros independentes por sincronização. Limita o aninhamento para evitar esgotar a pilha.
3. **Módulos** — resolve caminhos literais, canonicaliza, reutiliza unidades, impõe orçamento de loading e mostra cadeias de importação em ciclos.
4. **Validação estrutural** — percorre a AST iterativamente antes dos passes recursivos, limitando profundidade e quantidade de nós.
5. **Semântica** — registra símbolos, resolve tipos e herança, valida chamadas, retornos, constantes e escopos; bloqueia capturas. Identificadores mantêm a identidade da declaração resolvida.
6. **Segurança estática** — antecipa falhas locais provadas de operadores, contratos e índices antes do backend, preservando tratamento de exceções com avisos.
7. **Pureza e fluxo** — valida funções `//>puro` e emite avisos de código inalcançável/possível retorno implícito, independentemente de otimização.
8. **Otimização opcional** — passa até ponto fixo, contabilizando mudanças. Dobra literais, propaga constantes por identidade, simplifica ramos e preserva efeitos/exceções. A CTFE tem orçamento e fallback nativo.
9. **Lowering** — converte operações em chamadas explícitas do runtime.
10. **Backend C** — emite callbacks, descritores, classes, inicializadores de módulos e `delegua_main`. Nomes/textos C usam codificação direta em buffers reservados.
11. **Toolchain** — separa descoberta e argv do pipeline, configura alvo/sysroot/runtime e executa o compilador C sem shell.

`--verificar` encerra após a análise; `--emitir-c` encerra após a emissão. Nenhum
desses modos exige linker ou runtime instalado. A configuração de cross
compilation não equivale a suporte validado a Windows/macOS.

## Mapa do repositório

| Caminho                     | Responsabilidade                                |
| --------------------------- | ----------------------------------------------- |
| `src/frontend/lexer/`       | Tokens e posições                               |
| `src/frontend/parser/`      | AST, expressões, declarações e tipos            |
| `src/frontend/semantic/`    | Símbolos, escopos e análise semântica           |
| `src/frontend/modules.d`    | Grafo de importação de fontes                   |
| `src/ctfe/`                 | Análise de pureza, bytecode e VM de compilação  |
| `src/frontend/validation.d` | Limites estruturais antes da semântica          |
| `src/frontend/flow.d`       | Avisos de fluxo conservadores                   |
| `src/middle/rewrite.d`      | Reescrita de slots com cache por execução       |
| `src/driver/toolchain.d`    | Descoberta, argv e configuração de alvo         |
| `src/opt/`                  | Otimizações da AST                              |
| `src/middle/`               | Lowering                                        |
| `src/backend/c/`            | Emissão C99 e destinos de atribuição            |
| `src/driver/`               | CLI, arquivos, tempos e chamada ao compilador C |
| `src/errors.d`              | Diagnósticos com severidade e posição           |
| `vendor/delegua-runtime/`   | Runtime C e seus próprios testes                |
| `testes/unit/`              | Testes unitários de D                           |
| `testes/integracao.py`      | Semântica observável, erros e segurança         |
| `testes/exemplos.py`        | Validação de todo o catálogo de exemplos        |
| `scripts/validar.py`        | Matriz de compiladores e modos de build         |
| `docs/`                     | Documentação e website estático                 |

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

Os contratos detalhados de passes, códigos de diagnóstico e configuração da
toolchain estão em [Desenvolvimento](desenvolvimento.md). O guia web
[Delégua no CGD](linguagem.html) descreve a linguagem pelo ponto de vista do usuário.

Os pontos de erro do C usam descritores estáticos e escritas de ponteiro, sem
chamadas de localização por linha. O catálogo central também alimenta a referência
web e a opção `--explicar`. Veja os limites em Desenvolvimento.

## Análise persistente e formatação

`frontend/analysis.d` devolve AST, contexto, tokens e diagnósticos sem chamar o
driver de compilação nem executar CTFE. O LSP (`src/lsp/`) mantém documentos e
versões em memória, overlays de importações e dependências; consulta índices da
revisão analisada para hover, referências e completion. Uma edição invalida o
documento e os dependentes abertos. O protocolo usa stdio e posições UTF-16.

`frontend/formatter.d` preserva os lexemas de strings/comentários e organiza
espaçamento, blocos e listas com quatro espaços. Sua idempotência e preservação
dos contratos são verificadas sobre cópias de todo o catálogo. Não se deve usar
Prettier de JavaScript sobre fontes Delégua. Os metadados em `lsp/builtins.d`
precisam acompanhar a lista de métodos permitidos por tipo no runtime; campos
privados e membros sombreados não podem aparecer como membros públicos herdados.

As primitivas `cgdCurl*` usam assinaturas explícitas em `frontend/natives.d`;
arrays paralelos possuem contratos estáticos de comprimento/aridade. O runtime
possui handles opacos gerenciados, buffers com limites e callbacks internos.
Bibliotecas Delégua recebem esses valores sem acesso aos endereços C.
