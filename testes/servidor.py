#!/usr/bin/env python3
"""Servidor real compilado: framing hostil, limites, lifecycle e roteamento HTTP."""

import json
import socket
import subprocess
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = r"""
const Servidor: qualquer = importar("cgd:servidor")
const IO: qualquer = importar("cgd:io").IO
var app: qualquer = Servidor.HTTP(2048, 4096, 150, 200)
app.usar(funcao(req: qualquer, res: qualquer): vazio {
    req.contexto["middleware"] = "sim"
    res.cabecalho("x-cgd", "nativo")
    se req.caminho == "/bloqueado" { res.status(403).enviar("bloqueado") }
})
app.get("/", funcao(req: qualquer, res: qualquer): vazio { res.enviar("Olá 🌍") })
app.head("/", funcao(req: qualquer, res: qualquer): vazio { res.enviar("Olá 🌍") })
app.get("/usuario/:nome", funcao(req: qualquer, res: qualquer): vazio {
    res.json({nome: req.parametro("nome"), query: req.consulta, middleware: req.contexto["middleware"]})
})
app.post("/eco", funcao(req: qualquer, res: qualquer): vazio { res.status(201).json(req.json()) })
app.put("/eco", funcao(req: qualquer, res: qualquer): vazio { res.enviar(req.texto()) })
app.patch("/eco", funcao(req: qualquer, res: qualquer): vazio { res.enviar(req.texto()) })
app.delete("/eco", funcao(req: qualquer, res: qualquer): vazio { res.status(204).enviar() })
app.options("*", funcao(req: qualquer, res: qualquer): vazio { res.cabecalho("allow", "GET, POST").status(204).enviar() })
app.get("/erro", funcao(req: qualquer, res: qualquer): vazio { falhar "segredo que não pode vazar" })
app.get("/injecao", funcao(req: qualquer, res: qualquer): vazio { res.cabecalho("x-teste", "a\r\nInjected: sim").enviar("invalido") })
app.get("/vazio", funcao(req: qualquer, res: qualquer): vazio {})
app.get("/parar", funcao(req: qualquer, res: qualquer): vazio { res.enviar("fim").pararServidor() })
app.abrir("127.0.0.1", 0)
IO.escreverLinha(texto(app.portaLocal()))
tente {
    enquanto app.ativo() {
        se !app.atenderUma(5000) { falhar "teste sem conexão no prazo" }
    }
} pegue (erro) {
    app.fechar()
}
"""


def exchange(port, payload, *, pieces=None):
    with socket.create_connection(("127.0.0.1", port), timeout=3) as client:
        client.settimeout(3)
        if pieces:
            for piece in pieces:
                client.sendall(piece)
                time.sleep(0.01)
        else:
            client.sendall(payload)
        answer = bytearray()
        while True:
            try:
                chunk = client.recv(65536)
            except ConnectionResetError:
                break
            if not chunk:
                break
            answer.extend(chunk)
    return bytes(answer)


def parse(answer, head=False):
    headers, body = answer.split(b"\r\n\r\n", 1)
    lines = headers.split(b"\r\n")
    status = int(lines[0].split()[1])
    fields = dict(line.lower().split(b": ", 1) for line in lines[1:])
    assert fields[b"connection"] == b"close"
    if b"content-length" in fields:
        assert len(body) == (0 if head else int(fields[b"content-length"]))
    return status, fields, body


def request(port, method="GET", path="/", body=b"", *, headers=b""):
    wire = (
        f"{method} {path} HTTP/1.1\r\nHost: localhost\r\nContent-Length: {len(body)}\r\n".encode()
        + headers
        + b"\r\n"
        + body
    )
    return parse(exchange(port, wire), method == "HEAD")


with tempfile.TemporaryDirectory(prefix="cgd-http-") as temp:
    folder = Path(temp)
    source, binary = folder / "servidor.delegua", folder / "servidor"
    source.write_text(SOURCE)
    for optimized in [False, True]:
        subprocess.run(
            [str(ROOT / "cgd"), str(source), "-s", str(binary)] + (["-o"] if optimized else []),
            check=True,
        )
        server = subprocess.Popen(
            [str(binary)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
        try:
            port = int(server.stdout.readline())
            fd_start = len(list(Path(f"/proc/{server.pid}/fd").iterdir()))
            assert request(port)[2] == "Olá 🌍".encode()
            assert request(port, "HEAD")[2] == b""
            status, _, body = request(port, path="/usuario/Jos%C3%A9?x=1&x=2&v=a+b&v=%2B")
            assert status == 200
            assert json.loads(body) == {
                "nome": "José",
                "query": {"x": ["1", "2"], "v": ["a b", "+"]},
                "middleware": "sim",
            }
            assert request(port, "POST", "/eco", b'{"ok":true}')[0] == 201
            for method in ["PUT", "PATCH"]:
                assert request(port, method, "/eco", b"abc\x00def")[2] == b"abc\x00def"
            assert request(port, "DELETE", "/eco")[0] == 204
            assert request(port, "OPTIONS", "*")[0] == 204
            assert request(port, path="/ausente")[0] == 404
            assert request(port, "POST", "/")[0] == 405
            assert request(port, path="/bloqueado")[0] == 403
            assert request(port, path="/vazio")[0] == 204
            result = request(port, path="/erro")
            assert result[0] == 500 and b"segredo" not in result[2]
            assert parse(exchange(port, b"HEAD / HTTP/1.1\r\n\r\n"), head=True)[0] == 400
            # Nenhum byte injetado deve chegar ao cliente, mesmo por erro do handler.
            injected = exchange(port, b"GET /injecao HTTP/1.1\r\nHost: x\r\n\r\n")
            assert b"Injected" not in injected and parse(injected)[0] == 500
            bad = [
                (b"CONNECT / HTTP/1.1\r\nHost: x\r\n\r\n", 501),
                (b"GET * HTTP/1.1\r\nHost: x\r\n\r\n", 400),
                (b"GET / HTTP/1.1\r\nHost: x:99999\r\n\r\n", 400),
                (b"GET / HTTP/1.1\r\nHost: [invalid]\r\n\r\n", 400),
                (b"GET / HTTP/1.1\r\nHost: x#fragment\r\n\r\n", 400),
                (b"GET / HTTP/1.1\r\n\r\n", 400),
                (b"GET / HTTP/1.0\r\nHost: x\r\n\r\n", 400),
                (b"GET / HTTP/1.1\r\nHost: x\r\nHost: y\r\n\r\n", 400),
                (b"GET / HTTP/1.1\r\nHost : x\r\n\r\n", 400),
                (b"GET / HTTP/1.1\r\nHost: x\r\n folded: x\r\n\r\n", 400),
                (
                    b"POST /eco HTTP/1.1\r\nHost: x\r\nContent-Length: 2\r\nContent-Length: 2\r\n\r\n{}",
                    400,
                ),
                (b"POST /eco HTTP/1.1\r\nHost: x\r\nContent-Length: +2\r\n\r\n{}", 400),
                (b"POST /eco HTTP/1.1\r\nHost: x\r\nContent-Length: 2,2\r\n\r\n{}", 400),
                (
                    b"POST /eco HTTP/1.1\r\nHost: x\r\nContent-Length: 999999999999999999999999\r\n\r\n",
                    413,
                ),
                (b"POST /eco HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n", 501),
                (
                    b"POST /eco HTTP/1.1\r\nHost: x\r\nContent-Length: 2\r\nTransfer-Encoding: chunked\r\n\r\n",
                    501,
                ),
                (b"POST /eco HTTP/1.1\r\nHost: x\r\nExpect: 100-continue\r\n\r\n", 417),
                (b"GET /%2e%2e/segredo HTTP/1.1\r\nHost: x\r\n\r\n", 400),
                (b"GET /a%2fb HTTP/1.1\r\nHost: x\r\n\r\n", 400),
                (b"GET /%00 HTTP/1.1\r\nHost: x\r\n\r\n", 400),
                (b"GET /%xy HTTP/1.1\r\nHost: x\r\n\r\n", 400),
                (b"GET / HTTP/1.1\r\nHost: x\r\nX: a\x00b\r\n\r\n", 400),
                (b"GET / HTTP/1.1\r\nHost: x\r\nX: " + b"a" * 2100 + b"\r\n\r\n", 431),
                (b"PUT /eco HTTP/1.1\r\nHost: x\r\nContent-Length: 4097\r\n\r\n", 413),
            ]
            for payload, status in bad:
                actual = parse(exchange(port, payload))[0]
                assert actual == status, (payload, actual, status)
            partial = [b"PUT /eco HTTP/1.1\r\nHo", b"st: x\r\nContent-Length: 3\r\n\r", b"\nabc"]
            assert parse(exchange(port, b"", pieces=partial))[2] == b"abc"
            # Deadline total, não reiniciado por byte: slowloris termina em 408.
            begin = time.monotonic()
            assert parse(exchange(port, b"GET / HTTP/1.1\r\nHost:"))[0] == 408
            assert time.monotonic() - begin < 1.5
            assert (
                parse(
                    exchange(port, b"PUT /eco HTTP/1.1\r\nHost: x\r\nContent-Length: 3\r\n\r\na")
                )[0]
                == 408
            )
            # Pipelining não executa a segunda requisição: conexão fecha após a primeira.
            pipeline = b"GET / HTTP/1.1\r\nHost: x\r\n\r\n" * 2
            assert exchange(port, pipeline).count(b"HTTP/1.1") == 1
            for _ in range(8):
                with socket.create_connection(("127.0.0.1", port), timeout=3) as client:
                    client.sendall(b"GET / HTTP/1.1\r\nHost:")
            # Clientes concorrentes são atendidos em sequência, sem threads no GC.
            with ThreadPoolExecutor(max_workers=8) as executor:
                assert all(
                    code == 200
                    for code in executor.map(
                        lambda _, selected_port=port: request(selected_port)[0], range(16)
                    )
                )
            for _ in range(20):
                assert request(port)[0] == 200
            assert len(list(Path(f"/proc/{server.pid}/fd").iterdir())) <= fd_start + 1
            assert request(port, path="/parar")[2] == b"fim"
            server.wait(timeout=3)
            assert server.returncode == 0, server.stderr.read()
        finally:
            if server.poll() is None:
                server.kill()
                server.wait()
            server.stdout.close()
            server.stderr.close()
print("HTTP: rotas, limites, entradas hostis, desconexões e shutdown passaram nos dois modos.")
