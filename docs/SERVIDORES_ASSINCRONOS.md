# Servidores Assíncronos: HTTP/1.1 e WebSocket RFC 6455

O CGD oferece bibliotecas de rede em português construídas sobre `cgd:sockets` e o reactor `epoll` de `cgd:assincrono`:

- `cgd:rede/http` (`Servidor`, `RespostaHTTP`)
- `cgd:rede/websocket` (`OpcodeWS`, `QuadroWS`, `ProtocoloWS`, `ConexaoWS`, `ServidorWebSocket`, `ClienteWebSocket`)

## Servidor HTTP/1.1 assíncrono (`cgd:rede/http`)

```delegua
importar cgd.rede.http como HTTP
importar cgd.dados.json como JSON

funcao listar(req: qualquer): HTTP.RespostaHTTP {
    retorna HTTP.RespostaHTTP.json(200, JSON.serializar({"ok": verdadeiro}))
}

var srv = HTTP.Servidor()
srv.obter("/api/status", listar)
// srv.escutar("127.0.0.1", 8080)
```

Recursos suportados:
- Métodos de roteamento em português: `obter`, `publicar`, `atualizar`, `remendar`, `remover` e `rota`.
- Parâmetros de rota (`/api/tarefas/:id`) e query strings (`req["parametros"]`, `req["consulta"]`).
- Concorrência assíncrona via `assincrona`/`aguardar` e `epoll` (`escutar`), com limite de conexões simultâneas, timeout de leitura e `metricas()` (`requisicoes`, `ativas`, `erros`).
- Encerramento gracioso via `srv.parar()`.

## WebSocket RFC 6455 (`cgd:rede/websocket`)

Implementação real do protocolo RFC 6455 em Delégua usando `cgd:bytes` (buffers binários seguros fora da validação estrita UTF-8 de `texto`) e `Sec-WebSocket-Accept` calculado via `EVP_sha1` + Base64 em `libcrypto` (`vendor/delegua-runtime/src/cripto.c`):

- **Handshake HTTP Upgrade** completo (`Upgrade: websocket`, `Sec-WebSocket-Key`, `Sec-WebSocket-Accept`).
- **Framing RFC 6455**: payloads de 7 bits, 16 bits (`126`) e 64 bits (`127`), mascaramento cliente→servidor de 4 bytes, opcodes `TEXTO` (`0x1`), `BINARIO` (`0x2`), `FECHAR` (`0x8`), `PING` (`0x9`), `PONG` (`0xA`).
- **Cliente e servidor**: `ServidorWebSocket` e `ClienteWebSocket` validados ponta a ponta em `testes/stdlib_expansao.py` e no chat multi-cliente de `exemplos/rede/websocket/chat/`.

### Nota sobre o reactor `epoll`

No Linux `epoll` usado por `cgd:assincrono`, evite registrar duas operações concorrentes pendentes sobre o mesmo descritor de socket sem `aguardar` a primeira. `ConexaoWS.enviarTexto()` escreve diretamente no socket, mantendo o loop de `receber()` simples e livre de contenção.

### Limites atuais

- HTTP/1.1 sem TLS nativo no servidor (para HTTPS em produção, use proxy reverso como Nginx/Caddy; o cliente `cgd:rede/cliente` sobre libcurl já suporta HTTPS/TLS).
- HTTP/2 não está implementado nesta versão.
