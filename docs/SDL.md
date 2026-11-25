# Jogos e Aplicações Multimídia com SDL3 (`cgd:interface/sdl`)

A biblioteca `cgd:interface/sdl` encapsula a **ABI nativa da SDL3 (3.x)** em Delégua, vinculada sob demanda por meio da ponte opcional `libdelegua_sdl3.o` e `pkg-config --libs sdl3`.

## Diferenças reais da SDL3 já encapsuladas

- Coordenadas em ponto flutuante (`SDL_FRect`) para retângulos, texturas e renderização em lote (`desenharRetangulosLote` sobre `SDL_RenderFillRects`).
- Eventos nativos `SDL_EVENT_QUIT`, `SDL_EVENT_KEY_DOWN`, `SDL_EVENT_KEY_UP`, `SDL_EVENT_MOUSE_MOTION`, `SDL_EVENT_MOUSE_BUTTON_DOWN`, `SDL_EVENT_WINDOW_RESIZED`.
- Escala DPI real via `SDL_GetWindowDisplayScale`.
- Áudio por *stream* (`SDL_OpenAudioDeviceStream`) em vez do modelo antigo SDL2.
- Suporte a execução *headless* com `SDL_VIDEODRIVER=dummy` e `SDL_AUDIODRIVER=dummy` para CI/testes determinísticos.

## Classes disponíveis

- `SDL`: `iniciar`, `encerrar`, `versao`, `tempoMs`, `esperarMs`, `lerEvento`, `teclaPressionada`, `criarJanela`, `criarRenderizador`.
- `Janela`: `largura`, `altura`, `escalaDpi`, `definirTitulo`, `fechar`.
- `Renderizador`: `definirCor`, `limpar`, `desenharRetangulo`, `desenharContorno`, `desenharLinha`, `desenharRetangulosLote`, `criarTexturaRGBA`, `desenharTextura`, `apresentar`, `fechar`.
- `Textura`: `largura`, `altura`, `fechar`.
- `Audio`: `abrirStream`, `tocarTom`, `fechar`.

## Segurança e desempenho

- **Zero ponteiros crus**: janelas, renderizadores, texturas e streams de áudio usam handles geracionais anti-UAF (testado explicitamente após `tex.fechar()` em `testes/graficos.py`).
- **Batching real**: `desenharRetangulosLote` aceita um vetor plano `[x0, y0, w0, h0, ...]` e envia todos os retângulos em uma única chamada C `SDL_RenderFillRects`, reduzindo drasticamente o custo por quadro.
- **Teardown ordenado**: `SDL.encerrar()` fecha handles pendentes na ordem segura (texturas/áudio → renderizadores → janelas → `SDL_Quit`).

Veja o jogo Pong completo em `exemplos/jogos/pong/` e os testes automatizados em `testes/graficos.py`.
