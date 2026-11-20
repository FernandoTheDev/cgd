# Assincronismo nativo do CGD

Data: 18/11/2026. Projeto das Etapas 0–5 e implementação experimental de
async/await, handlers, cancelamento, reactor, timers, HTTP e TCP. As seções 1–15
especificam o modelo alvo; as seções 16–17 registram a evolução. As mudanças de
18/11 ainda não foram testadas por instrução do usuário. Não declarar estabilidade.
A preparação das rotinas está descrita em [rotinas.md](rotinas.md).

O CGD é uma implementação própria do perfil compilado de
[Delégua](https://github.com/DesignLiquido/delegua), com extensões explícitas;
não representa o interpretador oficial. Autoria e licença Apache-2.0 dos projetos
continuam preservadas. O runtime permanece no submódulo delegua-runtime.

## 1. Escopo e decisões de base

A primeira entrega será assincronismo cooperativo em uma thread Linux x86_64,
com funções stackless, Promessas nativas, microtasks e reactor. Uma chamada
assíncrona não cria thread. Capturas externas continuam proibidas; argumentos e
receptores são a passagem explícita de dados. Aliasing entre tarefas da mesma
thread continua possível quando o programa passa o mesmo objeto: execução
sequencial de segmentos evita data races nativas, mas não elimina interferência
lógica entre pontos de suspensão.

O runtime possui um pool interno Linux que entrega resultados de callbacks C
ao reactor. A execução de funções Delégua nos workers depende da auditoria de
threads e da validação do assincronismo. Canais, grupos, M:N e stacks próprias
permanecem em etapas futuras. Consulte [rotinas.md](rotinas.md).

Decisões propostas para fixar o contrato antes do código:

| Tema            | Decisão                                                               |
| --------------- | --------------------------------------------------------------------- |
| Sintaxe         | `assincrona` como modificador de função/método; `aguardar` prefixo    |
| Resultado       | assinatura declara T; chamada produz Promessa<T>                      |
| Início          | execução imediata até primeira suspensão ou conclusão                 |
| Await           | somente em corpo assíncrono, inclusive quando o operando já terminou  |
| Operando        | somente Promessa nativa; qualquer exige verificação dinâmica          |
| Retorno         | retorna T; delegação exige `retorna aguardar outra()`                 |
| Cancelamento    | pedido cooperativo sobre tarefa proprietária; não sobre dependências  |
| Finalmente      | pode suspender; cancelamento fica mascarado durante limpeza           |
| Microtasks      | FIFO drenada integralmente em cada checkpoint                         |
| Módulos         | inicialização síncrona, sem await no topo                             |
| Entrada         | executar raiz síncrona, depois drenar loop no runtime                 |
| Compatibilidade | APIs síncronas preservadas; novas APIs têm nomes/importações próprios |

Essas decisões são normativas para a implementação proposta. Mudá-las exige
atualizar este documento e os testes correspondentes antes de mudar o código.

## 2. Auditoria do estado existente

Base inspecionada: CGD `abe4290`, runtime `7833699`, **mais alterações locais**.
Os hashes não reproduzem sozinhos o estado auditado: bibliotecas de sistema,
sockets e servidor HTTP estão modificadas/não versionadas. Nenhuma dessas
alterações foi revertida. Não houve commit ou publicação nesta etapa.

| Área e fontes                                                                 | Representação observada                                                                                             | Reuso e lacuna                                                                                      |
| ----------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| `frontend/lexer/token.d`, `keywords.d`; `parser/parse_decl.d`, `parse_expr.d` | tokens próprios, declaração FnDecl e FunctionExpr; métodos com isStatic                                             | acrescentar Async/Await, sem tratar async como chamada comum                                        |
| `parser/ast.d`                                                                | AST compartilhada por validação, semântica, otimização, lowering e editor                                           | acrescentar marcador de função e nó AwaitExpr; atualizar todas as travessias                        |
| `type_expr.d`, `parser/parse_type.d`                                          | tipos nomeados, arrays, tuplas; nenhum argumento genérico                                                           | Promessa precisa de representação sintática própria e leitura de `<T>` em contexto de tipo          |
| `type_sema.d`, `type_registry.d`, `type_resolver.d`                           | tipos builtin, array, tupla e classe; `funcao` sem assinatura paramétrica completa                                  | adicionar Promise e contrato de chamada assíncrona, sem reduzir Promessa a qualquer                 |
| `semantic/pipeline.d`, `analyzer.d`, `context.d`                              | declarações, resolução, segurança, pureza e fluxo comuns à CLI/LSP; capturas recebem aviso e erro                   | reusar identidade de vínculos e contexto lexical; separar retorno interno T de resultado da chamada |
| `semantic/flow.d`                                                             | análise conservadora de término e caudas, sem CFG/vivacidade                                                        | necessária análise nova por arestas normais e excepcionais                                          |
| `middle/lowering.d`                                                           | reescrita recursiva AST → chamadas de runtime; preserva curto-circuito                                              | insuficiente para suspensões; introduzir IR assíncrona antes da emissão C                           |
| `middle/rewrite.d`, `opt/pass_manager.d`, `ctfe/`                             | travessias e otimização até ponto fixo; CTFE de funções elegíveis                                                   | Await é efeito/barreira; funções assíncronas não entram na VM                                       |
| `backend/c/codegen.d`, `lvalue.d`                                             | materialização ordenada, funções C com argc/argv, variáveis tagged, contratos e descritores estáticos               | reusar avaliação e contratos; emitir wrapper e step próprios para async                             |
| `runtime/src/objetos.c`                                                       | função contém ponteiro C, aridade mínima/máxima, receptor ligado e decoradores; objetos têm classe e mapa de campos | wrapper async conserva ABI de chamada; não há ambiente de closure lexical a reutilizar              |
| `runtime/src/excecoes.c`, `delegua_rt.h`                                      | cadeia active, setjmp/longjmp, profundidade global; backend duplica limpeza nas saídas                              | nunca preservar jmp_buf como continuação; handlers suspensos serão dados da IR                      |
| `runtime/src/interno.h`, `delegua_rt.h`                                       | rt_alloc usa GC_MALLOC; texto usa alocação atômica; delegua_value é tagged com referências                          | frames e listas precisam de memória rastreada; buffers sem ponteiros podem ser atômicos             |
| `runtime/src/delegua_rt.c`                                                    | GC_INIT, contexto, delegua_main, liberação de contexto, saída                                                       | integrar loop após raiz e antes de liberar contexto; preservar programa síncrono                    |
| `runtime/src/rede.c`                                                          | curl_easy_perform síncrono; lote usa curl_multi_perform/poll até terminar                                           | reusar opções, limites, TLS e conversão; lote atual não é async da linguagem                        |
| `sockets_posix.c`, `http_servidor.c` locais                                   | descritores nonblocking opacos, mas API espera com poll/prazos dentro da chamada                                    | reusar validações/close; separar iniciar/tentar/registrar, sem chamar espera síncrona pelo reactor  |
| `processo_posix.c`, `sistema_posix.c`; bibliotecas processo/tempo             | poll de pipes/waitpid e dormir síncronos                                                                            | manter contratos; processos assíncronos ficam para extensão posterior                               |
| `frontend/modules.d`, `analysis.d`, `lsp/`                                    | módulos estáticos, buffers por revisão, análise sem codegen/CTFE/processos                                          | namespace assíncrono estático; editor usa mesmos tipos e diagnósticos                               |

Pontos críticos confirmados pela leitura:

- `compileFnDecl()` emite função retornando delegua_value e materializa `isto`
  em métodos não estáticos. `functionValue()` cria função com aridade; referências
  indiretas passam por `delegua_chamar()`. Isso permite devolver uma Promise pela
  ABI atual, mas exige metadados novos para contratos de retorno e editor.
- `compileTry()` e `cleanupCode()` implementam pegue/finalmente com frames C.
  Mesmo quando delegua_try_frame é alocado no GC, seu jmp_buf referencia uma
  ativação C. Retomar esse frame depois de retornar seria inválido.
- Destrutores são explícitos e possuem proteção de reentrada em objetos.c.
  Sair de um escopo não chama destrutor automaticamente. Async não introduzirá
  destruição automática de objetos do usuário; operações nativas têm limpeza
  interna obrigatória e o programa continua usando finalmente para fechar recursos.
- active, delegua_call_depth, localização atual e contadores nativos são estado
  global. Uma thread simplifica acesso, mas cada step ainda precisa salvar e
  restaurar contexto antes de entregar o controle a outra tarefa.
- pkg-config local informou Boehm 8.2.6 e headers libcurl 8.22.0-DEV. Isso não
  verifica versão carregada, resolvedor DNS ou configuração de threads do GC.
  Não houve execução de programa para validar essas propriedades nesta etapa.

## 3. Gramática e contextos

Delta EBNF sobre a gramática existente (bloco, parâmetros e expressões mantêm
suas regras atuais):

```ebnf
declaracao_funcao = ["assincrona"], palavra_funcao, nome,
                   "(", parametros, ")", [":", tipo], bloco ;
expressao_funcao = ["assincrona"], palavra_funcao,
                  "(", parametros, ")", [":", tipo], bloco ;
metodo = [modificador_estatico], ["assincrona"], nome,
         "(", parametros, ")", [":", tipo], (bloco | assinatura_abstrata) ;
unaria = "aguardar", unaria | unaria_existente ;
tipo_primario = "Promessa", "<", tipo, ">" | tipo_primario_existente ;
```

palavra_funcao inclui os aliases atuais funcao/função. A grafia nova inicial é
assincrona, sem aliases ingleses. `aguardar f().campo` aguarda o resultado da
expressão de chamada/acesso; `(aguardar f()).campo` acessa o valor resolvido.
`aguardar a + b` significa `(aguardar a) + b`. O parser deve tratar fechamentos
de `Promessa<Promessa<inteiro>>` em contexto de tipo sem alterar shifts em
expressões. Promessa é construtor de tipo intrínseco, não genéricos arbitrários
de classes. `Promessa<T>[]` é válido. Promessa sem T em anotação é erro.

Métodos seguem a sintaxe de classe existente, sem palavra funcao. Ordem inicial:
estatico assincrona nome(). Blocos de visibilidade continuam externos ao método.
Arrows assíncronas são adiadas; funções anônimas assíncronas com funcao atendem
callbacks sem introduzir outra precedência.

Permitido: aguardar em laços, condicionais, argumentos, retornos, pegue e
finalmente dentro do corpo async. O contexto reinicia em cada função aninhada:
uma função síncrona interna não herda permissão de aguardar.

Proibido: aguardar no topo do programa/módulo, defaults de parâmetros,
inicializadores de atributos, decoradores, construtores, destrutores, getters e
setters. Construtores e destrutores não podem ser assincronos; fábricas async
explícitas podem construir objetos. Assinaturas FFI não podem receber modificador
async: uma ABI escalar não vira operação não bloqueante por anotação. Métodos de
interfaces/abstratos podem declarar async; implementação e override devem manter
o efeito e o contrato de resultado.

Adicionar palavras-chave é uma quebra lexical para identificadores homônimos.
Antes da Etapa 2, inventariar fontes/bibliotecas e documentar migração; não
reinterpretar código silenciosamente.

## 4. Tipos e regras de chamada

Escrevemos Γ ⊢ e : T para tipagem e A para contexto de corpo assíncrono.

```text
assincrona f(args): T  ⇒  tipo de chamada f(args) = Promessa<T>
Γ ⊢ p : Promessa<T>, contexto = A  ⇒  Γ ⊢ aguardar p : T
Γ ⊢ retorna e, corpo async com retorno T  ⇒  e deve satisfazer T
```

Promessa<T> é invariante. Promessa<inteiro> não satisfaz inteiro nem
Promessa<Objeto>. Uso de qualquer mantém guardas dinâmicas, inclusive contrato
do valor resolvido. Preservar descritor de T na Promise e nas fronteiras de
variáveis, campos, parâmetros, retornos e coleções; não validar apenas a tag.
Promessa<vazio> resolve internamente nulo; aguardar como comando é permitido,
usar seu resultado em posição que exige valor recebe diagnóstico.

Uma função async com retorno T verifica T quando completa, não contra a Promise
externa. Retorno implícito conserva a regra atual da linguagem: aviso de fluxo
quando aplicável e verificação dinâmica correspondente, sem inventar default.
`retorna p` onde p é Promessa<T> não substitui `retorna aguardar p` quando o
retorno declarado é T. Um retorno explicitamente Promessa<T> produz
Promessa<Promessa<T>>; não há assimilação automática no retorno de funções.

O operando qualquer de aguardar deve ser uma Promise nativa em execução;
caso contrário lança Excecao. Valores comuns e objetos com método entao não são
assimilados. Essa é uma diferença deliberada em relação ao await JavaScript.

Funções síncronas podem criar, receber, armazenar e devolver Promessas, registrar
entao/capturar e iniciar funções async. Não podem bloquear para obter seu valor
nem executar o loop recursivamente. Uma função síncrona que retorna Promessa<T>
é distinta de uma função async que retorna T.

O builtin funcao atual não expressa toda essa assinatura. Acrescentar metadados
de efeito, parâmetros e retorno aos símbolos de funções/métodos; chamadas
indiretas conhecidas usam esses dados. Nas desconhecidas, resultado qualquer
passa por validação nativa. O LSP não deve prometer uma assinatura inventada.

Avaliar callee, receptor e argumentos da esquerda para a direita antes de entrar
no corpo. Erro nessa avaliação e erro de aridade de delegua_chamar permanecem
síncronos. Depois de criada a Promise no wrapper, defaults, contratos dos
parâmetros e execução do corpo falham por rejeição. Falha irrecuperável de
alocação antes de criar a Promise não ganha garantia de rejeição.

## 5. Ciclo de vida e Promessas

Promise e ativação são entidades diferentes. Uma Promise contém estado
PENDENTE, RESOLVIDA ou REJEITADA, descritor de resultado, valor/erro, localização
da falha, reações FIFO e observação. Uma ativação contém pc, handlers, conclusão
pendente, slots vivos, referência à Promise de saída e cancelamento. Promessas
resolvidas manualmente não precisam de ativação.

Transição terminal é única. Há também trava interna de resolução: adotar outra
Promise mantém PENDENTE, mas impede outro resolve/reject de ganhar. Autoadotar
ou criar ciclo na cadeia de adoção rejeita com Excecao; atravessar a cadeia deve
ter limite de recursos. Após terminal, liberar reações destacadas e referências
que não sejam resultado/erro ainda observáveis.

API inicial proposta:

| API                       | Contrato                                                              |
| ------------------------- | --------------------------------------------------------------------- |
| Promessa.resolvida(valor) | devolve Promise terminal; reações sempre diferidas                    |
| Promessa.rejeitada(erro)  | normaliza erro como Excecao e devolve Promise rejeitada               |
| p.entao(callback)         | nova Promise; callback recebe resultado; rejeição é encaminhada       |
| p.capturar(callback)      | nova Promise; callback recebe Excecao; sucesso é encaminhado          |
| p.cancelar()              | logico: indica novo pedido aceito por uma ativação proprietária ativa |

Callback executa em microtask e não captura léxico externo. Método ligado pode
conservar receptor explícito. Se callback devolve Promise nativa, a Promise de
encadeamento adota seu destino; se devolve valor, resolve; se lança, rejeita.
Não assimilar objetos arbitrários. A tipagem do encadeamento usa retorno do
callback conhecido; qualquer exige contrato em execução.

Não expor executor com closures de resolução nesta primeira API. A resolução de
operações nativas pertence a primitivas controladas; ponteiros e continuadores
C permanecem internos. cancelamento de Promise sem ativação proprietária,
incluindo Promise terminal, retorna falso; não simular cancelamento de valor.

Combinadores entram depois da base: todas preserva ordem dos resultados e
rejeita na primeira falha observada; corrida segue primeira conclusão;
qualquer resolve no primeiro sucesso e agrega falhas em ordem de entrada;
todasResolvidas retorna registros de estado na ordem de entrada. Entrada deve
ser coleção de Promessas nativas. Casos vazios: todas/todasResolvidas resolvem
vetor vazio, qualquer rejeita erro agregado, corrida permanece pendente. Perder
uma corrida não cancela operações compartilhadas. Cada combinador instala
observadores nas entradas antes de permitir notificação; nenhuma reação inline.

## 6. Ordem de execução e Event Loop

Uma chamada async executa imediatamente seu segmento inicial. Toda ocorrência
de aguardar suspende e retorna ao chamador, mesmo com Promise já resolvida ou
rejeitada. O primeiro segmento pode terminar sem suspensão: devolve Promise
terminal e continuações ainda passam pela fila. Sem preempção; código CPU longo
e chamadas síncronas bloqueantes impedem progresso do loop.

Componentes: fila FIFO de eventos prontos, fila FIFO de microtasks, heap mínimo
de temporizadores por (prazo monotônico, sequência), reactor epoll e registro
fortemente enraizado de ativações/operações pendentes. Não criar fila adicional
de tarefas com uma prioridade indefinida.

Algoritmo do loop:

1. Ao retornar a raiz síncrona, executar checkpoint de microtasks.
2. Enquanto houver microtasks, retirar e executar uma, incluindo as anexadas
   durante essa drenagem. Cada execução salva/restaura contexto de diagnóstico.
3. No fim da drenagem, registrar rejeições não observadas para diagnóstico.
4. Coletar timers vencidos em ordem (prazo, sequência). Consultar epoll com
   timeout zero se já houver eventos prontos; caso contrário, esperar até o
   próximo prazo ou evento. Tratar EINTR recalculando o prazo monotônico.
5. Eventos de I/O do mesmo lote são ordenados pelo identificador de registro;
   anexar primeiro timers vencidos, depois I/O, à fila pronta. Eventos que já
   estavam na fila permanecem à frente. Não prometer ordem entre chegadas reais
   em instantes diferentes.
6. Retirar um evento pronto, avançar operação limitada e realizar novo checkpoint.

Uma reação já registrada é enfileirada quando a Promise termina; reação nova
em Promise terminal é anexada ao fim das microtasks. Retomada de await é uma
dessas reações. Nenhuma resolução chama código Delégua recursivamente.

Exemplo de ordem normativa: a raiz escreve A, chama função async que escreve B,
aguarda Promessa.resolvida(1), depois escreve D; a raiz escreve C. Saída:
A, B, C, D. `TempoAssincrono.dormir(0)` é evento de timer e fica depois das
microtasks já prontas.

Drenagem integral pode causar starvation se o programa gerar microtasks
infinitamente; não haverá quota silenciosa que mude essa ordem. Limites de
memória/pendências devem rejeitar novas operações com erro explícito. As quotas
de operações por callback de I/O são separadas da ordem de microtasks.

O único bloqueio legítimo de espera de I/O no loop é epoll_wait quando não há
trabalho pronto. Usar level-triggered inicialmente. Ler/escrever até EAGAIN ou
budget por evento; nesse último caso, registrar continuação justa na fila pronta.
Não tratar regular files como sockets assíncronos por terem descritor.

## 7. IR, vivacidade e lowering

Introduzir módulos próprios, por exemplo middle/async_ir.d, async_lowering.d e
liveness.d; nomes são propostos, arquivos ainda não existem. O fluxo futuro:

```text
lexer/parser → módulos → validação → semântica/fluxo/segurança
→ otimização AST opcional com barreiras de efeito
→ normalização ordenada → CFG async → vivacidade → layout do frame
→ emissão C99 de wrapper/step (síncronas mantêm caminho existente)
```

O lowering existente de operações será fatorado/reutilizado pela normalização;
não executar uma reescrita que apague vínculos, tipos ou posições necessários à
análise. Ordem exata entre normalização e lowering de operadores deve ficar
fixada no primeiro teste da IR. --verificar e LSP param na análise semântica.

IR por função: blocos identificados, temporários tipados, locais por identidade
resolvida, descritores de localização, região lexical, região de exceção e arestas
normais/excepcionais. Instruções: avaliar, copiar, contrato, chamada, acesso,
escrita e manipulação de handlers. Terminadores: salto, desvio, suspender,
concluir e lançar. Suspender contém operando Promise, destino do resultado,
sucessores de sucesso/falha/cancelamento e geração de espera.

Normalizar expressões em operações sequenciais antes de separar estados.
Em `f(a(), aguardar b(), c())`, materializar f e a, iniciar b, suspender, recuperar
valor, então avaliar c. Em atribuição indexada, persistir receptor e índice se
vivos, sem refazer getters. Curto-circuitos, coalescência, ternário, laços,
compreensões, interpolação e spreads mantêm seus ramos e efeitos. Não guardar
ponteiro para elemento de vetor que possa realocar durante suspensão: guardar
container/índice e aplicar a escrita segundo o contrato de avaliação original.

Calcular ponto fixo sobre CFG incluindo caminhos excepcionais e finalmente:

```text
OUT[b] = união de IN[s] para sucessores s
IN[b]  = USE[b] união (OUT[b] menos DEF[b])
```

Promover ao frame apenas vínculos/temporários que atravessam suspensão, além de
metadados obrigatórios de controle. Defaults, receptor e argumentos só persistem
quando vivos; o wrapper consome/copía argv antes de devolver controle, sem
reter ponteiro para argv do chamador. Referências em handlers e conclusões
pendentes entram em USE. Um slot morto pode ser limpo após seu último uso;
isso não autoriza descartar sua inicialização ou atribuições com efeitos.

Frame esquemático C99, sem ABI pública nova de callbacks para a linguagem:

```c
struct exemplo_frame {
    unsigned pc;
    unsigned status;
    size_t wait_generation;
    delegua_value output;
    delegua_value pending_completion;
    const delegua_local *location;
    /* handlers, cancelamento e somente os slots vivos nesta função */
};
```

Wrapper conserva `delegua_value f(sz argc, delegua_value *argv)` e devolve a
Promise. Step tem ponteiro de frame interno e roda switch(pc) em laço até
suspensão/conclusão; saltos internos não precisam recursão C. await registra
reação e estado seguinte antes de devolver. Nunca usar stack C ou jmp_buf como
continuação. Recursão async antes de primeira suspensão ainda consome stack C;
preservar limite de profundidade e diagnóstico atual, sem alegar stack constante.

Estado de ativação: EXECUTANDO → SUSPENSA → PRONTA → EXECUTANDO, ou FINALIZADA.
Uma espera carrega identidade e geração. Evento obsoleto é ignorado; reação só
transita SUSPENSA uma vez; fila não insere ativação já PRONTA; step rejeita
reentrada; FINALIZADA nunca retoma. Verificador da IR confere sucessores, tipos,
definições dominantes e slots necessários em toda suspensão.

## 8. Exceções, finalmente e cancelamento

Cada invocação de step instala uma fronteira C de exceção **válida somente
durante essa invocação**. longjmp de primitivas síncronas é capturado nela,
convertido em conclusão excepcional e roteado pela tabela/stack de handlers da
IR. Antes de suspender/concluir, remover a fronteira e restaurar active,
profundidade e localização do chamador. Não copiar active entre tarefas.
Locais C modificados após setjmp e lidos no erro precisam obedecer às regras C
de volatile ou residir no frame; revisar isso no backend e testar com otimização.

Conclusão explícita: NORMAL, RETORNO(valor), FALHA(erro), SALTO(destino),
CANCELAMENTO(erro). finally recebe a conclusão pendente, pode suspender e,
quando termina normalmente, a restaura. Return/throw/break/continue de finally
substituem a conclusão como no contrato síncrono; falha de limpeza substitui
falha anterior, preservando-a como contexto de diagnóstico sem imprimi-la duas
vezes. finally entra uma vez por saída da região, inclusive em cancelamento.

Rejeição de operando await segue a aresta excepcional na localização de await,
com origem da falha preservada separadamente. pegue recebe Excecao pelo contrato
existente. Localização usa descritores estáticos; renderizar só no erro.

Cancelar marca um pedido idempotente. Pontos seguros: início de step e retomada
de await, nunca instrução C arbitrária. Cancelar ativação suspensa invalida sua
reação de espera, agenda retomada com Excecao de cancelamento e inicia unwind.
Se sucesso já foi enfileirado mas step ainda não começou, pedido de cancelamento
ganha no ponto seguro. Se tarefa já concluiu, pedido retorna falso.

O cancelamento é injetado uma única vez, pode ser tratado por pegue e não cancela
a Promise aguardada, que pode ter outros consumidores. Durante finally iniciado
por unwind, mascarar nova injeção até completar a limpeza; awaits de limpeza
podem portanto demorar indefinidamente. Não prometer timeout forçado seguro.
Se pegue consumir cancelamento e terminar normalmente, a tarefa pode resolver.

Uma operação nativa tem dono e cancel hook idempotente. Cancelar sua própria
tarefa remove interesse no reactor, solta recursos e rejeita sua Promise;
cancelar um consumidor não fecha recurso compartilhado do produtor. Callbacks
curl/OS não podem executar código Delégua nem longjmp através de frames de
biblioteca: registrar código de erro/abortar pelo retorno nativo e converter em
rejeição depois de sair da biblioteca. Inclusive falhas de alocação exigem essa
disciplina; os callbacks atuais devem ser auditados antes de reuso.

## 9. Encerramento e rejeições não observadas

Após a raiz síncrona, loop drena tarefas iniciadas, mesmo sem variável guardando
sua Promise. Registro de ativações é raiz de GC até finalizar. Não criar tarefa
órfã esquecida porque o usuário descartou o resultado.

Registrar rejeição como observada quando existe await, capturar ou encadeamento
que a encaminha para outra Promise. No último caso, responsabilidade passa ao
destino: entao sem tratador não suprime erro. No checkpoint, marcar rejeição
terminal sem observador como candidata; observador posterior antes do shutdown
retira a candidatura. No encerramento, renderizar candidatas em ordem de criação
e sair com falha. Não interromper outras limpezas na primeira rejeição candidata.

Se não há trabalho pronto, timer ou registro de I/O capaz de progredir, mas há
ativação suspensa, diagnosticar falta de progresso. Solicitar cancelamento das
ativações, drenar limpezas possíveis, reportar pendências restantes e sair com
falha; não girar em busy-wait nem declarar sucesso. Promise pendente isolada
sem consumidor/ativação, como corrida vazia descartada, não mantém loop vivo.
Rejeições não observadas continuam contabilizadas até shutdown.

Operação de I/O registrada pode nunca terminar: o programa permanece ativo até
deadline/cancelamento explícitos. Saída abrupta por sinal/abort não garante
finally. Falha síncrona não capturada na raiz deve passar pela fronteira externa
do runtime futuro: cancelar/drainar tarefas antes de reportar; manter ABI C antiga
de delegua_falhar fora desse contexto. Falta de memória fatal pode impedir limpeza.

## 10. GC, recursos e ABI

Frames, Promessas, reações e nós de filas usam GC_MALLOC/rt_alloc rastreado,
nunca GC_MALLOC_ATOMIC quando contêm referências. O loop permanece alcançável
por raiz global/contexto durante toda a execução. Registro liga operação →
Promise → frame/reações; uma fila nativa alocada com malloc não é raiz suficiente.
Dados guardados em epoll.data ou CURLOPT_PRIVATE também precisam desse registro.
O coletor conservador pode reter memória; não prometer liberação imediata.

Desvincular reação cancelada da Promise produtora, limpar slots mortos e remover
operação terminal do registro. Ciclos sem raízes podem ser coletados; Promise
rejeitada candidata mantém erro até observação/relatório. Evitar criar histórico
ilimitado de frames para diagnóstico: referências de origem têm limite explícito.

FDs, CURL easy/multi e buffers externos têm proprietário e close determinístico;
finalizadores GC são apenas contingência. Remover registro epoll antes de close;
usar geração por registro para não aceitar evento de FD reutilizado. Cancel hook
e conclusão competem por uma única transição terminal na thread do loop.

Adicionar tag de Promise **ao final** da enumeração tagged, preservando números,
layout e símbolos C existentes. Adicionar descritor Promise em paralelo, mantendo
APIs antigas; expandir impressão, tipo de, igualdade por identidade, contratos,
clonagem (rejeitar clone de Promise), serialização e coleções com diagnósticos
consistentes. Não converter Promise para inteiro/ponteiro por FFI escalar.
ABI gerenciada pode transportar valor opaco com tag reconhecida, sem conceder
permissão de resolver ou retomar a partir de threads estrangeiras.

O modelo inicial não cria threads do CGD e não valida GC multithread. Antes da
fase paralela serão obrigatórios auditoria do build de Boehm, registro de threads,
roots/stacks, finalizadores, sincronização, publicação de memória e remoção de
globais inseguros. GC seguro não implica objetos livres de data races.

## 11. Temporizadores, sockets e libcurl

Não mudar `cgd:tempo.Tempo.dormir`, `cgd:rede` ou Processo.executar existentes.
Proposta de módulos novos: cgd:tempo_assincrono, cgd:rede_assincrona e
cgd:sockets_assincronos. Nomes de APIs HTTP definitivos precisam ser alinhados
às classes reais, não copiar HTTP.obter fictício por cima do servidor HTTP atual.

TempoAssincrono.dormir(ms): Promessa<vazio> valida inteiro não negativo e
overflow de prazo monotônico antes de registrar timer. Zero agenda próximo evento.
Cancelar remove timer; não usar sleep no callback. Empates usam sequência crescente.

Sockets: conexão, aceite, leitura e escrita com nonblocking/CLOEXEC, prazos,
EINTR/EAGAIN, EOF, envios parciais e orçamento por evento. Um leitor e um escritor
pendentes por conexão; tentativa duplicada rejeita explicitamente. Fechar rejeita
pendências uma vez; buffers permanecem vivos e envio recebe snapshot para evitar
mutação entre awaits. Preservar ausência de SIGPIPE. O teto síncrono atual de
128 sockets exige revisão/limite explícito antes de testar milhares de sockets;
milhares de timers não provam escalabilidade de rede.

HTTP cliente: um CURLM do loop, CURL easy por requisição, integração por
CURLMOPT_SOCKETFUNCTION e TIMERFUNCTION; epoll dispara curl_multi_socket_action
e depois curl_multi_info_read coleta conclusões. Respeitar pedidos de remover
socket e timer da libcurl. Sem laço curl_multi_poll interno aguardando o lote.
Reusar TLS, limites e opções seguras, sem compartilhar sessão easy ativa com
chamada síncrona, reset/opcao/fechar: definir posse exclusiva até concluir.
Callbacks internos apenas acumulam bytes limitados e registram falha.

DNS é condição de aceitação, não detalhe: API multi pode ainda bloquear na
resolução dependendo do build. Verificar curl_version_info em execução e
resolvedor usado. Preferir build com c-ares para cumprir ausência de threads de
espera por operação; não declarar HTTP/DNS não bloqueante apenas por usar multi.
Se incapaz de garantir resolução não bloqueante, rejeitar a API async nesse
ambiente com motivo claro, sem fallback bloqueante. Handshake TLS e protocolo
também exigem validação de responsividade com timers concorrentes.

Arquivos comuns e processos permanecem síncronos nesta primeira biblioteca.
Poll de pipes pode ser integrado depois; espera de filho deve usar estratégia
não bloqueante/reaping definida. Não anunciar arquivo async com read bloqueante.
Servidor atual continua sequencial até migração explícita posterior.

## 12. Ferramentas, diagnósticos e limites

CLI e LSP devem compartilhar regras via semantic/pipeline.d. Hover mostra
retorno declarado T e resultado Promessa<T>; inlay hints inferem Promessa<T>
sem editar texto. Completion após Promise usa membros próprios, nunca métodos
globais como fallback. Semantic tokens destacam novas palavras; formatter
preserva quatro espaços, strings e comentários. Não compilar/linkar por edição.

Catálogo diagnostics/catalog.d receberá códigos após conferir faixa livre:
await fora de contexto, operando inválido, modificador proibido, retorno
incompatível, override divergente, genérico inválido e função async marcada pura.
Não inventar códigos numéricos disponíveis sem registrá-los. Falhas dinâmicas
mantêm categoria R0001 inicialmente, com mensagem/origem de cancelamento,
rejeição ou falta de progresso. --explicar, JSON e tabela gerada acompanham catálogo.

Toda travessia com switch/final switch deve reconhecer AwaitExpr/Promise:
validação estrutural, módulos, semântica, fluxo, segurança, pureza, CTFE,
otimização, rewrite, backend, formatter, indexação e editor. Mesmo ramos
descartados passam pela semântica. Segurança estática mantém W31xx em pegue.
Não considerar await função pura e não executar event loop em hover/CTFE.

Antes de implementar, fixar budgets para frames, filas, timers, reações, operações
e bytes de corpo. Checar overflow e reserva antes de instalar operação; falha
de registro desfaz recursos parciais. Valores de quota devem ser centralizados,
documentados e testados nos limites; esta RFC não inventa limites sem medição.

## 13. Implementação incremental e estratégia de validação

| Etapa | Entrega e condição de avanço                                                                                               |
| ----- | -------------------------------------------------------------------------------------------------------------------------- |
| 0     | auditoria e contratos; sem scheduler/alteração da linguagem                                                                |
| 1     | núcleo C Promise/reação/fila, transição única, adoção, observação e limpeza; testes C sem I/O                              |
| 2     | tipos, lexer/parser/AST, semântica comum, CFG, vivacidade, wrapper/step; suspensão de Promise pronta e pendente controlada |
| 3     | timers, reactor, sockets e curl multi; verificar DNS e responsividade                                                      |
| 4     | cancelamento, finally suspenso, diagnóstico, encerramento, budgets, stress                                                 |
| 5     | regressão síncrona, longa duração, sanitizadores, benchmarks e documentação pública                                        |

Para cada etapa, executar apenas testes pertinentes até estabilizar mudanças;
matriz completa é gate da Etapa 5, não repetição a cada edição. Testar com/sem
otimização e DMD/LDC2, C99 Clang/GCC, debug/release nas mudanças de backend.
Não usar sleeps frágeis como prova de ordem: relógio/reactor falsos nos testes
unitários do loop e operações locais controladas nos testes de integração.

Regressões obrigatórias:

- Gramática, precedência, tipos aninhados, contextos aninhados, palavras antes
  usadas como identificadores e diagnóstico consistente CLI/LSP/--verificar.
- Ordem observável de callee/argumentos/getters/indexações, curta avaliação,
  aliases, escritas e inicializadores não utilizados; snapshots de stdout/erro
  devem distinguir comportamento incorreto, não apenas recompilação de fixtures.
- CFG/vivacidade: variável morta não ocupa slot; objeto, receptor, índice e
  conclusão pendente vivos sobrevivem a GC forçado entre suspensões. Validar
  efeitos de inicialização mesmo quando vínculo não fica no frame.
- Await aninhado, em laços/condicionais/compreensões/métodos, herança, funções
  recursivas e indiretas; argumentos opcionais/rest e retorno com contratos.
- Promise já resolvida/rejeitada, reações registradas antes/depois da conclusão,
  resolução dupla, adoção/ciclos, callback que lança, cadeia que encaminha falha,
  combinadores vazios e entradas fora de ordem.
- Tente/pegue/finalmente em múltiplos níveis; await em catch/finally; return,
  break, continue e throw com limpeza; cancelamento antes/depois da suspensão,
  sucesso já pronto, cancelamento tratado e falha durante limpeza.
- Reação duplicada, FD reutilizado, evento atrasado, close duplicado, cancel hook
  repetido, falha ao registrar; nenhuma retomada depois do estado terminal.
- Loop sem progresso, raiz que falha com tarefas vivas, rejeição observada tarde,
  erro encaminhado, recursos fechados e exit status coerente.
- Milhares de timers/Promessas pendentes e, com quota adequada, conexões locais;
  respostas HTTP parciais, timeout, DNS, TLS, EOF e cancelamento de transferência.
  Um timer deve disparar enquanto outro socket permanece sem responder.
- Longa duração: lotes repetidos com estabilização de contagem de FDs/registros,
  RSS e heap após coletas. Reportar duração, volume e pico reais; RSS conservador
  não demonstra sozinho vazamento. ASan/UBSan, API C anterior e política do GC
  para leak detection continuam documentados.
- LSP persistente: hover, assinatura, tokens, completion por receptor,
  formatação e diagnóstico, sem build ou loop do programa durante edição.

Benchmarks devem separar criação de Promise, custo de suspensão/retomada,
timers, latência do reactor e throughput HTTP. Registrar hardware, quotas,
versões carregadas, concorrência e distribuição de latência; comparação síncrona
usa a mesma carga local. Nenhum benchmark foi executado nesta Etapa 0.

Paralelismo continua bloqueado por critério técnico até todos os 14 itens de
estabilidade do pedido estarem cobertos: compilação, await em níveis diversos,
resolução/rejeição, exceções, locais, finally, loop responsivo, timers, I/O real,
recursos estáveis, cancelamento, longa duração, milhares de pendências e
regressão síncrona. Registrar evidências em CONTINUIDADE.md, sem antecipar suporte.

## 14. Decisões pendentes antes de codificar cada camada

Não há necessidade de aprovação remota ou de publicação para trabalho local.
As escolhas abaixo são tarefas de engenharia com evidência ainda necessária:

1. Confirmar versão carregada e backend DNS da libcurl; escolher dependência
   c-ares se o ambiente não satisfizer o contrato. Isso precede HTTP async.
2. Definir números dos budgets e faixa de diagnóstico; inventariar switches,
   símbolos chamados assincrona/aguardar/Promessa e todos os contratos de tipo.
3. Fixar esquema do descritor Promise<T> e metadados de callbacks/assinaturas,
   com testes negativos de qualquer e coleções, antes do parser da Etapa 2.
4. Prototipar no teste C da Etapa 1 a fronteira longjmp, contexto restaurado e
   erros sem salto através de callbacks externos; isso precede reuso de rede.c.
5. Especificar layout de IR/verificador e integração da normalização com
   materialize/LValue, medindo slots promovidos e mantendo caminho síncrono.
6. Alinhar nomes/classes dos módulos async à biblioteca existente e definir
   exclusividade de sessão, antes de publicar exemplos de usuário executáveis.

As decisões semânticas das seções anteriores permitem iniciar a Etapa 1 sem
improvisar await bloqueante. Esta entrega se encerra na Etapa 0 conforme a
instrução inicial do pedido; implementação e testes funcionais seguem pendentes.

## 15. Fontes primárias consultadas

Consulta em 17/11/2026, além dos fontes locais da seção 2:

- [ECMAScript: objetos Promise](https://tc39.es/ecma262/multipage/control-abstraction-objects.html#sec-promise-objects):
  referência conceitual para estados, reações e encadeamento. A proposta CGD
  não promete identidade semântica, em particular para valores comuns e thenables.
- [Interface C do Boehm GC](https://www.hboehm.info/gc/gcinterface.html) e
  `/usr/include/gc/gc.h` local: distinção entre memória rastreada/atômica,
  raízes e registro de threads. O projeto deve verificar o build efetivo.
- [Visão geral libcurl multi](https://curl.se/libcurl/c/libcurl-multi.html) e
  [CURLMOPT_SOCKETFUNCTION](https://curl.se/libcurl/c/CURLMOPT_SOCKETFUNCTION.html):
  integração de sockets/timers sob controle da aplicação; uso de multi não
  constitui por si só teste de ausência de bloqueio DNS.
- [epoll(7), Linux man-pages](https://man7.org/linux/man-pages/man7/epoll.7.html):
  readiness level-triggered, tratamento de descritores e integração do reactor.

Semântica de cancelamento, prioridades, IR e encerramento aqui definida é
proposta própria do CGD, não garantia fornecida por essas bibliotecas.

## 16. Histórico da Etapa 1: núcleo C sem I/O

Estado entregue antes da Etapa 2, descrita a seguir.

O runtime possui `src/assincrono.h` e `src/assincrono.c`, API interna
monothread C99. Os tipos rt_async_loop e rt_promise são opacos. Não houve
mudança na enumeração tagged, na ABI C existente, no main ou no compilador:
Promise ainda não é um delegua_value, e o núcleo não está exposto por FFI ou
Primitivas. A integração tipada e sua tag pertencem à Etapa 2.

Implementado:

- Criar/fechar loop e Promessas, resolver/rejeitar uma única vez, consultar estado,
  resultado terminal e localização. Rejeições normalizam valores como Excecao.
- Encadear callbacks C internos de sucesso/falha com contexto gerenciado,
  encaminhar resultados e falhas, adotar Promessas do mesmo loop, rejeitar
  autoadopção/ciclos na cadeia de adoção e limitar sua caminhada.
- FIFO de reações. Resolver apenas enfileira; checkpoint drena inclusive
  reações anexadas por callbacks. Adoção também termina através da fila,
  sem chamar consumidores inline ou recursão C por cadeia de reações.
- Fronteira setjmp/longjmp válida durante o checkpoint, instalada antes de
  modificar a fila. Falhas de callbacks rejeitam o destino; localização atual,
  API legada de localização e profundidade são restauradas. Origem da falha é
  copiada na Promise, inclusive quando vem da API legada, sem renderização.
- Raiz global de loops abertos, registro de Promessas pendentes/rejeições não
  observadas, filas e contextos rastreados pelo Boehm. Resultados concluídos e
  observados saem do registro; nós consumidos soltam referências.
- Encaminhar erro transfere a responsabilidade ao destino. Consultar valor não
  observa falha. O reporter C pode enumerar rejeições em ordem de criação e
  reconhecer explicitamente cada uma, sem alocar nova reação; isso permite
  reportar/encerrar mesmo com a quota de Promessas ocupada por erros.
- Quotas positivas fornecidas na criação: Promessas retidas no registro, reações
  pendentes/prontas e profundidade de adoção. Reservar reação ao registrar,
  não ao resolver. Falha de quota não registra destino, não observa fonte e não
  trava adoção parcialmente. Sem defaults globais de produção nesta etapa.
- Fechamento explícito somente sem pendências, reações e rejeições não observadas;
  reentrada no checkpoint, fechamento durante callback e adoção entre loops
  lançam erro capturável. Handles de loop fechado são rejeitados.

O contexto C de callback deve usar memória rastreada pelo GC para referências
persistentes; ponteiros para locais temporários do chamador não são continuação.
Essa API não cria threads e exige uso em uma thread. Tampouco aceita um jmp_buf
como estado persistente de tarefa.

### Verificação executada

`python3 testes/assincronismo.py` compila todos os fontes do runtime para pastas
isoladas em out/assincronismo, liga os testes novos e a suíte C anterior, sem
substituir libdelegua_rt.o nem a instalação do usuário. Requer a tabela curl
já preparada por build-runtime. O relatório resultado.json indica complete=true
somente quando todas as variantes terminam.

Passaram Clang sem otimização, GCC com núcleo/teste novos em O2 e Clang O1 com
NDEBUG e ASan/UBSan. A variante GCC usa O0 nos fontes anteriores: compilá-los todos com
O2 e -Werror encontrou avisos de fluxo em rede/textos, associados a helpers
panic sem noreturn. Eles não foram suprimidos e esses fontes não foram alterados.
Isso não equivale à matriz completa GCC/O2.

A suíte verifica ordem FIFO, callbacks nunca inline, registro tardio, rejeição e
recuperação, falha no callback, restauração do handler síncrono/localização,
adoção pendente/pronta, resolução dupla, ciclos, limites transacionais, reentrada,
fechamento inválido, rejeições sem observador e reconhecimento pelo reporter.
Inclui coletas forçadas entre registro/execução, 20000 ciclos sob quota de quatro
Promessas e cadeia de 12000 reações pendentes, sem recursão C de encadeamento.
A suíte da API C anterior e seus 23 modos de erro R0001 passaram nas mesmas
variantes. Clang-format e Ruff verificam os arquivos novos.
A suíte nova também integra vendor/delegua-runtime/tests/run.sh; a inclusão foi
conferida com shfmt e sh -n, sem substituir o runtime normal para executá-la.

ASan usa detect_leaks=0 e detect_stack_use_after_return=0, como o runner existente
do projeto, pois o GC não rastreia a fake stack do ASan como stack nativa. A
primeira tentativa sem esta segunda opção falhou no teste anterior de mapa após
GC; a execução com a configuração do projeto passou. Não afirmar prova universal
de ausência de vazamento nem teste de longa duração.

### Limites e próxima etapa

Ainda faltam descritores Promessa<T>, funções de linguagem, lexer/parser/AST,
vivacidade/IR e frames de suspensão; depois vêm timers, reactor, curl multi,
cancelamento de ativações, finally suspenso e encerramento integrado no main.
Não há combinadores, scheduler de tarefas prontas de I/O ou cancelamento neste
núcleo. O reporter apenas enumera/reconhece falhas: política de impressão e
exit status do programa pertence à integração futura. Ciclos de dependência
através de callbacks arbitrários não são detectados como ciclos de adoção;
falta de progresso será responsabilidade do loop integrado.

Próxima ação: Etapa 2, começando por tipos/contratos de retorno, diagnóstico de
contexto, inventário de travessias e IR verificável. Não habilitar async/await
como chamada bloqueante. Paralelismo continua condicionado à estabilização de
todo o modelo assíncrono.

## 17. Primeira entrega da Etapa 2: linguagem e suspensão

Há execução real de assincrona/aguardar no compilador, ainda com limites
experimentais. O exemplo executável
[41_assincronismo.delegua](../exemplos/linguagem/41_assincronismo.delegua) imprime
raiz, início, continua, 11: a função começa imediatamente, devolve sua Promise
e retoma depois da raiz. Não há espera bloqueante dentro de aguardar.

### Frontend e ferramentas

- Tokens Async/Await, marcador isAsync em FnDecl, AwaitExpr na AST e tipos
  sintático/semântico próprios de Promessa<T>. Arrays/tuplas podem conter o tipo,
  e fechamentos aninhados `>>` são separados apenas na gramática de tipos.
  Promessa é reservado como nome de tipo; assincrona/aguardar viram palavras-chave.
- A anotação de retorno continua descrevendo T; a chamada de função ou método
  async produz Promessa<T>. Promessas aninhadas exigem awaits distintos. Não há
  unwrap automático no retorno de função. Uso de qualquer tem guardas nativas.
  Promessa é invariante, com refinamentos dinâmicos sujeitos a todos os contratos.
- Metadados de chamadas conhecidas por referências imutáveis preservam o efeito;
  parâmetros funcao e demais chamadas desconhecidas continuam dinâmicos, com
  guardas em execução. Capturas de variáveis externas continuam recebendo
  W4001/E4001; receptor e argumentos são passagem explícita, sem clonagem implícita.
- E3301: contexto inválido; E3302: operando sem Promise; E3303: async puro/CTFE;
  E3304: efeito incompatível em contrato/override; E3305: lowering ainda ausente;
  E3306: consumo de resultado vazio como valor; E3307: orçamento da IR excedido.
  Tipos incompatíveis mantêm E3002 e falhas dinâmicas continuam R0001.
- CLI/LSP compartilham análise; hover mostra assincrona, T e Promessa<T>, dicas
  virtuais mostram tipos inferidos, tokens reconhecem as palavras/tipo e
  completion de uma Promise oferece entao/capturar, sem fallback global após ponto.
  Não há build, link, execução de tarefas ou CTFE de async durante a edição.
- O formatador lexical mantém quatro espaços e modificadores juntos; atualmente
  pode escrever `Promessa < inteiro >`, que é uma anotação válida equivalente.

### IR e emissão C99

middle/async_ir.d normaliza avaliações em instruções atômicas e cria CFG com
Evaluate, Jump, Branch, Await, Resume, Return e Throw. Vínculos usam identidade
resolvida e slots únicos; sombras lexicais não se confundem. Receptor, índices,
callee, argumentos e valores anteriores de atribuição composta são materializados
na ordem original, antes de qualquer suspensão subsequente.

Vivacidade por ponto fixo seleciona os slots que atravessam Await. Definições de
atribuições e incrementos entram no cálculo; um vínculo escrito novamente antes
de ser lido após suspensão não precisa do valor anterior no frame. Inicializadores
e escritas mantêm seus efeitos mesmo quando seu resultado não persiste.
O verificador inicial verifica intervalos, expressões sem await oculto e pareamento
de suspensão/retomada; verificação completa de dominância/tipos continua evolução.

O backend emite wrapper da ABI argc/argv e step com switch(pc). O frame rastreado
pelo GC contém pc e somente slots persistentes. Variáveis e temporários restantes
são locais C do step. Argumentos são consumidos no primeiro segmento, sem guardar
argv do chamador. Defaults são avaliados antes dos contratos, como nas funções
síncronas. Antes de suspender, salvar slots vivos; na retomada, recuperar valores
e limpar referências do frame que já não precisam permanecer enraizadas.

Limites atuais por função: 100000 instruções e slots, 2000000 fatos simultâneos
de vivacidade e 50000000 visitas de instrução/fato. Exceder gera E3307 na geração
C, sem stack trace de exceção D. --verificar e o editor não executam esse lowering.

### Runtime, tipos e ciclo de vida

DELEGUA_T_PROMESSA foi acrescentada no fim da enumeração, sem renumerar as tags
anteriores. Funções/métodos mantêm a ABI C de chamada; wrappers async devolvem
um valor tagged. O descritor estrutural preserva o resultado T, inclusive coleções
e classes. Registrar um vínculo mais restrito não pode apagar contratos de
aliases anteriores; resolução incompatível rejeita a Promise e resultados de
coleção mantêm suas restrições nas escritas posteriores.

Tarefas têm fronteira setjmp válida apenas enquanto o step está na stack C.
Uma suspensão nunca mantém jmp_buf de uma ativação retornada. Reações retomam
através da FIFO da Etapa 1, incluindo Promessas já prontas. Continuar/concluir
mais de uma vez é erro; o frame é desvinculado ao terminar. No erro, restaurar
localização/profundidade/handler do chamador. Propagação por await conserva
separadamente a localização do await e a origem da rejeição; o reporter imprime
uma nota de origem escapada, sem reimprimir a exceção nem reter a cadeia de frames.

O loop do programa é criado sob demanda e drenado após delegua_main. Sem tarefas,
o caminho síncrono apenas testa a ausência do loop. Rejeições não observadas
são reportadas em ordem de criação e causam status 1. Falta de progresso também
causa falha, sem busy-wait. Promessas C de outros loops não são aceitas por
aguardar/encadeamento da linguagem: a FFI gerenciada não autoriza misturar loops
ou retomar de outra thread.

Limites do loop padrão: 65536 Promessas retidas (pendentes/rejeições não
observadas), 65536 reações e profundidade de adoção 4096. Uma Promise aceita até
256 contratos distintos. Limites são contabilizados antes de registrar operação;
a criação da própria Promise pode falhar antes de existir um resultado rejeitável.
Não há preempção de código CPU ou de chamadas síncronas de I/O.

entao(callback) e capturar(callback) devolvem nova Promise. São métodos nativos
por receptor, com callback sem captura lexical ou método ligado a receptor
explícito. Callback executa em microtask; retorno de Promise é adotado; retorno de
valor resolve; exceção rejeita. Metadados atuais do encadeamento retornam
Promessa<qualquer>, com contratos dinâmicos ao vincular/aguardar.

### Limites de implementação e sequência

A IR agora representa arestas excepcionais, retorno pendente e limpeza em
saídas normais, erro, retorno, break e continue. `pegue` e `finalmente` podem
suspender sem guardar handlers C de ativações encerradas. Slots C locais são
volatile para manter valores definidos após longjmp. A checagem final do retorno
ocorre após as limpezas, preservando o contrato síncrono. Para cada, escolha,
compreensões, laços coletores e spread também têm lowering; E3305 permanece para
classes locais dentro de funções assíncronas.

### Cancelamento, combinadores e encerramento

Promessas produtoras oferecem `cancelar(): logico`: solicita uma vez e retorna
falso quando não há proprietário cancelável ou já terminou. Tarefas injetam uma
Excecao de cancelamento nos pontos seguros; não há preempção de código CPU.
Limpezas `finalmente` são protegidas durante suspensão. Cancelar uma tarefa
remove seu waiter, mas não cancela automaticamente a Promise aguardada.

`Promessa.resolvida`, `rejeitada`, `todas`, `corrida`, `qualquer` e
`todasResolvidas` estão implementadas. Combinadores recebem vetor de Promessas;
resultados de todas preservam a ordem de entrada. todasResolvidas produz mapas
com estado resolvida/rejeitada e valor/erro. qualquer agrega falhas em Excecao.erros.
Cancelamento do combinador desinscreve consumidores sem cancelar produtores.
As reações tardias de entradas perdedoras continuam observadas.

Ao falhar a raiz, o runtime solicita cancelamento dos produtores, preserva as
dependências das limpezas já suspensas e drena o trabalho de limpeza. Cancelamentos
de encerramento não substituem o erro original; falhas secundárias são reportadas.
Novas operações durante encerramento exigem contexto de limpeza. Após o cancelamento inicial, a drenagem
dispõe de cinco segundos de relógio monotônico. O reactor limita a espera por
I/O ao tempo restante e o loop verifica o prazo entre reações. O vencimento gera
um diagnóstico secundário e preserva o erro da raiz. Uma chamada síncrona já
em execução precisa devolver o controle para que o loop observe o prazo.

### I/O nativo: cgd:assincrono

O módulo separado `cgd:assincrono` oferece Tempo.dormir, HTTP e TCP. As bibliotecas
anteriores cgd:tempo, cgd:rede, cgd:sockets, servidor e processos permanecem síncronas.
Usar assincrona não transforma automaticamente essas chamadas em I/O não bloqueante.

O reactor Linux usa epoll level triggered e heap de prazos monotônicos, sem
thread por operação. Timers iguais seguem sequência de registro; microtasks são
drenadas antes da próxima espera. Até 65536 watches/timers; cada lote tem até 64
fontes. O registro mantém raízes fortes dos contextos gerenciados.

HTTP usa curl multi e curl_multi_waitfds (libcurl >= 8.8), descoberto dinamicamente
para preservar o mínimo da API síncrona anterior. HTTP.obter/requisitar/enviar
produzem RespostaHTTP com status, texto, url, tipoConteudo, sucesso e json.
URLs numéricas funcionam sem resolver; hostnames exigem libcurl com c-ares.
Não há fallback DNS bloqueante ou thread por consulta. Proxy de ambiente e
redirecionamentos estão desativados; TLS verifica certificado e hostname.
O último argumento opcional de HTTP.obter, HTTP.enviar e HTTP.requisitar limita
o corpo da resposta em bytes. O padrão é 16 MiB. Uma resposta exatamente no
limite é aceita; o primeiro byte excedente rejeita a promessa.
São até 4096 requisições; corpo até 64 MiB por operação, memória de resposta 256 MiB
global e cabeçalhos de envio 64 KiB por operação/16 MiB globais. Callbacks curl
não lançam longjmp através da biblioteca: falhas são convertidas fora deles.

TCP.conectar aceita IPv4 numérico e produz ConexaoTCP; enviar/receber e
OuvinteTCP.aceitar usam eventos de prontidão e timeout. Uma operação pendente por
socket, inclusive entre aliases; acesso síncrono concorrente é recusado.
Cancelar/expirar/falhar uma conexão fecha o recurso, inclusive em escrita parcial.
O cancelamento das promessas públicas de HTTP, conexão e aceite alcança a
operação nativa criada pela chamada. Após observar a rejeição do aceite, o
ouvinte pode aceitar outra conexão. Cancelar/expirar aceite preserva o ouvinte; fechar o recurso rejeita sua operação.
Leitura devolve texto binário e texto vazio no EOF; escrita resolve a contagem
após enviar o corpo inteiro. Limites: 128 sockets, leitura até 1 MiB, buffers de
leitura 16 MiB globais, escrita até 16 MiB. Não há DNS, IPv6 ou TLS nesse TCP.

Exemplo de uso da API nova (ainda aguardando a rodada de validação):

```delegua
assincrona funcao principal(): vazio {
    aguardar importar("cgd:assincrono").Tempo.dormir(10)
    const resposta: qualquer = aguardar importar("cgd:assincrono").HTTP.obter("http://127.0.0.1:8080/")
    escreva(resposta.status(), resposta.texto())
}
principal()
```

As novas integrações e os handlers ainda aguardam validação funcional. Há
regressões preparadas; não foram executadas após a suspensão de testes.
Uma rejeição propagada diretamente por esperas sucessivas conserva a origem e até
32 locais de `aguardar`. O relatório indica quando atingiu o limite. A adoção e o
encaminhamento sem tratador preservam os locais já registrados. A recuperação
seguida de outra suspensão pode interromper a cadeia de esperas. A API de grupos
e a execução de tarefas paralelas seguem para a etapa de rotinas.

Testes específicos: `python3 testes/async_linguagem.py`, a mesma suíte com CC=gcc
e `--sanitizadores`, unitários DMD/LDC e `python3 testes/assincronismo.py`.
A suíte de linguagem verifica saída/efeitos, defaults, aliases, sombras, laços,
herança, calls indiretas, encadeamento/recuperação, rejeição com origem e falta de
progresso, com/sem otimização. Os resultados finais e regressões síncronas
realmente executados estão em [CONTINUIDADE.md](CONTINUIDADE.md).
