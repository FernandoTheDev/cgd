#!/usr/bin/env python3
"""Testes reais do Marco D: isolamento de dependências, GTK4 (widgets/sinais/CSS/lifetime) e SDL3 (render/lote/eventos/lifetime)."""

from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
CGD = str(ROOT / "cgd")


def compile_src(source, folder, name, opt=False):
    src = folder / f"{name}.delegua"
    out = folder / name
    src.write_text(source)
    r = subprocess.run(
        [CGD, str(src), "-s", str(out)] + (["-o"] if opt else []),
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert r.returncode == 0, f"Falha compilando {name}:\n{r.stderr}\n{r.stdout}"
    return out


def ldd_libs(binary):
    r = subprocess.run(["ldd", str(binary)], capture_output=True, text=True, timeout=10)
    assert r.returncode == 0, r.stderr
    return r.stdout


with tempfile.TemporaryDirectory(prefix="cgd_graficos_") as tmp:
    folder = Path(tmp)

    # 1. Programa comum NÃO pode linkar GTK4 nem SDL3
    comum = compile_src('escreva("comum-ok")', folder, "comum")
    libs_comum = ldd_libs(comum)
    assert "libgtk-4" not in libs_comum and "libSDL3" not in libs_comum, libs_comum

    # 2. GTK4 completo: widgets, CSS, callbacks, sinais e encerramento limpo
    if (ROOT / "lib" / "libdelegua_gtk4.o").exists():
        gtk_src = r'''
importar cgd.interface.gtk como GTK

const estado: dicionario = { cliques: 0, alterado: falso }

funcao iniciarGtk(): inteiro {
    const app: GTK.Aplicacao = GTK.Aplicacao("dev.cgd.teste.gtk4")
    app.aoAtivar(funcao() {
        GTK.aplicarCSS("window { background: #141a18; }")
        const janela: GTK.Janela = GTK.Janela(app)
        janela.definirTitulo("Teste CGD GTK4").definirTamanho(480, 320)

        const barra: GTK.BarraCabecalho = GTK.BarraCabecalho()
        janela.definirBarraCabecalho(barra)

        const caixa: GTK.CaixaVertical = GTK.CaixaVertical(8)
        caixa.definirMargem(12)

        const rotulo: GTK.Rotulo = GTK.Rotulo("Inicial")
        const campo: GTK.CampoTexto = GTK.CampoTexto("Digite aqui")
        campo.definirTexto("Delégua")
        assercao(campo.obterTexto() == "Delégua")

        const area: GTK.AreaTexto = GTK.AreaTexto()
        area.definirTexto("Linha 1\nLinha 2")
        assercao(area.obterTexto() == "Linha 1\nLinha 2")

        const chk: GTK.CaixaSelecao = GTK.CaixaSelecao("Ativar")
        chk.definirMarcado(verdadeiro)
        assercao(chk.marcado() == verdadeiro)

        const lista: GTK.Lista = GTK.Lista()
        lista.adicionar(GTK.Rotulo("Item A"))
        lista.adicionar(GTK.Rotulo("Item B"))

        const rolagem: GTK.Rolagem = GTK.Rolagem()
        rolagem.definirConteudo(lista)

        const botao: GTK.Botao = GTK.Botao("Testar")
        botao.aoClicar(funcao() {
            escreva("CLIQUE-GTK-OK\n")
        })
        botao.simularClique()

        caixa.adicionar(rotulo)
        caixa.adicionar(campo)
        caixa.adicionar(area)
        caixa.adicionar(chk)
        caixa.adicionar(rolagem)
        caixa.adicionar(botao)
        janela.definirConteudo(caixa)
        janela.mostrar()

        // Encerra automaticamente após confirmar a renderização no loop GLib
        GTK.temporizador(120, funcao(): logico {
            escreva("TIMER-GTK-OK\n")
            janela.fechar()
            retorna falso
        })
    })
    retorna app.executar()
}

const codigo: inteiro = iniciarGtk()
assercao(codigo == 0)
escreva("GTK4-SUITE-OK\n")
'''
        # Nota: app não pode ser capturado dentro da função anônima aoAtivar, e janela dentro de temporizador!
        # Vamos estruturar sem capturas, usando classe Controlador (ou GTK.Aplicacao via método)!
        gtk_src_limpo = r'''
importar cgd.interface.gtk como GTK

classe TesteGTK {
    app: GTK.Aplicacao
    janela: qualquer
    rotulo: qualquer
    cliques: inteiro = 0

    construtor() {
        isto.app = GTK.Aplicacao("dev.cgd.teste.gtk4")
    }

    aoClicarBotao(): vazio {
        isto.cliques = isto.cliques + 1
        isto.rotulo.definirTexto("Clicado:" + texto(isto.cliques))
    }

    encerrar(): logico {
        assercao(isto.cliques == 1)
        assercao(isto.rotulo.obterTexto() == "Clicado:1")
        escreva("TIMER-GTK-OK\n")
        isto.janela.fechar()
        retorna falso
    }

    aoAtivar(): vazio {
        GTK.aplicarCSS("window { background: #141a18; }")
        const janela: GTK.Janela = GTK.Janela(isto.app)
        isto.janela = janela
        janela.definirTitulo("Teste CGD GTK4").definirTamanho(480, 320)

        const barra: GTK.BarraCabecalho = GTK.BarraCabecalho()
        janela.definirBarraCabecalho(barra)

        const caixa: GTK.CaixaVertical = GTK.CaixaVertical(8)
        caixa.definirMargem(12)

        const rotulo: GTK.Rotulo = GTK.Rotulo("Inicial")
        isto.rotulo = rotulo
        const campo: GTK.CampoTexto = GTK.CampoTexto("Digite aqui")
        campo.definirTexto("Delégua")
        assercao(campo.obterTexto() == "Delégua")

        const area: GTK.AreaTexto = GTK.AreaTexto()
        area.definirTexto("Linha 1\nLinha 2")
        assercao(area.obterTexto() == "Linha 1\nLinha 2")

        const chk: GTK.CaixaSelecao = GTK.CaixaSelecao("Ativar")
        chk.definirMarcado(verdadeiro)
        assercao(chk.marcado() == verdadeiro)

        const lista: GTK.Lista = GTK.Lista()
        lista.adicionar(GTK.Rotulo("Item A"))
        lista.adicionar(GTK.Rotulo("Item B"))

        const rolagem: GTK.Rolagem = GTK.Rolagem()
        rolagem.definirConteudo(lista)

        const botao: GTK.Botao = GTK.Botao("Testar")
        botao.aoClicar(isto.aoClicarBotao)
        botao.simularClique()

        caixa.adicionar(rotulo)
        caixa.adicionar(campo)
        caixa.adicionar(area)
        caixa.adicionar(chk)
        caixa.adicionar(rolagem)
        caixa.adicionar(botao)
        janela.definirConteudo(caixa)
        janela.mostrar()

        GTK.temporizador(120, isto.encerrar)
    }

    rodar(): inteiro {
        isto.app.aoAtivar(isto.aoAtivar)
        retorna isto.app.executar()
    }
}

const app: TesteGTK = TesteGTK()
const codigo: inteiro = app.rodar()
assercao(codigo == 0 e app.cliques == 1)
escreva("GTK4-SUITE-OK\n")
'''
        gtk_bin = compile_src(gtk_src_limpo, folder, "teste_gtk4")
        libs_gtk = ldd_libs(gtk_bin)
        assert "libgtk-4" in libs_gtk and "libSDL3" not in libs_gtk, libs_gtk
        if os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY"):
            run_gtk = subprocess.run([str(gtk_bin)], capture_output=True, text=True, timeout=15)
            assert run_gtk.returncode == 0, f"GTK4 falhou:\n{run_gtk.stderr}\n{run_gtk.stdout}"
            assert "TIMER-GTK-OK" in run_gtk.stdout and "GTK4-SUITE-OK" in run_gtk.stdout, run_gtk.stdout
            print("GTK4 real (GUI): OK")
        else:
            print("GTK4 compilado e linkado (sem DISPLAY/WAYLAND para execução GUI).")

    # 3. SDL3 completo: ABI 3.x, renderização em lote, texturas, eventos e proteção use-after-free
    if (ROOT / "lib" / "libdelegua_sdl3.o").exists():
        sdl_src = r'''
importar cgd.interface.sdl como SDL

assercao(SDL.inicializar(falso))
const ver: texto = SDL.versao()
assercao(ver.fatiar(0, 2) == "3.")

const janela: SDL.Janela = SDL.Janela("Teste CGD SDL3", 640, 360, verdadeiro)
const tam: dicionario = janela.tamanho()
assercao(tam["largura"] == 640 e tam["altura"] == 360)
assercao(janela.escalaDPI() >= 0.5)

const rend: SDL.Renderizador = janela.criarRenderizador()
rend.definirEscalaLogica(640, 360)
rend.definirTransparencia(verdadeiro)

const tex: SDL.Textura = rend.criarTextura(32, 32)
assercao(tex.largura() == 32 e tex.altura() == 32)

// Renderiza 10 quadros com lote de 200 retângulos cada
var coords: real[] = []
para (var i: inteiro = 0; i < 200; i++) {
    coords.adicionar(real((i * 13) % 600))
    coords.adicionar(real((i * 7) % 320))
    coords.adicionar(16.0)
    coords.adicionar(16.0)
}

const t0: inteiro = SDL.ticksMs()
para (var q: inteiro = 0; q < 10; q++) {
    const eventos: SDL.EventoSDL[] = SDL.obterEventos()
    rend.definirCor(18, 22, 28, 255)
    rend.limpar()
    rend.definirCor(64, 210, 128, 255)
    const desenhados: inteiro = rend.preencherRetangulosLote(coords)
    assercao(desenhados == 200)
    rend.desenharRetangulo(10.0, 10.0, 620.0, 340.0)
    rend.desenharLinha(0.0, 0.0, 640.0, 360.0)
    rend.desenharTextura(tex, 20.0, 20.0, 32.0, 32.0)
    rend.apresentar()
}
const dt: inteiro = SDL.ticksMs() - t0
assercao(dt >= 0)

// Teste de lifetime: usar textura fechada deve falhar com erro seguro (use-after-free bloqueado)
tex.fechar()
var bloqueado: logico = falso
tente {
    rend.desenharTextura(tex, 0.0, 0.0, 16.0, 16.0)
} pegue (erro: Excecao) {
    bloqueado = texto(erro).contem("use-after-free") ou texto(erro).contem("destruído")
}
assercao(bloqueado)

rend.fechar()
janela.fechar()
SDL.finalizar()
escreva("SDL3-SUITE-OK:", ver, ":", dt, "ms\n")
'''
        sdl_bin = compile_src(sdl_src, folder, "teste_sdl3", opt=True)
        libs_sdl = ldd_libs(sdl_bin)
        assert "libSDL3" in libs_sdl and "libgtk-4" not in libs_sdl, libs_sdl

        # Testa em headless (dummy) sempre, e também no driver gráfico real se disponível
        env_dummy = {**os.environ, "SDL_VIDEODRIVER": "dummy"}
        run_dummy = subprocess.run([str(sdl_bin)], env=env_dummy, capture_output=True, text=True, timeout=15)
        assert run_dummy.returncode == 0, f"SDL3 dummy falhou:\n{run_dummy.stderr}\n{run_dummy.stdout}"
        assert "SDL3-SUITE-OK:3." in run_dummy.stdout, run_dummy.stdout
        print("SDL3 (dummy):", run_dummy.stdout.strip())

        if os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY"):
            run_real = subprocess.run([str(sdl_bin)], capture_output=True, text=True, timeout=15)
            assert run_real.returncode == 0, f"SDL3 real falhou:\n{run_real.stderr}\n{run_real.stdout}"
            assert "SDL3-SUITE-OK:3." in run_real.stdout, run_real.stdout
            print("SDL3 (GUI real):", run_real.stdout.strip())

print("Marco D (GTK4 + SDL3 + isolamento ldd): todas as verificações passaram.")
