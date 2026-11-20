# Um servidor HTTP no executável

`cgd:rede` continua sendo o cliente HTTP. Para receber requisições, importe
`cgd:servidor`: o programa abre seus próprios sockets, sem Node, Python, shell
ou um servidor externo no caminho da comunicação.

Esta é a primeira etapa da infraestrutura de serviços: TCP IPv4 e um perfil
restrito de HTTP/1.1, com uma requisição por conexão. O servidor atende um cliente
por vez. Isso permite definir propriedade dos recursos e comportamento das
exceções antes de acrescentar concorrência ao runtime.

## Primeiro programa

```delegua
const Servidor: qualquer = importar("cgd:servidor")
var app: qualquer = Servidor.HTTP()

app.get("/", funcao(req: qualquer, res: qualquer): vazio {
    res.enviar("Olá, mundo!\n")
})
app.post("/usuarios", funcao(req: qualquer, res: qualquer): vazio {
    res.status(201).json({ criado: verdadeiro, usuario: req.json() })
})
app.escutar("127.0.0.1", 8080)
```

Compile normalmente e execute o binário. O exemplo completo em
[exemplos/servidor/http.delegua](../exemplos/servidor/http.delegua) também mostra
parâmetros e encerramento. No catálogo geral ele tem contrato de compilação,
pois iniciar um serviço bloqueante não cabe no runner de exemplos. O teste
`testes/servidor.py` inicia o serviço e faz requisições reais nos dois modos.

Os callbacks recebem a requisição e a resposta como argumentos. Continuam
valendo as restrições do CGD: não capturam variáveis locais externas. Passe
informações entre middleware e rota por `req.contexto`.

## Rotas e middleware

`get`, `post`, `put`, `patch`, `delete`, `head` e `options` recebem um caminho e
uma função `(req: qualquer, res: qualquer): vazio`. `rota(metodo, caminho, tratar)`
é a forma geral, com método maiúsculo. Registrar a mesma combinação duas vezes
lança uma exceção. A primeira rota compatível na ordem de registro é executada.

Um segmento `:nome` captura um parâmetro. `/usuarios/:nome` aceita
`/usuarios/Jos%C3%A9`; `req.parametro("nome")` devolve `José`. Não há wildcards,
expressões regulares ou conversão automática de parâmetros. A barra final faz
parte do caminho. `HEAD` precisa de rota própria; não executa `GET` implicitamente.
`options("*", callback)` atende `OPTIONS *` explicitamente.

Sem rota para o caminho, a resposta é 404. Havendo caminho mas não método, é
405 com `Allow`. Não há CORS, autenticação nem OPTIONS automático.

```delegua
app.usar(funcao(req: qualquer, res: qualquer): vazio {
    req.contexto["origem"] = "middleware"
    res.cabecalho("x-aplicacao", "exemplo")
    se req.caminho == "/indisponivel" {
        res.status(503).enviar("Tente novamente depois")
    }
})
```

`usar(callback)` executa middleware na ordem de registro. Uma resposta definida
por `enviar` ou `json` encerra o despacho; caso contrário, o próximo middleware e
depois a rota são executados. Não existe `next()` assíncrono. Cada requisição tem
seus próprios mapas de contexto e parâmetros e sua própria resposta.

## Requisicao

| Membro                                          | Contrato                                                       |
| ----------------------------------------------- | -------------------------------------------------------------- |
| `metodo: texto`                                 | Método recebido, sensível a maiúsculas.                        |
| `caminho: texto`                                | Caminho decodificado uma vez, sem query.                       |
| `alvo: texto`                                   | Request target original, ainda com escapes e query.            |
| `cabecalhos: dicionario`                        | Nomes em minúsculas; valores textuais.                         |
| `consulta: dicionario`                          | Cada chave contém um vetor de valores, preservando repetições. |
| `parametros: dicionario`                        | Segmentos capturados pela rota.                                |
| `contexto: dicionario`                          | Dados explícitos da aplicação/middleware.                      |
| `texto(): texto`                                | Corpo completo; o tamanho de transporte é medido em bytes.     |
| `json(): qualquer`                              | Usa o parser de `cgd:json` e seus limites próprios.            |
| `parametro(nome, alternativa = nulo): qualquer` | Obtém um segmento ou a alternativa.                            |
| `query(nome, alternativa = nulo): qualquer`     | Obtém o primeiro valor de query ou a alternativa.              |

Em query, `+` representa espaço e `%2B` representa `+`. Em caminhos, `+` permanece
literal. Escapes inválidos, controles, NUL, barras codificadas, contrabarras e
segmentos `.`/`..` são recusados com 400. Não existe serviço de arquivos embutido:
um caminho de URL nunca é usado como caminho do sistema de arquivos. A aplicação
que construir seu próprio serviço de arquivos precisa confinar a raiz de acesso.

`texto` do runtime armazena bytes; não há validação de UTF-8 de todo corpo HTTP.
Use JSON/texto válido nas operações Unicode. O transporte preserva inclusive NUL
no corpo, mas não nos headers ou no caminho. O Content-Type recebido não altera
o parser automaticamente. `req.json()` inválido lança; a rota pode capturar e
responder 400. Uma exceção não tratada no handler resulta em 500 genérico.

## Resposta

| Método                                           | Efeito                                                    |
| ------------------------------------------------ | --------------------------------------------------------- |
| `status(codigo: inteiro): Resposta`              | Código final 200..599; padrão 200.                        |
| `cabecalho(nome: texto, valor: texto): Resposta` | Define um header; o nome é normalizado.                   |
| `enviar(corpo: texto = ""): Resposta`            | Define o corpo; não faz I/O imediatamente.                |
| `json(valor: qualquer): Resposta`                | Serializa JSON e define Content-Type apropriado.          |
| `definida(): logico`                             | Informa se `enviar`/`json` já foi chamado.                |
| `pararServidor(): Resposta`                      | Solicita fechar o listener após transmitir esta resposta. |
| `deveParar(): logico`                            | Consulta essa solicitação.                                |

O tipo inicial é `text/plain; charset=utf-8`. A resposta fica em memória até o
handler terminar; não há streaming. Uma rota que termina sem definir a resposta
produz 204 vazio. Os status 204, 205 e 304 não aceitam corpo nesta API.
`HEAD` transmite os headers e o tamanho do corpo que seria enviado, mas nenhum
byte do corpo. O runtime calcula Content-Length em bytes, inclusive para Unicode.

Date, Content-Length, Transfer-Encoding, Connection, Trailer e Upgrade são reservados
ao transporte. Não podem ser sobrescritos. Date usa UTC e nomes de meses/dias
em inglês, sem depender do locale do processo. Nomes inválidos, CR/LF e outros
controles nos valores são recusados antes do envio. Se a validação da resposta
falhar, o servidor tenta responder 500 genérico. Se o transporte já falhou, fecha
a conexão e segue atendendo. Nenhum detalhe da exceção, credencial ou corpo é
registrado automaticamente.

## Ciclo de vida e limites

`HTTP(maxCabecalhos = 16384, maxCorpo = 1048576, leitura = 10000, escrita = 10000)`
recebe limites em bytes e prazos em milissegundos. Argumentos inválidos falham
na construção, antes de abrir sockets.

| Recurso                  | Limite                                                  |
| ------------------------ | ------------------------------------------------------- |
| Headers de requisição    | Configurável, 256..65536 bytes, incluindo request line. |
| Quantidade de headers    | 100 por requisição e por resposta.                      |
| Corpo de requisição      | Configurável, 0..16777216 bytes.                        |
| Corpo de resposta        | Até 16777216 bytes.                                     |
| Headers de resposta      | Até 65536 bytes.                                        |
| Parâmetros de query      | Até 256 ocorrências.                                    |
| Leitura/escrita          | Cada prazo entre 1 e 86400000 ms; relógio monotônico.   |
| Conexões HTTP ativas     | Uma por instância em atendimento sequencial.            |
| Backlog                  | 64, sujeito ao limite do kernel.                        |
| Sockets vivos do runtime | 128, incluindo listeners e clientes TCP.                |
| Requisições por conexão  | Uma; `Connection: close` em toda resposta.              |

O prazo de leitura cobre headers e corpo juntos e não reinicia a cada byte.
O prazo de escrita cobre headers e corpo juntos. Assim, um cliente lento não
mantém uma conexão indefinidamente. Ainda pode atrasar os próximos clientes até
o prazo expirar: esta versão sequencial não promete resistência a uma inundação
de conexões nem isolamento entre aplicações.

O parser exige HTTP/1.1, Host não vazio e CRLF. Host aceita nome ASCII sem escapes
percentuais ou endereço IPv6 entre colchetes, com porta opcional 0..65535.
Métodos fora dos sete disponíveis são recusados com 501; o alvo `*` é exclusivo
de OPTIONS. Rejeita headers repetidos
(inclusive Content-Length idênticos), folding e Content-Length inválido.
Transfer-Encoding é recusado com 501; Expect, com 417. Corpo excessivo produz
413, headers excessivos 431 e prazo de leitura expirado 408. Mensagem incompleta
ou inválida produz 400 quando ainda for possível responder. Não tenta recuperar
a conexão ou interpretar uma segunda mensagem depois de erro.

Não há keep-alive, chunked, pipelining, streaming, WebSocket, SSE, multipart,
upload, TLS, HTTP/2 ou compressão de resposta. Bytes extras depois da primeira
requisição são descartados ao fechar; uma segunda requisição não executa rota.
O perfil se baseia no framing de [RFC 9112](https://www.rfc-editor.org/rfc/rfc9112.html),
com as restrições adicionais descritas aqui; não afirma implementar o protocolo
inteiro.

`abrir(endereco = "127.0.0.1", porta = 8080)` abre o listener sem entrar no laço.
`portaLocal()` permite descobrir a porta escolhida com `porta = 0`.
`atenderUma(timeout = 1000)` aceita e trata uma conexão; devolve falso se a
espera por conexão expirar. `ativo()` consulta o estado do listener. Isso permite
que a aplicação controle seu próprio laço e condição de encerramento.
`escutar(endereco, porta)` reúne abrir, laço e fechamento em finally.

`fechar()` é idempotente e fecha o listener; cada conexão aceita é fechada em
finally, mesmo se o handler falhar. `pararServidor()` encerra após a resposta
atual; não instala handlers globais de sinais nem oferece cancelamento entre
threads. O destrutor chama fechar, mas use fechamento explícito/finally. Um
finalizador GC é apenas contingência: não há prazo garantido para sua execução.

## cgd:sockets

A camada TCP pode ser usada separadamente:

```delegua
const Sockets: qualquer = importar("cgd:sockets")
var conexao: qualquer = Sockets.conectar("127.0.0.1", 9000, 1000)
tente {
    conexao.enviar("mensagem", 1000)
    var resposta: texto = conexao.receber(65536, 1000)
} finalmente {
    conexao.fechar()
}
```

`conectar(endereco, porta, timeout = 30000)` devolve `Conexao`.
`OuvinteTCP(endereco = "127.0.0.1", porta = 0)` cria um listener;
`aceitar(timeout = 1000)` devolve Conexao ou nulo no timeout.
Ambos têm `portaLocal()` e `fechar()` idempotente. `Conexao.enviar` transmite
integralmente até 16 MiB e devolve bytes enviados. `receber(limite = 65536,
timeout = 30000)` lê até o limite (1..16777216 bytes); pode devolver um bloco
menor. Texto vazio representa EOF. Timeout ou falha de I/O fecha a conexão e
lança, evitando continuar um protocolo após uma operação incompleta.

`Conexao.lerHTTP`/`responderHTTP` são a adaptação usada pelo servidor. Não misture
leituras TCP manuais e parsing HTTP na mesma conexão. Erros de validação antes
do I/O lançam; o proprietário continua responsável por fechar em finally.

Os identificadores nativos são opacos e verificados por tag; não são números,
FDs, ponteiros Delégua nem sessões curl. Aliases compartilham o mesmo recurso:
fechar por um alias invalida os demais. Descritores são nonblocking/CLOEXEC,
com espera síncrona via poll e envio sem SIGPIPE. Endereços de abertura aceitam
IPv4 ou IPv6 numéricos sem DNS implícito; resolução explícita usa
`Sockets.resolverDNS(host, familia)` e datagramas usam `Sockets.abrirUDP`.

Para atendimento concorrente com HTTP/1.1 keep-alive sobre o reactor epoll,
`HTTP` oferece `escutarAsync(endereco, porta, maxRequisicoesPorConexao)` e
`atenderConexaoAsync(conexao, maxRequisicoes)`, reutilizando o mesmo parser
validado e a mesma tabela de rotas e middlewares de `HTTP`.
A implementação atual usa accept4 e flags de sockets do Linux; somente Linux
x86_64 é a plataforma validada do projeto.

## Validação e desempenho

`python3 testes/servidor.py` verifica rotas, os sete métodos, middleware, Unicode,
JSON, corpos binários, framing hostil, tamanhos, timeout, mensagens parciais,
pipelining recusado, desconexões, clientes simultâneos atendidos em sequência,
fechamento e shutdown. `python3 testes/sockets.py` cobre cliente TCP, EOF,
identificador inválido, reuso de porta e fechamento. Ambos compilam com e sem
otimização. O parser puro tem regressões e corpus pseudoaleatório determinístico
em `testes/http_parser.c`; o runner com sanitizadores fica em
`python3 testes/http_parser.py`. Isso não substitui fuzzing contínuo ou auditoria.

`scripts/benchmark_http.py` mede várias rodadas de conexões novas, RPS, latências
p50/p95/p99, RSS máximo observado, CPU do servidor e tempo de inicialização. Os
resultados incluem configuração do cliente e sistema e ficam em JSON. Não há
resultado de desempenho publicado nesta etapa nem comparação com outros servidores.
