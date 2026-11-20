#!/usr/bin/env python3
"""Benchmark repetível do servidor sequencial; clientes usam uma conexão por request."""

import argparse
import json
import math
import os
import platform
import socket
import statistics
import subprocess
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = """
const Servidor: qualquer = importar("cgd:servidor")
const IO: qualquer = importar("cgd:io").IO
var app: qualquer = Servidor.HTTP()
app.get("/", funcao(req: qualquer, res: qualquer): vazio { res.enviar("CGD") })
app.get("/parar", funcao(req: qualquer, res: qualquer): vazio { res.enviar("fim").pararServidor() })
app.abrir("127.0.0.1", 0)
IO.escreverLinha(texto(app.portaLocal()))
tente { enquanto app.ativo() { app.atenderUma() } } finalmente { app.fechar() }
"""


def request(port, path="/"):
    start = time.perf_counter()
    with socket.create_connection(("127.0.0.1", port), timeout=15) as stream:
        stream.settimeout(15)
        stream.sendall(f"GET {path} HTTP/1.1\r\nHost: localhost\r\n\r\n".encode())
        answer = bytearray()
        while True:
            chunk = stream.recv(65536)
            if not chunk:
                break
            answer.extend(chunk)
    assert answer.startswith(b"HTTP/1.1 200 ")
    assert answer.endswith(b"\r\n\r\nCGD") if path == "/" else answer.endswith(b"fim")
    return (time.perf_counter() - start) * 1000


def usage(pid):
    status = Path(f"/proc/{pid}/status").read_text()
    rss = next(int(line.split()[1]) for line in status.splitlines() if line.startswith("VmHWM:"))
    # Depois do comm entre parênteses, utime/stime são campos 12/13 da cauda.
    fields = Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()
    cpu = (int(fields[11]) + int(fields[12])) / os.sysconf("SC_CLK_TCK")
    return rss, cpu


def percentile(samples, fraction):
    ordered = sorted(samples)
    return ordered[max(0, math.ceil(len(ordered) * fraction) - 1)]


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--rodadas", type=int, default=5)
parser.add_argument("--requisicoes", type=int, default=200)
parser.add_argument("--clientes", type=int, default=8)
parser.add_argument("--saida", type=Path, default=ROOT / "out/benchmark-http.json")
args = parser.parse_args()
if (
    not 2 <= args.rodadas <= 100
    or not 1 <= args.requisicoes <= 100000
    or not 1 <= args.clientes <= 32
):
    parser.error("Use 2..100 rodadas, 1..100000 requisições e 1..32 clientes.")
results = []
with tempfile.TemporaryDirectory(prefix="cgd-bench-http-") as temporary:
    source, binary = Path(temporary) / "servidor.delegua", Path(temporary) / "servidor"
    source.write_text(SOURCE)
    subprocess.run([str(ROOT / "cgd"), str(source), "-o", "-s", str(binary)], check=True)
    for _ in range(args.rodadas):
        started = time.perf_counter()
        server = subprocess.Popen(
            [str(binary)], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True
        )
        try:
            port = int(server.stdout.readline())
            startup = (time.perf_counter() - started) * 1000
            # Aquecimento e recuperação de uma mensagem inválida ficam fora da medição.
            for _ in range(10):
                request(port)
            with socket.create_connection(("127.0.0.1", port), timeout=15) as stream:
                stream.sendall(b"GET / HTTP/1.1\r\n\r\n")
                while stream.recv(65536):
                    pass
            recovery = request(port)
            _, initial_cpu = usage(server.pid)
            start = time.perf_counter()
            with ThreadPoolExecutor(max_workers=args.clientes) as executor:
                samples = list(
                    executor.map(
                        lambda _, selected_port=port: request(selected_port),
                        range(args.requisicoes),
                    )
                )
            elapsed = time.perf_counter() - start
            rss, final_cpu = usage(server.pid)
            results.append(
                {
                    "rps": len(samples) / elapsed,
                    "duracao_s": elapsed,
                    "p50_ms": percentile(samples, 0.50),
                    "p95_ms": percentile(samples, 0.95),
                    "p99_ms": percentile(samples, 0.99),
                    "rss_pico_kib": rss,
                    "cpu_servidor_s": final_cpu - initial_cpu,
                    "cpu_percent_um_nucleo": (final_cpu - initial_cpu) / elapsed * 100,
                    "inicializacao_ms": startup,
                    "requisicao_apos_erro_ms": recovery,
                }
            )
            request(port, "/parar")
            server.wait(timeout=15)
            assert server.returncode == 0
        finally:
            if server.poll() is None:
                server.kill()
                server.wait()
            server.stdout.close()
report = {
    "sistema": platform.platform(),
    "python_cliente": platform.python_version(),
    "cgd": subprocess.check_output([str(ROOT / "cgd"), "--versao"], text=True).strip(),
    "modelo": "HTTP/1.1 sequencial, IPv4 loopback, conexão nova por request, resposta de 3 bytes",
    "configuracao": {
        "rodadas": args.rodadas,
        "requisicoes": args.requisicoes,
        "clientes": args.clientes,
        "aquecimento": 10,
    },
    "rodadas": results,
    "rps_mediana": statistics.median(row["rps"] for row in results),
}
args.saida.parent.mkdir(parents=True, exist_ok=True)
args.saida.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
print(f"Benchmark gravado em {args.saida}; compare várias rodadas em ambientes equivalentes.")
