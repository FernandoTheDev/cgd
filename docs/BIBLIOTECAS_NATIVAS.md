# Bibliotecas Nativas Opcionais e Pontes (Bridges)

O CGD mantém o compilador principal e o runtime núcleo (`libdelegua_rt.o`) **livres de dependências obrigatórias** de GTK4, SDL3 ou ncurses.

## Arquitetura de vinculação sob demanda

As pontes nativas ficam separadas em `vendor/delegua-runtime/bridges/`:

- `gtk4_bridge.c` → compila para `lib/libdelegua_gtk4.o` somente quando `pkg-config --exists gtk4` é verdadeiro.
- `sdl3_bridge.c` → compila para `lib/libdelegua_sdl3.o` somente quando `pkg-config --exists sdl3` é verdadeiro.

O script `./build-runtime` compila sempre `libdelegua_rt.o` (C99) e compila automaticamente as pontes opcionais disponíveis no sistema (em C11/`-std=gnu11` para compatibilidade com headers modernos de GTK4/SDL3), sem falhar caso GTK4 ou SDL3 não estejam instalados.

## Descoberta pelo driver (`src/driver/toolchain.d`)

Quando um programa Delégua importa uma classe `@definicao(biblioteca = "cgd-gtk4", abi = "delegua")` ou `@definicao(biblioteca = "cgd-sdl3", abi = "delegua")`:

1. O driver detecta o marcador da ponte usada pela AST efetivamente carregada.
2. Vincula o objeto correspondente (`libdelegua_gtk4.o` ou `libdelegua_sdl3.o`) e consulta `pkg-config --libs gtk4` ou `pkg-config --libs sdl3` (argumentos separados, sem invocar shell).
3. Programas comuns **não** recebem nenhum vínculo com GTK4 nem SDL3; programas GTK4 não recebem SDL3; programas SDL3 não recebem GTK4. Esse isolamento é verificado automaticamente via `ldd` em `testes/graficos.py`.

## Contratos de segurança nas pontes

- **Sem ponteiros crus em Delégua**: todos os objetos nativos são expostos como *handles* inteiros geracionais (`(geracao << 32) | indice`).
- **Proteção anti-UAF (Use-After-Free)**: tentar reutilizar um handle após `fechar()` ou após o objeto nativo ser destruído (`g_object_weak_ref` no GTK4; tabela geracional na SDL3) falha deterministicamente com diagnóstico em runtime.
- **Ancoragem no Boehm GC**: callbacks Delégua registrados em eventos nativos são mantidos em raízes visíveis ao coletor de lixo e executados protegidos por `delegua_tentar()` para que exceções Delégua não atravessem código C.
- **Limitação conhecida de TinyCC**: backends que consomem headers complexos de GTK4/SDL3 usam objetos `.o` pré-compilados com Clang/GCC; programas Delégua puros (incluindo o motor de xadrez e o Ray Tracer 3D) compilam e executam diretamente com TinyCC (`--cc tcc`).
