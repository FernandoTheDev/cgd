# Aplicações Gráficas Nativas com GTK4 (`cgd:interface/gtk`)

A biblioteca `cgd:interface/gtk` permite construir aplicações desktop nativas em Delégua usando GTK4 real, vinculada **opcionalmente** via `libdelegua_gtk4.o` e `pkg-config --libs gtk4`.

## Requisitos opcionais

- `gtk4` instalado com headers de desenvolvimento (`gtk4-devel` / `libgtk-4-dev`).
- `./build-runtime` gera `lib/libdelegua_gtk4.o` automaticamente quando `pkg-config --exists gtk4` encontra a biblioteca.
- Projetos que não importam `cgd:interface/gtk` continuam compilando normalmente mesmo sem GTK4 instalado.

## Classes disponíveis

- `Aplicacao`: ciclo de vida `GtkApplication` (`aoAtivar`, `executar`, `sair`, `agendar`).
- `Janela`: `GtkApplicationWindow` (`definirTitulo`, `definirTamanho`, `definirFilho`, `apresentar`, `fechar`).
- `Caixa`: `GtkBox` vertical ou horizontal (`adicionar`, `definirMargens`, `definirEspacamento`).
- `Grade`: `GtkGrid` (`anexar`, `definirEspacamento`).
- `Rotulo`: `GtkLabel` (`definirTexto`, `obterTexto`).
- `Botao`: `GtkButton` (`aoClicar`, `clicar` para testes, `definirRotulo`).
- `Entrada`: `GtkEntry` (`obterTexto`, `definirTexto`, `aoAlterar`, `aoAtivar`).
- `CheckBox`: `GtkCheckButton` (`obterAtivo`, `definirAtivo`, `aoAlternar`).
- `Lista`: `GtkListBox` (`adicionar`, `limpar`, `aoSelecionar`).
- `BarraCabecalho`: `GtkHeaderBar` e `GTK.aplicarCss(css)`.

## Padrão seguro de callbacks (sem capturas)

Como o CGD não expõe closures/capturas de variáveis locais, vincule callbacks a métodos ligados de uma classe (`isto.aoClicar`) ou funções top-level:

```delegua
importar cgd.interface.gtk como GTK

classe MeuApp {
    app: GTK.Aplicacao
    rotulo: GTK.Rotulo
    cliques: inteiro = 0

    iniciar(): vazio {
        var jan = GTK.Janela(isto.app, "Exemplo GTK4", 360, 200)
        var caixa = GTK.Caixa(verdadeiro, 12)
        isto.rotulo = GTK.Rotulo("Cliques: 0")
        var botao = GTK.Botao("Incrementar")
        botao.aoClicar(isto.incrementar)
        caixa.adicionar(isto.rotulo)
        caixa.adicionar(botao)
        jan.definirFilho(caixa)
        jan.apresentar()
    }

    incrementar(): vazio {
        isto.cliques = isto.cliques + 1
        isto.rotulo.definirTexto("Cliques: " + texto(isto.cliques))
    }
}
```

## Garantias de segurança

- Verificação de thread principal nas chamadas à ponte GTK4.
- `g_object_weak_ref` invalida handles geracionais quando um widget é destruído.
- Exceções Delégua em callbacks são interceptadas por `delegua_tentar()` sem corromper o loop principal do GLib.

Veja o projeto completo em `exemplos/graficos/gtk/calculadora/` e a suíte de validação em `testes/graficos.py`.
