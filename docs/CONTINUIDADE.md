# Publicação solicitada — 17/11/2026

Solicitação: incluir os novos exemplos nos testes e publicar runtime e CGD em dev.

- Calculadora: contrato de saída exata 90/15/25.
- MiniJS/jsvm.delegua: contrato de saída exata cobrindo Fibonacci, chamadas,
  vetores/objetos, laços, escopos, booleanos e resto. programa.js é fixture local.
- Runner: diretorio: fonte executa a partir da pasta do exemplo, preservando
  recursos relativos também nas cópias usadas pelo teste do formatador.
- MiniJS é um programa didático em Delégua; não altera a exclusão definitiva de
  integração JS/host JavaScript no compilador. Fontes existentes preservados.
- Validação executada: 120 exemplos/240 verificações com e sem otimização,
  zero falhas; formatador em 129 arquivos idempotentes e os mesmos 240 contratos
  passaram. Logs: out/exemplos-publicacao.log e out/formatador-publicacao.log.
- Política de tipos, referência gerada e git diff --check passaram. Não foi
  repetida a matriz: as mudanças desta etapa são exemplos/contratos/runner.
- Runtime publicado primeiro em origin/dev: 7833699 (ampliação das APIs nativas,
  inicializadores de classe, comparação textual e diagnósticos visuais), incluindo
  as mudanças validadas na etapa anterior. Sem stashes ou artefatos versionados.
- CGD: preparado para commit/push com atualização do ponteiro do submódulo;
  confirmar sincronização com origin/dev ao concluir a publicação.

---

# Implementação e validação — 17/11/2026

- Corrigir @decoradores no formatador; coloração de tipos, metadados e estrangeira.
- Valores padrão tipados e inicializadores de atributos por instância.
- Inlay hints de inferência, hover de pureza/comptime, comparação textual e ícone.
- Referência web própria completa; JS, herança de interfaces e múltiplos dialetos
  são exclusões definitivas por decisão do usuário, não pendências.
- O usuário autorizou agora todos os testes necessários. A suspensão anterior
  está revogada. Preservar alterações existentes e registrar resultados reais.

Continuação ativa: renderer visual do runtime e ampliação substancial da stdlib.

Implementado em 17/11:

- Defaults de variáveis/campos, inicializadores por objeto/base antes da derivada,
  coleções independentes, contratos e efeitos preservados.
- Formatador une @nome; lexer reserva estrangeira; tokens de tipos/metadados;
  inlay hints virtuais; hover com pureza/CTFE; ícone existente da linguagem.
- Diagnóstico visual R0001 com localização, trecho e marcador, leitura apenas na
  falha; controles escapados, arquivos ausentes/FIFO tratados sem bloquear.
- Novos módulos Textos, Estatistica, Caminhos e ampliação de Colecoes, Arquivo,
  Matematica. Testes públicos com -Wall/-Wextra/-Werror nos dois modos.
- Referência web própria de 25 capítulos, gerada de linguagem.json e exemplos;
  exclusões definitivas documentadas. GitHub Pages dev/docs preservado.
- Contratos dos exemplos novos de perceptron exigem 24 checks sem falhas e 8/8
  acertos. MiniGPT preserva as 150 épocas; contrato automático é explicitamente
  compilação/vínculo. Uma execução experimental foi interrompida por timeout de
  180 segundos; não afirmar validação do treinamento completo.

Resultados reais até agora:

- 9 módulos unitários DMD e LDC2; API C e caminhos de erro passaram.
- Driver 26, integração 407, bibliotecas 342 e stdlib 98 contratos passaram;
  expansão e runtime_diagnosticos passaram em ambos os modos onde aplicável.
- LSP passou com hints, cores, pureza/CTFE, UTF-16 e buffers em memória.
- Formatador: 126 arquivos idempotentes, 117 exemplos/234 verificações sem falhas.
- Web: links/âncoras/assets e Chrome desktop/mobile passaram.
- VS Code real: Extension Host passou com associação/ícones, inferência virtual,
  hover de pureza, demais providers e edição sem build.
- Política de tipos explícitos passou.

A matriz DMD/LDC2 × debug/release × Clang/GCC concluiu sem falhas (51 etapas
registradas em out/validacao.json), com instalações
isoladas. A solicitação adicional de enums/arrow chegou durante essa execução;
os casos novos recebem validação incremental posterior, sem atribuir resultados
anteriores a alterações ainda não testadas.

Continuação adicional autorizada: espaçamento de =>, incluindo => ( e => [;
enums em funções, métodos, blocos, classes/interfaces e classes estrangeiras.
Aliases têm escopo lexical; enums de classe usam namespace estático imutável,
com visibilidade/herança. Membros escalares não capturam o mapa e funcionam em
CTFE; receptores com efeitos continuam avaliados. O namespace inteiro não ganha
captura implícita ou representação como mapa na VM. DMD/LDC2 passaram os 9 módulos
unitários atualizados; enums.py passou com Clang em DMD/debug, e o protocolo LSP
passou também com completion de enums locais e de classe. Novo exemplo 40.

Validação incremental posterior à solicitação de enums/arrow:

- DMD e LDC2: 9 módulos unitários atualizados passaram, incluindo resultado CTFE
  de função com enum local e argumento vindo de membro de enum global.
- LSP: completion de enums locais/de classe e demais checks passaram.
- ASan/UBSan + NDEBUG: API C/caminhos de erro, integração 407, 118 exemplos/236
  verificações, bibliotecas 342, expansão, enums (2 modos/9 rejeições), stdlib 114
  e diagnósticos visuais passaram. Runtime normal restaurado; relatório
  out/sanitizadores.json. Detecção de leaks desativada para Boehm GC, conforme
  configuração explícita do script; não declarar validação de leaks.
- Runtime: alinhamento com linha >=10000 e janela de colunas longas passaram.
- Web atualizada: Chrome desktop/mobile e política de tipos/formatação passaram.

Conferência final concluída:

- GCC normal/LDC release: enums nos dois modos e 9 casos negativos, stdlib 114,
  driver 26 e integração 407 passaram; out/gcc-final.json.
- Formatador atualizado: 127 arquivos idempotentes; 118 exemplos, 236 verificações
  com/sem otimização, sem falhas. Inclui => antes de parênteses/vetores/blocos e
  exemplo 40 de enums locais/de classe. out/formatador.log.
- Extension Host real repetido: todos os 13 checks passaram; out/vscode/extensao.json.
- Formatação de todos os fontes/documentação e git diff --check (CGD/runtime)
  passaram. Referência gerada sincronizada e política de tipos verificada.
- Extensão 0.5.0 instalada e confirmada pelo CLI, associação \*.delegua preservando
  preferências. out/cgd-0.5.0.vsix inclui o mesmo binário LDC release/runtime normal
  validados, logo e bibliotecas; conteúdo conferido byte a byte. Recarregar janela
  do VS Code para substituir o servidor já em execução.

Uma execução de formatador.py coincidiu com o objeto ASan e falhou no vínculo sem
flags de sanitização. Log mantido em out/formatador-concorrente.log; repetição
com runtime normal passou integralmente. Isso não foi registrado como sucesso.

Sem publicação ou push. Alterações preexistentes foram preservadas; o submódulo
continua sendo seu próprio repositório. O treinamento completo de 150 épocas do
MiniGPT não foi validado (timeout experimental de 180 s); seu contrato automático
é compilação/vínculo. Recursos da wiki fora do perfil e limitações reais continuam
explicitados em compatibilidade.md/evolucao-linguagem.md, sem equivalência integral.
Próxima ação do usuário: recarregar a janela do VS Code. Não repetir a matriz
sem alterações relevantes; resultados e comandos acima permitem retomada.

---

# Histórico: organização, editor e bibliotecas (16/11/2026)

- Revisar responsabilidades dos passes e unificar a análise usada pela CLI/LSP.
- Corrigir completion de isto, palavras-chave/construtor, reconhecimento de arquivos
  e oferecer prévia CTFE no hover sem compilar por edição.
- Acrescentar destrutores com contrato explícito de ciclo de vida e expandir JSON,
  rede, arquivos/I/O e métodos de dicionário, preservando APIs anteriores.
- Melhorar emissão C sem descartar efeitos/inicializadores/contratos.
- **O usuário proibiu executar testes até nova ordem.** Nenhum teste foi executado
  nesta solicitação; resultados abaixo pertencem exclusivamente ao trabalho anterior.
- Alterações preexistentes preservadas: JSON e exemplo, exemplos de dicionários,
  perceptron, lsp/builtins.d e runtime/src/biblioteca.c. Sem subagentes/publicação.

## Histórico: wiki, FFI e extensão 0.4.0

O usuário autorizou explicitamente FFI e instalação do novo LSP. Essa autorização
substitui a exclusão anterior de FFI em AGENTS.md; não autoriza testes. Sem
subagentes, sem publicação. Mudanças preexistentes foram preservadas.

Implementado, com validação funcional pendente:

- Pipeline semântico comum CLI/LSP; declarations/analyzer substituem Sema1/2/3.
  Fluxo/segurança/pureza e constantes ficam na área semântica; destinos e
  visibilidade têm regras compartilhadas. Lowering não valida atribuições.
- Completion de isto/super incompletos, catálogo lexical único, metadados nativos,
  prévia CTFE sob demanda e sem alterar a AST. VM limita texto/slots/operandos e
  descarta resultados de comandos. C omite temporários escalares e rótulos sem
  uso; mantém snapshots de identificadores, inicializadores, efeitos e contratos.
- Destrutores explícitos, dicionários ampliados, Arquivo, JSON navegável com
  enumeração resistente a colisões de nomes, ClienteHTTP/RespostaHTTP.
- Classe abstrata e métodos abstratos; interfaces e implementa com contratos
  explícitos; enum numérico congelado com alias inteiro; arrows sem captura.
- FFI com @definicao: ABI C escalar e ABI delegua gerenciada. Libs usam Primitivas
  de cgd:nativo e pontes.c; aliases antigos continuam para compatibilidade.
- Matematica/libm e Colecoes.reduzir/agrupar/achatar. Para cada elem: T já existia.
- Wiki oficial clonada em out/wiki-oficial; docs/evolucao-linguagem.md registra
  sintaxe, motivos das diferenças e limites. Não declarar cobertura completa:
  mescla, host JS, herança de interfaces, enums nominais e ABI C composta pendem.

Execução real nesta solicitação: builds de aplicação LDC2 debug e compilação dos
fontes C do runtime com Clang/C99 e -Werror; formatação com ferramentas próprias.
DUB_HOME=out/dub contorna cache global somente leitura. Nenhuma suíte, exemplo,
programa de amostra, Extension Host ou sanitizador foi executado. Falhas de build
foram corrigidas durante a implementação; isso não valida a linguagem em execução.
A instalação 0.3.0 foi confirmada pelo instalador e associou \*.delegua ao CGD.
A 0.4.0 foi instalada e confirmada pelo CLI (fernandothedev.cgd@0.4.0), com
associação de \*.delegua. O pacote fica em out/cgd-0.4.0.vsix. O usuário precisa
recarregar a janela para substituir o servidor já aberto. Não houve teste de LSP.

Regressões escritas em testes/unit/expansion.d e testes/expansao.py (incluída na
matriz/sanitizadores); exemplos 36/37/38 e bibliotecas/arquivos/json_navegacao/
matematica. Não executar até nova ordem. Quando autorizado: build-runtime,
dub test em DMD/LDC2, testes/expansao.py, matriz, sanitizadores e Extension Host.
Não confundir instalação por CLI com teste do comportamento do LSP.

---

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
