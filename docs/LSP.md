# Servidor de Linguagem (LSP) do CGD

O CGD inclui um servidor LSP persistente (`cgd --lsp`), escrito em D (`src/lsp/`), integrado diretamente ao frontend semântico real do compilador — sem compilar ou linkar C durante a edição.

## Capacidades suportadas

| Recurso LSP | Status | Observações |
| --- | --- | --- |
| `textDocument/publishDiagnostics` | Completo | Overlays em memória; revalida dependentes abertos quando um módulo importado muda |
| `textDocument/hover` | Completo | Assinaturas, tipos inferidos, classes entre módulos, pureza `@puro` e prévia CTFE |
| `textDocument/definition` | Completo | Local, cross-module, membros de classes e clique direto em nomes de módulos |
| `textDocument/declaration` | Completo | Resolvido sobre declarações locais, módulos importados e namespaces |
| `textDocument/typeDefinition` | Completo | Vai diretamente à `classe` do tipo de variáveis, parâmetros, campos e tipos qualificados |
| `textDocument/completion` | Completo | `cgd:...`, `importar a.b.c`, namespaces (`aplicativo.` → `modelos`), aliases (`Auth.`), membros de classe respeitando visibilidade/herança (sem poluir com globais após `.`) |
| `textDocument/signatureHelp` | Completo | Parâmetros ativos de funções locais, builtins e módulos importados |
| `textDocument/references` & `documentHighlight` | Completo | Indexação sob demanda de `projeto.json` (`fontes/`, `src/`, `testes/`) com deduplicação |
| `textDocument/rename` & `prepareRename` | Completo | Validação léxica e proteção contra sombreamento/colisão |
| `textDocument/documentSymbol` & `workspace/symbol` | Completo | Descoberta de símbolos em todo o projeto `projeto.json` |
| `textDocument/documentLink` | Completo | Links clicáveis tanto em `importar("...")` quanto em `importar a.b.c` |
| `textDocument/formatting` & `rangeFormatting` | Completo | Formatador oficial (4 espaços), preservando indentação de bloco no intervalo selecionado |
| `textDocument/semanticTokens/full` | Completo | Tokens semânticos UTF-16 fiéis ao lexer/análise |
| `textDocument/inlayHint` | Completo | Dicas virtuais de tipos inferidos (sem modificar o arquivo-fonte) |
| `textDocument/codeAction`, `codeLens`, `foldingRange`, `selectionRange` | Completo | Quick-fixes `H3001` e ações de execução/verificação |

## Projetos e desempenho

- O LSP descobre automaticamente `projeto.json` a partir do arquivo aberto ou de `rootUri`/`workspaceFolders`.
- Consultas como `hover` e `completion` reutilizam a análise em cache sem reanalisar o documento (`cgd/status`).
- A indexação de arquivos não abertos do projeto acontece sob demanda (em `workspace/symbol`, `references` e `rename`) com limite de segurança, evitando varreduras a cada tecla.

## Testes automatizados

- `testes/lsp.py`: protocolo stdio, UTF-16, overlays, cache, hover CTFE, rename, tokens semânticos e `cgd:` completion.
- `testes/lsp_projetos.py`: projetos `projeto.json`, módulos qualificados, `declaration`, `typeDefinition` cross-module, completion de namespaces/imports com digitação incompleta, `workspace/symbol`, `rangeFormatting` e resiliência a erro sintático.
