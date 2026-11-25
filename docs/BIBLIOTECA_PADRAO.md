# Biblioteca Padrão do CGD

A biblioteca padrão foi organizada em áreas temáticas hierárquicas, mantendo 100% de compatibilidade com os nomes legados (`cgd:arquivos`, `cgd:memoria`, `cgd:bytes`, etc.) por meio de aliases canônicos que resolvem para o mesmo `ModuleUnit` (sem duplicar código nem quebrar identidade de tipos).

## Mapa hierárquico

| Área | Caminhos hierárquicos (`cgd:...`) | Compatibilidade legada | Descrição |
| --- | --- | --- | --- |
| **Núcleo** | `cgd:nucleo/colecoes` | — | `Deque`, `HeapMin`, `FilaPrioridade` |
| **Sistema** | `cgd:sistema/arquivos`, `cgd:sistema/caminhos`, `cgd:sistema/processos`, `cgd:sistema/ambiente`, `cgd:sistema/memoria`, `cgd:sistema/plataforma`, `cgd:sistema/cli`, `cgd:sistema/tempo`, `cgd:sistema/io`, `cgd:sistema/log`, `cgd:sistema/terminal` | `cgd:arquivos`, `cgd:caminhos`, `cgd:processo`, `cgd:ambiente`, `cgd:memoria`, `cgd:sistema`, `cgd:cli`, `cgd:tempo`, `cgd:io`, `cgd:log` | Sistema operacional, memória controlada (`Arena`, `FatiaBytes`, GC), tempo (`Tempo.agoraMs()`), processos e terminal POSIX |
| **Dados** | `cgd:dados/json`, `cgd:dados/csv`, `cgd:dados/toml`, `cgd:dados/binario`, `cgd:dados/compressao`, `cgd:dados/sqlite` | `cgd:json`, `cgd:bytes`, `cgd:compressao`, `cgd:sqlite` | Serialização JSON, CSV (RFC 4180 + `LeitorCSV`), TOML, buffers binários `Bytes`, zlib e SQLite |
| **Rede** | `cgd:rede/http`, `cgd:rede/websocket`, `cgd:rede/tcp`, `cgd:rede/udp`, `cgd:rede/dns`, `cgd:rede/sockets`, `cgd:rede/cliente`, `cgd:rede/assincrono` | `cgd:sockets`, `cgd:rede`, `cgd:servidor` | Servidor HTTP/1.1 assíncrono, WebSocket RFC 6455, cliente libcurl e sockets TCP/UDP/DNS |
| **Matemática** | `cgd:matematica/base`, `cgd:matematica/estatistica`, `cgd:matematica/algoritmos`, `cgd:matematica/algebra`, `cgd:matematica/grafos` | `cgd:matematica`, `cgd:estatistica`, `cgd:algoritmos` | Álgebra linear (`Vetor2`, `Vetor3`, `Matriz`), grafos (`Grafo`: BFS, DFS, Dijkstra, ordenação topológica), estatística |
| **Texto** | `cgd:texto/regex`, `cgd:texto/unicode`, `cgd:texto/formatacao`, `cgd:texto/utilitarios` | `cgd:textos` | Expressões regulares POSIX (`Regex`: `validar`, `encontrar`, `encontrarTodos`, `substituir`) e utilitários Unicode |
| **Concorrência** | `cgd:concorrencia/assincrono`, `cgd:concorrencia/rotinas`, `cgd:concorrencia/canais`, `cgd:concorrencia/tarefas` | `cgd:assincrono` | `assincrona`/`aguardar`, `Promessa<T>`, `rotina`, `Tarefa<T>`, `Canal`, timers e reactor Linux |
| **Interface** | `cgd:interface/terminal`, `cgd:interface/tui`, `cgd:interface/gtk`, `cgd:interface/sdl` | — | Terminal raw POSIX, TUI com double buffering, GTK4 (opcional) e SDL3 (opcional) |
| **Segurança** | `cgd:seguranca/criptografia`, `cgd:seguranca/hashing`, `cgd:seguranca/aleatoriedade` | `cgd:cripto` | SHA-256, HMAC, PBKDF2, AES-256-GCM, WebSocket accept (SHA-1/Base64) e CSPRNG |

## Formas de importação equivalentes

```delegua
const Arquivos = importar("cgd:sistema/arquivos")
const ArquivosLegado = importar("cgd:arquivos")
importar cgd.interface.tui como TUI
```

Todas as novas bibliotecas têm cobertura automatizada em `testes/stdlib_expansao.py` (executada com e sem `-o`).
