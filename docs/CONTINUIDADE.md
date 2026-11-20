# Segurança estática ampliada (E3109–E3112) e inferência no LSP — 20/11/2026

Solicitação ativa: continuidade da revisão 0.9.0 após reinicialização do sistema,
concluindo as melhorias de segurança estática e inferência do LSP, validação,
commit/publicação em `dev` e reinstalação do binário CGD e da extensão VS Code.

## Implementação entregue

- **Diagnósticos estáticos `E3109`–`E3112` (e `W3109`–`W3112` em `pegue`)**:
  - `src/diagnostics/catalog.d`: adicionados `E3109` (membro inexistente),
    `E3110` (mutação de coleção imutável), `E3111` (operação sobre valor
    comprovadamente nulo) e `E3112` (valor não invocável).
  - `src/frontend/semantic/analyzer.d` e `src/frontend/parser/ast.d`:
    inferência em ternário e `para cada`, `ClassField.type_sema`, resolução de
    exportações de módulos (`classe`/`função`/`variável`), construtores
    qualificados por módulo e aliases `const`, emissão de `E3112` em chamadas
    tipadas não invocáveis.
  - `src/frontend/semantic/static_safety.d`: rastreamento de variáveis não
    mutadas e mapa de subclasses/implementadores do programa; verificação de
    membros em módulos, classes gerenciadas (preservando acesso polimórfico a
    membros de subclasses quando o receptor não é classe nem instância exata),
    primitivos/vetores/tuplas/`Promessa`/`Tarefa` com sugestões por distância de
    Levenshtein (`H3001`); verificação de mutação em `texto`/`tupla` (`E3110`),
    operações sobre `nulo` (`E3111`), chamadas não invocáveis (`E3112`) e
    contratos de elementos em vetores tipados (`adicionar`/`empilhar` e
    atribuição por índice preservando `TypeExpr` exato como `inteiro[]`).
- **Inferência e navegação no LSP (`src/lsp/model.d`)**:
  - Inferência de tipos para `rotina` (`Tarefa<T>`), `aguardar`, vetores
    literais homogêneos, indexação, ternário, binários/coalescência, fábricas
    de classes qualificadas por módulo e membros via `resolveClassMember`
    (incluindo `mescla` e herança).
- **Documentação e contratos**:
  - `exemplos/seguranca/07_tupla_imutavel.delegua` atualizado para `fase: compilacao`
    / `E3110`; `docs/desenvolvimento.md`, `scripts/gerar_referencia.py`,
    `docs/linguagem.html` e `docs/livro` regenerados e sincronizados.

## Testes realmente executados

- Unitários D: DMD e LDC2 (10 módulos cada, incluindo novas regressões em
  `testes/unit/static_safety.d` para `E3109`–`E3112`, polimorfismo vs instância
  exata, contratos de `inteiro[]` e `W3112`).
- Build release: `dub build --compiler=ldc2 --build=release`.
- Integração e linguagem: `integracao.py` (409 verificações com Clang e GCC),
  `lsp.py` (incluindo inlay hints de `Tarefa<T>`, `aguardar`, vetor homogêneo,
  indexação e hover em `mescla`), `exemplos.py` (136 exemplos / 272
  verificações, 0 falhas), `formatador.py` (160 arquivos idempotentes / 272
  verificações preservadas), `driver.py` (26), `bibliotecas.py` (342),
  `linguagem_nova.py` (8), `rotinas.py` (15), `stdlib_avancada.py` (11),
  `async_linguagem.py` (30), `validar_instalacao.py`.
- Documentação e estilo: `gerar_referencia.py --check`, `gerar_livro.py --check`,
  `testes/livro.py` (39 páginas), `testes/site.py --static-only`,
  `scripts/verificar_tipos.py` e `scripts/formatar.py --check`.

---

# Revisão 0.9.0 — Rotinas paralelas, linguagem, stdlib avançada e refatoração — 20/11/2026

Solicitação ativa: melhorar o compilador e implementar os recursos pendentes
documentados em `docs/` e `AGENTS.md`, com autorização explícita do usuário para
executar todos os testes necessários, commitar e publicar em `dev` (runtime e
CGD) e reinstalar o binário e a extensão VS Code. Sem subagentes.

## Implementação entregue

- **Rotinas paralelas e isolamento por thread**:
  - Runtime C (`delegua_rt.h`, `excecoes.c`, `valores.c`, `delegua_rt.c`):
    `DELEGUA_NORETURN` nos helpers de pânico (eliminando avisos GCC `-O2` em
    todo o runtime, inclusive `rede.c`/`textos.c`), otimização de
    `create_text_concat`, TLS por thread (`__thread`) para exceções,
    profundidade de chamadas e localização, `pthread_once` para classes núcleo
    (`Objeto`/`Excecao`), e registro de threads de workers no Boehm GC
    (`GC_THREADS`/`GC_NO_THREAD_REDIRECTS`, `GC_allow_register_threads`, hooks
    de ciclo de vida em `rotinas_pool.c` mantendo o pool isolado para TSan).
  - Tags `DELEGUA_T_TAREFA`, `DELEGUA_T_CANAL`, `DELEGUA_T_BYTES` e
    `DELEGUA_T_SQLITE` ao fim de `enum delegua_type` (ABI anterior preservada).
  - `delegua_rotina_iniciar` em `rotinas_reactor.c`: executa funções Delégua
    compiladas em workers com fronteira TLS de exceção, propagando rejeições e
    cancelamento para a thread principal via epoll.
  - Frontend/backend/LSP: palavra-chave `rotina`, tipo paramétrico `Tarefa<T>`,
    `aguardar` aceitando `Promessa<T>` e `Tarefa<T>`, métodos
    `concluida`/`cancelada`, auditoria transitiva de efeitos em
    `src/frontend/semantic/routine_validation.d` (`E3401`–`E3404`).
  - `assincrono_canal.c` e `cgd:assincrono`: `Canal` limitado com backpressure
    assíncrono sobre valores transferíveis e `GrupoTarefas`.
- **Recursos pendentes da linguagem**:
  - Campos estáticos tipados (`estatico campo: Tipo = valor`) com defaults,
    visibilidade, herança, contratos de escrita no runtime e bloqueio em
    rotinas (`E3402`).
  - Composição por mixins (`classe C mescla M1, M2`) com precedência,
    encapsulamento privado/protegido por dono, inicializadores de campos,
    `eInstanciaDe` e satisfação de interfaces.
  - Envelopes de decoradores em métodos de instância e estáticos (com ajuste de
    aridade do receptor `delegua_ajustar_metodo_envelope`).
  - Otimizador (`opt/constant_folding.d`): propagação de constantes tipadas
    quando o literal já satisfaz o tipo primitivo, dobras unárias (`-real`,
    `+real`, `~inteiro`) e simplificações de curto-circuito (`verdadeiro e x`,
    `falso ou x`).
- **Stdlib avançada e servidor HTTP concorrente**:
  - Novos módulos: `cgd:bytes` (`Bytes`), `cgd:cripto` (`Cripto` sobre OpenSSL
    `libcrypto.so.3`), `cgd:compressao` (`Compressao` gzip/deflate sobre
    `libz.so.1` com limite contra bombas de descompressão) e `cgd:sqlite`
    (`SQLite`/`BancoSQLite` sobre `libsqlite3.so.0` com consultas parametrizadas
    e transações).
  - Expansões: `DataHora` em `cgd:tempo`, `SocketUDP`/`resolverDNS`/IPv6 em
    `cgd:sockets`, e `HTTP.escutarAsync`/`atenderConexaoAsync` com atendimento
    concorrente sobre epoll e HTTP/1.1 keep-alive em `cgd:servidor`.
- **Refatoração e organização**:
  - Separação de `src/middle/async_ir.d` e `src/middle/async_lower.d`;
    extração de `src/backend/c/async_codegen.d`, `src/backend/c/descriptors.d`
    e `src/lsp/features.d`; remoção de binários soltos (`http`, `minigpt`) na
    raiz; atualização de gramáticas TextMate/mdBook, exemplos 42/43 e
    `bytes_cripto_sqlite`, referência web e livro (39 páginas).

## Testes realmente executados

- Builds: `CC=gcc CFLAGS="-O2" ./build-runtime` (zero avisos em todo o
  runtime), `./build-runtime` (Clang C99 estrito), `dub build` LDC2 release e
  debug.
- Unitários D: DMD e LDC2 (10 módulos cada) passaram.
- Núcleo async e rotinas: `python3 testes/assincronismo.py` passou em Clang,
  GCC, ASan/UBSan e TSan (pool isolado).
- Linguagem e bibliotecas (Clang e GCC, com e sem `-o`): `driver.py` (26),
  `lsp.py`, `bibliotecas.py` (342), `expansao.py`, `enums.py`, `stdlib.py`
  (114), `runtime_diagnosticos.py`, `processo.py`, `servidor.py`, `sockets.py`,
  `http_parser.py` (50000 entradas ASan/UBSan), `async_linguagem.py` (30, normal
  e `--sanitizadores` ASan/UBSan + GCC), `rotinas.py` (15, Clang e GCC),
  `linguagem_nova.py` (8, Clang e GCC), `stdlib_avancada.py` (11, Clang e GCC),
  `integracao.py` (407) e `exemplos.py` (136 exemplos / 272 verificações, 0
  falhas).
- Sanitizadores: `scripts/sanitizadores.py --rede` (API C, parser HTTP,
  servidor e sockets com NDEBUG + ASan/UBSan; runtime normal restaurado).
- Instalação isolada (`scripts/validar_instalacao.py`), formatador
  (`testes/formatador.py`: 160 arquivos idempotentes e 136 exemplos / 272
  verificações preservados), documentação e estilo:
  `gerar_referencia.py --check`, `gerar_livro.py --check`, `testes/livro.py`
  (39 páginas), `testes/site.py --static-only`, `scripts/formatar.py --check` e
  `scripts/verificar_tipos.py` passaram.
- Limites conhecidos: Linux x86_64 é a única plataforma validada; enums
  nominais, structs/callbacks compostos na ABI C, classes locais em corpos
  async (`E3305`) e DAP permanecem pendentes.

---

# Integração do pool de rotinas com o reactor — 18/11/2026

A solicitação é completar as rotinas e deixar a execução dos testes com o usuário.
Implementada a ponte C interna em `rotinas_reactor.c`: submissão limitada,
notificação por epoll, resolução e rejeição na thread principal, cancelamento
cooperativo e join no fechamento do reactor ocioso. Workers podem produzir
pacotes escalares e texto copiado. A ponte mantém raízes fortes até a entrega.

Foram preparados cenários de cancelamento em execução, pressão de GC, conclusão
em lotes, retorno com byte NUL e falhas de transferência. Builds com GCC e Clang
passaram e ambos aceitaram a fonte C da regressão com `-fsyntax-only`.
O executável isolado do pool para ThreadSanitizer foi vinculado com Clang.
O GCC local não dispõe de libtsan; a suíte usa o runtime de TSan do Clang.
Nenhuma suíte executada. A execução de Delégua em workers permanece condicionada
à validação do pool e do assincronismo. Faltam isolamento do contexto de execução,
auditoria transitiva de efeitos, frontend e emissão de `rotina` / `Tarefa<T>`.
Canais e grupos dependem do pool validado.

Comandos de validação na raiz: `./build-runtime`,
`python3 testes/assincronismo.py`, `python3 scripts/validar.py`,
`python3 scripts/sanitizadores.py`, `python3 testes/livro.py` e `python3 testes/site.py`.

---

# Continuação das rotinas — 18/11/2026

Implementado o pool interno de workers C no runtime Linux, com fila FIFO,
capacidade limitada até o consumo da conclusão, cancelamento cooperativo,
eventfd e encerramento com join. Contrato de posse em `docs/rotinas.md`.
A submissão aceita callbacks C internos sobre pacotes exclusivos. Ainda falta
ligar a conclusão ao reactor, auditar efeitos, isolar o estado por thread e
implementar a expressão Delégua e o tipo Tarefa.

Builds executados com sucesso: `CC=gcc ./build-runtime` e `./build-runtime`
(Clang). Regressão preparada em `vendor/delegua-runtime/tests/assincrono.c`
para fila cheia, cancelamento em fila, prontidão do descritor e posse do pacote.
Nenhum teste funcional executado nesta continuação. A suspensão mais recente
continua vigente. Após liberação, executar `python3 testes/assincronismo.py` e
`python3 testes/async_linguagem.py` antes de habilitar execução Delégua em threads.

---

# Assincronismo completo e início das rotinas — 18/11/2026

Solicitação ativa: concluir as partes restantes do assincronismo e começar as
corrotinas/rotinas previstas no projeto. O usuário suspendeu explicitamente os
testes: NÃO executar suítes, exemplos, programas de amostra ou benchmarks até
nova ordem. Builds e formatação continuam permitidos; não equivalem a testes.
Não publicar/instalar sem autorização desta etapa; sem subagentes.

Prioridade de implementação: handlers/finalmente na IR stackless, demais formas
de fluxo/coleção, cancelamento cooperativo, temporizadores e reactor/I/O real,
API nativa de Promessas e combinadores. Iniciar paralelismo pela definição dos
valores transferíveis e isolamento do runtime; não expor mutação compartilhada
ou declarar estabilidade sem validação autorizada. Não confundir as corrotinas
stackless já em construção com threads paralelas.

Checkpoint anterior: havia build LDC release em andamento quando o pedido novo
chegou; nenhum teste novo foi iniciado após esta instrução. Antes da suspensão,
passaram unitários DMD/LDC (10 módulos), núcleo C/API anterior em Clang/GCC e
ASan/UBSan, 407 integrações, 132 exemplos/264 verificações e LSP expandido.
O novo exemplo 41 e as últimas alterações ainda precisam da rodada final;
não reutilizar resultados anteriores para afirmar validação do estado atual.

Implementado nesta continuação, ainda sem validação funcional:

- IR stackless com arestas excepcionais, pegue tipado e finalmente suspenso;
  limpezas em retorno/erro/break/continue, snapshot de retorno antes da limpeza
  e contrato após ela. Locais C volatile para a fronteira setjmp viva por ativação.
- Lowering de para cada, escolha, compreensões, laços coletores, destructuring e
  spread; E3305 agora se restringe a classes locais em corpos async. Parser aceita
  finalmente vazio. Vivacidade inclui arestas excepcionais e preserva valores
  anteriores quando uma operação falha antes de concluir sua definição.
- Cancelamento cooperativo de tarefas com job de controle pré-alocado, máscara
  durante limpezas, remoção de waiter sem cancelar produtores compartilhados e
  marcador nativo de cancelamento. Exceções conservam a primeira origem.
- API estática Promessa.resolvida/rejeitada/todas/corrida/qualquer/todasResolvidas,
  resultados ordenados, agregação de erros e cancelamento de consumidores.
- Reactor epoll em assincrono_io.c: heap monotônico de timers, limites, raízes
  fortes, lotes e cleanup de watchers; sem sleep/busy-wait/thread por operação.
- HTTP real em assincrono_http.c: curl multi + waitfds (runtime >=8.8), DNS somente
  c-ares ou IP numérico, sem proxy/redirect, TLS verificado, limites de memória,
  callbacks sem longjmp atravessando libcurl e cancelamento da requisição.
- TCP real em assincrono_sockets.c: conectar/aceitar/receber/enviar, IPv4 numérico,
  FD nonblocking, prazos/cancelamento, uma operação por handle, fechamento em falha
  de conexão/escrita parcial; aceite cancelado preserva ouvinte. Helpers internos
  do socket síncrono rejeitam uso enquanto ocupado; fechamento notifica operação.
- Módulo bibliotecas/assincrono.delegua: Tempo, HTTP/RespostaHTTP, TCP/ConexaoTCP e
  OuvinteTCP, com tipos explícitos e API estrangeira gerenciada controlada.
- Fronteira externa captura falhas da raiz/drain; shutdown cancela produtores,
  protege dependências de finally já suspenso, permite trabalho novo só em limpeza
  e reporta erro original mesmo se drenagem falhar. O prazo de drenagem foi acrescentado na continuação abaixo.
- Início concreto das rotinas: docs/rotinas.md define expressão rotina/Tarefa,
  isolamento, pool fixo e gates antes de executar Delégua em workers. Módulo C
  rotinas_transferencia implementa pacotes exclusivos sem referências ao GC,
  nulo/lógico/inteiro/real/texto copiado, até 4096 itens/16 MiB. Sem sintaxe rotina,
  workers, canais, grupos, TLS de execução ou registro de threads no GC ainda.
- Regressões preparadas em testes/async_linguagem.py (finally, catch, fluxo,
  combinadores, timers, cancelamento e TCP loopback) e runtime/tests/assincrono.c
  (transferência, rejeição de mutáveis, cópia binária/GC). Removidas expectativas
  antigas de E3305 para finally. NÃO EXECUTADAS nesta continuação.
- README/compatibilidade/referência e livro atualizados; livro inclui rotinas.

Builds reais desta continuação: ./build-runtime (Clang/C99 estrito) passou;
dub build --compiler=ldc2 --build=debug passou, com rebuild após ajustes da emissão;
dub build --compiler=dmd --build=debug passou. Formatação C/dfmt/Ruff/Prettier e
formatador Delégua foram aplicados; geradores de referência e mdBook passaram.
Esses builds não demonstram correção funcional dos novos caminhos. Nenhuma suíte,
exemplo, smoke, benchmark ou binário de regressão foi executado após a suspensão.

Continuação de 18/11: HTTP.enviar passou a encaminhar o limite opcional de
resposta (padrão preservado de 16 MiB). O buffer inicial de recepção agora
respeita limites menores que 4 KiB. Preparado cenário POST em loopback com
resposta de seis bytes em UTF-8, aceita com limite seis e recusada com cinco.
Build do runtime, verificação de formatação Delégua e compilação sintática do
arquivo Python passaram. A suspensão de execução das suítes continua vigente.
Após liberação, executar `python3 testes/async_linguagem.py`.

Continuação de 18/11 — encerramento após erro: depois do cancelamento inicial,
o runtime concede cinco segundos de relógio monotônico às limpezas. A drenagem
verifica o prazo entre reações e limita a espera do epoll. O caminho normal
mantém a drenagem FIFO. Preparada regressão com finalmente aguardando 60 s,
falha da raiz e timeout externo de 15 s, nos dois modos de otimização.
Build do runtime e compilação sintática da suíte Python concluídos. A regressão
funcional aguarda liberação para rodar `python3 testes/async_linguagem.py`.

Pendências: quando o usuário liberar, validar primeiro handlers/finalmente e
cancelamento com/sem otimização e sanitizadores; depois reactor/timers, TCP e
HTTP em loopback, falhas/parcial/limites, encerramento e API C anterior. Preparar
mais cenários HTTP e stress/GC; executar integração/exemplos/LSP e matriz conforme
resultados. Só depois habilitar workers, após isolar exceções/localização/caches
por thread e definir efeitos seguros. A infraestrutura async continua experimental;
não chamar estabilidade ou paralelismo de concluídos. Sem commits/push/instalação.
Próximos comandos permitidos agora: formatação e builds. Comandos de testes ficam
pendentes de ordem explícita, sem iniciar automaticamente.

---

# Assincronismo nativo — Etapa 2 em validação (17/11/2026)

O usuário pediu continuidade da Etapa 1 e reiterou continuar durante o trabalho.
Implementação local em andamento; sem subagentes/commit/push. As alterações
preexistentes de servidor/bibliotecas/livro permanecem preservadas.

Implementados tokens/parser/AST de assincrona/aguardar e Promessa<T>, contexto
semântico, resultado da chamada separado do retorno interno, contratos e efeitos
em interfaces/overrides. Criados middle/async_ir.d (CFG normalizado e vivacidade)
e semantic/async_validation.d (limites temporários compartilhados CLI/LSP).
Backend emite wrapper e step C99, mantendo em frame somente slots vivos nas
suspensões; argumentos são consumidos na entrada síncrona, sem guardar argv.
Runtime ganhou tag ao fim da enumeração, descritor estrutural e contratos de
resultado, tarefas com fronteira C válida por ativação, retomadas por microtask,
drenagem após a raiz e reporte de rejeições não observadas. entao/capturar usam
callbacks sem captura, com adoção quando devolvem Promise. Sem paralelismo/I/O.

Limites explícitos desta etapa: tente/pegue/finalmente, para cada, escolha,
compreensões, laços-coletores, spread e classes locais dentro de async recebem
E3305; não são convertidos em chamadas bloqueantes. Cancelamento, I/O e API
estática de Promessa ainda pendem. Tratadores suspensos exigem IR própria e não
reutilizam jmp_buf. Exceções não tratadas no topo síncrono ainda encerram pelo
caminho antigo. Não considerar o modelo assíncrono estável/completo.

Verificações intermediárias reais: build C99/Clang normal e LDC debug passaram;
smoke em C gerado produziu A/B/C/17 com suspensão em laço. Unitários LDC passaram
(10 módulos, incluindo frontend/IR); testes C da Etapa 1/API anterior passaram em
Clang, GCC (núcleo O2) e NDEBUG/ASan/UBSan após corrigir qualifiers volatile no
caminho de setjmp. Suíte de linguagem com/sem otimização passou antes da última
ampliação entao/capturar; rodada ampliada está em execução. Ainda validar DMD,
editor, integração/exemplos e final sanitizado. Não anunciar resultados pendentes.

Próximos comandos: python3 testes/async_linguagem.py; python3 testes/assincronismo.py;
dub test em DMD/LDC; testes/lsp.py, integracao.py, exemplos.py e rodada sanitizada
de async. Documentar resultados reais/limites ao encerrar. Sem publicação remota.

---

# Assincronismo nativo — Etapa 2 em implementação (17/11/2026)

Continuidade autorizada pelo usuário. Trabalho local sem publicação/subagentes;
fontes anteriores preservados. Frontend já tem assincrona/aguardar e Promessa<T>,
contexto e tipos separados entre retorno interno e resultado da chamada. Nova
middle/async_ir.d normaliza avaliação, controla ramos/laços, calcula vivacidade e
seleciona slots persistentes. Backend emite wrapper e step com switch(pc).
Runtime ganhou tag ao fim da enumeração, descritor de Promise, tarefas stackless
e drenagem do loop após a raiz síncrona. Programa de verificação A/B/C/17 passou
com await em laço; isso não é ainda aprovação da etapa.

Em curso: regressões de linguagem, contratos dinâmicos, métodos, sombras,
ordem de efeitos, parâmetros opcionais e análise de slots. Tente/pegue/finalmente,
para cada, escolha, compreensões e spread ainda recebem E3305 dentro de async;
não implementar fallback bloqueante. Cancelamento, I/O e Promessa.entao na
linguagem seguem para etapas posteriores. LSP deve exibir Promessa<T> e palavras
novas sem build por edição.

Testes desta implementação ainda em andamento: build LDC debug e runtime C99
passaram; suíte C passou em Clang, mas GCC/O2 encontrou avisos legítimos de
clobber nos novos parâmetros modificados após setjmp em settle. Parâmetros
marcados volatile; repetir teste focado após fechar regressões. Não atribuir
os resultados da Etapa 1 ao código novo sem reexecutar.

---

# Assincronismo nativo — Etapa 1 concluída (17/11/2026)

O usuário pediu continuidade após a especificação do anexo a9825980.
Implementado núcleo C de Promessas e microtasks, sem I/O, sintaxe nova ou
paralelismo. Criados no Git do vendor src/assincrono.h, src/assincrono.c e
tests/assincrono.c; atualizado tests/run.sh do vendor para incluir a suíte nova
na validação C/sanitizada. Runner isolado testes/assincronismo.py no CGD. Atualizada
seção 14 de docs/assincronismo.md com API, verificação e limites reais.
Alterações locais anteriores foram preservadas; sem commit/push/subagentes.

Implementado: conclusão única, adoção/ciclos e limite de cadeia, encadeamento,
FIFO com reserva por reação, fronteira de exceção por checkpoint e restauração
de localização/profundidade/handler externo, raiz forte no GC, observação e
encaminhamento de rejeições, reconhecimento pelo reporter, quotas transacionais
e fechamento explícito. Localização do erro é copiada, inclusive da API legada.
Não alterados tag/ABI pública anterior, main, D/CLI ou LSP. API C opaca interna,
uso monothread, sem exposição de ponteiros à linguagem.

Testes realmente executados: python3 testes/assincronismo.py passou em Clang
normal, GCC com núcleo/teste O2 e Clang O1 NDEBUG/ASan/UBSan. Em cada variante, passaram
a suíte nova (incluindo 20000 ciclos sob quota pequena e 12000 reações pendentes)
e API C anterior com 23 modos de erro R0001. Coleta forçada, contextos vivos,
ordem, adoção pendente/pronta, resolução dupla, ciclos, exceções, localização,
limites/observação e reentrada têm regressões. Relatório completo:
out/assincronismo/resultado.json. Objetos/binaries/FFI de teste ficam em out;
libdelegua_rt.o normal e instalação do usuário não foram substituídos.

Limites da verificação: GCC/O2 integral encontrou avisos nos fontes anteriores
rede/textos, com helpers panic sem noreturn; nessa variante só núcleo/teste novos
estão em O2, legados em O0. Sem suprimir warnings ou alterar essas fontes. A
primeira rodada ASan da API antiga falhou no mapa após GC com fake stack;
runner adotou detect_stack_use_after_return=0 e detect_leaks=0, como o runner
sanitizado já existente do projeto; rodada final passou. Isso não prova ausência
universal de vazamentos. Sem teste de longa duração, I/O, LSP ou async da linguagem.
Clang-format, Ruff e Prettier passaram nos arquivos/seções desta etapa; shfmt
e sh -n passaram no runner do runtime. A inclusão no runner foi conferida
estaticamente; as execuções C acima usaram o runner isolado em Python.

Próxima etapa: tipos Promessa<T>/assinaturas e frontend/IR/frame de suspensão
(Etapa 2). Acrescentar tag só ao integrar valores da linguagem; o núcleo atual
usa rt_promise opaco e resultados delegua_value. Depois, timers/epoll/curl multi,
DNS não bloqueante, cancelamento, finally e shutdown integrado. Sem combinadores
ou identificação de ciclos arbitrários entre callbacks nesta etapa. Não iniciar
rotinas/threads/canais antes da matriz de estabilidade. Não publicar sem autorização.

---

# Histórico: Assincronismo nativo — Etapa 0 (17/11/2026)

Solicitação ativa: anexo a9825980, projeto de assincronismo e paralelismo nativo.
A instrução inicial pede começar exclusivamente pela Etapa 0: auditoria profunda
e especificação. Entrega atual limitada a essa etapa; não implementar rotinas,
workers, canais ou scheduler M:N antes de concluir/validar o assincronismo.
Sem publicação remota e sem subagentes. Alterações locais do servidor HTTP,
bibliotecas, livro, runtime e demais fontes foram preservadas.

Criado docs/assincronismo.md, proposta técnica, ainda sem recurso executável:

- Auditoria rastreável de lexer/parser/AST/tipos, semântica/fluxo/pureza, módulos,
  lowering/backend C99, ABI de funções/métodos/FFI, exceções, GC e bibliotecas
  tempo/rede/processos/sockets. Base CGD abe4290/runtime 7833699 mais alterações
  locais; hashes isolados não reproduzem o estado auditado.
- Gramática assincrona/aguardar e tipo intrínseco Promessa<T>; retorno declarado
  T versus chamada Promessa<T>, contextos proibidos, métodos e contratos.
- Máquina stackless com CFG e vivacidade, avaliação ordenada e slots que cruzam
  suspensão. Não guardar argv do chamador nem jmp_buf entre steps.
- Promise com transição única, adoção/reações, microtasks FIFO, reactor epoll,
  timers monotônicos, cancelamento cooperativo, finally suspenso, observação de
  rejeições e encerramento/falta de progresso. APIs síncronas continuam síncronas;
  proposta usa módulos separados para I/O async.
- Riscos concretos: longjmp/estado global, callbacks externos sem saltos,
  rastreamento dos frames e filas pelo GC, posse de recursos e eventos obsoletos.
  curl_multi atual ainda espera o lote; precisa integração socket/timer e auditoria
  do resolvedor DNS efetivo. APIs atuais de dormir/processos também bloqueiam.
- Estratégia de testes por etapa e gate de estabilidade antes do paralelismo.
  Pendências de engenharia explícitas: budgets/códigos, descritores/assinaturas,
  backend DNS carregado, verificador IR e nomes definitivos da biblioteca async.

Verificações desta etapa: leitura de fontes e documentação primária (Boehm,
libcurl, ECMAScript e epoll); pkg-config informou GC 8.2.6 e headers libcurl
8.22.0-DEV, sem verificar a versão carregada ou resolver. Prettier --write/--check passou no documento novo e na seção nova de
continuidade (formatada isoladamente para preservar o histórico preexistente).
Revisão textual e conferência dos caminhos principais concluídas. Nenhum build, suíte funcional, benchmark,
programa de amostra ou teste do editor foi executado; não reaproveitar resultados
anteriores como validação de async. Nenhuma alteração no compilador/runtime.

Próxima etapa: implementar Etapa 1, núcleo C de Promessas/reações/filas e testes
sem I/O, seguindo docs/assincronismo.md. Antes do frontend (Etapa 2), fixar
representação paramétrica/assinaturas, inventário de travessias e verificador da
IR. Não iniciar integração HTTP sem validar DNS não bloqueante e callbacks.
Não publicar sem autorização. O trabalho anterior continua registrado abaixo.

---

# Servidor HTTP nativo — 17/11/2026

Solicitação ativa: novo anexo c654117f, auditoria e implementação de cgd:servidor
primeiro, com sockets opacos, HTTP/1.1, limites, rotas e documentação. Preservar
as oito bibliotecas da etapa anterior, o livro e alterações locais. Sem push.
O novo anexo solicita testes por etapa; a autorização de execução será usada
apenas na validação específica desta implementação, sem repetir a matriz geral.

Auditoria: cgd:rede é cliente libcurl; não fornece servidor. ABI gerenciada usa
valores tagged e GC Boehm; curl já usa recurso opaco com finalizador de segurança.
Não reutilizar a tag de curl para sockets. Adicionar tag no fim da enumeração,
preservando valores da ABI anterior. Destrutores são explícitos: close idempotente
é obrigatório e finalização GC é apenas contingência. Exceções usam longjmp:
nenhum recurso temporário sem dono pode sobreviver a uma alocação que lança.
Runtime atual não garante segurança entre threads: servidor inicial sequencial,
sem prometer concorrência, TLS, HTTP/2 ou shutdown por sinais globais.

Implementação entregue nesta etapa (fases 1–3 do novo anexo):

- Transporte POSIX em vendor/delegua-runtime/src/sockets_posix.c e contrato
  sockets_interno.h. Tag opaca própria adicionada ao fim da enumeração da ABI,
  preservando tags antigas. Budget explícito de 128 sockets, nonblocking/CLOEXEC,
  poll com prazo monotônico, envio sem SIGPIPE, fechamento idempotente e
  finalizador GC apenas como contingência. TCP IPv4 numérico, sem DNS implícito.
- Parser puro em http_parser.c/http_interno.h; adaptação gerenciada em
  http_servidor.c. Headers/corpo com limites antes de alocar; uma requisição por
  conexão; rejeição de CL repetido/inválido, TE, Expect, folding, Host inválido,
  controles, caminhos/escapes proibidos. Date UTC, CL em bytes, HEAD sem corpo,
  status sem corpo e headers de transporte reservados. Não há arquivos servidos.
- bibliotecas/sockets.delegua: Conexao, OuvinteTCP e conectar. Sem FD público.
- bibliotecas/servidor.delegua: HTTP, Requisicao, Resposta, sete métodos, rotas
  por segmento, query com valores repetidos, middleware síncrono sem captura,
  JSON, 404/405/500, abrir/atenderUma/ativo/escutar/fechar e shutdown após resposta.
  Callback que lança não expõe sua mensagem ao cliente. Resposta inválida tenta
  500; conexão interrompida não encerra o listener. Conexões fechadas em finally.
- Registro estático via frontend/modules.d e assinaturas de Primitivas; nenhuma
  mudança em lexer, parser da linguagem, análise semântica ou CTFE.
- testes/servidor.py, sockets.py e http_parser.c/http_parser.py. Matriz recebe os
  contratos HTTP/TCP; scripts/sanitizadores.py --rede permite validar apenas API C
  e rede e sempre restaurar o runtime normal. Relatório próprio, sem sobrescrever
  o resultado da suíte completa anterior interrompida. Wrapper CC passa argv por
  execvp Python, sem construir comando de shell.
- scripts/benchmark_http.py: várias rodadas, conexões novas, latência/RPS, CPU,
  RSS de pico, inicialização e recuperação após mensagem inválida. Smoke test
  de duas rodadas/12 requisições/4 clientes passou; não é prova de desempenho.
- docs/servidor-http.md integra o livro (37 páginas); exemplo real em
  exemplos/servidor/http.delegua tem contrato de compilação. Teste dedicado faz
  end-to-end. README, compatibilidade e índice de exemplos apontam para o guia.

Testes realmente executados nesta etapa:

- Runtime C99/Clang com warnings estritos e CGD LDC release: builds passaram.
- HTTP e sockets reais com/sem otimização: passaram. Incluem requisições parciais,
  framing hostil, header injection, 408/413/417/431, EOF, fechamento repetido,
  reuso de porta, teto de 128 recursos, desconexões, 16 clientes simultâneos
  atendidos sequencialmente e shutdown. Não afirmam atendimento concorrente.
- Parser puro: regressões e 50000 entradas pseudoaleatórias limitadas com
  ASan/UBSan passaram. Corpus determinístico não substitui fuzzing contínuo.
- scripts/sanitizadores.py --rede: API C antiga, parser puro e contratos HTTP/TCP
  passaram com ASan/UBSan; runtime normal restaurado. LeakSanitizer desabilitado
  por causa do GC; não afirmar ausência de vazamentos comprovada universalmente.
- 407 verificações de integração e 132 exemplos/264 verificações passaram.
- Livro: 37 páginas, links, recursos e índice de busca passaram. Ruff nos scripts
  novos/runner sanitizado passou. Não foi repetida a matriz completa DMD/LDC2 ×
  debug/release × GCC/Clang nem o navegador Chrome nesta etapa.

Instalação autorizada: CGD 0.8.0 em ~/.local/bin/cgd (prefixo
~/.local/share/cgd), runtime normal e 19 bibliotecas. Extensão
fernandothedev.cgd 0.8.0 com LSP local/bibliotecas/runtime, pacote
out/cgd-0.8.0.vsix e associação \*.delegua. Recarregar a janela do VS Code para
substituir o processo LSP já aberto. Nenhum commit/push/publicação remota.

Pendências reais do novo anexo (não entregues como APIs fictícias): UDP/sockets
locais, DNS/IPv6 do transporte, keep-alive/chunked/streaming/WebSocket/SSE,
multipart/upload/TLS/HTTP2/compressão e atendimento simultâneo. O servidor é
sequencial e não garante proteção contra inundação/distribuição de conexões.
Shutdown é explícito, sem instalação global de signal handlers ou threads.
Fase 4: ampliar Tempo com calendário, logs estruturados (reusar cgd:log, evitando
namespace duplicado), fluxos/bytes e criptografia com biblioteca auditada.
Ambiente básico já existe. OpenSSL 3.5.8, SQLite 3.51.2 e zlib foram encontrados,
mas nenhuma dependência/API dessas bibliotecas foi acrescentada nesta etapa.
Fase 5 e demais módulos prioritários seguem pendentes. Concorrência exige estudo
Boehm/longjmp/estado global: não expor threads sobre valores compartilhados sem
contrato. Não considerar o documento inteiro concluído só pelo MVP HTTP.

Próximos comandos úteis:
python3 testes/servidor.py; python3 testes/sockets.py;
python3 testes/http_parser.py; python3 scripts/sanitizadores.py --rede;
python3 scripts/benchmark_http.py --rodadas 5 --requisicoes 200 --clientes 8.
A publicação continua dependendo de autorização explícita neste novo pedido.

Etapa anterior: oito módulos (Processo/Ambiente/Sistema/Tempo/IO/Algoritmos/CLI/Log),
17 bibliotecas ao todo. Antes da interrupção do usuário, passaram os testes de
processos, oito exemplos (16 verificações) e unitários DMD/LDC2 (9 módulos cada).
Sanitizadores foram interrompidos a pedido: API C e integração 407 passaram,
mas a suíte completa não terminou. Não afirmar aprovação total. Instalação final
precisa ser refeita após incorporar os novos módulos.

---

# Stdlib de sistema — 17/11/2026

Pedido ativo: documento anexado de expansão arquitetural, começando por auditoria
e implementação funcional de Processo/Ambiente, com fundamentos nativos necessários.

Auditoria antes das alterações: módulos cgd: são resolvidos estaticamente em
frontend/modules.d, hoje com whitelist de nove módulos. Bibliotecas já usam
Primitivas via ABI gerenciada explícita: nenhuma mudança lexical é necessária.
main do runtime já preserva argc/argv em program_context; reutilizar esse contexto,
sem outro global público. Valores usam Boehm GC; recursos POSIX exigem fechamento
antes de construir resultados/lançar, pois exceções fazem longjmp. Destrutores
são explícitos, não callbacks do GC. Arquivo já lê/escreve/remove arquivos regulares;
Rede já encapsula libcurl e URI. Textos/coleções/matemática/estatística/caminhos são
reutilizáveis. Texto armazena bytes com tamanho mas seus índices são Unicode;
não apresentar vetor de inteiros como buffer nativo eficiente. CTFE aceita funções
marcadas e subconjunto primitivo: FFI/OS continuam fora da VM. Linux x86_64 é o
único alvo validado; APIs POSIX novas ficarão em módulos C próprios. Não alegar
Windows/macOS. Testes reais compilam amostras nos dois modos; exemplos têm contratos.

Decisão inicial: Processo síncrono com argv separado, poll simultâneo em stdout,
stderr e stdin, timeout e limite de bytes; shell separado e explícito. Ambiente
isolado no filho por sobrescritas, sem mudar o ambiente do pai. Processo persistente
será avaliado; não criar iniciar falsamente bloqueante. Preservar trabalho anterior
do livro e exemplos; nenhuma publicação autorizada nesta etapa.

---

# Livro e expansão dos exemplos — 17/11/2026

Solicitação ativa: fortalecer exemplos e contratos; recriar a documentação com um
livro no estilo Rust, syntax highlighting Delégua e textos mais naturais no guia,
site e README. Usado mdBook 0.4.52, já instalado; sem migração de hospedagem.

Implementado:

- Livro em docs/livro, configuração/tema em livro; capítulos preparados pelo
  scripts/gerar_livro.py a partir de linguagem.json, guias e exemplos reais.
- Busca, sumário, temas, navegação, cópia e impressão do mdBook; tema verde/escuro
  preservado. Gramática própria Delégua, sem aproximar pela gramática JavaScript.
- Conteúdo introdutório reescrito nos 25 capítulos, README e trechos do site;
  explicação de atributos/classes revisada. Catálogo de diagnósticos no livro.
- Novos exemplos Textos, Estatistica e Caminhos; Colecoes ampliado preservando
  os exemplos anteriores. Índice 36–40 e aviso antigo de suspensão corrigidos.
- Contratos históricos positivos agora verificam saída, negativos fixam fase e
  diagnóstico. E0001 genérico usa mensagem específica para não aceitar outra falha.
- Build reproduzível com --check; fontes intermediárias ficam em out. Recursos
  gerados pelo mdBook não são formatados/editados manualmente.

Validação final:

- 123 exemplos, 246 verificações com/sem otimização: sem falhas.
- Teste de cópias formatadas: 132 arquivos idempotentes e os 246 contratos passaram.
- Livro: 35 páginas, links/âncoras/recursos locais e índice de busca conferidos.
- Chrome desktop/mobile: busca real do livro, sumário, destaque Delégua, ausência
  de overflow e demais checks do site passaram. Capturas em out/site/livro-\*.png.
- --check do livro reconstrói em pasta temporária e compara todos os arquivos;
  saída determinística confirmada. Referência antiga sincronizada, política de
  tipos, formatadores próprios e git diff --check passaram.
- Não houve mudança no compilador/runtime; matriz e sanitizadores não foram
  repetidos. MiniGPT continua explicitamente com contrato de compilação/vínculo,
  sem afirmar validação do treino completo.

Nenhum push nesta etapa. Fontes e saída do livro estão prontas para o Pages em
`dev/docs`, preservando a página antiga e seus links. Próximos comandos úteis:
python3 scripts/gerar_livro.py --check; python3 testes/livro.py;
python3 testes/site.py. Para atualizar conteúdo, edite as fontes, regenere
referência/livro e valide; não edite docs/livro manualmente.

---

# Avaliação dos exemplos — 17/11/2026

Pedido: avaliar o catálogo existente. Inspeção estática de organização, contratos,
runner e amostras; nenhuma suíte repetida e nenhuma publicação nesta avaliação.
Inventário: 120 fontes, 40 didáticos de linguagem, 15 de compilador, 13 CTFE,
18 de erros/segurança, 7 de bibliotecas, 2 de módulos e demais aplicações/históricos.
Pontos principais: aplicações maiores exercitam integração, mas não substituem
regressões mínimas; contratos históricos por status precisam de fase/código;
MiniGPT testa apenas compilação; README tem índice incompleto (36–40) e aviso
obsoleto de testes suspensos. Bibliotecas recentes merecem exemplos dedicados.
Resultados de 240 verificações pertencem à execução anterior, não a esta análise.

---

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
- CGD publicado em origin/dev: 0f2f966, com os exemplos, contratos, evolução da
  linguagem/stdlib/LSP e ponteiro do runtime atualizado para 7833699. Ambos os
  pushes foram confirmados pelo Git. Formatação completa passou e árvores ficaram
  limpas após a publicação. Este registro é versionado em commit documental seguinte.
- Não há push pendente desta solicitação. Não repetir a matriz sem mudanças relevantes.

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
