#!/usr/bin/env python3
"""Contratos TCP cliente/servidor e recursos opacos em programas CGD reais."""

import socket
import subprocess
import tempfile
import threading
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = r"""
const Sockets: qualquer = importar("cgd:sockets")
const Primitivas: qualquer = importar("cgd:nativo").Primitivas
const Processo: qualquer = importar("cgd:processo").Processo
var porta: inteiro = inteiro(Processo.argumentos()[0])
var cliente: qualquer = Sockets.conectar("127.0.0.1", porta, 1000)
tente {
    se cliente.enviar("ping" + Primitivas.caractereUnicode(0) + "🌍", 1000) != 9 { falhar "tamanho em bytes" }
    var recebidos: texto = ""
    enquanto tamanho(recebidos) < 4 { recebidos += cliente.receber(2, 1000) }
    se recebidos != "pong" { falhar "eco" }
    se cliente.receber(10, 1000) != "" { falhar "EOF" }
} finalmente { cliente.fechar(); cliente.fechar() }
var fechou: logico = falso
tente { cliente.enviar("erro") } pegue (erro) { fechou = verdadeiro }
se !fechou { falhar "recurso fechado aceito" }
var invalido: logico = falso
tente { Sockets.Conexao("não é um handle").receber() } pegue (erro) { invalido = verdadeiro }
se !invalido { falhar "recurso forjado aceito" }
var servidor: qualquer = Sockets.OuvinteTCP("127.0.0.1", 0)
var reabrir: inteiro = servidor.portaLocal()
se servidor.aceitar(10) != nulo { falhar "timeout de accept" }
servidor.fechar(); servidor.fechar()
para (var i: inteiro = 0; i < 20; i++) {
    servidor = Sockets.OuvinteTCP("127.0.0.1", reabrir)
    servidor.fechar()
}
var recursos: qualquer[] = []
para (var i: inteiro = 0; i < 128; i++) {
    recursos.adicionar(Sockets.OuvinteTCP("127.0.0.1", 0))
}
var limitado: logico = falso
tente { Sockets.OuvinteTCP("127.0.0.1", 0) } pegue (erro) { limitado = verdadeiro }
para cada recurso: qualquer em recursos { recurso.fechar() }
se !limitado { falhar "limite de sockets ignorado" }
var invalidos: inteiro = 0
tente { Sockets.conectar("localhost", 80) } pegue (erro) { invalidos++ }
tente { Sockets.OuvinteTCP("127.0.0.1", -1) } pegue (erro) { invalidos++ }
tente { Sockets.conectar("127.0.0.1", 0, 0) } pegue (erro) { invalidos++ }
se invalidos != 3 { falhar "argumentos inválidos aceitos" }
escreva("sockets OK")
"""


def serve(listener):
    with listener, listener.accept()[0] as client:
        client.settimeout(3)
        received = bytearray()
        while len(received) < 9:
            received.extend(client.recv(20))
        assert received == b"ping\x00" + "🌍".encode()
        client.sendall(b"pong")


with tempfile.TemporaryDirectory(prefix="cgd-sockets-") as temporary:
    source = Path(temporary) / "cliente.delegua"
    binary = Path(temporary) / "cliente"
    source.write_text(SOURCE)
    for optimize in [False, True]:
        subprocess.run(
            [str(ROOT / "cgd"), str(source), "-s", str(binary)] + (["-o"] if optimize else []),
            check=True,
        )
        listener = socket.socket()
        listener.bind(("127.0.0.1", 0))
        listener.listen(1)
        worker = threading.Thread(target=serve, args=(listener,), daemon=True)
        worker.start()
        result = subprocess.run(
            [str(binary), str(listener.getsockname()[1])],
            check=False,
            capture_output=True,
            text=True,
            timeout=10,
        )
        worker.join(timeout=4)
        assert not worker.is_alive()
        assert result.returncode == 0, result.stdout + result.stderr
        assert result.stdout == "sockets OK\n"
print("Sockets TCP: argv, EOF, close idempotente, handles, limites e reuso de porta passaram.")
