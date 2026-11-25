#!/usr/bin/env python3
"""Testes reais do Marco C: reorganização hierárquica da stdlib, TUI, HTTP, WebSocket, CSV, TOML, Regex, Coleções, Álgebra e Grafos."""

from pathlib import Path
import socket
import subprocess
import tempfile
import threading
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
CGD = str(ROOT / "cgd")


def compile_and_run(source, name, opt=False):
    with tempfile.TemporaryDirectory(prefix=f"cgd_mc_{name}_") as tmp:
        src = Path(tmp) / f"{name}.delegua"
        out = Path(tmp) / name
        src.write_text(source)
        comp = subprocess.run(
            [CGD, str(src), "-s", str(out)] + (["-o"] if opt else []),
            capture_output=True,
            text=True,
            timeout=60,
        )
        assert comp.returncode == 0, f"Falha compilando {name} (opt={opt}):\n{comp.stderr}\n{comp.stdout}"
        res = subprocess.run([str(out)], capture_output=True, text=True, timeout=30)
        assert res.returncode == 0, f"Falha executando {name} (opt={opt}):\n{res.stderr}\n{res.stdout}"
        return res.stdout


PROGRAMA_STDLIB = r'''
const MemA = importar("cgd:sistema/memoria")
const MemB = importar("cgd:memoria")
const Arq = importar("cgd:sistema/arquivos")
const Bin = importar("cgd:dados/binario")
const Json = importar("cgd:dados/json")
const Cripto = importar("cgd:seguranca/criptografia")
const CSV = importar("cgd:dados/csv")
const TOML = importar("cgd:dados/toml")
const RegexMod = importar("cgd:texto/regex")
const Col = importar("cgd:nucleo/colecoes")
const Alg = importar("cgd:matematica/algebra")
const Grafos = importar("cgd:matematica/grafos")
const Term = importar("cgd:interface/terminal")
const TUI = importar("cgd:interface/tui")
const WS = importar("cgd:rede/websocket")

// 1. Compatibilidade e identidade de aliases hierárquicos
const arena: MemA.Arena = MemB.Arena(4096)
const fatia: MemA.FatiaInt64 = arena.criarInt64(4)
fatia.definir(0, 42)
assercao(fatia.obter(0) == 42)
arena.liberar()

const b: qualquer = Bin.Bytes.deTexto("CGD")
assercao(b.tamanho() == 3)
assercao(Json.analisar('{"ok":true}')["ok"] == verdadeiro)
assercao(tamanho(Cripto.Cripto.sha256("abc")) == 64)

// 2. CSV (RFC 4180 + streaming)
const textoCsv: texto = 'nome,nota,obs\nAna,9.5,"excelente, ""top"""\nBruno,8.0,"linha1\nlinha2"'
const linhasCsv: texto[][] = CSV.CSV.analisar(textoCsv)
assercao(tamanho(linhasCsv) == 3)
assercao(linhasCsv[1][2] == 'excelente, "top"')
assercao(linhasCsv[2][2] == "linha1\nlinha2")
const objsCsv: dicionario[] = CSV.CSV.analisarObjetos(textoCsv)
assercao(tamanho(objsCsv) == 2 e objsCsv[0]["nome"] == "Ana")
const reCsv: texto = CSV.CSV.serializar(linhasCsv)
assercao(CSV.CSV.analisar(reCsv)[1][2] == 'excelente, "top"')

// 3. TOML
const cfgToml: texto = "# Configuração de exemplo\nnome = \"cgd-demo\"\nporta = 8080\nativo = true\ntags = [\"compilador\", \"nativo\"]\n\n[servidor]\nhost = \"127.0.0.1\"\nlimites = { corpo = 1024, conexoes = 64 }\n\n[[rotas]]\ncaminho = \"/\"\n[[rotas]]\ncaminho = \"/saude\"\n"
const parsedToml: dicionario = TOML.TOML.analisar(cfgToml)
assercao(parsedToml["nome"] == "cgd-demo")
assercao(parsedToml["porta"] == 8080)
assercao(parsedToml["ativo"] == verdadeiro)
assercao(parsedToml["servidor"]["host"] == "127.0.0.1")
assercao(parsedToml["servidor"]["limites"]["conexoes"] == 64)
assercao(tamanho(parsedToml["rotas"]) == 2)
assercao(parsedToml["rotas"][1]["caminho"] == "/saude")
const serToml: texto = TOML.TOML.serializar({ nome: "teste", versao: 1 })
assercao(TOML.TOML.analisar(serToml)["nome"] == "teste")

// 4. Regex POSIX
assercao(RegexMod.Regex.valida("^[a-z]+-[0-9]+$"))
assercao(!RegexMod.Regex.valida("[invalido"))
const re: RegexMod.Regex = RegexMod.Regex("([a-z]+)=([0-9]+)")
assercao(re.corresponde("a=10 b=20"))
const m1: qualquer = re.encontrar("a=10 b=20")
assercao(m1 != nulo e m1["texto"] == "a=10" e m1["grupos"][0] == "a" e m1["grupos"][1] == "10")
const todos: dicionario[] = re.encontrarTodos("a=10 b=20 c=30")
assercao(tamanho(todos) == 3 e todos[2]["grupos"][1] == "30")
const reNum: RegexMod.Regex = RegexMod.Regex("[0-9]+")
assercao(reNum.substituir("x1y22z333", "#") == "x#y#z#")
const reSep: RegexMod.Regex = RegexMod.Regex("[,;]+")
const partes: texto[] = reSep.dividir("um,dois;;tres")
assercao(tamanho(partes) == 3 e partes[2] == "tres")

// 5. Coleções (Deque, HeapMin, FilaPrioridade)
const dq: Col.Deque = Col.Deque()
dq.empilharFim(2)
dq.empilharInicio(1)
dq.empilharFim(3)
assercao(dq.tamanho() == 3 e dq.desempilharInicio() == 1 e dq.desempilharFim() == 3 e dq.desempilharInicio() == 2)
const fp: Col.FilaPrioridade = Col.FilaPrioridade(falso)
fp.enfileirar("baixa", 10.0)
fp.enfileirar("urgente", 1.0)
fp.enfileirar("media", 5.0)
assercao(fp.desenfileirar() == "urgente" e fp.desenfileirar() == "media" e fp.desenfileirar() == "baixa")

// 6. Álgebra Linear
const v1: Alg.Vetor3 = Alg.Vetor3(1.0, 0.0, 0.0)
const v2: Alg.Vetor3 = Alg.Vetor3(0.0, 1.0, 0.0)
const vc: Alg.Vetor3 = v1.produtoVetorial(v2)
assercao(vc.x == 0.0 e vc.y == 0.0 e vc.z == 1.0)
const id: Alg.Matriz = Alg.Matriz.identidade(2)
const mA: Alg.Matriz = Alg.Matriz(2, 2, 0.0)
mA.definir(0, 0, 2.0)
mA.definir(0, 1, 3.0)
mA.definir(1, 0, 4.0)
mA.definir(1, 1, 5.0)
const mP: Alg.Matriz = mA.multiplicar(id)
assercao(mP.obter(0, 1) == 3.0 e mP.obter(1, 0) == 4.0)
assercao(mA.transpor().obter(1, 0) == 3.0)

// 7. Grafos (BFS, DFS, Dijkstra, Ordenação Topológica)
const g: Grafos.Grafo = Grafos.Grafo(verdadeiro)
g.adicionarAresta("A", "B", 2.0)
g.adicionarAresta("A", "C", 10.0)
g.adicionarAresta("B", "C", 3.0)
g.adicionarAresta("C", "D", 1.0)
const dij: dicionario = g.dijkstra("A", "D")
assercao(dij["encontrado"] == verdadeiro e dij["distancia"] == 6.0)
assercao(tamanho(dij["caminho"]) == 4 e dij["caminho"][1] == "B")
const topo: texto[] = g.ordenacaoTopologica()
assercao(tamanho(topo) == 4 e topo[0] == "A" e topo[3] == "D")

// 8. Terminal e TUI (double buffering incremental, Unicode, ASCII fallback, Menu, CampoTexto)
assercao(Term.Terminal.larguraVisual("Olá") == 3)
assercao(Term.Terminal.larguraVisual("♔") == 1)
const _supUni: logico = Term.Terminal.suportaUnicode()
const _supCor: logico = Term.Terminal.suportaCores()
const _supTc: logico = Term.Terminal.suportaTrueColor()
assercao(_supUni == verdadeiro ou _supUni == falso)
assercao(_supCor == verdadeiro ou _supCor == falso)
assercao(_supTc == verdadeiro ou _supTc == falso)
const tela: TUI.Tela = TUI.Tela(40, 10, verdadeiro, verdadeiro)
tela.limpar()
tela.caixa(0, 0, 40, 10, "CGD TUI")
tela.escrever(2, 2, "Bem-vindo")
tela.barraProgresso(2, 4, 10, 0.5)
const menu: TUI.Menu = TUI.Menu(["Jogar", "Configurar", "Sair"])
menu.moverBaixo()
assercao(menu.itemAtual() == "Configurar")
menu.desenhar(tela, 2, 6, 20, 3)
const alt1: inteiro = tela.apresentar()
const alt2: inteiro = tela.apresentar()
assercao(alt1 > 0 e alt2 == 0)
const render: texto = tela.renderizarTexto()
assercao(render.contem("CGD TUI") e render.contem("Bem-vindo") e render.contem("> Configurar"))
const telaAscii: TUI.Tela = TUI.Tela(20, 4, verdadeiro, falso)
telaAscii.caixa(0, 0, 20, 4, "ASCII")
assercao(telaAscii.renderizarTexto().contem("+---"))

// 9. WebSocket RFC 6455 vetor oficial de handshake e framing
assercao(WS.ProtocoloWS.calcularAccept("dGhlIHNhbXBsZSBub25jZQ==") == "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")
const frameEnc: texto = WS.ProtocoloWS.codificarQuadro(WS.OpcodeWS.TEXTO, "Olá WebSocket!", verdadeiro)
const frameDec: dicionario = WS.ProtocoloWS.decodificarQuadro(frameEnc)
assercao(!frameDec["incompleto"] e frameDec["erro"] == "" e frameDec["quadro"].payload == "Olá WebSocket!")

escreva("STDLIB-EXPANSAO-OK")
'''

PROGRAMA_HTTP_WS = r'''
importar cgd.rede.http como HTTP
importar cgd.rede.websocket como WS

// Teste integrado HTTP assíncrono + WebSocket assíncrono em loopback
assincrona funcao rodarTestesRede(): vazio {
    // 1. Servidor HTTP assíncrono
    const srv: HTTP.Servidor = HTTP.Servidor()
    srv.obter("/saude", funcao(req: qualquer, res: qualquer) {
        res.json({ status: "ok", modo: "async" })
    })
    srv.obter("/eco/:valor", funcao(req: qualquer, res: qualquer) {
        res.texto("eco:" + texto(req.parametro("valor", "")))
    })
    srv.obter("/parar", funcao(req: qualquer, res: qualquer) {
        res.texto("tchau").pararServidor()
    })
    srv.abrir("127.0.0.1", 0)
    const portaHttp: inteiro = srv.portaLocal()
    srv.fechar()
    const tarefaHttp: Promessa<vazio> = srv.escutarAsync("127.0.0.1", portaHttp)

    // Faz 3 requisições HTTP concorrentes usando sockets assíncronos
    assincrona funcao requisitar(p: inteiro, caminho: texto): texto {
        const sock: qualquer = importar("cgd:sockets")
        const c: qualquer = aguardar sock.conectarAsync("127.0.0.1", p, 5000)
        aguardar c.enviarAsync("GET " + caminho + " HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n", 5000)
        var resp: texto = ""
        enquanto verdadeiro {
            const ped: texto = aguardar c.receberAsync(4096, 5000)
            se tamanho(ped) == 0 {
                sustar
            }
            resp = resp + ped
        }
        c.fechar()
        retorna resp
    }

    const r1: Promessa<texto> = requisitar(portaHttp, "/saude")
    const r2: Promessa<texto> = requisitar(portaHttp, "/eco/delegua")
    const b1: texto = aguardar r1
    const b2: texto = aguardar r2
    assercao(b1.contem('"status":"ok"'))
    assercao(b2.contem("eco:delegua"))
    const b3: texto = aguardar requisitar(portaHttp, "/parar")
    assercao(b3.contem("tchau"))
    aguardar tarefaHttp

    // 2. Servidor WebSocket assíncrono + cliente RFC 6455 (usando sockets async para não bloquear o mesmo event loop!)
    const wsSrv: WS.ServidorWebSocket = WS.ServidorWebSocket(5000)
    wsSrv.abrir("127.0.0.1", 0)
    const portaWs: inteiro = wsSrv.portaLocal()
    wsSrv.aoMensagem(funcao(conn: qualquer, msg: texto) {
        conn.enviarTexto("ECO:" + msg)
    })
    const tarefaWs: Promessa<vazio> = wsSrv.escutarAsync("127.0.0.1", portaWs)

    // Conecta cliente WebSocket assíncrono na mesma thread do event loop
    const sock: qualquer = importar("cgd:sockets")
    const cws: qualquer = aguardar sock.conectarAsync("127.0.0.1", portaWs, 5000)
    const chave: texto = "dGhlIHNhbXBsZSBub25jZQ=="
    aguardar cws.enviarAsync("GET /chat HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: " + chave + "\r\nSec-WebSocket-Version: 13\r\n\r\n", 5000)
    const respHs: texto = aguardar cws.receberAsync(4096, 5000)
    assercao(respHs.contem("101") e respHs.contem("s3pPLMBiTxaQ9kYGzzhZRbK+xOo="))

    // Ping -> Pong
    aguardar cws.enviarAsync(WS.ProtocoloWS.codificarQuadro(WS.OpcodeWS.PING, "teste-ping", verdadeiro), 5000)
    const rawPong: texto = aguardar cws.receberAsync(4096, 5000)
    const qPong: dicionario = WS.ProtocoloWS.decodificarQuadro(rawPong)
    assercao(!qPong["incompleto"] e qPong["quadro"].opcode == WS.OpcodeWS.PONG e qPong["quadro"].payload == "teste-ping")

    // Texto -> Echo
    aguardar cws.enviarAsync(WS.ProtocoloWS.codificarQuadro(WS.OpcodeWS.TEXTO, "olá mundo", verdadeiro), 5000)
    const rawEco: texto = aguardar cws.receberAsync(4096, 5000)
    const qEco: dicionario = WS.ProtocoloWS.decodificarQuadro(rawEco)
    assercao(!qEco["incompleto"] e qEco["quadro"].opcode == WS.OpcodeWS.TEXTO e qEco["quadro"].payload == "ECO:olá mundo")

    cws.fechar()
    wsSrv.fechar()
    aguardar tarefaWs

    escreva("HTTP-WS-OK")
}

rodarTestesRede()
'''

for opt in [False, True]:
    out1 = compile_and_run(PROGRAMA_STDLIB, "stdlib_exp", opt=opt)
    assert "STDLIB-EXPANSAO-OK" in out1, out1

out2 = compile_and_run(PROGRAMA_HTTP_WS, "http_ws_exp", opt=False)
assert "HTTP-WS-OK" in out2, out2
out3 = compile_and_run(PROGRAMA_HTTP_WS, "http_ws_exp_opt", opt=True)
assert "HTTP-WS-OK" in out3, out3

print("Stdlib expansão (Marco C): todas as verificações (sem/com -o) passaram.")
