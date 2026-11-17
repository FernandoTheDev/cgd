#!/usr/bin/env python3
"""Bibliotecas reais compiladas uma vez por modo; HTTP só no loopback local."""

import json
from pathlib import Path
import subprocess
import tempfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import threading
import random

ROOT = Path(__file__).resolve().parents[1]


def compile_source(source, folder, name, opt=False):
    file = folder / (name + ".delegua")
    file.write_text(source)
    output = folder / name
    result = subprocess.run(
        [str(ROOT / "cgd"), str(file), "-s", str(output)] + (["-o"] if opt else []),
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, result.stderr
    return output


json_path = (ROOT / "bibliotecas/json.delegua").as_posix()
rede_path = (ROOT / "bibliotecas/rede.delegua").as_posix()
valid = [
    "null",
    "true",
    "false",
    "0",
    "-0",
    "-123",
    "1.5",
    "1e3",
    "1E-3",
    " [] ",
    "{}",
    '[1,true,null,"x"]',
    r'"a\nb\t\b\f\r\\\/\""',
    r'"\u0000\u00e7\uD83D\uDC9A"',
    '{"a":1,"a":2}',
    str(10**100),
    "1e999",
    '"ação 💚 ${literal}"',
]
invalid = [
    "",
    " ",
    "+1",
    "01",
    "-01",
    "1.",
    "1e",
    "1e+",
    "NaN",
    "Infinity",
    "true false",
    "[1,]",
    '{"x":1,}',
    "{x:1}",
    "[",
    "{",
    '"',
    '"x\ny"',
    r'"\q"',
    r'"\u000x"',
    r'"\uD800"',
    r'"\uDC00"',
    r'"\uD800\u0041"',
    "[1 2]",
    '{"x" 1}',
    "nullx",
    "[" * 129 + "0" + "]" * 129,
]
random.seed(7)
for i in range(100):
    valid.append(
        json.dumps(
            {
                "texto": "á💚\\\n" + str(i),
                "valores": [random.randint(-100000, 100000), random.random(), None, True],
            },
            ensure_ascii=False,
        )
    )


class HTTP(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/redirect":
            self.send_response(302)
            self.send_header("Location", "/ok")
            self.end_headers()
            return
        body = (
            b"x" * 10000
            if self.path == "/large"
            else json.dumps({"metodo": "GET", "caminho": self.path}).encode()
        )
        self.send_response(404 if self.path == "/404" else 200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
        self.send_response(201)
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


server = ThreadingHTTPServer(("127.0.0.1", 0), HTTP)
threading.Thread(target=server.serve_forever, daemon=True).start()
count = 0
try:
    with tempfile.TemporaryDirectory(prefix="cgd libs ") as tmp:
        folder = Path(tmp)
        for opt in (False, True):
            harness = compile_source(
                f'''var json=importar("{json_path}")
var casos=inteiro(leia())
para(var i=0;i<casos;i++){{
 var linhas=inteiro(leia());var partes=[]
 para(var j=0;j<linhas;j++){{partes.adicionar(leia())}}
 tente{{escreva("OK:"+json.serializar(json.analisar(partes.juntar("\\n"))))}}pegue(erro){{escreva("ERR")}}
}}
''',
                folder,
                "json-" + str(opt),
                opt,
            )
            payload = str(len(valid) + len(invalid)) + "\n"
            for source in valid + invalid:
                lines = source.split("\n")
                payload += str(len(lines)) + "\n" + "\n".join(lines) + "\n"
            result = subprocess.run(
                [str(harness)], input=payload, capture_output=True, text=True, timeout=60
            )
            assert result.returncode == 0, result.stderr
            answers = result.stdout.splitlines()
            assert len(answers) == len(valid) + len(invalid), (len(answers), result.stderr)
            for source, answer in zip(valid, answers):
                assert answer.startswith("OK:"), (source, answer)
                if source == "1e999":
                    assert answer[3:] == "1e999"
                else:
                    assert json.loads(answer[3:]) == json.loads(source), (source, answer)
                count += 1
            for source, answer in zip(invalid, answers[len(valid) :]):
                assert answer == "ERR", (source, answer)
                count += 1
            base = f"http://127.0.0.1:{server.server_port}"
            network = compile_source(
                f'''var rede=importar("{rede_path}")
var a=rede.obter("{base}/ok");assercao a.status==200
var b=rede.enviar("{base}/post","a\\0b",["Content-Type: application/octet-stream"]);assercao b.status==201;assercao b.corpo=="a\\0b"
var c=rede.obter("{base}/redirect",{{FOLLOWLOCATION:1}});assercao c.status==200
assercao rede.obter("{base}/404").status==404
var grande=rede.obter("{base}/large",{{CGD_MAX_BYTES:16}});assercao grande.codigo!=0
var s=rede.Sessao();s.opcao("URL","{base}/ok");var t=rede.Sessao();t.opcao("URL","{base}/ok")
assercao tamanho(rede.lote([s,t]))==2
assercao s.info("RESPONSE_CODE")==200
assercao s.info("EFFECTIVE_URL").inclui("/ok")
s.manter()
s.resetar();s.opcao("URL","{base}/post");s.multipart([{{nome:"campo",dados:"conteudo",arquivo:"arquivo.txt",tipo:"text/plain"}}])
var multi=s.executar();assercao multi.status==201;assercao multi.corpo.inclui("conteudo");assercao multi.corpo.inclui("arquivo.txt")
s.fechar();t.fechar()
assercao rede.componenteUrl("https://example.invalid:8443/a?q=1","host")=="example.invalid"
assercao rede.alterarUrl("https://example.invalid/a","path","/b")=="https://example.invalid/b"
assercao tamanho(rede.mensagemErro(0))>0
assercao tamanho(rede.detalhes().protocolos)>0
assercao rede.data("Sun, 06 Nov 1994 08:49:37 GMT")==784111777
var fluxo=rede.Sessao();fluxo.opcao("URL","{base}/ok").opcao("CONNECT_ONLY",1)
assercao fluxo.executar().codigo==0
var envio=fluxo.enviar("GET /ok HTTP/1.0\\r\\nHost: 127.0.0.1\\r\\n\\r\\n");assercao envio.codigo==0
fluxo.esperar(1000)
var recebido=fluxo.receber();assercao recebido.codigo==0;assercao recebido.corpo.inclui("200")
fluxo.fechar()
var bloqueios=0
var h=cgdCurlCriar()
tente{{cgdCurlOpcao(h,"WRITEFUNCTION",1)}}pegue(erro){{bloqueios+=1}}
tente{{cgdCurlOpcao(h,"POSTFIELDSIZE",999999)}}pegue(erro){{bloqueios+=1}}
cgdCurlFechar(h)
tente{{cgdCurlExecutar(h)}}pegue(erro){{bloqueios+=1}}
assercao bloqueios==3
assercao rede.decodificar(rede.escapar("á💚"))=="á💚"
escreva("OK")
''',
                folder,
                "rede-" + str(opt),
                opt,
            )
            result = subprocess.run([str(network)], capture_output=True, text=True, timeout=30)
            assert result.returncode == 0 and result.stdout == "OK\n", (
                result.stdout,
                result.stderr,
            )
            count += 26
finally:
    server.shutdown()
    server.server_close()
print(f"{count} verificações de bibliotecas passaram; HTTP apenas em 127.0.0.1.")
