# Terminal e Interface Textual (TUI)

O CGD inclui suporte nativo a aplicações de terminal interativas por meio de:

- `cgd:interface/terminal` (`Cores`, `Terminal`) — controle POSIX direto via `termios`, `ioctl(TIOCGWINSZ)`, `poll` e `SIGWINCH`, sem dependência de ncurses.
- `cgd:interface/tui` (`Estilo`, `Tela`, `Menu`, `CampoTexto`) — biblioteca TUI em Delégua com *double buffering* e renderização incremental.

## Recursos principais

- **Modo raw seguro**: `Terminal.entrarModoBruto()` salva o `termios` original e registra restauração automática via `atexit`, garantindo que o terminal volte ao estado normal mesmo em encerramentos inesperados ou exceções capturadas.
- **Leitura de eventos**: `Terminal.lerEvento(timeoutMs)` decodifica teclas direcionais (`CIMA`, `BAIXO`, `ESQUERDA`, `DIREITA`), `ENTER`, `ESC`, `TAB`, `BACKSPACE`, `Ctrl+C`, caracteres UTF-8 multibyte, eventos SGR de mouse (`MOUSE`) e redimensionamento (`REDIMENSIONAR`).
- **Largura visual Unicode**: `Terminal.larguraVisual(texto)` calcula a largura de exibição considerando caracteres combinantes e glifos largos.
- **Double buffering e diff**: `Tela` mantém dois buffers (`atual` e `anterior`) e envia somente as células alteradas ao apresentar (`tela.apresentar()`), reduzindo cintilação (*flicker*).
- **Modo headless testável**: `Tela.criarSimulada(largura, altura)` permite renderizar quadros completos em memória e inspecionar `tela.linhaTexto(y)` em testes automatizados sem precisar de TTY.
- **Fallback ASCII**: alternância limpa entre bordas Unicode (`┌─┐│└┘`) e ASCII (`+-+|+-+`).

## Exemplo mínimo

```delegua
importar cgd.interface.tui como TUI

var tela = TUI.Tela.criarSimulada(30, 5)
var borda = TUI.Estilo.criar(3, -1, verdadeiro, falso, falso)
tela.caixa(0, 0, 30, 5, "CGD TUI", borda, verdadeiro)
tela.escrever(2, 2, "Ola, terminal!", TUI.Estilo.padrao())
escreva(tela.linhaTexto(2))
```

Veja exemplos completos executáveis em `exemplos/terminal/tui/tarefas_tui/` e no tabuleiro interativo de `exemplos/jogos/xadrez/`.
