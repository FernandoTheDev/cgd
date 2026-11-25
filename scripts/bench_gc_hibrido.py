#!/usr/bin/env python3
"""
Benchmark científico reprodutível de ablação A/B/C/D/E para o CGD-GC e
Gerenciamento Híbrido de Memória (ANS, StackLocal, DeterministicHeap, Fusão, Devirt).

Configurações medidas:
  A: Baseline congelado pré-alterações (out/baseline_a/cgd + Boehm GC antigo)
  B: CGD novo + --gc=boehm --opcoes-memoria=nenhuma
  C: CGD novo + --gc=cgd   --opcoes-memoria=nenhuma
  D: CGD novo + --gc=boehm --opcoes-memoria=padrao
  E: CGD novo + --gc=cgd   --opcoes-memoria=padrao (padrão final)
"""

import argparse
import csv
import json
import os
import resource
import statistics
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CGD_NEW = ROOT / "cgd"
CGD_BASE_A = ROOT / "out/baseline_a/cgd"
DCC_DIR = Path("/home/fernandodev/dcc")
OUT_DIR = ROOT / "out/bench"


CONFIGS = {
    "A": {"label": "Baseline A (Boehm antigo)", "cgd": CGD_BASE_A, "flags": ["-o"]},
    "B": {
        "label": "Novo + Boehm (sem opts mem)",
        "cgd": CGD_NEW,
        "flags": ["-o", "--gc=boehm", "--opcoes-memoria=nenhuma"],
    },
    "C": {
        "label": "Novo + CGD-GC (sem opts mem)",
        "cgd": CGD_NEW,
        "flags": ["-o", "--gc=cgd", "--opcoes-memoria=nenhuma"],
    },
    "D": {
        "label": "Novo + Boehm (+ opts mem)",
        "cgd": CGD_NEW,
        "flags": ["-o", "--gc=boehm", "--opcoes-memoria=padrao"],
    },
    "E": {
        "label": "Novo + CGD-GC (+ opts mem)",
        "cgd": CGD_NEW,
        "flags": ["-o", "--gc=cgd", "--opcoes-memoria=padrao"],
    },
}


MICRO_BENCHMARKS = {
    "alloc_nursery_churn": """
var total: inteiro = 0
para (var i: inteiro = 0; i < 150000; i++) {
    var v = [i, i + 1, i + 2, i + 3]
    var s: texto = "obj-" + texto(i % 1000)
    total = total + v[2] + tamanho(s)
}
escreva(total)
""",
    "graph_cycles_retention": """
var retidos = []
para (var i: inteiro = 0; i < 4000; i++) {
    var a = { "id": i, "dados": [i, i + 1, i + 2] }
    var b = { "ref": a, "txt": "no-" + texto(i) }
    a["volta"] = b
    se (i % 4 == 0) {
        retidos.adicionar(a)
    }
    se (tamanho(retidos) > 500) {
        retidos = []
    }
}
escreva(tamanho(retidos))
""",
    "ans_numeric_fib": """
funcao fib(n: inteiro): inteiro {
    se (n <= 1) {
        retorna n
    }
    retorna fib(n - 1) + fib(n - 2)
}

funcao soma_escalar(n: inteiro): inteiro {
    var acc: inteiro = 0
    para (var i: inteiro = 1; i <= n; i++) {
        acc = acc + ((i * 3) ^ (i \\ 2))
    }
    retorna acc
}

var r1: inteiro = fib(32)
var r2: inteiro = soma_escalar(5000000)
escreva(r1 + r2)
""",
    "stack_det_fusion_devirt": """
classe Vet2 {
    x: inteiro
    y: inteiro
    construtor(x: inteiro, y: inteiro) {
        isto.x = x
        isto.y = y
    }
    norma2(): inteiro {
        retorna isto.x * isto.x + isto.y * isto.y
    }
}

funcao passo(i: inteiro): inteiro {
    var p: Vet2 = Vet2(i % 97, (i * 3) % 89)
    var n: inteiro = p.norma2()
    var buf = [i, n, i + n, n - i, i * 2]
    var t = (i, n, buf[2])
    retorna n + buf[4] + tamanho(t)
}

var total: inteiro = 0
para (var i: inteiro = 0; i < 120000; i++) {
    total = total + passo(i)
}
escreva(total)
""",
    "multithread_routines": """
funcao trabalho(base: inteiro): inteiro {
    var acc: inteiro = 0
    para (var i: inteiro = 0; i < 20000; i++) {
        var v = [base + i, i * 2, i + 1]
        acc = acc + v[0] + v[1]
    }
    retorna acc
}

assincrona funcao executar(): vazio {
    var t1: Tarefa<inteiro> = rotina trabalho(1)
    var t2: Tarefa<inteiro> = rotina trabalho(2)
    var t3: Tarefa<inteiro> = rotina trabalho(3)
    var t4: Tarefa<inteiro> = rotina trabalho(4)
    var s: inteiro = (aguardar t1) + (aguardar t2) + (aguardar t3) + (aguardar t4)
    escreva(s)
}

executar()
""",
}


def measure_cmd(cmd, cwd=ROOT, env=None, timeout=180):
    """Executa comando e mede tempo de parede (ms) e pico de RSS (KB) via /usr/bin/time -f."""
    merged_env = os.environ.copy()
    if env:
        merged_env.update(env)
    with tempfile.NamedTemporaryFile(prefix="cgd_rss_", suffix=".txt", delete=False) as tf:
        rss_file = Path(tf.name)
    try:
        wrapped = ["/usr/bin/time", "-f", "%M", "-o", str(rss_file)] + cmd
        t0 = time.perf_counter()
        proc = subprocess.run(
            wrapped,
            cwd=str(cwd),
            env=merged_env,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        dt_ms = (time.perf_counter() - t0) * 1000.0
        rss_kb = -1
        if rss_file.exists():
            txt = rss_file.read_text().strip().splitlines()
            if txt and txt[-1].isdigit():
                rss_kb = int(txt[-1])
        return proc, dt_ms, rss_kb
    finally:
        rss_file.unlink(missing_ok=True)


def compile_source(cfg_key: str, src_path: Path, out_bin: Path, mem_json: Path = None):
    cfg = CONFIGS[cfg_key]
    cmd = [str(cfg["cgd"]), str(src_path), "-s", str(out_bin)] + list(cfg["flags"])
    if mem_json is not None and cfg_key != "A":
        cmd.append(f"--relatorio-memoria-json={mem_json}")
    env = None
    if cfg_key == "A":
        # Garante que Baseline A use exatamente seu próprio runtime congelado
        env = {"CGD_RUNTIME": str(ROOT / "out/baseline_a/lib/libdelegua_rt.o")}
    proc, dt_ms, _ = measure_cmd(cmd, env=env, timeout=240)
    if proc.returncode != 0:
        raise RuntimeError(
            f"Falha compilando {src_path} [{cfg_key}]:\nSTDOUT:\n{proc.stdout}\nSTDERR:\n{proc.stderr}"
        )
    return dt_ms, out_bin.stat().st_size


def run_microbenchmarks(runs: int = 3):
    print("\n=== 1. MICRO/MACRO BENCHMARKS (Ablação A/B/C/D/E) ===")
    results = {}
    with tempfile.TemporaryDirectory(prefix="cgd_micro_") as td:
        td_path = Path(td)
        for name, src in MICRO_BENCHMARKS.items():
            src_path = td_path / f"{name}.delegua"
            src_path.write_text(src, encoding="utf-8")
            results[name] = {}
            ref_stdout = None
            for cfg_key in ("A", "B", "C", "D", "E"):
                bin_path = td_path / f"{name}_{cfg_key}"
                mem_json = td_path / f"{name}_{cfg_key}.mem.json"
                comp_ms, bin_sz = compile_source(cfg_key, src_path, bin_path, mem_json)
                times = []
                rss_list = []
                # Warmup + runs
                for r in range(runs + 1):
                    proc, dt_ms, rss_kb = measure_cmd([str(bin_path)], timeout=120)
                    assert proc.returncode == 0, f"{name}[{cfg_key}] falhou: {proc.stderr}"
                    if ref_stdout is None:
                        ref_stdout = proc.stdout
                    else:
                        assert proc.stdout == ref_stdout, (
                            f"Divergência semântica em {name}[{cfg_key}]: {proc.stdout!r} != {ref_stdout!r}"
                        )
                    if r > 0:
                        times.append(dt_ms)
                        rss_list.append(rss_kb)
                mem_rep = json.loads(mem_json.read_text()) if mem_json.exists() else None
                entry = {
                    "compile_ms": round(comp_ms, 2),
                    "bin_bytes": bin_sz,
                    "median_ms": round(statistics.median(times), 2),
                    "min_ms": round(min(times), 2),
                    "max_ms": round(max(times), 2),
                    "peak_rss_kb": max(rss_list),
                    "mem_report": mem_rep,
                }
                results[name][cfg_key] = entry
            a_ms = results[name]["A"]["median_ms"]
            e_ms = results[name]["E"]["median_ms"]
            speedup = a_ms / e_ms if e_ms > 0 else 0.0
            print(
                f"  {name:26s} | A={a_ms:7.1f}ms | B={results[name]['B']['median_ms']:7.1f}ms "
                f"| C={results[name]['C']['median_ms']:7.1f}ms | D={results[name]['D']['median_ms']:7.1f}ms "
                f"| E={e_ms:7.1f}ms ({speedup:5.2f}x vs A) | RSS A={results[name]['A']['peak_rss_kb']}KB -> E={results[name]['E']['peak_rss_kb']}KB"
            )
    return results


def discover_eligible_examples():
    ex_root = ROOT / "exemplos"
    project_dirs = [m.parent.resolve() for m in ex_root.rglob("projeto.json")]
    eligible = []
    skipped = []
    for f in sorted(ex_root.rglob("*.delegua")):
        if any(f.resolve().is_relative_to(pd) for pd in project_dirs):
            continue
        txt = f.read_text(encoding="utf-8", errors="replace")
        lines = txt.splitlines()
        hidx = 1 if lines and lines[0].strip() == "//$" else 0
        header = lines[hidx] if hidx < len(lines) else ""
        if header.startswith("//#"):
            skipped.append((str(f.relative_to(ROOT)), "expected-nonzero-exit"))
            continue
        if "leia(" in txt or "//@entrada:" in txt:
            skipped.append((str(f.relative_to(ROOT)), "requires-stdin"))
            continue
        if "cgd:graficos" in txt or "gtk" in str(f).lower() or "sdl" in str(f).lower():
            skipped.append((str(f.relative_to(ROOT)), "gui-window"))
            continue
        if "ServidorHTTP" in txt or "WebSocket" in txt:
            skipped.append((str(f.relative_to(ROOT)), "network-server"))
            continue
        eligible.append(f)
    return eligible, skipped


def run_examples_benchmarks(runs: int = 3):
    print("\n=== 2. TODOS OS EXEMPLOS ELEGÍVEIS EM exemplos/ (A vs C vs E) ===")
    eligible, skipped = discover_eligible_examples()
    print(f"  Encontrados {len(eligible)} exemplos elegíveis ({len(skipped)} ignorados por stdin/GUI/exit!=0).")
    rows = []
    with tempfile.TemporaryDirectory(prefix="cgd_ex_bench_") as td:
        td_path = Path(td)
        for idx, ex in enumerate(eligible):
            rel = str(ex.relative_to(ROOT))
            rec = {"example": rel, "status": "ok"}
            ref_out = None
            failed = False
            for cfg_key in ("A", "C", "E"):
                bin_path = td_path / f"ex_{idx}_{cfg_key}"
                mem_json = td_path / f"ex_{idx}_{cfg_key}.mem.json"
                try:
                    comp_ms, bin_sz = compile_source(cfg_key, ex, bin_path, mem_json)
                except RuntimeError as err:
                    # Alguns exemplos novos (Prompt Mestre X) podem usar recursos não existentes no Baseline A
                    if cfg_key == "A":
                        rec["A"] = {"error": "unsupported_in_baseline_a"}
                        continue
                    rec["status"] = f"compile_error_{cfg_key}"
                    rec["error"] = str(err)[:200]
                    failed = True
                    break
                times = []
                rss_list = []
                for r in range(runs):
                    try:
                        proc, dt_ms, rss_kb = measure_cmd([str(bin_path)], timeout=12)
                    except subprocess.TimeoutExpired:
                        rec["status"] = f"timeout_{cfg_key}"
                        failed = True
                        break
                    if proc.returncode != 0:
                        rec["status"] = f"runtime_error_{cfg_key}"
                        failed = True
                        break
                    if ref_out is None:
                        ref_out = proc.stdout
                    times.append(dt_ms)
                    rss_list.append(rss_kb)
                if failed:
                    break
                mem_rep = json.loads(mem_json.read_text()) if mem_json.exists() else None
                rec[cfg_key] = {
                    "compile_ms": round(comp_ms, 2),
                    "bin_bytes": bin_sz,
                    "median_ms": round(statistics.median(times), 2),
                    "peak_rss_kb": max(rss_list),
                    "mem_report": mem_rep,
                }
            rows.append(rec)
    ok_rows = [r for r in rows if r["status"] == "ok" and "E" in r]
    both_ae = [r for r in ok_rows if "A" in r and "median_ms" in r["A"]]
    a_tot = sum(r["A"]["median_ms"] for r in both_ae)
    e_tot = sum(r["E"]["median_ms"] for r in both_ae)
    a_rss = statistics.median(r["A"]["peak_rss_kb"] for r in both_ae) if both_ae else 0
    e_rss = statistics.median(r["E"]["peak_rss_kb"] for r in both_ae) if both_ae else 0
    print(
        f"  Exemplos validados: {len(ok_rows)}/{len(eligible)} OK ({len(both_ae)} comparáveis com Baseline A)."
    )
    if both_ae:
        print(
            f"  Soma medianas tempo (A vs E): A={a_tot:.1f}ms vs E={e_tot:.1f}ms ({a_tot / max(e_tot, 0.01):.2f}x) | "
            f"RSS mediano: A={a_rss:.0f}KB vs E={e_rss:.0f}KB"
        )
    return {"eligible_count": len(eligible), "skipped": skipped, "rows": rows}


def run_dcc_benchmarks(runs: int = 3):
    print("\n=== 3. DCC SEM MODIFICAÇÕES (/home/fernandodev/dcc) — A/B/C/D/E ===")
    dcc_main = DCC_DIR / "src/main.delegua"
    dcc_workloads = [
        ("hello_libc.c", DCC_DIR / "examples/hello_libc.c"),
        ("vm_pilha.c", DCC_DIR / "examples/vm_pilha.c"),
        ("assembler.c", DCC_DIR / "examples/assembler.c"),
        ("interpretador.c", DCC_DIR / "examples/interpretador.c"),
    ]
    out_dcc = OUT_DIR / "dcc_ablation"
    out_dcc.mkdir(parents=True, exist_ok=True)
    res = {"builds": {}, "workloads": {}}
    bins = {}

    for cfg_key in ("A", "B", "C", "D", "E"):
        bin_path = out_dcc / f"dcc_{cfg_key}"
        mem_json = out_dcc / f"dcc_{cfg_key}.mem.json"
        comp_ms, bin_sz = compile_source(cfg_key, dcc_main, bin_path, mem_json)
        mem_rep = json.loads(mem_json.read_text()) if mem_json.exists() else None
        ldd_out = subprocess.check_output(["ldd", str(bin_path)], text=True)
        has_libgc = "libgc.so" in ldd_out
        res["builds"][cfg_key] = {
            "compile_ms": round(comp_ms, 2),
            "bin_bytes": bin_sz,
            "links_libgc": has_libgc,
            "mem_report": mem_rep,
        }
        bins[cfg_key] = bin_path
        print(
            f"  Build DCC [{cfg_key}]: {comp_ms:7.1f}ms | bin={bin_sz / 1048576.0:.2f} MiB | libgc={has_libgc}"
        )

    with tempfile.TemporaryDirectory(prefix="cgd_dcc_wk_") as td:
        td_path = Path(td)
        for wname, cfile in dcc_workloads:
            res["workloads"][wname] = {}
            ref_asm = None
            for cfg_key in ("A", "B", "C", "D", "E"):
                times = []
                rss_list = []
                asm_out = td_path / f"{wname}_{cfg_key}.s"
                for r in range(runs + 1):
                    proc, dt_ms, rss_kb = measure_cmd(
                        [str(bins[cfg_key]), "-S", str(cfile), "-o", str(asm_out)],
                        timeout=120,
                    )
                    assert proc.returncode == 0, f"DCC[{cfg_key}] falhou em {wname}: {proc.stderr}"
                    if ref_asm is None:
                        ref_asm = asm_out.read_bytes()
                    else:
                        assert asm_out.read_bytes() == ref_asm, (
                            f"Assembly divergente em DCC[{cfg_key}] para {wname}!"
                        )
                    if r > 0:
                        times.append(dt_ms)
                        rss_list.append(rss_kb)
                res["workloads"][wname][cfg_key] = {
                    "median_ms": round(statistics.median(times), 2),
                    "min_ms": round(min(times), 2),
                    "max_ms": round(max(times), 2),
                    "peak_rss_kb": max(rss_list),
                }
            a_ms = res["workloads"][wname]["A"]["median_ms"]
            e_ms = res["workloads"][wname]["E"]["median_ms"]
            print(
                f"  DCC -S {wname:16s} | A={a_ms:6.1f}ms | B={res['workloads'][wname]['B']['median_ms']:6.1f}ms "
                f"| C={res['workloads'][wname]['C']['median_ms']:6.1f}ms | D={res['workloads'][wname]['D']['median_ms']:6.1f}ms "
                f"| E={e_ms:6.1f}ms ({a_ms / max(e_ms, 0.01):.2f}x) | RSS A={res['workloads'][wname]['A']['peak_rss_kb']}KB -> E={res['workloads'][wname]['E']['peak_rss_kb']}KB"
            )
    return res


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--runs", type=int, default=3)
    parser.add_argument("--only-dcc", action="store_true")
    args = parser.parse_args()
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    if not args.only_dcc:
        micro = run_microbenchmarks(args.runs)
        (OUT_DIR / "bench_micro.json").write_text(json.dumps(micro, indent=2, ensure_ascii=False))

        ex_data = run_examples_benchmarks(args.runs)
        (OUT_DIR / "bench_exemplos.json").write_text(json.dumps(ex_data, indent=2, ensure_ascii=False))
        with (OUT_DIR / "bench_exemplos.csv").open("w", newline="", encoding="utf-8") as cf:
            w = csv.writer(cf)
            w.writerow(
                [
                    "example",
                    "status",
                    "A_ms",
                    "C_ms",
                    "E_ms",
                    "A_rss_kb",
                    "C_rss_kb",
                    "E_rss_kb",
                    "E_ans_fns",
                    "E_stack_objs",
                    "E_det_free",
                    "E_devirt",
                ]
            )
            for r in ex_data["rows"]:
                mr = (r.get("E") or {}).get("mem_report") or {}
                w.writerow(
                    [
                        r["example"],
                        r["status"],
                        (r.get("A") or {}).get("median_ms", ""),
                        (r.get("C") or {}).get("median_ms", ""),
                        (r.get("E") or {}).get("median_ms", ""),
                        (r.get("A") or {}).get("peak_rss_kb", ""),
                        (r.get("C") or {}).get("peak_rss_kb", ""),
                        (r.get("E") or {}).get("peak_rss_kb", ""),
                        mr.get("funcoesANS", ""),
                        mr.get("objetosStack", ""),
                        mr.get("liberacoesDeterministicas", ""),
                        mr.get("chamadasDesvirtualizadas", ""),
                    ]
                )

    dcc_data = run_dcc_benchmarks(args.runs)
    (OUT_DIR / "bench_dcc.json").write_text(json.dumps(dcc_data, indent=2, ensure_ascii=False))
    print(f"\nBenchmarks concluídos! Resultados salvos em {OUT_DIR}/")


if __name__ == "__main__":
    main()
