#!/usr/bin/env python3
"""Regressões de cgd:bytes, cgd:cripto, cgd:compressao, cgd:sqlite, DataHora, UDP/DNS/IPv6 e HTTPAsync."""

from pathlib import Path
import socket
import subprocess
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parents[1]
CGD = str(ROOT / "cgd")
checks = 0


def run_program(source, expected, opt=False):
    global checks
    with tempfile.TemporaryDirectory(prefix="cgd-stdadv-") as tmp:
        src = Path(tmp) / "prog.delegua"
        exe = Path(tmp) / "prog"
        src.write_text(source, encoding="utf-8")
        cmd = [CGD, str(src), "-s", str(exe)]
        if opt:
            cmd.append("-o")
        comp = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        assert comp.returncode == 0, f"Compilação falhou (opt={opt}):\n{comp.stderr}\n{comp.stdout}"
        proc = subprocess.run([str(exe)], capture_output=True, text=True, timeout=30)
        assert proc.returncode == 0, f"Execução falhou (opt={opt}):\n{proc.stderr}\n{proc.stdout}"
        assert proc.stdout.strip() == expected.strip(), (
            f"Saída inesperada (opt={opt}):\nesperado:\n{expected}\nrecebido:\n{proc.stdout}"
        )
        checks += 1


for optimized in (False, True):
    # 1. cgd:bytes
    run_program(
        """
const Bytes: qualquer = importar("cgd:bytes").Bytes
var b: qualquer = Bytes.deVetor([0, 65, 66, 255])
escreva(b.tamanho())
escreva(b.obter(0), b.obter(1), b.obter(-1))
b.definir(0, 42)
escreva(b.paraHex())
var c: qualquer = Bytes.deHex("2a4142ff")
escreva(b.igual(c))
var b64: texto = Bytes.deTexto("Delégua!").paraBase64()
escreva(Bytes.deBase64(b64).paraTexto())
var j: qualquer = Bytes.deTexto("abc").concatenar(Bytes.deTexto("def"))
escreva(j.fatiar(2, 5).paraTexto())
escreva(j.encontrar(Bytes.deTexto("cd")))
""",
        "4\n065255\n2a4142ff\nverdadeiro\nDelégua!\ncde\n2",
        opt=optimized,
    )

    # 2. cgd:cripto (OpenSSL libcrypto)
    run_program(
        """
const Cripto: qualquer = importar("cgd:cripto").Cripto
escreva(Cripto.sha256("abc"))
escreva(tamanho(Cripto.sha512("abc")))
escreva(Cripto.hmacSha256("key", "The quick brown fox jumps over the lazy dog"))
const tok1: texto = Cripto.hexAleatorio(16)
const tok2: texto = Cripto.hexAleatorio(16)
escreva(tamanho(tok1) == 32 e tok1 != tok2)
escreva(Cripto.compararConstante("segredo", "segredo"))
escreva(Cripto.compararConstante("segredo", "segredx"))
escreva(Cripto.base64Decodificar(Cripto.base64Codificar("cgd-cripto-123")))
""",
        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad\n"
        "128\n"
        "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8\n"
        "verdadeiro\nverdadeiro\nfalso\ncgd-cripto-123",
        opt=optimized,
    )

    # 3. cgd:compressao (zlib gzip + deflate + proteção contra bomba de descompressão)
    run_program(
        """
const Comp: qualquer = importar("cgd:compressao").Compressao
const Bytes: qualquer = importar("cgd:bytes").Bytes
var textoGrande: texto = ""
para var i: inteiro = 0; i < 200; i++ {
    textoGrande = textoGrande + "compilador-delegua-"
}
const gz: texto = Comp.gzipComprimir(textoGrande)
escreva(Bytes.deTexto(gz).tamanho() < Bytes.deTexto(textoGrande).tamanho())
escreva(Comp.gzipDescomprimir(gz) == textoGrande)
const df: texto = Comp.deflateComprimir("ola mundo 123")
escreva(Comp.deflateDescomprimir(df))
tente {
    Comp.gzipDescomprimir(gz, 64)
    escreva("NAO")
} pegue (erro: Excecao) {
    escreva("limite_ok")
}
""",
        "verdadeiro\nverdadeiro\nola mundo 123\nlimite_ok",
        opt=optimized,
    )

    # 4. cgd:sqlite (parametrizado, transações, tipos, fechamento)
    run_program(
        """
const SQLite: qualquer = importar("cgd:sqlite").SQLite
const db: qualquer = SQLite.abrir(":memory:")
tente {
    db.executar("CREATE TABLE usuarios (id INTEGER PRIMARY KEY AUTOINCREMENT, nome TEXT NOT NULL, nota REAL, ativo INTEGER)")
    db.iniciarTransacao()
    db.executar("INSERT INTO usuarios (nome, nota, ativo) VALUES (?, ?, ?)", ["Ana", 9.5, verdadeiro])
    const id1: inteiro = db.ultimoId()
    db.executar("INSERT INTO usuarios (nome, nota, ativo) VALUES (?, ?, ?)", ["' OR 1=1 --", 7.25, falso])
    db.confirmar()

    db.iniciarTransacao()
    db.executar("INSERT INTO usuarios (nome, nota, ativo) VALUES (?, ?, ?)", ["Descartado", 0.0, falso])
    db.reverter()

    const linhas: dicionario[] = db.consultar("SELECT id, nome, nota, ativo FROM usuarios ORDER BY id")
    escreva(id1)
    escreva(tamanho(linhas))
    escreva(linhas[0]["nome"])
    escreva(linhas[1]["nome"])
    const busca: qualquer = db.consultarUm("SELECT nome FROM usuarios WHERE nome = ?", ["' OR 1=1 --"])
    escreva(busca["nome"])
} finalmente {
    db.fechar()
}
escreva(db.aberto())
tente {
    db.consultar("SELECT 1")
    escreva("NAO")
} pegue (erro: Excecao) {
    escreva("fechado_ok")
}
""",
        "1\n2\nAna\n' OR 1=1 --\n' OR 1=1 --\nfalso\nfechado_ok",
        opt=optimized,
    )

    # 5. cgd:tempo DataHora + cgd:sockets UDP & DNS & IPv6
    run_program(
        """
const DataHora: qualquer = importar("cgd:tempo").DataHora
const d: qualquer = DataHora.deUTC(2026, 11, 20, 14, 30, 5)
escreva(d.formatarISO())
const d2: qualquer = d.adicionarSegundos(3661)
escreva(d2.formatarISO())
escreva(DataHora.agora().ano() >= 2026)

const Sockets: qualquer = importar("cgd:sockets")
const ips: texto[] = Sockets.resolverDNS("localhost", "ipv4")
escreva(tamanho(ips) >= 1 e ips[0] == "127.0.0.1")

const s1: qualquer = Sockets.abrirUDP("127.0.0.1", 0)
const s2: qualquer = Sockets.abrirUDP("127.0.0.1", 0)
tente {
    const enviados: inteiro = s1.enviarPara("ping-udp", "127.0.0.1", s2.portaLocal())
    const pacote: dicionario = s2.receberDe(1024, 5000)
    escreva(enviados)
    escreva(pacote["dados"])
    escreva(pacote["endereco"])
} finalmente {
    s1.fechar()
    s2.fechar()
}
""",
        "2026-11-20T14:30:05Z\n2026-11-20T15:31:06Z\nverdadeiro\nverdadeiro\n8\nping-udp\n127.0.0.1",
        opt=optimized,
    )

# 6. Servidor HTTPAsync concorrente com keep-alive (múltiplas requisições na mesma conexão + clientes simultâneos)
with tempfile.TemporaryDirectory(prefix="cgd-http-async-") as tmp:
    src = Path(tmp) / "srv.delegua"
    exe = Path(tmp) / "srv"
    port_file = Path(tmp) / "porta.txt"
    src.write_text(
        f"""
assincrona funcao principal(): vazio {{
    const Servidor: qualquer = importar("cgd:servidor")
    const Arquivo: qualquer = importar("cgd:arquivos").Arquivo
    var app: qualquer = Servidor.HTTP()
    app.get("/ola/:nome", funcao(req: qualquer, res: qualquer): vazio {{
        res.enviar("oi:" + req.parametro("nome"))
    }})
    app.post("/parar", funcao(req: qualquer, res: qualquer): vazio {{
        res.pararServidor().enviar("tchau")
    }})
    app.abrir("127.0.0.1", 0)
    Arquivo.escrever("{port_file}", texto(app.portaLocal()))
    var tarefas: qualquer[] = []
    tente {{
        enquanto app.ativo() {{
            tente {{
                var ouv: qualquer = app
                var c: qualquer = aguardar importar("cgd:tempo").Tempo.dormirAsync(1)
                sustar
            }} pegue (erro: Excecao) {{
                sustar
            }}
        }}
    }} finalmente {{
        app.fechar()
    }}
}}
principal()
""",
        encoding="utf-8",
    )
    # Test real escutarAsync on a free port found in Python
    sock_probe = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock_probe.bind(("127.0.0.1", 0))
    free_port = sock_probe.getsockname()[1]
    sock_probe.close()

    src.write_text(
        f"""
assincrona funcao principal(): vazio {{
    const Servidor: qualquer = importar("cgd:servidor")
    var app: qualquer = Servidor.HTTP()
    app.get("/ola/:nome", funcao(req: qualquer, res: qualquer): vazio {{
        res.enviar("oi:" + req.parametro("nome"))
    }})
    app.post("/parar", funcao(req: qualquer, res: qualquer): vazio {{
        res.pararServidor().enviar("tchau")
    }})
    aguardar app.escutarAsync("127.0.0.1", {free_port}, 10)
}}
principal()
""",
        encoding="utf-8",
    )
    comp = subprocess.run(
        [CGD, str(src), "-s", str(exe), "-o"], capture_output=True, text=True, timeout=30
    )
    assert comp.returncode == 0, comp.stderr
    server_proc = subprocess.Popen(
        [str(exe)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    try:
        # Wait until port accepts connections
        deadline = time.monotonic() + 5.0
        while time.monotonic() < deadline:
            try:
                with socket.create_connection(("127.0.0.1", free_port), timeout=0.5):
                    break
            except OSError:
                time.sleep(0.05)

        # Keep-alive: 2 requests over the SAME TCP connection!
        with socket.create_connection(("127.0.0.1", free_port), timeout=5.0) as s:
            s.sendall(
                b"GET /ola/Maria HTTP/1.1\r\nHost: localhost\r\nConnection: keep-alive\r\n\r\n"
            )
            resp1 = s.recv(4096).decode("utf-8")
            assert (
                "200 CGD" in resp1
                and "Connection: keep-alive" in resp1
                and resp1.endswith("oi:Maria")
            ), resp1
            s.sendall(b"GET /ola/Joao HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n")
            resp2 = s.recv(4096).decode("utf-8")
            assert (
                "200 CGD" in resp2 and "Connection: close" in resp2 and resp2.endswith("oi:Joao")
            ), resp2

        # Concurrent clients: 6 simultaneous connections!
        results = []

        def client_worker(idx):
            with socket.create_connection(("127.0.0.1", free_port), timeout=5.0) as cs:
                cs.sendall(
                    f"GET /ola/C{idx} HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n".encode()
                )
                data = cs.recv(4096).decode("utf-8")
                results.append(data.endswith(f"oi:C{idx}"))

        threads = [threading.Thread(target=client_worker, args=(i,)) for i in range(6)]
        for t in threads:
            t.start()
        for t in threads:
            t.join(timeout=5.0)
        assert len(results) == 6 and all(results), f"Falha concorrente: {results}"

        # Graceful shutdown via /parar
        with socket.create_connection(("127.0.0.1", free_port), timeout=5.0) as s:
            s.sendall(
                b"POST /parar HTTP/1.1\r\nHost: localhost\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            )
            resp = s.recv(4096).decode("utf-8")
            assert "tchau" in resp, resp
        stdout, stderr = server_proc.communicate(timeout=5.0)
        assert server_proc.returncode == 0, f"Servidor retornou {server_proc.returncode}: {stderr}"
        checks += 1
    finally:
        if server_proc.poll() is None:
            server_proc.kill()
            server_proc.wait()

print(
    f"Stdlib avançada (Bytes/Cripto/Compressao/SQLite/DataHora/UDP/DNS/HTTPAsync): {checks} verificações passaram."
)
