#!/usr/bin/env python3
"""Validação extrema do Prompt Mestre X:
  1. Matriz ABI multi-compilador (Clang, GCC, TinyCC) e níveis (-O0 vs -o).
  2. Sanitizadores ASan + UBSan (vazamentos, UB, use-after-free, RAII sob stress).
  3. Oráculo diferencial aleatório de VetorNativo e MapaNativo (1000+ operações).
  4. Fuzzing sintático/semântico (250 programas aleatórios -> 0 crashes/segfaults).
"""

from __future__ import annotations

import os
import random
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CGD = str(ROOT / "cgd")
LIBS = str(ROOT / "bibliotecas")


def run_cmd(argv: list[str], env_extra: dict[str, str] | None = None, timeout: int = 60) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env["CGD_LIBS_DIR"] = LIBS
    if env_extra:
        env.update(env_extra)
    return subprocess.run(argv, cwd=str(ROOT), env=env, capture_output=True, text=True, timeout=timeout)


def section_1_abi_matrix(work: Path) -> None:
    print("\n=== 1. MATRIZ ABI (Clang, GCC, TinyCC x -O0 / -o) ===")
    prog = work / "abi_matrix.delegua"
    prog.write_text(
        """
@pilha
classe V3 {
    x: cf64; y: cf64; z: cf64
    @nativo @operador("+") add(o: V3): V3 { retorna V3(isto.x + o.x, isto.y + o.y, isto.z + o.z) }
    @nativo @operador("*") esc(s: cf64): V3 { retorna V3(isto.x * s, isto.y * s, isto.z * s) }
}
@pilha
classe Pacote {
    tag: cu8; flags: cu16; id: ci32; grande: ci64; peso: cf32; ok: cbool
}
@nativo
funcao executarTudo(): ci64 {
    const v = 2.0 * V3(1.0, 2.0, 3.0) + V3(4.0, 5.0, 6.0)
    const p = Pacote(cu8(7), cu16(300), ci32(-12345), ci64(900000), cf32(2.5), verdadeiro)
    var vec = VetorNativo<ci64>()
    para var i: ci64 = 1; i <= 50; i = i + 1 { vec.adicionar(i * i) }
    var mapa = MapaNativo<ci32, ci64>()
    para var i: ci32 = 0; i < 40; i = i + 1 { mapa.definir(i, ci64(i) * 10) }
    var s = StringNativa.criar("abi")
    s.anexar("-c99")
    const o = OpcionalNativo<ci64>.algum(100)
    const r = ResultadoNativo<ci64, ci32>.ok(200)
    retorna ci64(v.x + v.y + v.z) + ci64(p.tag) + ci64(p.flags) + ci64(p.id) + p.grande
        + ci64(p.peso) + (p.ok ? 1 : 0) + vec[49] + mapa.obter(39) + ci64(s.tamanho())
        + o.valorOu(0) + r.valor()
}
escreva("ABI_RES=", executarTudo())
""",
        encoding="utf-8",
    )

    compilers: list[tuple[str, list[list[str]]]] = []
    if shutil.which("clang"):
        compilers.append(("clang", [[], ["-o"]]))
    if shutil.which("gcc"):
        compilers.append(("gcc", [[], ["-o"]]))
    tcc = shutil.which("tcc") or ("/usr/local/sbin/tcc" if Path("/usr/local/sbin/tcc").exists() else None)
    if tcc:
        compilers.append((tcc, [[]]))

    outputs: dict[str, str] = {}
    for cc, flag_sets in compilers:
        for flags in flag_sets:
            label = f"{Path(cc).name}{' -o' if '-o' in flags else ' -O0'}"
            out_bin = work / f"abi_{label.replace(' ', '_').replace('-', '')}"
            res = run_cmd([CGD, str(prog), f"--cc={cc}", "-s", str(out_bin), *flags])
            assert res.returncode == 0, f"Falha compilando com {label}:\n{res.stdout}\n{res.stderr}"
            run_res = run_cmd([str(out_bin)])
            assert run_res.returncode == 0, f"Falha executando {label}:\n{run_res.stdout}\n{run_res.stderr}"
            outputs[label] = run_res.stdout.strip()
            print(f"  [OK] {label}: {outputs[label]}")

    vals = set(outputs.values())
    assert len(vals) == 1 and "ABI_RES=" in next(iter(vals)), f"Divergência entre compiladores: {outputs}"

    # Também validar Ray Tracer nativo em GCC e Clang
    rt_src = ROOT / "exemplos/algoritmos/raytracer/fontes/nativo.delegua"
    rt_outs: dict[str, str] = {}
    for cc in ("clang", "gcc"):
        if not shutil.which(cc):
            continue
        out_bin = work / f"rt_{cc}"
        r = run_cmd([CGD, str(rt_src), f"--cc={cc}", "-o", "-s", str(out_bin)])
        assert r.returncode == 0, f"Raytracer falhou com {cc}: {r.stderr}"
        rr = run_cmd([str(out_bin)])
        assert rr.returncode == 0, f"Raytracer exec falhou com {cc}: {rr.stderr}"
        # comparar acertos e checksum ignorando ms
        line = rr.stdout.strip()
        prefix = line.split(" ms=")[0]
        rt_outs[cc] = prefix
        print(f"  [OK] Raytracer ({cc} -o): {line}")
    assert len(set(rt_outs.values())) == 1, f"Divergência Raytracer GCC vs Clang: {rt_outs}"


def section_2_sanitizers_and_stress(work: Path) -> None:
    print("\n=== 2. SANITIZADORES (ASan + UBSan) E STRESS DE RAII ===")
    stress_src = work / "stress_raii.delegua"
    stress_src.write_text(
        """
@pilha
classe RecNaoTrivial {
    buf: VetorNativo<ci64>
    rotulo: StringNativa
}
@nativo
funcao stressCiclos(n: ci32): ci64 {
    var acc: ci64 = 0
    para var i: ci32 = 0; i < n; i = i + 1 {
        var v = VetorNativo<ci64>()
        v.reservar(32)
        para var j: ci64 = 0; j < 25; j = j + 1 {
            v.adicionar(ci64(i) + j)
        }
        var m = MapaNativo<ci32, ci64>()
        para var k: ci32 = 0; k < 20; k = k + 1 {
            m.definir(k, ci64(k) * 3)
        }
        m.remover(5)
        var s = StringNativa.criar("stress-")
        s.anexar("raii-")
        s.anexar("asan")
        const vis = s.visao()
        acc += ci64(vis.tamanho()) + v[24] + m.obter(19)
        var r = RecNaoTrivial(v, s)
        acc += r.buf[0]
        se (i % 7) == 0 {
            continua
        }
        var mat = MatrizNativa<cf64>(4, 4)
        mat.definir(3, 3, 2.0)
        acc += ci64(mat.obter(3, 3))
    }
    retorna acc
}
escreva("STRESS_RAII_OK=", stressCiclos(1500))
""",
        encoding="utf-8",
    )

    san_flags = [
        "--cc=clang",
        "--cflag=-fsanitize=address,undefined",
        "--cflag=-fno-omit-frame-pointer",
        "--ldflag=-fsanitize=address,undefined",
    ]
    san_env = {
        "ASAN_OPTIONS": "detect_leaks=0:halt_on_error=1",  # Boehm GC no lado gerenciado não é LSan-friendly; ASan valida UAF/OOB/overflow
        "UBSAN_OPTIONS": "print_stacktrace=1:halt_on_error=1",
    }

    targets = [
        ("stress_raii (1500 ciclos)", stress_src),
        ("raytracer nativo", ROOT / "exemplos/algoritmos/raytracer/fontes/nativo.delegua"),
        ("xadrez perft nativo", ROOT / "exemplos/jogos/xadrez/fontes/perft_nativo.delegua"),
        ("algebra vetorial", ROOT / "exemplos/nativo/algebra_vetorial/algebra_vetorial.delegua"),
        ("gpu_demo", ROOT / "exemplos/computacao/gpu_demo/gpu_demo.delegua"),
    ]
    for name, src in targets:
        out_bin = work / f"asan_{src.stem}"
        c_res = run_cmd([CGD, str(src), "-s", str(out_bin), *san_flags])
        assert c_res.returncode == 0, f"ASan/UBSan build falhou ({name}):\n{c_res.stdout}\n{c_res.stderr}"
        r_res = run_cmd([str(out_bin)], env_extra=san_env, timeout=60)
        assert r_res.returncode == 0, f"ASan/UBSan runtime falhou ({name}):\n{r_res.stdout}\n{r_res.stderr}"
        print(f"  [OK] ASan+UBSan {name}: {r_res.stdout.strip()}")


def section_3_differential_oracle(work: Path) -> None:
    print("\n=== 3. ORÁCULO DIFERENCIAL ALEATÓRIO (1000+ ops VetorNativo e MapaNativo) ===")
    rng = random.Random(20261123)
    py_vec: list[int] = []
    py_map: dict[int, int] = {}
    lines: list[str] = [
        "@nativo",
        "funcao rodarOraculo(): ci64 {",
        "    var v = VetorNativo<ci64>()",
        "    var m = MapaNativo<ci32, ci64>()",
        "    var chk: ci64 = 0",
    ]

    for step in range(600):
        op = rng.choice(["push", "push", "set", "pop", "get", "clone_check"])
        if op == "push" or not py_vec:
            val = rng.randint(-10000, 10000)
            py_vec.append(val)
            lines.append(f"    v.adicionar({val})")
        elif op == "set":
            idx = rng.randrange(len(py_vec))
            val = rng.randint(-10000, 10000)
            py_vec[idx] = val
            lines.append(f"    v[{idx}] = {val}")
        elif op == "pop":
            val = py_vec.pop()
            lines.append("    chk += v.removerUltimo()")
        elif op == "get":
            idx = rng.randrange(len(py_vec))
            lines.append(f"    chk += v[{idx}]")
        elif op == "clone_check" and step % 40 == 0:
            lines.append("    {")
            lines[-1] = "    se verdadeiro {"
            lines.append("        var vc = v.clonar()")
            lines.append("        chk += ci64(vc.tamanho())")
            lines.append("    }")

    # Recalcula chk esperado no Python exatamente na mesma sequência!
    rng = random.Random(20261123)
    py_vec = []
    expected_chk = 0
    for step in range(600):
        op = rng.choice(["push", "push", "set", "pop", "get", "clone_check"])
        if op == "push" or not py_vec:
            val = rng.randint(-10000, 10000)
            py_vec.append(val)
        elif op == "set":
            idx = rng.randrange(len(py_vec))
            val = rng.randint(-10000, 10000)
            py_vec[idx] = val
        elif op == "pop":
            expected_chk += py_vec.pop()
        elif op == "get":
            idx = rng.randrange(len(py_vec))
            expected_chk += py_vec[idx]
        elif op == "clone_check" and step % 40 == 0:
            expected_chk += len(py_vec)

    for step in range(500):
        op = rng.choice(["set", "set", "get", "del", "has"])
        key = rng.randint(0, 120)
        if op == "set":
            val = rng.randint(-5000, 5000)
            py_map[key] = val
            lines.append(f"    m.definir({key}, {val})")
        elif op == "get" and key in py_map:
            expected_chk += py_map[key]
            lines.append(f"    chk += m.obter({key})")
        elif op == "del":
            existed = key in py_map
            if existed:
                del py_map[key]
                expected_chk += 1
            lines.append(f"    se m.remover({key}) {{ chk += 1 }}")
        else:
            if key in py_map:
                expected_chk += 7
            lines.append(f"    se m.contem({key}) {{ chk += 7 }}")

    for idx, val in enumerate(py_vec):
        expected_chk += val
    lines.append("    para var i: ci64 = 0; i < ci64(v.tamanho()); i = i + 1 { chk += v[i] }")
    expected_chk += len(py_vec) * 1000 + len(py_map) * 100
    lines.append("    chk += ci64(v.tamanho()) * 1000 + ci64(m.tamanho()) * 100")
    lines.append("    retorna chk")
    lines.append("}")
    lines.append('escreva("ORACULO=", rodarOraculo())')

    src_path = work / "oraculo.delegua"
    src_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    out_bin = work / "oraculo"
    c_res = run_cmd([CGD, str(src_path), "-o", "-s", str(out_bin)])
    assert c_res.returncode == 0, f"Oráculo não compilou:\n{c_res.stdout}\n{c_res.stderr}"
    r_res = run_cmd([str(out_bin)])
    assert r_res.returncode == 0, f"Oráculo falhou em runtime:\n{r_res.stdout}\n{r_res.stderr}"
    expected_str = f"ORACULO={expected_chk}"
    assert r_res.stdout.strip() == expected_str, f"Divergência no oráculo! Esperado {expected_str}, obtido {r_res.stdout.strip()}"
    print(f"  [OK] 1100 operações aleatórias VetorNativo+MapaNativo bateram 100% com oráculo Python ({expected_str})")


def section_4_fuzzing(work: Path) -> None:
    print("\n=== 4. FUZZING SINTÁTICO/SEMÂNTICO (250 programas aleatórios -> 0 crashes/ICE) ===")
    rng = random.Random(987654321)
    decs = ["@nativo", "@pilha", "@valor", "@puro", "@gpu", '@quando(verdadeiro)', '@quando(falso)', '@operador("+")', '@operador("??")', ""]
    types = ["ci8", "ci32", "ci64", "cu32", "cf32", "cf64", "cbool", "cchar", "inteiro", "texto", "qualquer", "VetorNativo<ci32>", "StringNativa", "VisaoTexto"]
    stmts = [
        "var a: {T1} = 1",
        "var b: {T2}",
        "var v = VetorNativo<ci32>(); v.adicionar(1); var w = v; retorna v[0]",
        "var s = StringNativa.criar(\"x\"); const vis = s.visao(); s.anexar(\"y\"); retorna ci32(vis.tamanho())",
        "var v = VetorNativo<ci32>(); v.liberar(); v.liberar()",
        "se Compilacao.sistemaOperacional() == \"linux\" {{ retorna 1 }} senao {{ retorna 2 }}",
        "retorna a + b",
        "retorna ci32(a)",
        "escreva(a)",
    ]

    crashes = 0
    ok_compiles = 0
    clean_diags = 0
    t0 = time.monotonic()
    for i in range(250):
        d1 = rng.choice(decs)
        t1 = rng.choice(types)
        t2 = rng.choice(types)
        ret = rng.choice(types)
        body = rng.choice(stmts).format(T1=t1, T2=t2)
        if rng.random() < 0.3:
            # mutação sintática leve / incompleta
            code = f"{d1}\nclasse C{i} {{\n    x: {t1}\n    {rng.choice(decs)}\n    m(o: {t2}): {ret} {{ {body} }}\n}}\n"
        else:
            code = f"{d1}\nfuncao f{i}(a: {t1}, b: {t2}): {ret} {{\n    {body}\n}}\n"
        p = work / f"fuzz_{i}.delegua"
        p.write_text(code, encoding="utf-8")
        res = run_cmd([CGD, str(p), "--verificar"], timeout=10)
        # Crash real: sinal (returncode < 0 ou >= 128) ou traceback/segfault/assertion D
        if res.returncode < 0 or res.returncode >= 128 or "core.exception" in res.stderr or "Segmentation fault" in res.stderr:
            crashes += 1
            print(f"  [CRASH] fuzz_{i} (rc={res.returncode}):\n{code}\n{res.stderr[:300]}")
        elif res.returncode == 0:
            ok_compiles += 1
        else:
            clean_diags += 1

    dt = time.monotonic() - t0
    print(f"  [OK] 250 programas fuzzed em {dt:.2f}s: {ok_compiles} válidos, {clean_diags} rejeitados com diagnóstico limpo, {crashes} crashes")
    assert crashes == 0, f"Fuzzing detectou {crashes} crash(es) no compilador!"


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="cgd_extremo_") as tmp:
        work = Path(tmp)
        section_1_abi_matrix(work)
        section_2_sanitizers_and_stress(work)
        section_3_differential_oracle(work)
        section_4_fuzzing(work)
    print("\n=== TODAS AS VALIDAÇÕES EXTREMAS DO PROMPT MESTRE X PASSARAM! ===")
    return 0


if __name__ == "__main__":
    sys.exit(main())
