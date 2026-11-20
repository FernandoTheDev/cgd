# Rotinas paralelas (`rotina`, `Tarefa<T>`, `Canal`, `GrupoTarefas`)

Data: 20/11/2026 (CGD 0.9.0). Execução paralela de funções Delégua auditadas
sobre pool de workers nativos com isolamento por thread (TLS) e registro de
threads no Boehm GC.

## Sintaxe e tipos implementados

`rotina chamada(argumentos)` é uma expressão prefixa que produz `Tarefa<T>`.
Como comando de expressão, inicia a mesma tarefa; o loop principal aguarda a
drenagem antes do encerramento do processo. Callee e argumentos são avaliados
uma única vez, da esquerda para a direita, na thread chamadora, antes da submissão.
`aguardar tarefa` integra a conclusão ao reactor epoll sem bloquear a thread
principal. `Tarefa<T>` distingue trabalho paralelo de `Promessa<T>`, mantendo
`entao`, `capturar`, `cancelar`, `concluida` e `cancelada` (e compatibilidade
com combinadores `Promessa.todas`/`corrida`/`qualquer`/`todasResolvidas`).

A auditoria transitiva de efeitos (`frontend/semantic/routine_validation.d`,
códigos `E3401`–`E3404`) exige função de topo ou método estático conhecido sem
captura, transitivamente livre de I/O global, FFI, campos estáticos mutáveis,
chamadas indiretas sem contrato e funções assíncronas. Argumentos e retorno
exigem tipos transferíveis (`nulo`, `logico`, `inteiro`, `real`, `texto` copiado
ou `qualquer` validado em execução pelo runtime). Exceções lançadas no worker
são capturadas na fronteira TLS da thread de trabalho e propagadas como
rejeição `Excecao` tratável com `tente`/`pegue` na thread principal.

## Transferência implementada como base interna

`vendor/delegua-runtime/src/rotinas_transferencia.{c,h}` implementa pacotes de
propriedade exclusiva, sem ponteiros para valores gerenciados. Aceita nulo,
lógico, inteiro, real e texto copiado com tamanho explícito, inclusive bytes NUL.
Rejeita funções, Promessas, sockets, classes, objetos, coleções e ponteiros,
sem conversões ou inspeção de campos. Limites: 4096 valores e 16 MiB por pacote.
Isso ainda não constitui suporte a rotinas na linguagem.

A conversão de e para valores Delégua ocorre na thread principal. Workers podem
construir pacotes de resultado a partir de views nativas com cópia dos textos. O pacote usa
`calloc/free`, e seus registros usam offsets para textos dentro da própria
alocação. Views são imutáveis e válidas apenas durante a vida do pacote.
Não há acesso concorrente autorizado ao destrutor: o proprietário só libera
após todos os leitores terminarem. O pool transfere
propriedade sob mutex; publicar um ponteiro sem sincronização não é transferência.
Não há finalizador do GC: o proprietário libera o pacote explicitamente. Em caso de recusa, a posse
continua com o chamador.

## Pool interno no Linux

O módulo C interno `rotinas_pool.{c,h}` cria de 1 a 64 threads por pool.
A capacidade configurável (1 a 4096 tarefas) conta as tarefas em fila FIFO,
em execução e concluídas que a thread principal ainda não recolheu. Na recusa,
o pacote continua com o chamador. Na aceitação, a fila assume sua propriedade
e devolve um identificador que não é reutilizado durante a vida do pool.

Cada conclusão acrescenta uma unidade a um eventfd não bloqueante. A thread
principal pode observar o descritor com epoll e consumir uma conclusão por
`rt_pool_take`, assumindo o pacote. O cancelamento remove uma tarefa em fila
imediatamente. Um callback em execução consulta `rt_pool_cancelled` em pontos
cooperativos. Ao destruir o pool, a thread principal interrompe o despacho,
sinaliza cancelamento, aguarda as threads e libera os pacotes restantes.

O pool aceita callbacks C internos que operam sobre pacotes exclusivos.

## Conclusão no reactor

A entrada C interna `rt_routine_start` copia os argumentos e usa um pool de
quatro workers com limite de 256 tarefas. O reactor acompanha um único eventfd
enquanto houver trabalho. A cada notificação ele recolhe até 32 conclusões,
converte o resultado escalar e resolve ou rejeita a Promessa na thread principal.
Um cancelamento aceito antes dessa entrega prevalece mesmo se o worker já
terminou. Fechar o reactor ocioso também encerra o pool.

As regressões preparadas cobrem conclusão em múltiplos lotes, pressão de GC,
texto com NUL, retorno inválido, argumento mutável e cancelamento em fila e em
execução. A validação funcional continua pendente.

## Isolamento por thread, canais e grupos

- Estado de exceções (`active`, `reporting`, `delegua_call_depth`) e localização
  (`delegua_local_atual` e campos legados) usam armazenamento TLS por thread.
- Classes núcleo (`Objeto`, `Excecao`) são inicializadas com `pthread_once` e
  pré-aquecidas em `main` antes de qualquer worker iniciar.
- Workers registram sua pilha no Boehm GC (`GC_allow_register_threads`,
  `GC_register_my_thread`/`GC_unregister_my_thread`) por hooks de ciclo de vida
  do pool, mantendo `rotinas_pool.c` desacoplado do GC para validação TSan.
- `cgd:assincrono` disponibiliza `Canal(capacidade)` (fila limitada de valores
  transferíveis com backpressure assíncrono, `tentarEnviar`/`tentarReceber` e
  `fechar`) e `GrupoTarefas` (espera agregada e cancelamento em falha).

M:N e corrotinas stackful permanecem fora do escopo atual.
