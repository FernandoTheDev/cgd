#!/usr/bin/env python3
"""Testes completos de cgd:memoria, Bytes congelado zero-copy, Arena (anti-UAF/double-free),
PoolBuffers, EscopoMemoria, detecção de recursos e Processo.executarLote."""

from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
CGD = str(ROOT / "cgd")
checks = 0


def run_program(source: str, expected: str, opt: bool = False) -> None:
    global checks
    with tempfile.TemporaryDirectory(prefix="cgd-mem-") as tmp:
        src = Path(tmp) / "programa.delegua"
        exe = Path(tmp) / "programa"
        src.write_text(source, encoding="utf-8")
        cmd = [CGD, str(src), "-s", str(exe)]
        if opt:
            cmd.append("-o")
        comp = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
        assert comp.returncode == 0, f"Compilação falhou (opt={opt}):\n{comp.stderr}\n{comp.stdout}"
        proc = subprocess.run([str(exe)], capture_output=True, text=True, timeout=60)
        assert proc.returncode == 0, f"Execução falhou (opt={opt}):\n{proc.stderr}\n{proc.stdout}"
        assert proc.stdout.strip() == expected.strip(), (
            f"Saída inesperada (opt={opt}):\nesperado:\n{expected}\nrecebido:\n{proc.stdout}"
        )
        checks += 1


for optimized in (False, True):
    # 1. Estatísticas de memória, sistema (CPU/RAM/cgroups) e controle seguro do GC
    run_program(
        """
const MemMod = importar("cgd:memoria")
const Memoria = MemMod.Memoria

const est: dicionario = Memoria.estatisticas()
assercao(inteiro(est["heapBytes"]) > 0, "heapBytes > 0")
assercao(inteiro(est["rssBytes"]) > 0, "rssBytes > 0")
assercao(inteiro(est["alocadosBytes"]) >= 0, "alocadosBytes >= 0")
assercao(inteiro(est["divisorEspacoLivre"]) >= 1, "divisor >= 1")

const divOrig: inteiro = Memoria.obterDivisorEspacoLivre()
Memoria.definirDivisorEspacoLivre(4)
assercao(Memoria.obterDivisorEspacoLivre() == 4, "divisor atualizado para 4")
Memoria.definirDivisorEspacoLivre(divOrig)

const sis: dicionario = Memoria.sistema()
assercao(inteiro(sis["cpusLogicas"]) >= 1, "cpusLogicas >= 1")
assercao(inteiro(sis["cpusEfetivas"]) >= 1, "cpusEfetivas >= 1")
assercao(inteiro(sis["totalBytes"]) > 0, "totalBytes > 0")
assercao(inteiro(sis["efetivaDisponivelBytes"]) >= 0, "efetivaDisponivelBytes >= 0")

Memoria.coletar(verdadeiro)
const coletou: logico = Memoria.coletarSeAcima(1, falso)
assercao(coletou == verdadeiro, "coletarSeAcima(1) deve coletar")
escreva("MEM-STATS-OK")
""",
        "MEM-STATS-OK",
        opt=optimized,
    )

    # 2. Arena binária: alocação, crescimento multi-chunk, limpar (anti-UAF), liberar (idempotente)
    run_program(
        """
const MemMod = importar("cgd:memoria")
const Memoria = MemMod.Memoria

const arena = Memoria.criarArena(4096, 1048576)
assercao(arena.ativa() == verdadeiro, "arena ativa")

const fb = arena.criarBytesReservado(64)
fb.anexarByte(65)
fb.anexarByte(66)
fb.anexarU32LE(305419896)
fb.anexarU64LE(123456789012345)
assercao(fb.tamanho() == 14, "tamanho fatia bytes")
assercao(fb.obter(0) == 65 e fb.obter(1) == 66, "bytes iniciais")
const bCopy = fb.paraBytes()
assercao(bCopy.tamanho() == 14 e bCopy.lerU32LE(2) == 305419896 e bCopy.lerU64LE(6) == 123456789012345, "conversao para Bytes")

const fi = arena.criarInt64(1000, -1)
assercao(fi.tamanho() == 1000 e fi.obter(0) == -1 e fi.obter(999) == -1, "fatia int64 init")
fi.definir(42, 987654321)
assercao(fi.obter(42) == 987654321, "fatia int64 set/get")

// Limpar incrementa geracao -> fatias antigas ficam imediatamente invalidas (use-after-reset bloqueado)
arena.limpar()
assercao(fb.valida() == falso, "fb invalida apos limpar")
assercao(fi.valida() == falso, "fi invalida apos limpar")

var bloqueouUar: logico = falso
tente {
    const x: inteiro = fi.obter(0)
    escreva(x)
} pegue (erro: Excecao) {
    bloqueouUar = verdadeiro
}
assercao(bloqueouUar == verdadeiro, "use-after-reset deve falhar")

// Reuso apos limpar sem realocar chunks
const fi2 = arena.criarInt64(500, 7)
assercao(fi2.valida() == verdadeiro e fi2.obter(10) == 7, "reuso apos limpar")
const st: dicionario = arena.estatisticas()
assercao(inteiro(st["geracao"]) == 2, "geracao == 2")

// Liberacao explicita + idempotencia (zero double-free) + use-after-free bloqueado
arena.liberar()
arena.liberar()
assercao(arena.ativa() == falso, "arena inativa")
assercao(fi2.valida() == falso, "fi2 invalida apos liberar")

var bloqueouUaf: logico = falso
tente {
    fi2.definir(0, 1)
} pegue (erro: Excecao) {
    bloqueouUaf = verdadeiro
}
assercao(bloqueouUaf == verdadeiro, "use-after-free deve falhar")

escreva("ARENA-OK")
""",
        "ARENA-OK",
        opt=optimized,
    )

    # 3. PoolBuffers + EscopoMemoria + Bytes estendido e congelado
    run_program(
        """
const MemMod = importar("cgd:memoria")
const BytesMod = importar("cgd:bytes")
const Memoria = MemMod.Memoria
const Bytes = BytesMod.Bytes

const pool = Memoria.criarPoolBuffers(128, 4)
const b1 = pool.adquirir()
b1.anexarTexto("ola")
b1.anexarByte(0)
assercao(b1.lerCString(0, 10) == "ola", "lerCString")
pool.devolver(b1)
const b2 = pool.adquirir()
assercao(b2.tamanho() == 0, "buffer reutilizado limpo")
assercao(inteiro(pool.estatisticas()["reutilizados"]) == 1, "reutilizacao contada")
pool.devolver(b2)
pool.limpar()

const escopo = Memoria.criarEscopo()
const aEsc = escopo.criarArena(4096)
const fEsc = aEsc.criarInt64(16, 5)
assercao(fEsc.obter(0) == 5, "escopo arena")
const bufEsc = Bytes.criarReservado(32)
bufEsc.anexarPreenchimento(144, 8)
assercao(bufEsc.tamanho() == 8 e bufEsc.obter(7) == 144, "preenchimento NOP")
escopo.registrarBuffer(bufEsc)
const rel: dicionario = escopo.relatorio()
assercao(inteiro(rel["arenasRegistradas"]) == 1 e inteiro(rel["buffersRegistrados"]) == 1, "relatorio escopo")
escopo.encerrar(falso, falso)
assercao(escopo.encerrado() == verdadeiro, "escopo encerrado")
assercao(aEsc.ativa() == falso e fEsc.valida() == falso, "escopo liberou arena")
assercao(bufEsc.tamanho() == 0, "escopo liberou buffer")

// Bytes congelado: leitura ok, mutacao bloqueada
const orig = Bytes.criarReservado(16)
orig.anexarU16LE(513)
orig.anexarU32LE(67305985)
orig.anexarU64LE(11223344556677)
const cong = orig.congelar()
assercao(cong.ehCongelado() == verdadeiro, "ehCongelado")
assercao(cong.lerU16LE(0) == 513 e cong.lerU32LE(2) == 67305985 e cong.lerU64LE(6) == 11223344556677, "leitura LE congelado")
var bloqueouMut: logico = falso
tente {
    cong.definir(0, 99)
} pegue (erro: Excecao) {
    bloqueouMut = verdadeiro
}
assercao(bloqueouMut == verdadeiro, "mutacao em congelado deve falhar")

// Copiar fatia de Bytes congelado para Bytes mutavel
const dst = Bytes.criarReservado(16)
dst.anexarBytesFatia(cong, 2, 4)
assercao(dst.tamanho() == 4 e dst.lerU32LE(0) == 67305985, "anexarBytesFatia")
escreva("ESCOPO-BYTES-OK")
""",
        "ESCOPO-BYTES-OK",
        opt=optimized,
    )

    # 4. Bytes congelado zero-copy em rotinas paralelas + Arena local em rotina + Rotinas.configurar + Processo.executarLote
    run_program(
        """
funcao somarFatiaCongelada(bufRaw: qualquer, ini: inteiro, fim: inteiro): inteiro {
    const BytesMod = importar("cgd:bytes")
    const MemMod = importar("cgd:memoria")
    const b = BytesMod.Bytes.deRecurso(bufRaw)
    const arena = MemMod.Arena(4096, 65536)
    const scratch = arena.criarInt64(4, 0)
    var soma: inteiro = 0
    para (var i: inteiro = ini; i < fim; i++) {
        soma = soma + b.obter(i)
    }
    scratch.definir(0, soma)
    const res: inteiro = scratch.obter(0)
    arena.liberar()
    retorna res
}

funcao produzirBytesEmWorker(base: inteiro, qtd: inteiro): qualquer {
    const BytesMod = importar("cgd:bytes")
    const b = BytesMod.Bytes.criarReservado(qtd)
    para (var i: inteiro = 0; i < qtd; i++) {
        b.anexarByte((base + i) & 255)
    }
    retorna b.congelar().recursoInterno()
}

assincrona funcao principal(): vazio {
    const BytesMod = importar("cgd:bytes")
    const AsyncMod = importar("cgd:assincrono")
    const ProcMod = importar("cgd:processo")
    const wRec: inteiro = AsyncMod.Rotinas.workersRecomendados(0)
    assercao(wRec >= 1, "workersRecomendados >= 1")
    const wConf: inteiro = AsyncMod.Rotinas.configurar(2, 128)
    assercao(wConf == 2, "configurar(2) == 2")

    const grande = BytesMod.Bytes.criarReservado(4096)
    para (var i: inteiro = 0; i < 4096; i++) grande.anexarByte(i & 255)
    const congelado = grande.congelar()
    const raw = congelado.recursoInterno()

    const r: qualquer[] = aguardar Promessa.todas([
        rotina somarFatiaCongelada(raw, 0, 1024),
        rotina somarFatiaCongelada(raw, 1024, 2048),
        rotina somarFatiaCongelada(raw, 2048, 3072),
        rotina somarFatiaCongelada(raw, 3072, 4096)
    ])
    const total: inteiro = inteiro(r[0]) + inteiro(r[1]) + inteiro(r[2]) + inteiro(r[3])
    // 16 ciclos de 0..255 => 16 * 32640 = 522240
    assercao(total == 522240, "soma zero-copy incorreta")

    const bRetRaw: qualquer = aguardar rotina produzirBytesEmWorker(10, 8)
    const bRet = BytesMod.Bytes.deRecurso(bRetRaw)
    assercao(bRet.ehCongelado() == verdadeiro e bRet.tamanho() == 8 e bRet.obter(0) == 10 e bRet.obter(7) == 17, "retorno Bytes congelado")

    const st: dicionario = AsyncMod.Rotinas.estatisticas()
    assercao(inteiro(st["workers"]) == 2 e inteiro(st["concluidasTotal"]) >= 5, "estatisticas pool")

    // Reconfigurar quando ocioso para 4 workers
    const wConf4: inteiro = AsyncMod.Rotinas.configurar(4, 256)
    assercao(wConf4 == 4, "reconfigurar para 4 workers")

    // Processo.executarLote com ordem deterministica
    const resLote: dicionario[] = ProcMod.Processo.executarLote([
        { programa: "/bin/echo", argumentos: ["A"] },
        { programa: "/bin/echo", argumentos: ["B"] },
        { programa: "/bin/echo", argumentos: ["C"] },
        { programa: "/bin/echo", argumentos: ["D"] }
    ], 2)
    assercao(resLote.tamanho() == 4, "lote 4 processos")
    assercao(texto(resLote[0]["stdout"]).aparar() == "A", "ordem 0")
    assercao(texto(resLote[1]["stdout"]).aparar() == "B", "ordem 1")
    assercao(texto(resLote[2]["stdout"]).aparar() == "C", "ordem 2")
    assercao(texto(resLote[3]["stdout"]).aparar() == "D", "ordem 3")
    escreva("ROTINAS-ZEROCOPY-LOTE-OK")
}
principal()
""",
        "ROTINAS-ZEROCOPY-LOTE-OK",
        opt=optimized,
    )

# 5. Garantir que I/O em arquivo de Bytes continua BLOQUEADO dentro de rotina (E3402)!
with tempfile.TemporaryDirectory(prefix="cgd-mem-err-") as tmp:
    src = Path(tmp) / "err_io.delegua"
    src.write_text(
        """
funcao lerEmWorker(p: texto): inteiro {
    const BytesMod = importar("cgd:bytes")
    const b = BytesMod.Bytes.lerArquivo(p)
    retorna b.tamanho()
}
var t: Tarefa<inteiro> = rotina lerEmWorker("/etc/hostname")
""",
        encoding="utf-8",
    )
    comp = subprocess.run(
        [CGD, str(src), "--verificar", "--diagnosticos=json"],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert comp.returncode == 1 and "E3402" in comp.stderr, (
        f"Bytes.lerArquivo deveria ser rejeitado em rotina com E3402, recebeu:\n{comp.stderr}"
    )
    checks += 1

print(f"cgd:memoria, Bytes zero-copy, Arena e Rotinas v2: {checks} verificações passaram (com/sem otimização).")
