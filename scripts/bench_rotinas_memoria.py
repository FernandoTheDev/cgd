#!/usr/bin/env python3
"""Suíte de microbenchmarks para rotinas paralelas, transferência, GC concorrente e cgd:memoria no CGD."""

from __future__ import annotations

import json
import os
import re
import statistics
import subprocess
import sys
import tempfile
import time
from pathlib import Path

CGD_ROOT = Path("/home/fernandodev/cgd")
CGD_BIN = CGD_ROOT / "cgd"
OUT_DIR = CGD_ROOT / "out"

TIME_FMT = "elapsed_s=%e\npeak_rss_kb=%M\nuser_s=%U\nsystem_s=%S"


def compile_and_run(name: str, source: str, reps: int = 3, opt: bool = True, cc: str = "clang") -> dict:
    with tempfile.TemporaryDirectory(prefix=f"cgd-bench-{name}-") as tmp:
        src = Path(tmp) / f"{name}.delegua"
        exe = Path(tmp) / name
        src.write_text(source, encoding="utf-8")
        cmd = [str(CGD_BIN), str(src), "-s", str(exe), f"--cc={cc}"]
        if opt:
            cmd.append("-o")
        comp = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
        if comp.returncode != 0:
            return {
                "name": name,
                "status": "compile_error",
                "stderr": comp.stderr.strip(),
                "stdout": comp.stdout.strip(),
            }

        runs = []
        last_stdout = ""
        for _ in range(reps):
            metrics_path = Path(tmp) / "metrics.txt"
            t0 = time.perf_counter()
            proc = subprocess.run(
                ["/usr/bin/time", "-f", TIME_FMT, "-o", str(metrics_path), str(exe)],
                capture_output=True,
                text=True,
                timeout=120,
            )
            dt_ms = (time.perf_counter() - t0) * 1000.0
            if proc.returncode != 0:
                return {
                    "name": name,
                    "status": "runtime_error",
                    "returncode": proc.returncode,
                    "stderr": proc.stderr.strip(),
                    "stdout": proc.stdout.strip(),
                }
            last_stdout = proc.stdout.strip()
            m: dict[str, float | int] = {"wall_ms": round(dt_ms, 3)}
            if metrics_path.exists():
                for line in metrics_path.read_text().splitlines():
                    if "=" in line:
                        k, v = line.split("=", 1)
                        m[k] = float(v) if k.endswith("_s") else int(v)
            for line in last_stdout.splitlines():
                if line.startswith("METRIC "):
                    for kv in line[7:].split():
                        if "=" in kv:
                            k, v = kv.split("=", 1)
                            try:
                                m[k] = float(v) if "." in v else int(v)
                            except ValueError:
                                m[k] = v
            runs.append(m)

        wall_vals = [float(r["wall_ms"]) for r in runs]
        rss_vals = [int(r.get("peak_rss_kb", 0)) for r in runs]
        inner_vals = [float(r["ms"]) for r in runs if "ms" in r]
        return {
            "name": name,
            "status": "ok",
            "reps": reps,
            "wall_ms": {
                "min": round(min(wall_vals), 3),
                "median": round(statistics.median(wall_vals), 3),
                "max": round(max(wall_vals), 3),
            },
            "inner_ms": (
                {
                    "min": round(min(inner_vals), 3),
                    "median": round(statistics.median(inner_vals), 3),
                    "max": round(max(inner_vals), 3),
                }
                if inner_vals
                else None
            ),
            "peak_rss_kb": {
                "min": min(rss_vals),
                "median": int(statistics.median(rss_vals)),
                "max": max(rss_vals),
            },
            "last_metrics": runs[-1],
            "sample_output": last_stdout.splitlines()[:6],
        }


BENCHMARKS: list[tuple[str, str]] = [
    (
        "01_spawn_small_tasks",
        """
funcao ident(x: inteiro): inteiro {
    retorna x + 1
}

assincrona funcao principal(): vazio {
    const tempo: qualquer = importar("cgd:tempo")
    const sis: qualquer = importar("cgd:sistema")
    const m0: dicionario = sis.Sistema.memoria()
    const cron: qualquer = tempo.Cronometro()
    var soma: inteiro = 0
    // 2000 tarefas em lotes de 100 (respeitando limite 256 da fila atual)
    para (var lote: inteiro = 0; lote < 20; lote++) {
        var tarefas: qualquer[] = []
        para (var i: inteiro = 0; i < 100; i++) {
            tarefas.empilhar(rotina ident(lote * 100 + i))
        }
        const res: qualquer[] = aguardar Promessa.todas(tarefas)
        para (var i: inteiro = 0; i < res.tamanho(); i++) {
            soma = soma + inteiro(res[i])
        }
    }
    const ms: real = cron.milisegundos()
    const m1: dicionario = sis.Sistema.memoria()
    const allocKb: inteiro = (inteiro(m1["gc_total"]) - inteiro(m0["gc_total"])) \\ 1024
    const cyc: inteiro = inteiro(m1["gc_cycles"]) - inteiro(m0["gc_cycles"])
    escreva("METRIC ms=${ms} us_per_task=${(ms * 1000.0) / 2000.0} alloc_kb=${allocKb} gc_cyc=${cyc} soma=${soma}")
}
principal()
""",
    ),
    (
        "02_cpu_bound_seq_vs_par",
        """
funcao trabalhoCpu(semente: inteiro, iters: inteiro): inteiro {
    var x: inteiro = semente | 1
    para (var i: inteiro = 0; i < iters; i++) {
        x = ((x * 1664525) + 1013904223) & 2147483647
    }
    retorna x
}

assincrona funcao principal(): vazio {
    const tempo: qualquer = importar("cgd:tempo")
    const iters: inteiro = 12000000
    const cron: qualquer = tempo.Cronometro()

    // 1. Sequencial (8 blocos)
    var sSeq: inteiro = 0
    para (var i: inteiro = 0; i < 8; i++) {
        sSeq = sSeq ^ trabalhoCpu(i + 1, iters)
    }
    const msSeq: real = cron.milisegundos()

    // 2. Paralelo (2 tarefas por vez, 4 lotes)
    cron.reiniciar()
    var sPar2: inteiro = 0
    para (var l: inteiro = 0; l < 4; l++) {
        const res2: qualquer[] = aguardar Promessa.todas([
            rotina trabalhoCpu(l * 2 + 1, iters),
            rotina trabalhoCpu(l * 2 + 2, iters)
        ])
        sPar2 = sPar2 ^ inteiro(res2[0]) ^ inteiro(res2[1])
    }
    const msPar2: real = cron.milisegundos()

    // 3. Paralelo (4 tarefas por vez, 2 lotes)
    cron.reiniciar()
    var sPar4: inteiro = 0
    para (var l: inteiro = 0; l < 2; l++) {
        const res4: qualquer[] = aguardar Promessa.todas([
            rotina trabalhoCpu(l * 4 + 1, iters),
            rotina trabalhoCpu(l * 4 + 2, iters),
            rotina trabalhoCpu(l * 4 + 3, iters),
            rotina trabalhoCpu(l * 4 + 4, iters)
        ])
        para (var j: inteiro = 0; j < 4; j++) sPar4 = sPar4 ^ inteiro(res4[j])
    }
    const msPar4: real = cron.milisegundos()

    // 4. Paralelo (8 tarefas simultaneas)
    cron.reiniciar()
    const res8: qualquer[] = aguardar Promessa.todas([
        rotina trabalhoCpu(1, iters), rotina trabalhoCpu(2, iters),
        rotina trabalhoCpu(3, iters), rotina trabalhoCpu(4, iters),
        rotina trabalhoCpu(5, iters), rotina trabalhoCpu(6, iters),
        rotina trabalhoCpu(7, iters), rotina trabalhoCpu(8, iters)
    ])
    var sPar8: inteiro = 0
    para (var j: inteiro = 0; j < 8; j++) sPar8 = sPar8 ^ inteiro(res8[j])
    const msPar8: real = cron.milisegundos()

    assercao(sSeq == sPar2 e sSeq == sPar4 e sSeq == sPar8, "resultados devem ser identicos")
    escreva("METRIC ms=${msPar4} seq_ms=${msSeq} par2_ms=${msPar2} par4_ms=${msPar4} par8_ms=${msPar8} speedup4=${msSeq / msPar4}")
}
principal()
""",
    ),
    (
        "03_transfer_text_roundtrip",
        """
funcao ecoTexto(s: texto): texto {
    retorna s
}

funcao construirTexto(tam: inteiro): texto {
    var partes: texto[] = []
    const bloco: texto = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
    const reps: inteiro = tam \\ 64
    para (var i: inteiro = 0; i < reps; i++) partes.empilhar(bloco)
    retorna partes.juntar("")
}

assincrona funcao principal(): vazio {
    const tempo: qualquer = importar("cgd:tempo")
    const sis: qualquer = importar("cgd:sistema")
    const t64k: texto = construirTexto(65536)
    const t4m: texto = construirTexto(4194304)

    const cron: qualquer = tempo.Cronometro()
    para (var i: inteiro = 0; i < 100; i++) {
        const r: texto = aguardar rotina ecoTexto(t64k)
        assercao(r.tamanho() == 65536, "64k")
    }
    const ms64k: real = cron.milisegundos()

    const m0: dicionario = sis.Sistema.memoria()
    cron.reiniciar()
    para (var i: inteiro = 0; i < 10; i++) {
        const r: texto = aguardar rotina ecoTexto(t4m)
        assercao(r.tamanho() == 4194304, "4m")
    }
    const ms4m: real = cron.milisegundos()
    const m1: dicionario = sis.Sistema.memoria()
    const allocMb: inteiro = (inteiro(m1["gc_total"]) - inteiro(m0["gc_total"])) \\ 1048576
    escreva("METRIC ms=${ms4m} rt64k_100_ms=${ms64k} rt4m_10_ms=${ms4m} alloc4m_mb=${allocMb}")
}
principal()
""",
    ),
    (
        "04_channel_throughput",
        """
assincrona funcao produtor(ch: qualquer, n: inteiro): vazio {
    para (var i: inteiro = 0; i < n; i++) {
        aguardar ch.enviar(i)
    }
    ch.fechar()
}

assincrona funcao consumidor(ch: qualquer): inteiro {
    var soma: inteiro = 0
    enquanto (verdadeiro) {
        tente {
            const v: inteiro = aguardar ch.receber()
            soma = soma + v
        } pegue (erro: Excecao) {
            sustar
        }
    }
    retorna soma
}

assincrona funcao principal(): vazio {
    const tempo: qualquer = importar("cgd:tempo")
    const Async: qualquer = importar("cgd:assincrono")
    const n: inteiro = 10000
    const ch: qualquer = Async.Canal(64)
    const cron: qualquer = tempo.Cronometro()
    const p: Promessa<vazio> = produtor(ch, n)
    const c: Promessa<inteiro> = consumidor(ch)
    aguardar p
    const soma: inteiro = aguardar c
    const ms: real = cron.milisegundos()
    assercao(soma == (n * (n - 1)) \\ 2, "soma canal")
    escreva("METRIC ms=${ms} msgs=${n} us_per_msg=${(ms * 1000.0) / real(n)}")
}
principal()
""",
    ),
    (
        "05_gc_concurrent_alloc",
        """
classe NoBench {
    a: inteiro
    b: inteiro
    c: texto
    construtor(a: inteiro, b: inteiro, c: texto) {
        isto.a = a
        isto.b = b
        isto.c = c
    }
}

funcao alocarEmWorker(seed: inteiro, n: inteiro): inteiro {
    var acc: inteiro = 0
    var janela: NoBench[] = []
    para (var i: inteiro = 0; i < n; i++) {
        const obj: NoBench = NoBench(i + seed, i * 3, "item_" + texto(i & 255))
        janela.empilhar(obj)
        se (janela.tamanho() > 256) {
            acc = acc + janela[0].a + janela[janela.tamanho() - 1].b
            janela.limpar()
        }
    }
    retorna acc
}

assincrona funcao principal(): vazio {
    const tempo: qualquer = importar("cgd:tempo")
    const sis: qualquer = importar("cgd:sistema")
    const n: inteiro = 80000

    const m0: dicionario = sis.Sistema.memoria()
    const cron: qualquer = tempo.Cronometro()
    var sSeq: inteiro = 0
    para (var i: inteiro = 0; i < 4; i++) {
        sSeq = sSeq + alocarEmWorker(i, n)
    }
    const msSeq: real = cron.milisegundos()
    const m1: dicionario = sis.Sistema.memoria()

    cron.reiniciar()
    const res4: qualquer[] = aguardar Promessa.todas([
        rotina alocarEmWorker(0, n),
        rotina alocarEmWorker(1, n),
        rotina alocarEmWorker(2, n),
        rotina alocarEmWorker(3, n)
    ])
    const sPar4: inteiro = inteiro(res4[0]) + inteiro(res4[1]) + inteiro(res4[2]) + inteiro(res4[3])
    const msPar4: real = cron.milisegundos()
    const m2: dicionario = sis.Sistema.memoria()

    // Execucao concorrente com coleta explicita na thread principal durante workers ativos
    cron.reiniciar()
    const tA: Tarefa<inteiro> = rotina alocarEmWorker(0, n)
    const tB: Tarefa<inteiro> = rotina alocarEmWorker(1, n)
    sis.Sistema.coletarGC(verdadeiro)
    const tC: Tarefa<inteiro> = rotina alocarEmWorker(2, n)
    const tD: Tarefa<inteiro> = rotina alocarEmWorker(3, n)
    sis.Sistema.coletarGC(falso)
    const rAll: qualquer[] = aguardar Promessa.todas([tA, tB, tC, tD])
    const msParGc: real = cron.milisegundos()
    const m3: dicionario = sis.Sistema.memoria()

    assercao(sSeq == sPar4, "gc alloc determinismo")
    const cycSeq: inteiro = inteiro(m1["gc_cycles"]) - inteiro(m0["gc_cycles"])
    const cycPar: inteiro = inteiro(m2["gc_cycles"]) - inteiro(m1["gc_cycles"])
    const heapMb: inteiro = inteiro(m3["gc_heap"]) \\ 1048576
    escreva("METRIC ms=${msPar4} seq_ms=${msSeq} par4_ms=${msPar4} par_with_gc_ms=${msParGc} speedup=${msSeq / msPar4} cyc_seq=${cycSeq} cyc_par=${cycPar} heap_mb=${heapMb}")
}
principal()
""",
    ),
    (
        "06_bytes_frozen_zero_copy",
        """
funcao checksumFatia(bufRaw: qualquer, ini: inteiro, fim: inteiro): inteiro {
    const BytesMod = importar("cgd:bytes")
    const b = BytesMod.Bytes.deRecurso(bufRaw)
    var acc: inteiro = 0
    para (var i: inteiro = ini; i < fim; i = i + 8) {
        acc = (acc + b.lerU64LE(i)) & 2147483647
    }
    retorna acc
}

assincrona funcao principal(): vazio {
    const BytesMod = importar("cgd:bytes")
    const AsyncMod = importar("cgd:assincrono")
    const MemMod = importar("cgd:memoria")
    const tempo = importar("cgd:tempo")

    // Cria buffer de 16 MiB (4M de u32) e congela uma unica vez
    const tam: inteiro = 16 * 1024 * 1024
    const b = BytesMod.Bytes.criarReservado(tam)
    b.anexarPreenchimento(171, tam)
    const cong = b.congelar()
    const raw = cong.recursoInterno()
    b.liberar()
    MemMod.Memoria.coletar(verdadeiro)

    // Sequencial
    const cron = tempo.Cronometro()
    const sSeq: inteiro = checksumFatia(raw, 0, tam)
    const msSeq: real = cron.milisegundos()

    // 4 workers lendo a mesma visao congelada zero-copy (10 iteracoes de dispatch)
    AsyncMod.Rotinas.configurar(4, 256)
    const m0: dicionario = MemMod.Memoria.estatisticas()
    cron.reiniciar()
    var sPar: inteiro = 0
    const quarto: inteiro = tam \\ 4
    para (var rep: inteiro = 0; rep < 10; rep++) {
        const res: qualquer[] = aguardar Promessa.todas([
            rotina checksumFatia(raw, 0, quarto),
            rotina checksumFatia(raw, quarto, quarto * 2),
            rotina checksumFatia(raw, quarto * 2, quarto * 3),
            rotina checksumFatia(raw, quarto * 3, tam)
        ])
        sPar = (inteiro(res[0]) + inteiro(res[1]) + inteiro(res[2]) + inteiro(res[3])) & 2147483647
    }
    const msPar10: real = cron.milisegundos()
    const msPar1: real = msPar10 / 10.0
    const m1: dicionario = MemMod.Memoria.estatisticas()
    const allocKb: inteiro = (inteiro(m1["alocadosBytes"]) - inteiro(m0["alocadosBytes"])) \\ 1024
    const st: dicionario = AsyncMod.Rotinas.estatisticas()
    assercao(sSeq == sPar, "checksum deterministico")
    escreva("METRIC ms=${msPar1} seq_ms=${msSeq} par4_ms=${msPar1} speedup=${msSeq / msPar1} alloc_gc_kb_10x=${allocKb} transfer_ms=${st[\"tempoTransferenciaMs\"]}")
}
principal()
""",
    ),
    (
        "07_arena_vs_bytes_vs_vetor_vs_dict",
        """
funcao principal(): vazio {
    const MemMod = importar("cgd:memoria")
    const BytesMod = importar("cgd:bytes")
    const tempo = importar("cgd:tempo")
    const n: inteiro = 50000
    const rodadas: inteiro = 20

    // 1. Arena FatiaInt64 reutilizada com arena.limpar()
    MemMod.Memoria.coletar(verdadeiro)
    const mA0: dicionario = MemMod.Memoria.estatisticas()
    const cron = tempo.Cronometro()
    const arena = MemMod.Memoria.criarArena(512 * 1024, 8 * 1024 * 1024)
    var somaArena: inteiro = 0
    para (var r: inteiro = 0; r < rodadas; r++) {
        const fi = arena.criarInt64(n, 0)
        para (var i: inteiro = 0; i < n; i++) fi.definir(i, i * 3 + r)
        para (var i: inteiro = 0; i < n; i++) somaArena = somaArena + fi.obter(i)
        arena.limpar()
    }
    arena.liberar()
    const msArena: real = cron.milisegundos()
    const mA1: dicionario = MemMod.Memoria.estatisticas()
    const allocArenaKb: inteiro = (inteiro(mA1["alocadosBytes"]) - inteiro(mA0["alocadosBytes"])) \\ 1024

    // 2. Bytes (GC_MALLOC_ATOMIC) reutilizado com limpar()
    MemMod.Memoria.coletar(verdadeiro)
    const mB0: dicionario = MemMod.Memoria.estatisticas()
    cron.reiniciar()
    const buf = BytesMod.Bytes.criarReservado(n * 8)
    var somaBytes: inteiro = 0
    para (var r: inteiro = 0; r < rodadas; r++) {
        buf.limpar()
        para (var i: inteiro = 0; i < n; i++) buf.anexarU64LE(i * 3 + r)
        para (var i: inteiro = 0; i < n; i++) somaBytes = somaBytes + buf.lerU64LE(i * 8)
    }
    buf.liberar()
    const msBytes: real = cron.milisegundos()
    const mB1: dicionario = MemMod.Memoria.estatisticas()
    const allocBytesKb: inteiro = (inteiro(mB1["alocadosBytes"]) - inteiro(mB0["alocadosBytes"])) \\ 1024

    // 3. Vetor inteiro[] gerenciado pelo GC
    MemMod.Memoria.coletar(verdadeiro)
    const mV0: dicionario = MemMod.Memoria.estatisticas()
    cron.reiniciar()
    var somaVec: inteiro = 0
    para (var r: inteiro = 0; r < rodadas; r++) {
        var vec: inteiro[] = []
        para (var i: inteiro = 0; i < n; i++) vec.empilhar(i * 3 + r)
        para (var i: inteiro = 0; i < n; i++) somaVec = somaVec + vec[i]
        vec.limpar()
    }
    const msVec: real = cron.milisegundos()
    const mV1: dicionario = MemMod.Memoria.estatisticas()
    const allocVecKb: inteiro = (inteiro(mV1["alocadosBytes"]) - inteiro(mV0["alocadosBytes"])) \\ 1024

    // 4. Dicionario por chave texto(i) (padrao antigo do IR optimizer) - 5x menor para manter rapido
    MemMod.Memoria.coletar(verdadeiro)
    const mD0: dicionario = MemMod.Memoria.estatisticas()
    cron.reiniciar()
    const nDict: inteiro = 10000
    var somaDict: inteiro = 0
    para (var r: inteiro = 0; r < 4; r++) {
        var d: dicionario = {}
        para (var i: inteiro = 0; i < nDict; i++) d[texto(i)] = i * 3 + r
        para (var i: inteiro = 0; i < nDict; i++) somaDict = somaDict + inteiro(d[texto(i)])
        d.limpar()
    }
    const msDict: real = cron.milisegundos()
    const mD1: dicionario = MemMod.Memoria.estatisticas()
    const allocDictKb: inteiro = (inteiro(mD1["alocadosBytes"]) - inteiro(mD0["alocadosBytes"])) \\ 1024

    assercao(somaArena == somaBytes e somaArena == somaVec, "somas identicas")
    escreva("METRIC ms=${msArena} arena_ms=${msArena} arena_gc_kb=${allocArenaKb} bytes_ms=${msBytes} bytes_gc_kb=${allocBytesKb} vec_ms=${msVec} vec_gc_kb=${allocVecKb} dict_ms=${msDict} dict_gc_kb=${allocDictKb}")
}
principal()
""",
    ),
    (
        "08_workers_1_2_4_8_scaling",
        """
funcao cargaComArena(seed: inteiro, n: inteiro): inteiro {
    const MemMod = importar("cgd:memoria")
    const arena = MemMod.Arena(65536, 4 * 1024 * 1024)
    const arr = arena.criarInt64(4096, 0)
    var x: inteiro = seed | 1
    para (var r: inteiro = 0; r < n; r++) {
        const idx: inteiro = r & 4095
        x = ((x * 1664525) + 1013904223) & 2147483647
        arr.definir(idx, x)
    }
    var acc: inteiro = 0
    para (var i: inteiro = 0; i < 4096; i++) acc = (acc + arr.obter(i)) & 2147483647
    arena.liberar()
    retorna acc
}

assincrona funcao rodarComWorkers(w: inteiro, iters: inteiro): (real, inteiro) {
    const AsyncMod = importar("cgd:assincrono")
    const tempo = importar("cgd:tempo")
    AsyncMod.Rotinas.configurar(w, 256)
    const cron = tempo.Cronometro()
    var tarefas: qualquer[] = []
    para (var i: inteiro = 0; i < 8; i++) {
        tarefas.empilhar(rotina cargaComArena(i + 1, iters))
    }
    const res: qualquer[] = aguardar Promessa.todas(tarefas)
    const ms: real = cron.milisegundos()
    var s: inteiro = 0
    para (var i: inteiro = 0; i < 8; i++) s = s ^ inteiro(res[i])
    retorna tupla([ms, s])
}

assincrona funcao principal(): vazio {
    const iters: inteiro = 1500000
    const r1: (real, inteiro) = aguardar rodarComWorkers(1, iters)
    const r2: (real, inteiro) = aguardar rodarComWorkers(2, iters)
    const r4: (real, inteiro) = aguardar rodarComWorkers(4, iters)
    const r8: (real, inteiro) = aguardar rodarComWorkers(8, iters)
    assercao(r1[1] == r2[1] e r1[1] == r4[1] e r1[1] == r8[1], "resultados deterministicos")
    escreva("METRIC ms=${r4[0]} w1_ms=${r1[0]} w2_ms=${r2[0]} w4_ms=${r4[0]} w8_ms=${r8[0]} sp2=${r1[0] / r2[0]} sp4=${r1[0] / r4[0]} sp8=${r1[0] / r8[0]}")
}
principal()
""",
    ),
]


def main() -> int:
    reps = int(sys.argv[1]) if len(sys.argv) > 1 else 3
    tag = sys.argv[2] if len(sys.argv) > 2 else "baseline"
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    results = []
    for name, src in BENCHMARKS:
        print(f"Running {name} ({reps} reps)...", flush=True)
        res = compile_and_run(name, src, reps=reps)
        results.append(res)
        if res["status"] == "ok":
            print(
                f"  OK wall={res['wall_ms']['median']}ms inner={res['inner_ms']['median'] if res['inner_ms'] else 'n/a'}ms "
                f"rss={res['peak_rss_kb']['median']}KB | {res['sample_output'][0] if res['sample_output'] else ''}",
                flush=True,
            )
        else:
            print(f"  {res['status']}: {res.get('stderr', '')[:300]}", flush=True)

    out_file = OUT_DIR / f"bench_rotinas_{tag}.json"
    out_file.write_text(json.dumps({"tag": tag, "results": results}, indent=2), encoding="utf-8")
    print(f"Saved {out_file}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
