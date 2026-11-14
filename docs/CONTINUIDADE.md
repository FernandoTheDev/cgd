# Continuidade: rede, JSON e ferramentas do editor

Solicitação ativa em 14/11/2026. Este arquivo deve ser atualizado durante a
implementação, antes de interromper trabalho ou concluir cada etapa. Pedidos
futuros também devem registrar objetivo, decisões, arquivos, testes, pendências
reais e próximo comando; não confiar apenas no histórico da conversa.

## Estado atual: formatação, tipos e contexto do editor

Implementado nesta continuação; runtime publicado e commit CGD preparado:

- Formatador nativo `frontend/formatter.d`, quatro espaços, comentários/strings
  preservados, mapas/desestruturações compactos, blocos/métodos separados e quebra
  conservadora de listas longas. Propriedades/métodos escritos juntos também são
  separados, com regressão idempotente de classe. CLI --formatar/--verificar-formatacao; LSP
  textDocument/formatting e Ctrl+Shift+I. O estilo é lexical; não inventa tipos.
- Removido `auto` de src e testes/unit. Tipos concretos também nos foreach e nos
  argumentos das lambdas D. `scripts/verificar_tipos.py` impede regressões.
- Bibliotecas Delégua com argumentos, retornos, variáveis e iterações explícitos.
  Exemplos receberam 343 anotações obtidas do frontend, mais ajustes manuais.
  Fixtures negativas mantêm construções necessárias ao diagnóstico; não remover
  tipos para passar testes. Dados JSON heterogêneos/handles opacos usam qualquer.
- Métodos estatico/estático no parser/AST/sema/codegen/runtime: sem isto, herdados,
  disponíveis por classe ou instância. Campos estáticos continuam sem suporte.
- JSON.analisar/serializar estáticos; instâncias JSON(valor) com valor/obter/
  definir/texto e encadeamento. Mantidas funções soltas por compatibilidade.
- Biblioteca Colecoes.unicos/intervalo; alias cgd:colecoes além de cgd:json/rede.
- Tipos explícitos em para cada, compreensões e desestruturação; contratos
  gerados para elementos. StaticSafety antecipa falhas provadas de campos e
  iterações; conserva avisos W31xx em regiões tratadas por pegue.
- FlowAnalysis reconhece término através de tente/pegue/finalmente. Não eliminar
  efeitos de finalmente. Regressões específicas em testes/unit/frontend.d.
- LSP: sugestões por receptor conhecido, campos/métodos com kinds distintos,
  herança, estáticos, privados ocultos externamente, encadeamento, namespaces,
  escopos locais, recuperação de ponto incompleto, parâmetros/índice ativo em
  signature help, incluindo construtores importados (JSON(...)). Buffers em
  memória e cache por revisão preservados.
- Assinaturas cgdNativeParameters/cgdNativeReturns descrevem argumentos e retornos
  reais das primitivas controladas; não exibir arg0 genérico quando há contrato.
- VSIX foi elevado a 0.2.0; instalador deriva versão do manifest. A instalação
  0.2.0 instalada e confirmada por code --list-extensions --show-versions.
- Referência web ampliada a 19 capítulos; docs/ferramentas.md explica APIs,
  arquitetura e limites. Layout e GitHub Pages dev/docs preservados.

### Validação já concluída no estado recente

- LDC2 debug: build, testes unitários (7 módulos) e testes LSP expandidos passaram.
- 107 exemplos, 214 verificações em ambos os modos, passaram após tipagem.
- Formatador: 110 cópias de fontes idempotentes; todos os contratos executados
  após formatação passaram. Não testar somente snapshots do layout.
- Bibliotecas: 342 verificações passaram; HTTP apenas em 127.0.0.1, ambos os modos.
- Verificação de tipos passou. Formatação geral e referência regeneradas.
- Fetch de origin/dev no CGD e runtime: nenhum commit remoto novo; branches dev.
  Pull --ff-only do runtime confirmou Already up to date antes do novo commit.

### Validação final e commits

- Matriz final: **39 etapas passaram**, DMD/LDC2 × debug/release × Clang/GCC,
  incluindo 407 verificações de integração e 214 de exemplos por combinação,
  LSP/bibliotecas/driver por build e instalações isoladas. out/validacao.json.
- Depois da matriz: refinamento restrito ao LSP (metadados de métodos nativos,
  cache limitado por família de receptor, vetor qualquer[] e recuperação de
  chamadas incompletas). LSP específico passou em DMD e LDC2 release; unittests
  finais passaram com ambos, **8 módulos**. Rodada focada app/CLI/LSP concluída em ambos,
  incluindo o acabamento da ajuda e erros de I/O do formatador; não repetir a
  matriz C sem mudanças de backend/runtime.
- Driver ampliado: **26 verificações**, incluindo CLI de formatação sem CC e erro
  de arquivo ausente centralizado em E9001.
- Sanitizadores passaram: API C, integração, todos os exemplos e 342 verificações
  de bibliotecas. ASan/UBSan, leak detection desativada conforme contrato Boehm GC;
  runtime normal restaurado. out/sanitizadores.json.
- Formatador final: 110 cópias idempotentes, contratos preservados (214 execuções).
- Website passou em Chrome desktop/mobile, busca, navegação e layout; 19 capítulos.
- Extension Host passou no VS Code real: hover/definition/completion/tokens/rename,
  formatting aplicado ao documento, diagnóstico, nenhuma compilação por edição e
  compilação explícita. O teste inicialmente pressupunha que o VS Code retornava
  o texto inteiro: ajustado para aplicar as edições normalizadas e verificar o
  documento resultante. out/vscode/extensao.json.
- VSIX **0.2.0 instalado** e associação \*.delegua → cgd confirmada. Pacote inclui
  binário release existente, runtime/headers e bibliotecas; não executa DUB na
  instalação nem no uso. Recarregar janela do VS Code para ativar a revisão nova.
- Runtime commit **a04e04d**, publicado em origin/dev; stashes originais preservados.
- CGD implementação commit **8b2436d**; correção de sombra privada herdada **a87b914**,
  também verificada no LSP com DMD/LDC2 release; documentação em 8df1fbe/ee94393.
  Acabamento posterior: assinaturas de construtores importados e diagnósticos
  centrais E3011/E3012 para campos estáticos ausentes/construtor estático.
- Artefatos executáveis não foram versionados. Na conferência final, 07_funcoes
  já havia sido enviado à lixeira (registro local de 19:24); essa mudança externa
  foi respeitada, sem restaurar/substituir o binário. Fontes e stashes preservados.

### Encerramento e publicação

Implementação, testes focados finais e instalação concluídos. Runtime e CGD
foram publicados em origin/dev. Pages confirmou o build da revisão de conteúdo
8df1fbe em dev/docs; o relatório desta publicação fica em out/pages.json. O
comando de publicação usado para a revisão final é
`python3 scripts/github_pages.py --publish` (fonte dev/docs). Seu resultado real
fica no relatório local em out; não criar outra hospedagem. Para futuras mudanças,
repetir os testes pertinentes e publicar a revisão enviada, mantendo este registro.

A API C normal também passou com GCC; o runtime Clang normal foi restaurado.
Tipos, formatação geral, referência gerada, Chrome e hash do binário instalado
foram conferidos. A cópia de 07_funcoes na lixeira não foi alterada.
Não há implementação pendente escondida: os limites abaixo são explícitos e o
depurador continua adiado por solicitação do usuário. Novos pedidos devem abrir
uma seção ativa aqui e registrar decisões/testes antes de encerrar a próxima etapa.

Limites intencionais: sem DAP, campos estáticos, indexação total do disco ou FFI
arbitrária. Suporte WebSocket depende da libcurl; ws/wss não existe neste ambiente.
Não alegar equivalência total com o interpretador ou formatação via AST completa.

## Objetivo e ordem

1. Expor libcurl por funções nativas próprias do CGD, sem FFI arbitrária, ponteiros
   ou callbacks C fornecidos pela linguagem. Construir a biblioteca de rede em
   Delégua sobre essas primitivas. Cobrir opções disponíveis que possuem
   representação segura e explicar as recusas de opções nativas inseguras.
2. Implementar parser e serializador JSON em Delégua puro: gramática estrita,
   Unicode/escapes e pares substitutos, números, coleções, limites e diagnósticos.
3. Reaproveitar o frontend em um LSP persistente local via stdin/stdout. Nenhum
   compilador C, linker ou processo de build na edição; cache por versão do
   documento, documentos abertos em memória, posições UTF-16 do protocolo.
4. Criar extensão VS Code própria com semantic tokens produzidos pelo LSP,
   diagnósticos, hover, definição, referências, completion, símbolos, rename e
   signature help. Compilar/executar só por comando explícito; F5 pode executar
   uma configuração sem prometer depuração que ainda não existe.
5. Empacotar VSIX, instalar com code --install-extension e verificar instalação.
   Registrar limites reais e testes. Depurador/DAP é etapa futura explicitamente
   adiada pelo usuário: não anunciar suporte a breakpoints/stepping inexistente.

## Contratos

- Preservar AGENTS.md, segurança do perfil compilado, alterações locais e stashes.
- O binário local não versionado `07_funcoes` já existia no início desta tarefa.
- Sem subagentes. Git do runtime é do submódulo; publicar runtime antes do CGD.
- Libcurl existe no ambiente (pkg-config). A rede do editor/LSP deve ser zero;
  a biblioteca de rede só acessa a rede quando o programa solicitar.
- Não recompilar o CGD ao iniciar a extensão nem por edição. Recompilar o binário
  somente quando os próprios fontes do compilador forem alterados nesta tarefa.
- Não expor setters de callbacks, ponteiros de usuário, FILE\*, SSL context,
  compartilhamento nativo ou opções equivalentes através de valores arbitrários.

## Estado inicial

- CGD e runtime na dev, último estado publicado: CGD 5ceb1e9/runtime bea5fb0.
- Ainda não há LSP, extensão, biblioteca JSON ou binding libcurl no projeto.
- VS Code disponível em /usr/bin/code; Node/npm disponíveis.
- Pipeline atual CLI termina o processo ao reportar erros; o servidor precisa de
  uma API de análise que devolva Diagnostics sem exit e sem lowering/CTFE executada.

## Registro de execução

- Planejamento e inspeção inicial concluídos. Próximo passo: implementar as
  primitivas de rede e a API de análise persistente, seguidas das bibliotecas.
- Testes desta etapa: ainda pendentes. Não confundir com relatórios anteriores.

### Checkpoint de implementação

- Criados `vendor/delegua-runtime/src/rede.c` e tipo gerenciado `rede`: sessões
  libcurl, opções com introspecção de tipo, corpo/headers limitados, TLS padrão,
  encerramento/finalizador, lote multi, percent-encoding e primitivas Unicode.
  Build e link agora usam pkg-config libcurl. API C perigosa continua bloqueada.
- `bibliotecas/rede.delegua`: Sessao, requisitar/obter/enviar/lote e introspecção.
- `bibliotecas/json.delegua`: parser/serializador puro; NumeroJSON preserva
  números fora do intervalo nativo. Exemplo Unicode/arrays já executou com sucesso.
- Corrigida falsa detecção de ciclo de herança em classes com referências mútuas:
  assinatura/identidade são registradas antes de analisar corpos de métodos.
- `frontend/analysis.d`: análise sem exit/codegen/execução CTFE; ModuleLoader aceita
  buffers em memória. Lexer oferece comentários para ferramentas sem alterar CLI.
- `src/lsp/model.d` e `server.d`, CLI --lsp: servidor stdio e índice de símbolos.
  Teste de protocolo em `testes/lsp.py` em execução; ainda falta reforçar features,
  criar/instalar extensão e realizar testes completos das bibliotecas.
- Nenhum commit desta tarefa foi publicado ainda. Binário 07_funcoes preservado.

### Checkpoint: bibliotecas e Extension Host

- `testes/bibliotecas.py`: 310 verificações passaram, compilando o harness JSON
  uma vez por modo e usando só HTTP loopback. Unicode, substitutos, sintaxe
  inválida, números grandes e limites cobertos; HTTP GET/POST binário, redirects,
  status, limite, lote e recusa de callbacks/handles fechados cobertos.
- `testes/lsp.py` passou: stdio, hover, definição, referências, rename, semantic
  tokens, posição UTF-16 e nenhuma reanálise em 10 consultas de hover.
- `scripts/testar_extensao.py` passou no VS Code 1.138 já instalado com perfil
  temporário isolado: ativação, hover/definition/completion, semantic tokens,
  rename, diagnóstico E3101, ausência de build por edição e compilação explícita.
- Corrigida interoperabilidade: vscode-languageclient acrescenta --stdio; CGD
  aceita --lsp --stdio. Não é necessário baixar/recompilar outro editor/compilador.
- Extensão está em `extensao-vscode/`, com client 9.0.1 e 8 dependências JS de
  execução incluídas. Empacotamento usa ZIP/XML padrão com Python; downloads das
  ferramentas pesadas VSCE falharam e foram eliminados, não são necessários.
- Pacote `out/cgd-0.1.0.vsix` gerado. Instalação e associação \*.delegua em curso
  via scripts/instalar_extensao.py --associate. Confirmar resultado antes de dizer
  que está instalada. Ainda faltam revisão final, testes de regressão e commits.

### Checkpoint: instalação concluída, acabamento pendente

- Confirmada instalação `fernandothedev.cgd@0.1.0` por `code --list-extensions
--show-versions`. Associação global \*.delegua → cgd alterada com jsonc-parser,
  preservando o restante do settings. Não desinstalada a extensão oficial.
- O snapshot incluído no VSIX precisa ser reempacotado/reinstalado ao final,
  pois continuam ocorrendo melhorias no frontend/LSP e runtime desta tarefa.
- Rede ampliada: getinfo gerenciáveis gerados dos headers locais, URL API,
  versão detalhada, datas/erros/upkeep, streams connect-only, espera e entrypoints
  WebSocket. Libcurl efetivamente carregada é 8.18.0, headers pkg-config 8.22.0;
  protocolos locais listados não incluem ws/wss. Não afirmar WS funcional aqui.
- Testes das bibliotecas ampliados a 334 verificações, incluindo getinfo, URL API,
  datas e stream TCP via libcurl no loopback. Ainda testar essas últimas mudanças
  após build final, além da matriz/GC/sanitizadores e documentação de limites.
- Em andamento: recuperação parcial da AST durante edição, completion por módulo/
  classe, buffers untitled, aliases estáticos cgd:json/cgd:rede e cópia das libs no
  instalador. Rodar testes LSP expandidos e Extension Host após concluir.

### Checkpoint: editor instalado e novas regressões

- Instalação confirmada e associação CGD ativa; binário precisa ser atualizado no
  VSIX final após novos builds do frontend.
- Rede agora inclui multipart gerenciado, upload com callback interno (nunca lê
  stdin implicitamente), streams e getinfo gerados da toolchain. POSTFIELDSIZE
  direto é recusado para impedir leitura fora do corpo copiado. Testes: 342 checks.
- LSP ampliado para recuperação parcial durante edição, navegação de módulos em
  memória, completion de módulos/classes e untitled. Teste expandido está rodando.
- Empacotamento usa apenas Python stdlib e dependências JS de execução. Npm ficou
  reduzido a 9 pacotes instalados; VSCE e downloads de Electron não são necessários.
- Próximos passos concretos: conferir testes LSP expandidos; corrigir regressões;
  formatar; rodar DMD/LDC2 e testes de runtime/bibliotecas; documentar APIs e limites;
  testar VSIX instalado/Extension Host final; publicar commits runtime/CGD dev.
