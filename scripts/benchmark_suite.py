#!/usr/bin/env python3
"""Suíte reproduzível de microbenchmarks e benchmarks de aplicação real (DCC) para o CGD."""

from pathlib import Path
import argparse
import json
import os
import re
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]

MICROBENCHMARKS = {
    "int_loop": """
var soma: inteiro = 0
para (var i: inteiro = 0; i < 2000000; i++) {
    soma += (i ^ (i >> 1)) & 1023
}
assercao(soma > 0)
escreva(soma)
""",
    "float_loop": """
var acc: real = 1.0
para (var i: inteiro = 1; i <= 1000000; i++) {
    acc = acc + (i * 0.5) / (i + 1.0)
}
assercao(acc > 0.0)
escreva(inteiro(acc))
""",
    "fn_calls": """
funcao passo(a: inteiro, b: inteiro): inteiro {
    retorna (a + b) ^ (a >> 2)
}
var acc: inteiro = 1
para (var i: inteiro = 0; i < 1000000; i++) {
    acc = passo(acc, i)
}
escreva(acc)
""",
    "oop_fields_methods": """
classe Contador {
    valor: inteiro = 0
    passo: inteiro = 1

    construtor(inicial: inteiro, passo: inteiro) {
        isto.valor = inicial
        isto.passo = passo
    }

    avancar(extra: inteiro): inteiro {
        isto.valor = isto.valor + isto.passo + extra
        retorna isto.valor
    }
}

var c: Contador = Contador(0, 3)
var total: inteiro = 0
para (var i: inteiro = 0; i < 400000; i++) {
    total += c.avancar(i & 7)
}
assercao(total > 0)
escreva(total)
""",
    "array_ops": """
var v: inteiro[] = []
para (var i: inteiro = 0; i < 200000; i++) {
    v.empilhar(i * 3)
}
var soma: inteiro = 0
const n: inteiro = v.tamanho()
para (var j: inteiro = 0; j < n; j++) {
    v[j] = v[j] + 1
    soma += v[j]
}
assercao(soma > 0)
escreva(soma)
""",
    "dict_ops": """
var d: dicionario = {}
para (var i: inteiro = 0; i < 50000; i++) {
    d["chave_" + texto(i & 4095)] = i
}
var soma: inteiro = 0
para (var j: inteiro = 0; j < 100000; j++) {
    const k: texto = "chave_" + texto(j & 4095)
    se (k em d) {
        soma += d[k]
    }
}
assercao(soma > 0)
escreva(soma)
""",
    "string_unicode_preproc": """
var linhas: texto[] = []
para (var i: inteiro = 0; i < 1500; i++) {
    linhas.empilhar("#define MACRO_" + texto(i) + " (valor_longo_de_teste_preproc + /* comentario UTF-8: ação */ 42)")
}
const fonte: texto = linhas.juntar("\\n")
const n: inteiro = fonte.tamanho()
var tokens: inteiro = 0
var pos: inteiro = 0
enquanto (pos < n) {
    const ch: texto = fonte[pos]
    se (ch == " " ou ch == "\\t" ou ch == "\\r" ou ch == "\\n") {
        pos++
    } senao se (ch == "#") {
        const fatia: texto = fonte.fatiar(pos, pos + 7 < n ? pos + 7 : n)
        se (fatia == "#define") {
            tokens++
        }
        pos += 7
    } senao {
        tokens++
        pos += 4
    }
}
assercao(tokens > 0)
escreva(tokens)
""",
    "stdlib_bytes_json": """
const modBytes: qualquer = importar("cgd:bytes")
const modJson: qualquer = importar("cgd:json")

var buf: qualquer = modBytes.Bytes.criar(50000)
para (var i: inteiro = 0; i < 50000; i++) {
    buf.definir(i, i & 255)
}
var somaBytes: inteiro = 0
para (var j: inteiro = 0; j < 50000; j++) {
    somaBytes += buf.obter(j)
}
var itens: qualquer[] = []
para (var k: inteiro = 0; k < 400; k++) {
    itens.empilhar({"id": k, "nome": "item_" + texto(k), "ativo": (k & 1) == 0})
}
const serializado: texto = modJson.JSON.serializar(itens)
const restaurado: qualquer = modJson.JSON.analisar(serializado)
assercao(somaBytes > 0 e tamanho(restaurado) == 400)
escreva(somaBytes + tamanho(restaurado))
""",
}


def run_timed(cmd, cwd=ROOT, env=None):
    t0 = time.perf_counter()
    proc = subprocess.run(
        cmd, cwd=cwd, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    elapsed_ms = (time.perf_counter() - t0) * 1000.0
    if proc.returncode != 0:
        raise RuntimeError(f"Command failed ({cmd}):\n{proc.stdout}\n{proc.stderr}")
    return elapsed_ms, proc


def analyze_c_file(c_path: Path) -> dict:
    text = c_path.read_text() if c_path.exists() else ""
    lines = len(text.splitlines()) if text else 0
    size_bytes = c_path.stat().st_size if c_path.exists() else 0
    return {
        "c_lines": lines,
        "c_bytes": size_bytes,
        "cgd_tmp_decl": text.count("delegua_value cgd_tmp_"),
        "volatile_decl": text.count("volatile delegua_value"),
        "delegua_is_truthy": text.count("delegua_is_truthy("),
        "delegua_assegurar": len(re.findall(r"\bdelegua_assegurar_[a-z_]+\(", text)),
        "delegua_chamar_direto": text.count("delegua_chamar_direto("),
        "delegua_chamar_membro": text.count("delegua_chamar_membro("),
        "delegua_chamar_ic": text.count("delegua_chamar_ic("),
        "delegua_prop_ic": text.count("delegua_prop_ic("),
        "delegua_def_ic": text.count("delegua_def_ic("),
        "delegua_instanciar": text.count("delegua_instanciar("),
        "functions_count": len(re.findall(r"^delegua_value cgd_user_[^(]+\(sz argc", text, re.M)),
    }


def parse_tempo(stderr_text: str) -> dict:
    phases = {}
    for line in stderr_text.splitlines():
        m = re.match(r"^\[([^\]]+)\]\s+(\d+)\s+us$", line.strip())
        if m:
            phases[m.group(1)] = round(int(m.group(2)) / 1000.0, 3)
    return phases


def parse_gc_stats(stderr_text: str) -> dict:
    collections = 0
    total_allocated = 0
    total_freed = 0
    max_heap_kib = 0
    complete_ms = 0.0
    for line in stderr_text.splitlines():
        m = re.search(r"collection #(\d+) after (\d+) allocated bytes", line)
        if m:
            collections = max(collections, int(m.group(1)))
            total_allocated += int(m.group(2))
        m = re.search(r"freed (\d+) bytes, heap (\d+) KiB", line)
        if m:
            total_freed += int(m.group(1))
            max_heap_kib = max(max_heap_kib, int(m.group(2)))
        m = re.search(r"Complete collection took (\d+) ms (\d+) ns", line)
        if m:
            complete_ms += int(m.group(1)) + int(m.group(2)) / 1_000_000.0
    return {
        "gc_collections": collections,
        "total_allocated_bytes": total_allocated,
        "total_freed_bytes": total_freed,
        "max_heap_kib": max_heap_kib,
        "complete_gc_ms": round(complete_ms, 3),
    }


def benchmark_dcc_version(
    version: str, dcc_dir: Path, cgd_bin: str, cc: str, tmp_path: Path
) -> dict | None:
    dcc_main = dcc_dir / "src" / "main.delegua"
    if not dcc_main.exists():
        return None
    dcc_out = tmp_path / f"dcc_{version}_{cc}"
    emit_ms, emit_proc = run_timed(
        [cgd_bin, "-o", "-t", "--emitir-c", str(dcc_main), "-s", str(dcc_out)]
    )
    dcc_c = Path(str(dcc_out) + ".c")
    c_metrics = analyze_c_file(dcc_c)
    tempo_phases = parse_tempo(emit_proc.stderr or emit_proc.stdout)
    build_ms, _ = run_timed([cgd_bin, "-o", f"--cc={cc}", str(dcc_main), "-s", str(dcc_out)])
    bin_bytes = dcc_out.stat().st_size

    hello_c = dcc_dir / "examples" / "hello_libc.c"
    hello_bin = tmp_path / f"hello_{version}_{cc}"
    # Warmup
    run_timed([str(dcc_out), str(hello_c), "-o", str(hello_bin)])
    dcc_runs = []
    for _ in range(5):
        ms, _ = run_timed([str(dcc_out), str(hello_c), "-o", str(hello_bin)])
        dcc_runs.append(ms)
    dcc_runs.sort()

    gc_env = dict(os.environ, GC_PRINT_STATS="1")
    _, gc_proc = run_timed([str(dcc_out), str(hello_c), "-o", str(hello_bin)], env=gc_env)
    gc_stats = parse_gc_stats(gc_proc.stderr)

    info = {
        "emit_c_ms": round(emit_ms, 2),
        "full_build_ms": round(build_ms, 2),
        "bin_bytes": bin_bytes,
        "compile_hello_libc_ms": round(dcc_runs[len(dcc_runs) // 2], 2),
        "compile_hello_libc_min_ms": round(dcc_runs[0], 2),
        "compile_hello_libc_max_ms": round(dcc_runs[-1], 2),
        "tempo_ms": tempo_phases,
        "gc": gc_stats,
        **c_metrics,
    }
    print(
        f"[dcc {version}] emit_c: {emit_ms:.1f} ms | build ({cc} -O2): {build_ms:.1f} ms | "
        f"C: {c_metrics['c_lines']} lines ({c_metrics['c_bytes']} B) | "
        f"tmp: {c_metrics['cgd_tmp_decl']} | direct: {c_metrics['delegua_chamar_direto']} | "
        f"hello_libc: {info['compile_hello_libc_ms']:.1f} ms "
        f"(min {info['compile_hello_libc_min_ms']:.1f} / max {info['compile_hello_libc_max_ms']:.1f})"
    )
    return info


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--output",
        "--json-out",
        dest="output",
        type=Path,
        default=ROOT / "out" / "bench_results.json",
    )
    parser.add_argument("--cc", type=str, default="gcc")
    args = parser.parse_args()

    results = {"compiler": args.cc, "microbenchmarks": {}, "dcc": {}, "dcc_versions": {}}
    cgd_bin = str(ROOT / "cgd")

    with tempfile.TemporaryDirectory(prefix="cgd_bench_") as tmp:
        tmp_path = Path(tmp)
        for name, code in MICROBENCHMARKS.items():
            src_file = tmp_path / f"{name}.delegua"
            out_bin = tmp_path / name
            src_file.write_text(code.strip() + "\n")

            compile_ms, _ = run_timed(
                [cgd_bin, "-o", f"--cc={args.cc}", str(src_file), "-s", str(out_bin)]
            )
            run_timed([cgd_bin, "-o", "--emitir-c", str(src_file), "-s", str(out_bin)])
            c_file = tmp_path / f"{name}.c"
            c_metrics = analyze_c_file(c_file)

            # Warmup + 5 runs for min/median/max
            run_timed([str(out_bin)])
            runs = []
            proc = None
            for _ in range(5):
                exec_ms, proc = run_timed([str(out_bin)])
                runs.append(exec_ms)
            runs.sort()
            median_ms = runs[len(runs) // 2]
            results["microbenchmarks"][name] = {
                "compile_ms": round(compile_ms, 2),
                "exec_ms": round(median_ms, 2),
                "min_ms": round(runs[0], 2),
                "max_ms": round(runs[-1], 2),
                **c_metrics,
                "output": proc.stdout.strip() if proc is not None else "",
            }
            print(
                f"[micro] {name:24s} | exec: {median_ms:8.2f} ms (min {runs[0]:6.2f} / max {runs[-1]:6.2f}) | "
                f"compile: {compile_ms:7.1f} ms | C: {c_metrics['c_lines']:5d} lines ({c_metrics['c_bytes']:7d} B)"
            )

        dcc_v010_dir = ROOT / "out" / "dcc_v010"
        if (dcc_v010_dir / "src" / "main.delegua").exists():
            v010_info = benchmark_dcc_version("0.1.0", dcc_v010_dir, cgd_bin, args.cc, tmp_path)
            if v010_info is not None:
                results["dcc"] = v010_info
                results["dcc_versions"]["0.1.0"] = v010_info

        dcc_v020_dir = ROOT / "out" / "dcc_v020"
        if not (dcc_v020_dir / "src" / "main.delegua").exists():
            fallback = Path("/home/fernandodev/dcc")
            if (fallback / "src" / "main.delegua").exists():
                dcc_v020_dir = fallback
        v020_info = benchmark_dcc_version("0.2.0", dcc_v020_dir, cgd_bin, args.cc, tmp_path)
        if v020_info is not None:
            if not results["dcc"]:
                results["dcc"] = v020_info
            results["dcc_versions"]["0.2.0"] = v020_info

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(results, indent=2, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()
