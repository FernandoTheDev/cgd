#!/usr/bin/env python3
"""Contratos de suspensão, tipagem, efeitos e operações assíncronas."""

import argparse
import json
import os
import shlex
import subprocess
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from threading import Thread

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "out/async-linguagem"
GOOD = r"""
funcao marcar(log: inteiro[], valor: inteiro): inteiro {
    log.adicionar(valor)
    retorna valor
}
funcao soma(a: inteiro, b: inteiro, c: inteiro): inteiro { retorna a + b + c }
assincrona funcao comDefault(log: inteiro[], x: inteiro, y: inteiro = marcar(log, 55)): inteiro { retorna y }
funcao chamada(log: inteiro[], x: qualquer): Promessa<inteiro> { retorna comDefault(log, x) }
assincrona funcao imediato(x: inteiro): inteiro { retorna x }
assincrona funcao numero(log: inteiro[], x: inteiro): inteiro {
    log.adicionar(x)
    retorna aguardar imediato(x)
}
assincrona funcao variadica(...valores: inteiro): inteiro { valores = [aguardar imediato(2), 3]; retorna valores[0] + valores[1] }
assincrona funcao alterar(vetor: inteiro[]): inteiro { vetor[0] = 100; retorna aguardar imediato(3) }
assincrona funcao caixa(): Promessa<inteiro> { retorna imediato(8) }
assincrona funcao falha(): inteiro { falhar "falha esperada" }
funcao recuperar(erro: Excecao): inteiro { retorna 42 }
assincrona funcao recursiva(x: inteiro): inteiro {
    se x == 0 { retorna 0 }
    retorna 1 + aguardar recursiva(x - 1)
}
classe Base {
    valor: inteiro = 20
    assincrona obter(x: inteiro = 1): inteiro { retorna isto.valor + aguardar imediato(x) }
}
classe Filha herda Base {
    assincrona obter(x: inteiro = 1): inteiro { retorna 1 + aguardar super.obter(x) }
    estatico assincrona estatico(x: inteiro): inteiro { retorna aguardar imediato(x) }
}

assincrona funcao limpeza(log: inteiro[]): inteiro {
    tente {
        retorna aguardar imediato(7)
    } finalmente {
        log.adicionar(aguardar imediato(80))
    }
}
assincrona funcao robustez(): vazio {
    var log: inteiro[] = []
    assercao(-(aguardar imediato(7)) == -7)
    assercao(aguardar limpeza(log) == 7 e log[0] == 80)
    tente {
        aguardar falha()
    } pegue (erro: Excecao) {
        log.adicionar(aguardar imediato(81))
    } finalmente {
        log.adicionar(aguardar imediato(82))
    }
    assercao(log[1] == 81 e log[2] == 82)
    var soma: inteiro = 0
    para cada item: inteiro em [1, 2, 3] {
        tente {
            se item == 2 { continua }
            soma += aguardar imediato(item)
        } finalmente { log.adicionar(aguardar imediato(item)) }
    }
    assercao(soma == 4 e log.tamanho() == 6)
    const vetor: inteiro[] = [aguardar imediato(x * 2) para cada x: inteiro em [1, 2, 3]]
    assercao(vetor[0] == 2 e vetor[2] == 6)
    const todas: qualquer = aguardar Promessa.todas([imediato(1), imediato(2)])
    assercao(todas[0] == 1 e todas[1] == 2)
    assercao(aguardar Promessa.qualquer([falha(), imediato(3)]) == 3)
    const encerradas: qualquer = aguardar Promessa.todasResolvidas([falha(), imediato(4)])
    assercao(encerradas[0]["estado"] == "rejeitada" e encerradas[1]["valor"] == 4)
    const tempo: qualquer = importar("cgd:assincrono").Tempo
    aguardar importar("cgd:tempo").Tempo.dormirAsync(0)
    aguardar importar("cgd:tempo").Duracao(0).dormirAsync()
    const arquivo: qualquer = importar("cgd:arquivos").Arquivo("bibliotecas/tempo.delegua")
    assercao(aguardar arquivo.lerAsync() == arquivo.ler())
    var excedeu: logico = falso
    tente { aguardar arquivo.lerAsync(0) } pegue (erro: Excecao) { excedeu = verdadeiro }
    assercao(excedeu)
    const calculo: Promessa<inteiro> = importar("cgd:algoritmos").Algoritmos.crc32Async("123456789")
    assercao(aguardar calculo == 3421780262)
    assercao(aguardar importar("cgd:algoritmos").Algoritmos.crc32Async("") == 0)
    aguardar tempo.dormir(0)
    const primeiro: Promessa<vazio> = tempo.dormir(0)
    const segundo: Promessa<vazio> = tempo.dormir(0)
    aguardar primeiro
    assercao(segundo.cancelar())
    tente { aguardar segundo } pegue (erro: Excecao) { log.adicionar(98) }
    assercao(log[log.tamanho() - 1] == 98)
    const pendente: Promessa<vazio> = tempo.dormir(60000)
    assercao(pendente.cancelar())
    tente { aguardar pendente } pegue (erro: Excecao) { log.adicionar(99) }
    assercao(log[log.tamanho() - 1] == 99)
    const local: qualquer = importar("cgd:sockets").OuvinteTCP()
    const conexao: qualquer = local.aceitarAsync(2000)
    const origem: qualquer = aguardar importar("cgd:sockets").conectarAsync("127.0.0.1", local.portaLocal(), 2000)
    const destino: qualquer = aguardar conexao
    const dados: Promessa<texto> = destino.receberAsync(32, 2000)
    assercao(aguardar origem.enviarAsync("bytes", 2000) == 5)
    assercao(aguardar dados == "bytes")
    origem.fechar()
    destino.fechar()
    local.fechar()
    const ouvinte: qualquer = importar("cgd:assincrono").OuvinteTCP()
    const abandonada: qualquer = ouvinte.aceitar(60000)
    assercao(abandonada.cancelar())
    tente { aguardar abandonada } pegue (erro: Excecao) { log.adicionar(101) }
    assercao(log[log.tamanho() - 1] == 101)
    const aceita: qualquer = ouvinte.aceitar(2000)
    const cliente: qualquer = aguardar importar("cgd:assincrono").TCP.conectar("127.0.0.1", ouvinte.portaLocal(), 2000)
    const servidor: qualquer = aguardar aceita
    const leitura: qualquer = servidor.receber(64, 2000)
    aguardar tempo.dormir(1)
    assercao(aguardar cliente.enviar("abc", 2000) == 3)
    assercao(aguardar leitura == "abc")
    const interrompida: qualquer = servidor.receber(64, 2000)
    servidor.fechar()
    tente { aguardar interrompida } pegue (erro: Excecao) { log.adicionar(100) }
    assercao(log[log.tamanho() - 1] == 100)
    cliente.fechar()
    ouvinte.fechar()

}

assincrona funcao executar(log: inteiro[], objeto: Filha): vazio {
    escreva("B")
    aguardar robustez()
    var total: inteiro = soma(marcar(log, 1), aguardar numero(log, 2), marcar(log, 3))
    assercao(total == 6 e log[0] == 1 e log[1] == 2 e log[2] == 3)
    var vetor: inteiro[] = [5, 6]
    var alias: inteiro[] = vetor
    vetor[marcar(log, 0)] += aguardar imediato(4)
    assercao(alias[0] == 9 e log.tamanho() == 4)
    vetor[0] += aguardar alterar(vetor)
    assercao(vetor[0] == 12)
    const inutil: inteiro = marcar(log, 44)
    aguardar imediato(1)
    assercao(log[log.tamanho() - 1] == 44)
    const texto: texto = "v${aguardar imediato(3)}"
    assercao(texto == "v3")
    const mapa: dicionario = {"valor": aguardar imediato(6)}
    assercao(mapa["valor"] == 6)
    const externa: inteiro = 11
    se verdadeiro { const externa: inteiro = aguardar imediato(7); assercao(externa == 7) }
    assercao(externa == 11)
    para var i: inteiro = 0; i < 5; i++ {
        se i == 2 { continua }
        se i == 4 { sustar }
        total += aguardar imediato(i)
    }
    assercao(total == 10)
    var i: inteiro = 0
    fazer { i += aguardar imediato(1); se i < 2 { continua } } enquanto i < 3
    enquanto i < 5 { i += aguardar imediato(1) }
    assercao(i == 5)
    var j: inteiro = 0
    fazer { j++; se j == 2 { continua } aguardar imediato(1) } enquanto j < 3
    enquanto j < 5 { j += aguardar imediato(1) }
    assercao(j == 5)
    const antes: inteiro = log.tamanho()
    const sim: logico = falso e (aguardar numero(log, 99) > 0)
    const disjuncao: logico = verdadeiro ou (aguardar numero(log, 99) > 0)
    assercao(!sim e disjuncao e log.tamanho() == antes)
    const valor: inteiro = verdadeiro ? aguardar imediato(8) : aguardar numero(log, 77)
    assercao(valor == 8 e log.tamanho() == antes)
    const aninhada: Promessa<Promessa<inteiro>> = caixa()
    assercao(aguardar (aguardar aninhada) == 8)
    assercao(aguardar recursiva(20) == 20)
    const metodo: funcao = objeto.obter
    assercao(aguardar metodo(2) == 23)
    assercao(aguardar Filha.estatico(9) == 9)
    const callback: funcao = assincrona funcao(x: inteiro): inteiro { retorna aguardar imediato(x) }
    assercao(aguardar callback(12) == 12)
    assercao(aguardar chamada(log, "texto").capturar(recuperar) == 42)
    assercao(log[log.tamanho() - 1] == 55)
    assercao(aguardar falha().capturar(recuperar) == 42)
    const encadeada: Promessa<qualquer> = imediato(10).entao(funcao(x: inteiro): inteiro { retorna x + 2 })
    assercao(aguardar encadeada == 12)
    assercao(aguardar variadica(1, 2, 3) == 5)
    escreva("D")
}
funcao sincronaVariadica(...valores: inteiro): inteiro { valores = [2, 3]; retorna valores[0] + valores[1] }
assercao(sincronaVariadica(1, 2) == 5)
var log: inteiro[] = []
var objeto: Filha = Filha()
escreva("A")
executar(log, objeto)
escreva("C")
"""
ERRORS = {
    "contexto": ("funcao f() { aguardar 1 }", "E3301"),
    "vazio": (
        "assincrona funcao f(): vazio {} assincrona funcao g() { var x=aguardar f() }",
        "E3306",
    ),
    "pureza": ("//>puro\nassincrona funcao f(): inteiro { retorna 1 }", "E3303"),
    "operando": ("assincrona funcao f() { aguardar 1 }", "E3302"),
    "captura": ("var x: inteiro=1; assincrona funcao f() { escreva(x) }", "E4001"),
    "retorno": ("assincrona funcao f(): inteiro { retorna 1 } var p: inteiro=f()", "E3002"),
    "default": ("assincrona funcao f(x=aguardar g()) {} funcao g() {}", "E3301"),
}
RUNTIME_ERRORS = {
    "limpezas_compartilhadas": """assincrona funcao limpar(p: Promessa<vazio>): vazio {
    tente { var x: inteiro = 1 } finalmente { aguardar p; escreva("limpa") }
}
const p: Promessa<vazio> = importar("cgd:assincrono").Tempo.dormir(10)
para (var i: inteiro = 0; i < 256; i++) { limpar(p) }
falhar "falha-compartilhada" """,
    "prazo_limpeza": """assincrona funcao limpar(): vazio {
    tente { escreva("iniciada") } finalmente { aguardar importar("cgd:assincrono").Tempo.dormir(60000) }
}
limpar()
falhar "falha-raiz" """,
    "ciclo": 'assincrona funcao f(ctx: dicionario): vazio { aguardar pausa(); aguardar ctx["f"] } assincrona funcao pausa(): vazio {} var ctx: dicionario = {}; ctx["f"] = f(ctx)',
    "rejeicao": """assincrona funcao f(): inteiro { falhar "erro-assincrono" }
assincrona funcao g(): inteiro { retorna aguardar f() }
assincrona funcao h(): inteiro { retorna aguardar g() }
h()""",
    "contrato": """assincrona funcao f(): inteiro { retorna 1 }
var p: qualquer = f()
var q: Promessa<real> = p""",
    "dinamico": """assincrona funcao f(x: qualquer): vazio { aguardar x }
f(1)""",
}


def run(command, timeout=60):
    return subprocess.run(
        command, cwd=ROOT, capture_output=True, text=True, timeout=timeout, check=False
    )


class EcoHTTP(BaseHTTPRequestHandler):
    def do_POST(self):
        corpo = self.rfile.read(int(self.headers["Content-Length"]))
        self.send_response(201)
        self.send_header("Content-Length", str(len(corpo)))
        self.end_headers()
        self.wfile.write(corpo)

    def do_GET(self):
        if self.path == "/redirecionar":
            self.send_response(302)
            self.send_header("Location", "/destino")
            self.end_headers()
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        pass


def verificar_http(extra, toolchain):
    with HTTPServer(("127.0.0.1", 0), EcoHTTP) as servidor:
        fonte = OUT / "http.delegua"
        fonte.write_text(
            f"""assincrona funcao verificar(): vazio {{
    const url: texto = "http://127.0.0.1:{servidor.server_port}/"
    const bruta: dicionario = aguardar importar("cgd:rede").enviarAsync(url, "ação", [], 5000, 6)
    assercao(bruta["status"] == 201 e bruta["corpo"] == "ação")
    const resposta: qualquer = aguardar importar("cgd:assincrono").HTTP.enviar(url, "ação", [], 5000, 6)
    assercao(resposta.status() == 201 e resposta.texto() == "ação")
    var rejeitada: logico = falso
    tente {{
        aguardar importar("cgd:assincrono").HTTP.enviar(url, "ação", [], 5000, 5)
    }} pegue (erro: Excecao) {{ rejeitada = verdadeiro }}
    assercao(rejeitada)
    const redirecionada: qualquer = aguardar importar("cgd:assincrono").HTTP.obter(url + "redirecionar")
    assercao(redirecionada.status() == 302 e redirecionada.texto() == "")
    const ausente: qualquer = aguardar importar("cgd:assincrono").HTTP.obter(url + "ausente")
    assercao(ausente.status() == 404 e !ausente.sucesso())
    escreva("ok")
}}
verificar()
"""
        )
        binario = OUT / "http"
        result = run([str(ROOT / "cgd"), str(fonte), "--saida", str(binario), *extra, *toolchain])
        assert result.returncode == 0, result.stderr
        thread = Thread(target=servidor.serve_forever)
        thread.start()
        try:
            result = run([str(binario)])
            assert result.returncode == 0 and result.stdout == "ok\n", (
                result.stdout,
                result.stderr,
            )
        finally:
            servidor.shutdown()
            thread.join()


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sanitizadores", action="store_true")
    args = parser.parse_args()
    toolchain = []
    if args.sanitizadores:
        runtime = ROOT / "vendor/delegua-runtime"
        flags = shlex.split(
            subprocess.check_output(["pkg-config", "--cflags", "bdw-gc", "libcurl"], text=True)
        )
        objects = []
        folder = OUT / "san-objects"
        folder.mkdir(exist_ok=True)
        for source in sorted((runtime / "src").glob("*.c")):
            output = folder / (source.stem + ".o")
            subprocess.run(
                [
                    "clang",
                    "-std=c99",
                    "-Wall",
                    "-Wextra",
                    "-Werror",
                    "-O1",
                    "-g",
                    "-DNDEBUG",
                    "-fsanitize=address,undefined",
                    "-fno-omit-frame-pointer",
                    *flags,
                    "-c",
                    str(source),
                    "-o",
                    str(output),
                ],
                check=True,
                timeout=60,
            )
            objects.append(str(output))
        output = folder / "runtime-completo.o"
        subprocess.run(["clang", "-r", *objects, "-o", str(output)], check=True, timeout=60)
        toolchain = [
            "--cc",
            "clang",
            "--runtime-object",
            str(output),
            "--cflag=-DNDEBUG",
            "--cflag=-fsanitize=address,undefined",
            "--cflag=-fno-omit-frame-pointer",
        ]
        os.environ["ASAN_OPTIONS"] = (
            "detect_leaks=0:detect_stack_use_after_return=0:abort_on_error=1"
        )
        os.environ["UBSAN_OPTIONS"] = "halt_on_error=1:print_stacktrace=1"
    checks = 0
    for optimized in (False, True):
        extra = ["--otimizar"] if optimized else []
        verificar_http(extra, toolchain)
        checks += 1
        source = OUT / "correto.delegua"
        source.write_text(GOOD)
        formatted = run([str(ROOT / "cgd"), "--formatar", str(source)])
        assert formatted.returncode == 0, formatted.stderr
        formatted = run([str(ROOT / "cgd"), "--verificar-formatacao", str(source)])
        assert formatted.returncode == 0, formatted.stderr
        binary = OUT / ("correto-opt" if optimized else "correto")
        result = run([str(ROOT / "cgd"), str(source), "--saida", str(binary), *extra, *toolchain])
        assert result.returncode == 0, result.stderr
        result = run([str(binary)])
        assert result.returncode == 0 and result.stdout == "A\nB\nC\nD\n", (
            result.stdout,
            result.stderr,
        )
        checks += 1
        for name, (text, code) in ERRORS.items():
            source = OUT / (name + ".delegua")
            source.write_text(text)
            result = run(
                [str(ROOT / "cgd"), str(source), "--verificar", "--diagnosticos=json", *extra]
            )
            assert result.returncode != 0 and code in result.stderr, (name, result.stderr)
            checks += 1
        for name, text in RUNTIME_ERRORS.items():
            source = OUT / (name + ".delegua")
            source.write_text(text)
            result = run(
                [str(ROOT / "cgd"), str(source), "--saida", str(binary), *extra, *toolchain]
            )
            assert result.returncode == 0, (name, result.stderr)
            result = run([str(binary)], timeout=15 if name == "prazo_limpeza" else 60)
            assert result.returncode == 1 and "R0001" in result.stderr, (
                name,
                result.stdout,
                result.stderr,
            )
            if name == "limpezas_compartilhadas":
                assert result.stdout.splitlines() == ["limpa"] * 256, result.stdout
                assert result.stderr.splitlines().count("error[R0001]: falha-compartilhada") == 1, (
                    result.stderr
                )
            if name == "prazo_limpeza":
                assert "Prazo de limpeza assíncrona excedido." in result.stderr, result.stderr
                assert result.stderr.splitlines().count("error[R0001]: falha-raiz") == 1, (
                    result.stderr
                )
            if name == "rejeicao":
                assert result.stderr.splitlines().count("error[R0001]: erro-assincrono") == 1, (
                    result.stderr
                )
                assert result.stderr.count("error[R0001]") == 1, result.stderr
                assert (
                    "origem da rejeição assíncrona" in result.stderr
                    and f"{source}:1:" in result.stderr
                ), result.stderr
                assert "aguardada em" in result.stderr and f"{source}:2:" in result.stderr, (
                    result.stderr
                )
            checks += 1
    report_name = (
        "resultado-sanitizadores.json"
        if args.sanitizadores
        else "resultado-" + Path(os.environ.get("CC", "clang")).name + ".json"
    )
    (OUT / report_name).write_text(
        json.dumps({"checks": checks, "passed": True, "cc": os.environ.get("CC", "clang")}) + "\n"
    )
    print(f"Async linguagem: {checks} verificações passaram, com/sem otimização.")


if __name__ == "__main__":
    main()
