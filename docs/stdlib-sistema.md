# Programas que conversam com o sistema

Você já pode receber argumentos, chamar outro programa, ler stdin, escrever em
stderr e medir quanto uma tarefa levou. Estas bibliotecas usam a mesma sintaxe das
demais: importe um módulo `cgd:` e use suas classes.

A implementação desta etapa é para **Linux x86_64 com glibc >= 2.34**. Ela usa
`posix_spawn`, grupos de processos, `poll`, `waitid` e `waitpid`. Não foi validada em
Windows, macOS ou musl. Os exemplos também usam `/bin/printf` e os testes usam
Python 3. Não há dependência nova de execução para além da libc do sistema.

## Processo: argumentos reais

```delegua
var P: qualquer = importar("cgd:processo").Processo
escreva(P.argc())
escreva(P.argv())
escreva(P.argumentos())
```

| Método estático                   | Retorno e significado                                                                               |
| --------------------------------- | --------------------------------------------------------------------------------------------------- |
| `argv(): texto[]`                 | Cópia nova do argv original, incluindo argv[0]. Preserva ordem, espaços, argumento vazio e Unicode. |
| `argc(): inteiro`                 | Quantidade de itens de argv, incluindo argv[0].                                                     |
| `argumentos(): texto[]`           | Cópia dos argumentos da aplicação, sem argv[0].                                                     |
| `quantidadeArgumentos(): inteiro` | Quantidade de argumentos da aplicação.                                                              |
| `executavel(): texto`             | argv[0] como foi recebido: pode ser relativo ou só um nome. Não promete caminho canônico.           |
| `identificador(): inteiro`        | PID do processo atual.                                                                              |

Esses dados vêm de `program_context`, preenchido pelo `main` do runtime. Não há
uma variável Delégua global que o programa possa alterar para falsificar argv.
Mudar o vetor devolvido não altera as chamadas seguintes. O contexto C pode ser
vazio em consumidores que não usem o ponto de entrada padrão; nesse caso argv é
vazio, argc é zero e executavel devolve texto vazio.

## Executar outro programa

```delegua
var P: qualquer = importar("cgd:processo").Processo
var resultado: qualquer = P.executar("git", ["--version"])
resultado.exigirSucesso()
escreva(resultado.saidaPadrao())
```

A assinatura completa é:

```delegua
Processo.executar(
    programa: texto,
    argumentos: texto[] = [],
    diretorio: texto = "",
    ambiente: dicionario = {},
    timeout: inteiro = 30000,
    limite: inteiro = 16777216,
    entrada: texto = ""
): ResultadoProcesso
```

Cada item de `argumentos` vira **um argumento**, sem separar por espaços, expandir
`*`, substituir `$HOME` ou interpretar `;`. O programa é executado diretamente.
Arquivos sem formato executável e sem shebang falham; não há fallback para shell.
Isso evita interpretação de comandos, mas não torna os argumentos seguros para
qualquer programa: o programa chamado ainda interpreta suas próprias opções.

`diretorio` vazio herda o diretório atual. Outro caminho muda apenas o filho.
O ambiente é herdado, com sobrescritas do dicionário: valores precisam ser texto;
`nulo` remove a variável no filho. O pai não é alterado. O `PATH` utilizado na
procura de `programa` é o do **pai**, conforme `posix_spawnp`. Para escolher um
executável sem depender dessa procura, passe seu caminho absoluto.

`timeout` é em milissegundos, de 1 a 86400000. Ele inclui inicialização e espera
por EOF dos pipes, mesmo quando o filho terminou mas algum descendente manteve
uma saída aberta. `limite` é a soma dos bytes capturados de stdout e stderr,
de 1 a 67108864. Quando ultrapassado, o resultado contém o prefixo capturado até
o limite. As duas saídas não têm uma ordem global preservada entre si.

`entrada` é enviada ao stdin do filho e fechada ao terminar; o limite é 64 MiB.
Se o filho fechar stdin antes, o pai continua e coleta o resultado. Sem entrada,
o filho recebe EOF, em vez de ler acidentalmente o terminal do chamador.

### ResultadoProcesso

| Método de instância                  | Contrato                                                                                               |
| ------------------------------------ | ------------------------------------------------------------------------------------------------------ |
| `codigoSaida(): qualquer`            | Inteiro quando terminou normalmente; nulo quando terminou por sinal. Zero não é presumido para falhas. |
| `sinal(): qualquer`                  | Número do sinal ou nulo se terminou normalmente.                                                       |
| `saidaPadrao(): texto`               | Bytes capturados de stdout, preservando NUL.                                                           |
| `saidaErro(): texto`                 | Bytes capturados de stderr, preservando NUL.                                                           |
| `expirou(): logico`                  | O prazo foi atingido.                                                                                  |
| `excedeuLimite(): logico`            | A captura ultrapassou o limite configurado.                                                            |
| `sucesso(): logico`                  | Código zero, sem timeout nem excesso de saída.                                                         |
| `exigirSucesso(): ResultadoProcesso` | Devolve o mesmo resultado ou lança com código, sinal, flags e stderr.                                  |

As saídas usam o tipo texto existente, que armazena bytes e tamanho. Não há
conversão de encoding nem validação automática de UTF-8. Operações Unicode sobre
saídas binárias, ou sobre um prefixo cortado no meio de um caractere, não devem
ser usadas como se os dados fossem texto UTF-8 válido. Um buffer binário próprio
é uma etapa posterior, não um vetor de números apresentado como equivalente.

Falhas ao iniciar, caminhos inválidos, permissões e erros de sistema lançam
exceção com errno e mensagem nativa. Código de saída diferente de zero é um
resultado; use exigirSucesso se quiser tratá-lo como exceção. Argumentos, nomes
de ambiente e caminhos com NUL são rejeitados antes da aquisição de recursos.

O runtime drena stdout e stderr e envia stdin com `poll`, sem esperar uma saída
terminar para ler a outra. Em timeout/limite ele envia SIGKILL ao grupo criado,
fecha os descritores e recolhe o filho direto. O PID fica reservado até a coleta,
para não sinalizar um grupo de PID reutilizado. Descritores além de 0/1/2 não são
herdados pelo filho. Não é um sandbox: descendentes podem escapar do grupo, e o
runtime não promete controlar ou recolher processos que não sejam seus filhos.
A memória de captura também ocupa espaço: o limite de saída não é um limite de
memória total da aplicação.

### Configuração reutilizável

```delegua
var Comando: qualquer = importar("cgd:processo").Comando
var comando: qualquer = Comando("git", ["status", "--short"])
    .diretorio("/caminho/do/projeto")
    .timeout(5000)
    .limite(1048576)
var resultado: qualquer = comando.executar()
```

`Comando(programa: texto, argumentos: texto[] = [])` copia os argumentos. Seus
métodos `argumento(texto)`, `diretorio(texto)`, `ambiente(texto, qualquer)`,
`timeout(inteiro)`, `limite(inteiro)` e `entrada(texto)` devolvem o próprio comando.
`executar(): ResultadoProcesso` inicia um novo filho a cada chamada. Não há handle
persistente nem necessidade de destrutor para essa configuração.

### Shell explícito

`Processo.executarShell(comando: texto, diretorio: texto = "", ambiente: dicionario
= {}, timeout: inteiro = 30000, limite: inteiro = 16777216, entrada: texto = "")`
devolve ResultadoProcesso e chama `/bin/sh -c`. **Não concatene dados não
confiáveis nessa string.** Prefira executar com argumentos separados. Esta API
existe para quando a interpretação de shell é justamente o que você deseja.

`iniciar`, espera assíncrona e streams persistentes não são oferecidos nesta etapa.
Eles precisam de um dono para o handle, políticas de cancelamento e coleta,
limpeza em exceções e um mecanismo real de acompanhamento. Uma chamada síncrona
com outro nome não substitui esse trabalho.

## Ambiente

`importar("cgd:ambiente").Ambiente` oferece métodos estáticos:

| Assinatura                                                   | O que faz                                                       |
| ------------------------------------------------------------ | --------------------------------------------------------------- |
| `obter(nome: texto, alternativa: qualquer = nulo): qualquer` | Texto ou alternativa se ausente. Valor vazio é preservado.      |
| `contem(nome: texto): logico`                                | Distingue ausência de texto vazio.                              |
| `variaveis(): dicionario`                                    | Snapshot do ambiente atual. Mudar o mapa não altera o ambiente. |
| `definir(nome: texto, valor: texto): vazio`                  | Altera explicitamente o ambiente do processo atual.             |
| `remover(nome: texto): vazio`                                | Remove a variável atual; ausência não é erro.                   |
| `diretorioAtual(): texto`                                    | Consulta getcwd; lança em falha, inclusive diretório removido.  |
| `diretorioTemporario(): texto`                               | TMPDIR não vazio ou /tmp. Não cria nem verifica a pasta.        |
| `diretorioUsuario(): qualquer`                               | HOME ou nulo. Não garante que o caminho exista.                 |

Nome vazio, `=` e NUL são recusados; valores com NUL também. As alterações valem
para futuros filhos, não para processos já iniciados. Ambiente não é armazenamento
confidencial; não coloque sua enumeração em logs. Esta etapa não oferece um
contrato de sincronização com threads nativas externas alterando environ.

## Sistema

`importar("cgd:sistema").Sistema` consulta `uname` e o PID, sem executar comandos.
`nome(): texto`, `arquitetura(): texto`, `versao(): texto` e `informacoes():
dicionario` devolvem dados reais. O mapa tem nome, arquitetura, versao e pid.
`separadorCaminho(): texto` é `/`; `separadorBusca(): texto` é `:` nesta implementação.
`capacidades(): dicionario` informa processos, shell, ambiente e relógio monotônico
presentes; processos persistentes estão ausentes. A plataforma validada é
informada separadamente da arquitetura detectada. Falha de uname lança exceção.

## Tempo e durações

`importar("cgd:tempo")` fornece Tempo, Duracao e Cronometro:

- `Tempo.monotonico(): real`: segundos de CLOCK_MONOTONIC, para medir intervalos.
  A origem não é uma data nem um valor para persistir entre reinicializações.
- `Tempo.unix(): real`: segundos de CLOCK_REALTIME desde a época Unix. O relógio
  civil pode ser ajustado; não o use para medir o timeout de uma operação.
- `Tempo.dormir(milisegundos: inteiro): vazio`: 0..86400000 ms; retoma a espera
  restante após EINTR. O agendador pode fazer a espera durar mais.
- `Duracao(milisegundos: real)`: exige valor finito e não negativo.
  `emMilisegundos(): real`, `emSegundos(): real`, `somar(outra: Duracao): Duracao`
  e `dormir(): vazio`. A espera trunca a parte fracionária de milissegundos e
  respeita os mesmos limites de Tempo.dormir.
- `Cronometro()`: inicia uma medição. `reiniciar(): vazio`, `segundos(): real` e
  `milisegundos(): real` consultam o tempo decorrido.

Não há promises de precisão de nanossegundos, calendário, fusos horários ou
formatação de datas. Falhas dos relógios e durações inválidas lançam exceção.

## IO de console

`importar("cgd:io").IO` opera sobre os streams padrão já abertos:

| Assinatura                                      | Contrato                                                                                        |
| ----------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| `escrever(valor: texto): inteiro`               | Escreve sem quebra em stdout e faz flush; retorna bytes escritos.                               |
| `escreverLinha(valor: texto = ""): inteiro`     | Acrescenta LF.                                                                                  |
| `erro(valor: texto): inteiro`                   | Escreve em stderr e faz flush.                                                                  |
| `erroLinha(valor: texto): inteiro`              | Acrescenta LF em stderr.                                                                        |
| `lerLinha(limite: inteiro = 1048576): qualquer` | Texto sem LF/CRLF, inclusive texto vazio; nulo em EOF sem dados. Limite em bytes de 1 a 64 MiB. |

Leitura é bloqueante. Falha não retorna EOF falso: lança exceção. Excesso de linha
lança depois de consumir parte da entrada; não é uma operação com rollback.
Escrita pode ter sido parcial antes de falhar. O tipo texto preserva NUL, mas não
substitui uma API de buffer binário. IO não fecha stdin/stdout/stderr; eles
pertencem ao processo. Sinais como SIGPIPE continuam sujeitos às regras Unix.
Não há streams de arquivos com handles expostos nesta etapa.

## Algoritmos numéricos

`importar("cgd:algoritmos").Algoritmos` complementa Colecoes e as operações nativas.
Todos os métodos são estáticos e recebem `numero[]`:

- `limiteInferior(valores, alvo: numero): inteiro`: primeira posição com valor
  maior ou igual ao alvo; tamanho do vetor se não existir.
- `limiteSuperior(valores, alvo: numero): inteiro`: primeira posição estritamente maior.
- `buscaBinaria(valores, alvo: numero): inteiro`: primeira ocorrência ou -1.
- `estaOrdenado(valores): logico`: verifica ordem crescente, permitindo repetições.
- `ordenado(valores): numero[]`: cópia ordenada, sem alterar o original.
- `intercalar(a: numero[], b: numero[]): numero[]`: intercala dois vetores já
  ordenados, mantendo repetições e preferindo a esquerda nos empates.

Busca e limites são O(log n) e **exigem entrada ordenada com valores comparáveis,
sem NaN**. Não verificam essa precondição percorrendo o vetor inteiro. Intercalar
é O(n+m). Para reduzir, particionar, agrupar ou combinar, use Colecoes: não foram
criadas cópias dessas APIs neste módulo. Comparadores personalizados e iteradores
lazy ficam para uma etapa que consiga preservar seus contratos.

## CLI

```delegua
var CLI: qualquer = importar("cgd:cli").CLI
var parser: qualquer = CLI("Conversor")
    .opcao("ajuda", "h", falso, "Mostra esta ajuda")
    .opcao("saida", "s", verdadeiro, "Arquivo de destino")
var argumentos: qualquer = parser.atual()
se argumentos.tem("ajuda") { escreva(parser.ajuda()) }
```

`CLI(descricao: texto = "")` cria um parser. `opcao(nome: texto, curto: texto =
"", exigeValor: logico = falso, descricao: texto = ""): CLI` registra a opção.
Nomes/aliases duplicados e nomes inválidos lançam. `analisar(argumentos: texto[]):
ResultadoCLI` permite entradas explícitas; `atual(): ResultadoCLI` usa
**Processo.argumentos()**, sem outro acesso nativo ao argv. `ajuda(): texto` segue
a ordem de registro; imprimir ajuda é decisão da aplicação.

Aceita `--nome=valor`, `--nome valor`, `-n valor`, flags `--ajuda`/`-h`, posicionais
e `--` para encerrar as opções. Um valor pode ser vazio ou começar com `-`.
Opções desconhecidas, repetidas ou sem valor, assim como valor em flag booleana,
lançam. Flags curtas agrupadas, subcomandos e conversão automática de números não
fazem parte desta API. Não há abreviações implícitas ou execução de argumentos.

ResultadoCLI oferece `tem(nome: texto): logico`, `valor(nome: texto, alternativa:
qualquer = nulo): qualquer` e `posicionais(): texto[]`. Flags presentes devolvem
verdadeiro; opções com valor devolvem texto. Ausência devolve a alternativa.
Posicionais são copiados ao consultar.

## Log

`importar("cgd:log").Logger` é uma instância reutilizável. Seu construtor é
`Logger(nome: texto = "", minimo: inteiro = 1, usarErro: logico = verdadeiro,
timestamp: logico = verdadeiro)`.

Os níveis são `Logger.Nivel.Depuracao` (0), Informacao (1), Aviso (2) e Erro (3).
`registrar(nivel: inteiro, mensagem: texto): vazio` filtra pelo mínimo; `depurar`,
`info`, `aviso` e `erro` recebem texto e devolvem vazio. O destino padrão é stderr;
`usarErro = falso` escolhe stdout. O timestamp é Unix em segundos; pode ser
desligado para saídas reproduzíveis. Nível fora de 0..3 e falhas de IO lançam.

O formato é `[NIVEL] nome: mensagem`, precedido pelo timestamp quando ativado.
Não há arquivos de log, rotação, formatação de calendário ou sincronização entre
threads. Quebras de linha e controles da mensagem são preservados: trate dados
não confiáveis antes de registrar algo que possa imitar outra linha de log.

## CTFE, arquitetura e próximos passos

Estas bibliotecas não liberam OS na VM. Processos, ambiente, IO, relógios e logs
são dependentes do sistema e/ou têm efeitos; ficam fora de CTFE. Algoritmos e
parsing de CLI são determinísticos para a mesma entrada, mas usam classes,
coleções e métodos que não são aprovados pelo subconjunto CTFE atual. Duracao
representa valores, mas também é uma classe e não recebe promessa de CTFE.

A camada Delégua compõe a API e os resultados. As primitivas ficam em
`sistema_posix.c`, `processo_posix.c` e `io_posix.c`; o compilador apenas acrescenta
os nomes dos módulos à resolução estática. Não há palavras-chave novas, lexer
especial para bibliotecas ou relaxamento de pureza/capturas. Os módulos antigos
e seus entry points C foram preservados.

Esta entrega conclui o núcleo síncrono P0 e acrescenta Algoritmos, CLI e Log.
A expansão completa de diretórios/atomicidade/permissões, buffer de bytes,
codificações, regex, hashes e iteradores incrementais continua pendente. Regex
precisa de um mecanismo consolidado e dependência escolhida; criptografia não
será inventada aqui. URI já tem primitivas em Rede/libcurl e deve ser construída
sobre elas, sem outro parser concorrente. Processos persistentes precisam de
ownership/cancelamento próprios. Compressão, concorrência, datas e configuração
serão avaliadas após esses fundamentos; não há módulos vazios com esses nomes.

### Critérios para as próximas fases

| Área                  | Dependência ou decisão antes de implementar                                                                              | Aceitação mínima                                                                                                                              |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------- |
| Arquivos e diretórios | Definir seguir/não seguir symlinks, sobrescrita, atomicidade e descritores de diretório. Reutilizar Arquivo.             | Testar falhas de permissão, links, troca concorrente de caminhos, interrupção e limpeza de temporários.                                       |
| Bytes/codificação     | Avaliar um buffer GC de bytes separado de texto, com índices em bytes e integração de tipos/ABI.                         | Round-trip de todos os 256 valores, NUL, limites, endian e rejeição de encoding inválido. Não chamar vetor de números de buffer eficiente.    |
| Regex                 | Escolher um motor consolidado; PCRE2 é um candidato, com limites de trabalho e regras UTF explícitas.                    | Capturas/substituição Unicode, sintaxe inválida, limites de complexidade e limpeza do handle. Sem compatibilidade anunciada antes de validar. |
| Iteradores            | Protocolos de parada, avaliação preguiçosa e efeitos; callbacks continuam sem captura.                                   | Consumir parcialmente sem avaliar o restante, propagar falhas e fechar recursos no cancelamento.                                              |
| Hash/digests          | Separar hashing de coleções de digest criptográfico. Para digest, usar biblioteca consolidada e comparar implementações. | Vetores oficiais, entrada binária completa e limites; nenhuma criptografia criada à mão.                                                      |
| Compressão            | Biblioteca consolidada e buffer de bytes, com limite de expansão.                                                        | Round-trip e rejeição de dados truncados, corrupção e expansão excessiva.                                                                     |
| Criptografia          | Fonte de aleatoriedade do OS, biblioteca auditada e contrato de chaves.                                                  | Vetores oficiais e revisão de ownership/segredos; não compor protocolos próprios.                                                             |
| Concorrência          | Rever contexto do runtime, exceções, GC e dados compartilhados; hoje não há esse contrato.                               | Testes de corrida, cancelamento, propagação de erro e encerramento limpo.                                                                     |
| Sincronização         | Depende do contrato de concorrência.                                                                                     | Ownership, deadlocks, reentrada e destruição com participantes ativos.                                                                        |
| Terminal              | Detecção de TTY e capacidades, preservando IO como base.                                                                 | Pipes sem escapes inesperados e restauração do terminal após falha.                                                                           |
| Configuração          | Compor Arquivo/JSON/Ambiente; decidir precedência e formato.                                                             | Precedência reproduzível, chaves inválidas e mensagens com origem.                                                                            |
| Datas                 | Separar instante, calendário, timezone e duração; escolher fonte de fusos.                                               | Transições de horário, datas inválidas e round-trip.                                                                                          |
| Serialização          | JSON já existe; outro formato precisa de uso concreto e schema/versionamento.                                            | Ciclos, aliases, evolução de formato, limites e dados inválidos.                                                                              |

Timeout não é uma garantia de tempo real: o prazo é verificado pelo loop de
acompanhamento, e a inicialização síncrona da libc ou um estado ininterruptível do
kernel podem atrasar o retorno. A coleta do filho ainda é necessária para evitar
zumbis. Estas bibliotecas não fornecem isolamento de segurança de subprocessos.
