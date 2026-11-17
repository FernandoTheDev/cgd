#!/usr/bin/env python3
"""Contratos de destruição, dicionários, JSON, I/O e cliente HTTP; rede local."""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import subprocess
import tempfile
import threading

ROOT = Path(__file__).resolve().parents[1]


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'{"valor":42}')

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
        self.send_response(201)
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_):
        pass


server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
try:
    with tempfile.TemporaryDirectory(prefix="cgd expansao ") as temporary:
        folder = Path(temporary)
        for optimized in (False, True):
            path = json.dumps(str(folder / "ação.bin"), ensure_ascii=False)
            url = json.dumps(f"http://127.0.0.1:{server.server_port}")
            source = folder / "contratos.delegua"
            source.write_text(
                f"var caminho: texto = {path}\nvar url: texto = {url}\n"
                + """
var padraoNumero: numero
var padraoReal: real
var padraoTexto: texto
var padraoLogico: logico
var padraoVetor: inteiro[]
var padraoMapa: dicionario
assercao(padraoNumero==0 e padraoReal==0 e padraoTexto=="" e !padraoLogico)
assercao(tamanho(padraoVetor)==0 e tamanho(padraoMapa)==0)
funcao registrar(destino: qualquer[]): inteiro { destino.adicionar(1); retorna tamanho(destino) }
classe Padroes {
    valores: qualquer[]
    numero: inteiro = registrar(isto.valores)
}
classe PadroesFilha herda Padroes {
    herdado: inteiro = isto.numero
}
var p1: PadroesFilha = PadroesFilha()
var p2: PadroesFilha = PadroesFilha()
p1.valores.adicionar(2)
assercao(p1.numero==1 e p1.herdado==1 e tamanho(p1.valores)==2 e tamanho(p2.valores)==1)
//>puro
funcao digito(ch: texto): logico { se ch<'0' { retorna falso } retorna ch<='9' }
assercao(digito("5") e !digito("a"))
assercao("ação">"a" e "a\\0b"<"a\\0c")
var mapa: dicionario = {"nulo": nulo, "numero": 3}
var alias: dicionario = mapa
assercao(mapa.obter("ausente", 7) == 7)
assercao(mapa.obter("nulo", 7) == nulo)
assercao(mapa.contemChave("nulo"))
assercao(mapa.definir("outro", 8) == 8)
var pares: qualquer[] = mapa.itens()
mapa.limpar()
assercao(tamanho(alias) == 0 e tamanho(pares) == 3)

classe Base {
    protegido { eventos: qualquer[] }
    construtor(eventos: qualquer[]) { isto.eventos=eventos }
    destrutor(): vazio { isto.eventos.adicionar("base") }
}
classe Filha herda Base {
    destrutor(): vazio {
        isto.eventos.adicionar("filha")
        destruir(isto)
        falhar "falha deliberada"
    }
}
var eventos: qualquer[] = []
var objeto: Filha = Filha(eventos)
var outro: Filha = objeto
var tratado: logico = falso
tente { destruir(objeto) } pegue (erro) { tratado=verdadeiro }
destruir(outro)
assercao(tratado e tamanho(eventos)==2)
assercao(eventos[0]=="filha" e eventos[1]=="base")

classe Contador {
    valor: inteiro
    construtor() { isto.valor=0 }
    incrementar(): vazio { isto.valor++ }
}
funcao efeito(destino: qualquer[]): inteiro {
    destino.adicionar(1)
    retorna 1
}
var efeitos: qualquer[] = [];
[efeito(efeitos)]
assercao(tamanho(efeitos)==1)
var contador: Contador = Contador()
contador.incrementar()
assercao(contador.valor==1)

var json: qualquer = importar("cgd:json")
var documento: qualquer = json.JSON.deTexto('{"lista":[{"valor":42}],"nulo":null}')
"""
                + """
assercao(documento.caminho(["lista", 0, "valor"])==42)
assercao(documento.caminho(["nulo"], 7)==nulo)
assercao(documento.caminho(["ausente"], 7)==7)
var copia: qualquer = documento.copiar()
copia.definir("novo", 1)
assercao(!documento.contem("novo"))
var colisoes: qualquer = json.JSON.deTexto('{"chaves":1,"obter":2,"itens":3}')
assercao(json.analisar(colisoes.texto())["chaves"]==1)
assercao(tamanho(colisoes.chaves())==3)

var arquivos: qualquer = importar("cgd:arquivos")
var arquivo: qualquer = arquivos.Arquivo(caminho)
assercao(!arquivo.existe())
arquivo.escrever("ação\\0").anexar("fim")
assercao(arquivo.ler()=="ação\\0fim" e arquivo.tamanho()==10)
var limitado: logico = falso
tente { arquivo.ler(1) } pegue { limitado=verdadeiro }
assercao(limitado)
assercao(arquivo.remover() e !arquivo.remover())

var rede: qualquer = importar("cgd:rede")
var cliente: qualquer = rede.ClienteHTTP(url)
var resposta: qualquer = cliente.obter("/dados").exigirSucesso()
assercao(resposta.status()==200 e resposta.json()["valor"]==42)
var enviada: qualquer = cliente.enviarJSON("/dados", {"acao":"ok"})
assercao(enviada.status()==201 e enviada.json()["acao"]=="ok")
escreva("expansao OK")
""",
                encoding="utf-8",
            )
            binary = folder / "contratos"
            command = [
                str(ROOT / "cgd"),
                str(source),
                "-s",
                str(binary),
                "--cflag=-Wall",
                "--cflag=-Wextra",
                "--cflag=-Werror",
            ]
            if optimized:
                command.append("-o")
            compiled = subprocess.run(command, capture_output=True, text=True, timeout=120)
            assert compiled.returncode == 0, compiled.stdout + compiled.stderr
            executed = subprocess.run([str(binary)], capture_output=True, text=True, timeout=30)
            assert executed.returncode == 0, executed.stdout + executed.stderr
            assert executed.stdout == "expansao OK\n", executed.stdout
finally:
    server.shutdown()
    server.server_close()
    thread.join(timeout=5)

print("Contratos de expansão passaram em ambos os modos.")
