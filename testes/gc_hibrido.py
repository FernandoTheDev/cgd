#!/usr/bin/env python3
"""Suíte end-to-end de memória híbrida, CGD-GC, ANS, escape analysis e fuzzing diferencial."""

import json
import os
import random
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CGD = ROOT / "cgd"


def run_cmd(cmd, env=None, timeout=60):
    merged_env = os.environ.copy()
    if env:
        merged_env.update(env)
    return subprocess.run(
        cmd,
        cwd=str(ROOT),
        env=merged_env,
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def compile_and_run(src: str, extra_flags=None, run_env=None, tmpdir: Path = None):
    if tmpdir is None:
        with tempfile.TemporaryDirectory() as td:
            return compile_and_run(src, extra_flags, run_env, Path(td))
    tmpdir.mkdir(parents=True, exist_ok=True)
    src_path = tmpdir / "prog.delegua"
    bin_path = tmpdir / "prog_bin"
    src_path.write_text(src, encoding="utf-8")
    cmd = [str(CGD), str(src_path), "--saida", str(bin_path)]
    if extra_flags:
        cmd.extend(extra_flags)
    comp = run_cmd(cmd)
    assert comp.returncode == 0, f"Falha na compilação ({cmd}):\nSTDOUT:\n{comp.stdout}\nSTDERR:\n{comp.stderr}"
    exe = run_cmd([str(bin_path)], env=run_env)
    return comp, exe


def test_ans_and_semantic_edge_cases():
    src = """
funcao fib(n: inteiro): inteiro {
    se (n <= 1) {
        retorna n
    }
    retorna fib(n - 1) + fib(n - 2)
}

funcao soma_laco(limite: inteiro): inteiro {
    var acc: inteiro = 0
    para (var i: inteiro = 0; i < limite; i++) {
        se (i % 3 == 0) {
            continua
        }
        se (i > 40) {
            sustar
        }
        acc = acc + i
    }
    retorna acc
}

funcao media_real(a: real, b: real): real {
    retorna (a + b) / 2.0
}

funcao estouro(a: inteiro, b: inteiro): inteiro {
    retorna a + b
}

funcao div_zero(a: inteiro, b: inteiro): inteiro {
    retorna a \\ b
}

funcao shift_invalido(a: inteiro, b: inteiro): inteiro {
    retorna a << b
}

funcao rec_infinita(n: inteiro): inteiro {
    retorna rec_infinita(n + 1)
}

escreva(fib(15))
escreva(soma_laco(100))
escreva(media_real(3.5, 4.5))

tente {
    escreva(estouro(9223372036854775807, 1))
} pegue (err) {
    escreva("overflow-ok")
}

tente {
    escreva(div_zero(10, 0))
} pegue (err) {
    escreva("divzero-ok")
}

tente {
    escreva(shift_invalido(1, 64))
} pegue (err) {
    escreva("shift-ok")
}
"""
    rec_src = """
funcao rec_infinita(n: inteiro): inteiro {
    retorna rec_infinita(n + 1)
}
escreva(rec_infinita(0))
"""
    with tempfile.TemporaryDirectory() as td:
        td_path = Path(td)
        rep_path = td_path / "mem.json"
        comp_pad, exe_pad = compile_and_run(
            src,
            extra_flags=["--gc=cgd", "--opcoes-memoria=padrao", f"--relatorio-memoria-json={rep_path}"],
            run_env={"CGD_GC_PROFILE": "verify"},
            tmpdir=td_path / "pad",
        )
        assert exe_pad.returncode == 0, exe_pad.stderr
        report = json.loads(rep_path.read_text(encoding="utf-8"))
        assert report["funcoesANS"] >= 6, f"Esperava >=6 funções ANS, obteve {report}"
        assert report["chamadasANS"] >= 6, f"Esperava >=6 call sites ANS, obteve {report}"

        _, exe_none = compile_and_run(
            src,
            extra_flags=["--gc=cgd", "--opcoes-memoria=nenhuma"],
            tmpdir=td_path / "none",
        )
        assert exe_none.returncode == 0, exe_none.stderr
        assert exe_pad.stdout == exe_none.stdout, f"Divergência ANS:\n{exe_pad.stdout}\nvs\n{exe_none.stdout}"

        _, exe_boehm = compile_and_run(
            src,
            extra_flags=["--gc=boehm", "--opcoes-memoria=nenhuma"],
            tmpdir=td_path / "boehm",
        )
        assert exe_boehm.returncode == 0, exe_boehm.stderr
        assert exe_pad.stdout == exe_boehm.stdout
        expected = ["610", "547", "4", "overflow-ok", "divzero-ok", "shift-ok"]
        lines = [l.strip() for l in exe_pad.stdout.strip().splitlines()]
        assert lines == expected, f"Saída inesperada: {lines} != {expected}"

        # Verifica limite de recursão idêntico em ANS vs sem ANS
        _, rec_pad = compile_and_run(
            rec_src,
            extra_flags=["--gc=cgd", "--opcoes-memoria=padrao"],
            tmpdir=td_path / "rec_pad",
        )
        _, rec_none = compile_and_run(
            rec_src,
            extra_flags=["--gc=cgd", "--opcoes-memoria=nenhuma"],
            tmpdir=td_path / "rec_none",
        )
        assert rec_pad.returncode != 0 and rec_none.returncode != 0
        assert "Limite de recursão" in rec_pad.stderr and "Limite de recursão" in rec_none.stderr
    print("  [OK] test_ans_and_semantic_edge_cases")


def test_stack_alloc_det_free_fusion_devirt():
    src = """
classe Ponto {
    x: inteiro
    y: inteiro
    construtor(x: inteiro, y: inteiro) {
        isto.x = x
        isto.y = y
    }
    soma(): inteiro {
        retorna isto.x + isto.y
    }
}

funcao calcular_local(a: inteiro, b: inteiro): inteiro {
    var p: Ponto = Ponto(a, b)
    var s: inteiro = p.soma()
    var v = [1, 2, 3, 4, 5, 6]
    v.adicionar(s)
    var t = (a, b, s)
    var t2 = tupla([10, 20, 30])
    retorna v[6] + tamanho(v) + tamanho(t) + tamanho(t2)
}

funcao escapar_ponto(a: inteiro, b: inteiro): Ponto {
    var p: Ponto = Ponto(a, b)
    retorna p
}

funcao laco_det_free(n: inteiro): inteiro {
    var total: inteiro = 0
    para (var i: inteiro = 0; i < n; i++) {
        var buf = [i, i + 1, i + 2]
        se (i % 5 == 0) {
            continua
        }
        se (i == 17) {
            total = total + buf[2]
            sustar
        }
        total = total + buf[1]
    }
    retorna total
}

escreva(calcular_local(7, 8))
var pe: Ponto = escapar_ponto(10, 20)
escreva(pe.soma())
escreva(laco_det_free(50))
"""
    with tempfile.TemporaryDirectory() as td:
        td_path = Path(td)
        rep_path = td_path / "mem.json"
        _, exe_pad = compile_and_run(
            src,
            extra_flags=["--gc=cgd", "--opcoes-memoria=padrao", f"--relatorio-memoria-json={rep_path}"],
            run_env={"CGD_GC_PROFILE": "verify"},
            tmpdir=td_path / "pad",
        )
        assert exe_pad.returncode == 0, exe_pad.stderr
        rep = json.loads(rep_path.read_text(encoding="utf-8"))
        assert rep["objetosStack"] >= 1, f"Esperava objetosStack >= 1: {rep}"
        assert rep["liberacoesDeterministicas"] >= 2, f"Esperava liberacoesDeterministicas >= 2: {rep}"
        assert rep["tuplasFundidas"] >= 2, f"Esperava tuplasFundidas >= 2: {rep}"
        assert rep["vetoresPreDimensionados"] >= 1, f"Esperava vetoresPreDimensionados >= 1: {rep}"
        assert rep["chamadasDesvirtualizadas"] >= 2, f"Esperava chamadasDesvirtualizadas >= 2: {rep}"
        assert rep["fallbacksConservadores"] >= 1, f"Esperava fallback conservador para escape: {rep}"

        _, exe_boehm = compile_and_run(
            src,
            extra_flags=["--gc=boehm", "--opcoes-memoria=nenhuma"],
            tmpdir=td_path / "boehm",
        )
        assert exe_boehm.returncode == 0, exe_boehm.stderr
        assert exe_pad.stdout == exe_boehm.stdout
    print("  [OK] test_stack_alloc_det_free_fusion_devirt")


def test_memoria_telemetry_and_gc_stress():
    src = """
var mem = importar('cgd:memoria')

var lista = []
para (var i = 0; i < 4000; i++) {
    lista.adicionar({ "id": i, "txt": "item-" + texto(i) })
    se (tamanho(lista) > 200) {
        lista = []
    }
}
mem.Memoria.coletar(verdadeiro)
var st = mem.Memoria.estatisticas()
escreva(st["backendGC"])
escreva(st["ciclosGC"] >= 1)
escreva(st["heapBytes"] >= 0)
escreva(st["alocadosBytes"] > 0)
"""
    for profile in ("balanced", "verify", "stress"):
        with tempfile.TemporaryDirectory() as td:
            _, exe = compile_and_run(
                src,
                extra_flags=["--gc=cgd", "--opcoes-memoria=padrao"],
                run_env={"CGD_GC_PROFILE": profile},
                tmpdir=Path(td),
            )
            assert exe.returncode == 0, f"Falha no perfil {profile}: {exe.stderr}"
            lines = [l.strip() for l in exe.stdout.strip().splitlines()]
            assert lines == ["cgd-gc", "verdadeiro", "verdadeiro", "verdadeiro"], f"{profile}: {lines}"
    print("  [OK] test_memoria_telemetry_and_gc_stress (balanced/verify/stress)")


def generate_random_program(seed: int) -> str:
    rng = random.Random(seed)
    n_fns = rng.randint(2, 4)
    lines = [
        "classe Caixa {",
        "    v: inteiro",
        "    construtor(v: inteiro) { isto.v = v }",
        "    dobro(): inteiro { retorna isto.v * 2 }",
        "}",
    ]
    for f in range(n_fns):
        op = rng.choice(["+", "-", "*"])
        c1 = rng.randint(1, 7)
        c2 = rng.randint(2, 5)
        lines.append(f"funcao f{f}(a: inteiro, b: inteiro): inteiro {{")
        lines.append(f"    var r: inteiro = (a {op} b) + {c1}")
        lines.append(f"    para (var i: inteiro = 0; i < {c2}; i++) {{")
        lines.append("        se (i == 2) { continua }")
        lines.append("        r = r + i")
        lines.append("    }")
        lines.append("    retorna r")
        lines.append("}")

    lines.append("var acc: inteiro = 0")
    for k in range(6):
        fn_idx = rng.randrange(n_fns)
        a = rng.randint(-15, 25)
        b = rng.randint(-15, 25)
        lines.append(f"acc = acc + f{fn_idx}({a}, {b})")
        lines.append(f"var c{k}: Caixa = Caixa({a + k})")
        lines.append(f"acc = acc + c{k}.dobro()")
        arr_len = rng.randint(2, 7)
        elems = ", ".join(str(rng.randint(1, 20)) for _ in range(arr_len))
        lines.append(f"var v{k} = [{elems}]")
        lines.append(f"acc = acc + v{k}[0] + tamanho(v{k})")
        tup = ", ".join(str(rng.randint(1, 9)) for _ in range(rng.randint(2, 4)))
        lines.append(f"var t{k} = ({tup})")
        lines.append(f"acc = acc + tamanho(t{k})")
    lines.append("escreva(acc)")
    return "\n".join(lines) + "\n"


def test_differential_fuzzer():
    seeds = [101, 202, 303, 404, 505, 606, 707, 808, 909, 1010]
    with tempfile.TemporaryDirectory() as td:
        td_path = Path(td)
        for seed in seeds:
            src = generate_random_program(seed)
            _, r_cgd_opt = compile_and_run(
                src,
                extra_flags=["--gc=cgd", "--opcoes-memoria=padrao"],
                run_env={"CGD_GC_PROFILE": "verify"},
                tmpdir=td_path / f"s{seed}_cgd_opt",
            )
            _, r_cgd_none = compile_and_run(
                src,
                extra_flags=["--gc=cgd", "--opcoes-memoria=nenhuma"],
                tmpdir=td_path / f"s{seed}_cgd_none",
            )
            _, r_boehm = compile_and_run(
                src,
                extra_flags=["--gc=boehm", "--opcoes-memoria=nenhuma"],
                tmpdir=td_path / f"s{seed}_boehm",
            )
            assert r_cgd_opt.returncode == 0 and r_cgd_none.returncode == 0 and r_boehm.returncode == 0
            assert r_cgd_opt.stdout == r_cgd_none.stdout == r_boehm.stdout, (
                f"Divergência seed={seed}: {r_cgd_opt.stdout!r} vs {r_cgd_none.stdout!r} vs {r_boehm.stdout!r}"
            )
    print(f"  [OK] test_differential_fuzzer ({len(seeds)} programas aleatórios idênticos em CGD+opt / CGD / Boehm)")


def test_one_byte_heap_strings_and_intergenerational():
    """Regressão permanente para strings de 1 byte na heap e referências OLD -> YOUNG."""
    src = """
importar cgd.sistema.memoria como Mem

classe Coluna {
    nome: texto
    construtor(nome: texto) {
        isto.nome = nome
    }
}

classe Esquema {
    colunas: Coluna[]
    mapa: dicionario
    construtor() {
        isto.colunas = []
        isto.mapa = {}
    }
}

var esq = Esquema()
// Força promoção de `esq`, `colunas` e `mapa` para OLD
para (var w: inteiro = 0; w < 2000; w++) {
    var tmp: texto = "aquecimento_" + texto(w)
    se (tmp.tamanho() < 0) { escreva(tmp) }
}
Mem.Memoria.coletar(falso)

// Cria strings de 1 byte alocadas na heap via concatenação ("") + ch e armazena em containers OLD
var kStr: texto = "" + "k"
var vStr: texto = "" + "v"
esq.colunas.adicionar(Coluna(kStr))
esq.colunas.adicionar(Coluna(vStr))
esq.mapa[kStr] = "" + "x"
esq.mapa[vStr] = "" + "y"

// Pressão intensa forçando múltiplas coletas menores e maiores
para (var i: inteiro = 0; i < 15000; i++) {
    var lixo: texto = "pressao_" + texto(i) + "_utf8_çãõ"
    se (i % 3000 == 0) {
        Mem.Memoria.coletar(falso)
    }
}

se (esq.colunas[0].nome.minusculo() != "k") { falhar "k corrompido: " + esq.colunas[0].nome }
se (esq.colunas[1].nome.minusculo() != "v") { falhar "v corrompido: " + esq.colunas[1].nome }
se (texto(esq.mapa["k"]) != "x" ou texto(esq.mapa["v"]) != "y") { falhar "mapa corrompido" }
escreva("one_byte_old_young_ok")
"""
    for prof in ("verify", "low_mem", "stress"):
        _, exe = compile_and_run(
            src,
            extra_flags=["--gc=cgd"],
            run_env={"CGD_GC_PROFILE": prof},
        )
        assert exe.returncode == 0, f"Falha em profile={prof}: {exe.stderr}"
        assert "one_byte_old_young_ok" in exe.stdout, f"Saída inesperada em {prof}: {exe.stdout}"
    print("  [OK] test_one_byte_heap_strings_and_intergenerational (verify/low_mem/stress)")


def main():
    print("Executando suíte end-to-end de memória híbrida e CGD-GC...")
    test_ans_and_semantic_edge_cases()
    test_stack_alloc_det_free_fusion_devirt()
    test_memoria_telemetry_and_gc_stress()
    test_one_byte_heap_strings_and_intergenerational()
    test_differential_fuzzer()
    print("SUCESSO: Todas as verificações de memória híbrida e CGD-GC passaram!")


if __name__ == "__main__":
    main()
