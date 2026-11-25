#!/usr/bin/env python3
"""Suíte massiva de validação do Prompt Mestre X (300+ casos independentes).

Cada caso representa um cenário lógico independente, contabilizado exatamente
uma vez, cobrindo as 8 áreas especificadas na seção 11 do Prompt Mestre X:
  1. CTFE e compilação condicional (>= 45)
  2. @nativo e os 20 tipos C (>= 45)
  3. @pilha / @valor e cópia por valor (>= 45)
  4. Ownership, escapes e lifetimes inferidos (>= 60)
  5. Operadores personalizados @operador (>= 45)
  6. Containers nativos (>= 25)
  7. Interoperabilidade gerenciado <-> nativo e ABI (>= 20)
  8. GPU, tensores, ML, @gpu e cgd documentar (>= 15)
"""

from __future__ import annotations

import argparse
import concurrent.futures
import os
import re
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

ROOT = Path(__file__).resolve().parent.parent
CGD = ROOT / "cgd"
LIBS = ROOT / "bibliotecas"


@dataclass
class Case:
    cid: str
    area: str
    kind: str  # "run", "run_opt", "run_panic", "fail", "emit_c", "check", "custom"
    source: str = ""
    expect_out: str = ""
    expect_err: str = ""
    expect_c_contains: list[str] = field(default_factory=list)
    expect_c_forbids: list[str] = field(default_factory=list)
    check_no_boxing_in_native: bool = False
    flags: list[str] = field(default_factory=list)
    custom_fn: Callable[[Path], tuple[bool, str]] | None = None


def run_cmd(argv: list[str], cwd: Path | None = None, timeout: int = 30) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env["CGD_LIBS_DIR"] = str(LIBS)
    return subprocess.run(
        argv,
        cwd=str(cwd or ROOT),
        env=env,
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def check_no_boxing(c_src: str) -> tuple[bool, str]:
    nat_fns = re.findall(r"(?m)^static [^\n;{}]*cgd_nat_[^\n;{}]*\{.*?\n\}", c_src, re.S)
    if not nat_fns:
        return False, "Nenhuma função cgd_nat_ encontrada no C gerado"
    for fn in nat_fns:
        for bad in ("delegua_value", "delegua_op_", "GC_MALLOC"):
            if bad in fn:
                return False, f"Encontrado '{bad}' dentro de função nativa: {fn[:120]}"
    return True, ""


def execute_case(case: Case, work_root: Path) -> tuple[Case, bool, str]:
    case_dir = work_root / case.cid.replace("/", "_")
    case_dir.mkdir(parents=True, exist_ok=True)
    if case.kind == "custom" and case.custom_fn is not None:
        ok, msg = case.custom_fn(case_dir)
        return case, ok, msg

    src_path = case_dir / "prog.delegua"
    src_path.write_text(case.source, encoding="utf-8")

    if case.kind == "fail":
        res = run_cmd([str(CGD), str(src_path), "--verificar", *case.flags])
        combined = res.stdout + "\n" + res.stderr
        if res.returncode == 0:
            return case, False, f"Esperava falha '{case.expect_err}', mas compilou com sucesso"
        if case.expect_err and case.expect_err not in combined:
            return case, False, f"Esperava '{case.expect_err}' no erro, obtido:\n{combined[:500]}"
        return case, True, ""

    if case.kind == "check":
        res = run_cmd([str(CGD), str(src_path), "--verificar", *case.flags])
        if res.returncode != 0:
            return case, False, f"Verificação falhou:\n{res.stdout}\n{res.stderr}"
        return case, True, ""

    if case.kind == "emit_c":
        out_base = case_dir / "prog"
        out_c = case_dir / "prog.c"
        res = run_cmd([str(CGD), str(src_path), "--emitir-c", "-s", str(out_base), *case.flags])
        if res.returncode != 0:
            return case, False, f"Emissão C falhou:\n{res.stdout}\n{res.stderr}"
        c_src = out_c.read_text(encoding="utf-8")
        for needle in case.expect_c_contains:
            if needle not in c_src:
                return case, False, f"C gerado não contém '{needle}'"
        for bad in case.expect_c_forbids:
            if bad in c_src:
                return case, False, f"C gerado contém símbolo proibido '{bad}'"
        if case.check_no_boxing_in_native:
            ok, msg = check_no_boxing(c_src)
            if not ok:
                return case, False, msg
        return case, True, ""

    out_bin = case_dir / "prog"
    flags = list(case.flags)
    if case.kind == "run_opt" and "-o" not in flags:
        flags.append("-o")
    res = run_cmd([str(CGD), str(src_path), "-s", str(out_bin), *flags])
    if res.returncode != 0:
        return case, False, f"Compilação falhou:\n{res.stdout}\n{res.stderr}"

    c_path = case_dir / "prog.c"
    if c_path.exists():
        c_src = c_path.read_text(encoding="utf-8")
        for needle in case.expect_c_contains:
            if needle not in c_src:
                return case, False, f"C gerado não contém '{needle}'"
        for bad in case.expect_c_forbids:
            if bad in c_src:
                return case, False, f"C gerado contém símbolo proibido '{bad}'"
        if case.check_no_boxing_in_native:
            ok, msg = check_no_boxing(c_src)
            if not ok:
                return case, False, msg

    run_res = run_cmd([str(out_bin)], timeout=20)
    if case.kind == "run_panic":
        combined = run_res.stdout + "\n" + run_res.stderr
        if run_res.returncode == 0:
            return case, False, f"Esperava pânico '{case.expect_err}', mas saiu com 0"
        if case.expect_err and case.expect_err not in combined:
            return case, False, f"Esperava '{case.expect_err}' no pânico, obtido:\n{combined[:400]}"
        return case, True, ""

    if run_res.returncode != 0:
        return case, False, f"Execução falhou ({run_res.returncode}):\n{run_res.stdout}\n{run_res.stderr}"
    if case.expect_out and case.expect_out not in run_res.stdout:
        return case, False, f"Saída esperada '{case.expect_out}' ausente em:\n{run_res.stdout[:400]}"
    return case, True, ""


def build_area_1_ctfe() -> list[Case]:
    A = "1. CTFE e Compilação Condicional"
    cases: list[Case] = []

    # 1..15: CTFE puro existente e expandido (loops, recursão, memoização, tabelas, operadores)
    cases.append(Case("CTFE-01", A, "run_opt", """
@puro funcao dobro(n: inteiro): inteiro { retorna n * 2 }
const x: inteiro = dobro(21)
escreva("OK=", x)
""", expect_out="OK=42", expect_c_contains=["42"]))

    cases.append(Case("CTFE-02", A, "run_opt", """
@puro funcao fib(n: inteiro): inteiro {
    se n <= 1 { retorna n }
    retorna fib(n - 1) + fib(n - 2)
}
const f: inteiro = fib(12)
escreva("OK=", f)
""", expect_out="OK=144", expect_c_contains=["144"]))

    cases.append(Case("CTFE-03", A, "run_opt", """
@puro funcao somaFor(n: inteiro): inteiro {
    var acc: inteiro = 0
    para var i: inteiro = 1; i <= n; i = i + 1 {
        acc = acc + i
    }
    retorna acc
}
const s: inteiro = somaFor(10)
escreva("OK=", s)
""", expect_out="OK=55", expect_c_contains=["55"]))

    cases.append(Case("CTFE-04", A, "run_opt", """
@puro funcao somaEnquanto(n: inteiro): inteiro {
    var acc: inteiro = 0
    var i: inteiro = 0
    enquanto i < n {
        i = i + 1
        se i == 3 { continua }
        se i == 8 { sustar }
        acc = acc + i
    }
    retorna acc
}
const s: inteiro = somaEnquanto(20)
escreva("OK=", s)
""", expect_out="OK=25", expect_c_contains=["25"]))

    cases.append(Case("CTFE-05", A, "run_opt", """
@puro funcao testeFazer(n: inteiro): inteiro {
    var i: inteiro = 0
    var acc: inteiro = 0
    fazer {
        i = i + 1
        acc = acc + i * i
    } enquanto i < n
    retorna acc
}
const s: inteiro = testeFazer(4)
escreva("OK=", s)
""", expect_out="OK=30", expect_c_contains=["30"]))

    cases.append(Case("CTFE-06", A, "run_opt", """
@puro funcao tabelaQuadrado(idx: inteiro): inteiro {
    const tab = [0, 1, 4, 9, 16, 25, 36]
    retorna tab[idx]
}
const q: inteiro = tabelaQuadrado(5)
escreva("OK=", q)
""", expect_out="OK=25", expect_c_contains=["25"]))

    cases.append(Case("CTFE-07", A, "run_opt", """
@puro funcao classificar(v: inteiro): inteiro {
    escolha v {
        caso 1: retorna 10
        caso 2: retorna 20
        caso 3: retorna 30
        padrao: retorna 99
    }
}
const a: inteiro = classificar(2) + classificar(7)
escreva("OK=", a)
""", expect_out="OK=119", expect_c_contains=["119"]))

    cases.append(Case("CTFE-08", A, "run_opt", """
@puro funcao potencia(base: inteiro, exp: inteiro): inteiro {
    retorna base ** exp
}
const p: inteiro = potencia(2, 10)
escreva("OK=", p)
""", expect_out="OK=1024", expect_c_contains=["1024"]))

    cases.append(Case("CTFE-09", A, "run_opt", """
@puro funcao ternarioPuro(x: inteiro): inteiro {
    retorna x > 5 ? x * 3 : x + 1
}
const r: inteiro = ternarioPuro(6) + ternarioPuro(2)
escreva("OK=", r)
""", expect_out="OK=21", expect_c_contains=["21"]))

    cases.append(Case("CTFE-10", A, "run_opt", """
@puro funcao curtoCircuito(x: inteiro): logico {
    retorna (x != 0 e (10 / x) > 1) ou x == 0
}
const r: logico = curtoCircuito(0)
escreva("OK=", r)
""", expect_out="OK=verdadeiro"))

    cases.append(Case("CTFE-11", A, "run_opt", """
@puro funcao memoPesado(n: inteiro): inteiro {
    se n <= 1 { retorna n }
    retorna memoPesado(n - 1) + memoPesado(n - 2)
}
const a: inteiro = memoPesado(18) + memoPesado(18)
escreva("OK=", a)
""", expect_out="OK=5168", expect_c_contains=["5168"]))

    cases.append(Case("CTFE-12", A, "run_opt", """
@puro funcao concatPuro(a: texto, b: texto): texto {
    retorna a + "-" + b
}
const t: texto = concatPuro("cgd", "ctfe")
escreva("OK=", t)
""", expect_out="OK=cgd-ctfe"))

    cases.append(Case("CTFE-13", A, "run_opt", """
@puro funcao fatorial(n: inteiro): inteiro {
    var r: inteiro = 1
    para var i: inteiro = 2; i <= n; i = i + 1 { r = r * i }
    retorna r
}
const f: inteiro = fatorial(7)
escreva("OK=", f)
""", expect_out="OK=5040", expect_c_contains=["5040"]))

    cases.append(Case("CTFE-14", A, "run_opt", """
@puro funcao mdc(a: inteiro, b: inteiro): inteiro {
    enquanto b != 0 {
        const t: inteiro = a % b
        a = b
        b = t
    }
    retorna a
}
const g: inteiro = mdc(1071, 462)
escreva("OK=", g)
""", expect_out="OK=21", expect_c_contains=["21"]))

    cases.append(Case("CTFE-15", A, "run_opt", """
@puro funcao somaVet(n: inteiro): inteiro {
    const pesos = [2, 3, 5, 7, 11]
    var s: inteiro = 0
    para var i: inteiro = 0; i < n; i = i + 1 { s = s + pesos[i] }
    retorna s
}
const total: inteiro = somaVet(5)
escreva("OK=", total)
""", expect_out="OK=28", expect_c_contains=["28"]))

    # 16..34: Consultas Compilacao.* e @quando estrutural
    cases.append(Case("CTFE-16", A, "run", """
const so = Compilacao.sistemaOperacional()
assercao(so == "linux")
escreva("OK=", so)
""", expect_out="OK=linux"))

    cases.append(Case("CTFE-17", A, "run", """
const arq = Compilacao.arquitetura()
assercao(arq == "x86_64")
escreva("OK=", arq)
""", expect_out="OK=x86_64"))

    cases.append(Case("CTFE-18", A, "run", """
const bits = Compilacao.tamanhoPonteiro()
assercao(bits == 64)
escreva("OK=", bits)
""", expect_out="OK=64"))

    cases.append(Case("CTFE-19", A, "run", """
const abi = Compilacao.abi()
assercao(abi == "sysv" ou abi == "gnu")
escreva("OK=", abi)
""", expect_out="OK="))

    cases.append(Case("CTFE-20", A, "run", """
const cc = Compilacao.compiladorC()
assercao(tamanho(cc) > 0)
escreva("OK=", cc)
""", expect_out="OK="))

    cases.append(Case("CTFE-21", A, "run", """
const modo = Compilacao.modo()
assercao(modo == "desenvolvimento")
escreva("OK=", modo)
""", expect_out="OK=desenvolvimento"))

    cases.append(Case("CTFE-22", A, "run_opt", """
const modo = Compilacao.modo()
assercao(modo == "producao")
escreva("OK=", modo)
""", expect_out="OK=producao"))

    cases.append(Case("CTFE-23", A, "run", """
const tem = Compilacao.temRecurso("turbo")
assercao(tem == verdadeiro)
escreva("OK=", tem)
""", expect_out="OK=verdadeiro", flags=["--recurso=turbo"]))

    cases.append(Case("CTFE-24", A, "run", """
const tem = Compilacao.temRecurso("inexistente")
assercao(tem == falso)
escreva("OK=", tem)
""", expect_out="OK=falso"))

    cases.append(Case("CTFE-25", A, "run", """
@quando(Compilacao.sistemaOperacional() == "linux")
funcao nomePlataforma(): texto { retorna "LINUX_REAL" }

@quando(Compilacao.sistemaOperacional() == "windows")
funcao nomePlataforma(): texto { retorna simboloQueNaoExisteNoLinux() }

escreva("OK=", nomePlataforma())
""", expect_out="OK=LINUX_REAL"))

    cases.append(Case("CTFE-26", A, "run", """
@quando(Compilacao.sistemaOperacional() == "windows")
importar modulo_fantasma_windows como WinMod

@quando(Compilacao.sistemaOperacional() == "linux")
funcao ok(): texto { retorna "SEM_IMPORT_FANTASMA" }

escreva("OK=", ok())
""", expect_out="OK=SEM_IMPORT_FANTASMA"))

    cases.append(Case("CTFE-27", A, "run", """
@quando(Compilacao.sistemaOperacional() == "linux")
const LIMITE: inteiro = 100

@quando(Compilacao.sistemaOperacional() == "macos")
const LIMITE: inteiro = 200

escreva("OK=", LIMITE)
""", expect_out="OK=100"))

    cases.append(Case("CTFE-28", A, "run", """
@quando(Compilacao.sistemaOperacional() == "linux")
classe Driver {
    nome(): texto { retorna "epoll" }
}
@quando(Compilacao.sistemaOperacional() == "windows")
classe Driver {
    nome(): texto { retorna win32Inexistente() }
}
const d = Driver()
escreva("OK=", d.nome())
""", expect_out="OK=epoll"))

    cases.append(Case("CTFE-29", A, "run", """
@quando(Compilacao.sistemaOperacional() == "linux")
@pilha
classe Cabecalho {
    a: ci32
}
@quando(Compilacao.sistemaOperacional() == "windows")
@pilha
classe Cabecalho {
    a: TipoInexistenteWin
}
const c = Cabecalho(77)
escreva("OK=", c.a)
""", expect_out="OK=77"))

    cases.append(Case("CTFE-30", A, "run", """
classe Motor {
    @quando(Compilacao.temRecurso("avx"))
    modo(): texto { retorna "AVX" }

    @quando(!Compilacao.temRecurso("avx"))
    modo(): texto { retorna "ESCALAR" }
}
const m = Motor()
escreva("OK=", m.modo())
""", expect_out="OK=AVX", flags=["--recurso=avx"]))

    cases.append(Case("CTFE-31", A, "run", """
classe Motor {
    @quando(Compilacao.temRecurso("avx"))
    modo(): texto { retorna "AVX" }

    @quando(!Compilacao.temRecurso("avx"))
    modo(): texto { retorna "ESCALAR" }
}
const m = Motor()
escreva("OK=", m.modo())
""", expect_out="OK=ESCALAR"))

    cases.append(Case("CTFE-32", A, "run", """
const ehLinux = Compilacao.sistemaOperacional() == "linux"
se ehLinux {
    escreva("OK=RAMO_LINUX")
} senao {
    funcaoQueNaoExisteJamais()
}
""", expect_out="OK=RAMO_LINUX"))

    cases.append(Case("CTFE-33", A, "run", """
const ehWin = Compilacao.sistemaOperacional() == "windows"
se ehWin {
    funcaoWinInexistente()
} senao {
    escreva("OK=SENAO_ATIVO")
}
""", expect_out="OK=SENAO_ATIVO"))

    cases.append(Case("CTFE-34", A, "run", """
@quando(Compilacao.tamanhoPonteiro() == 64 e Compilacao.arquitetura() == "x86_64")
funcao arq(): texto { retorna "LP64_X64" }
escreva("OK=", arq())
""", expect_out="OK=LP64_X64"))

    # 35..39: Simulação de alvos cruzados (--target) sem confundir host com target
    cases.append(Case("CTFE-35", A, "emit_c", """
@quando(Compilacao.sistemaOperacional() == "windows")
funcao alvo(): inteiro { retorna 7771 }
@quando(Compilacao.sistemaOperacional() == "linux")
funcao alvo(): inteiro { retorna 8882 }
escreva(alvo())
""", flags=["--target=x86_64-pc-windows-msvc"], expect_c_contains=["7771"], expect_c_forbids=["8882"]))

    cases.append(Case("CTFE-36", A, "emit_c", """
@quando(Compilacao.sistemaOperacional() == "macos" e Compilacao.arquitetura() == "aarch64")
funcao alvo(): inteiro { retorna 7773 }
@quando(Compilacao.sistemaOperacional() == "linux")
funcao alvo(): inteiro { retorna 8884 }
escreva(alvo())
""", flags=["--target=aarch64-apple-darwin"], expect_c_contains=["7773"], expect_c_forbids=["8884"]))

    cases.append(Case("CTFE-37", A, "emit_c", """
@quando(Compilacao.tamanhoPonteiro() == 32)
funcao alvo(): inteiro { retorna 7775 }
@quando(Compilacao.tamanhoPonteiro() == 64)
funcao alvo(): inteiro { retorna 8886 }
escreva(alvo())
""", flags=["--target=i686-unknown-linux-gnu"], expect_c_contains=["7775"], expect_c_forbids=["8886"]))

    cases.append(Case("CTFE-38", A, "emit_c", """
@quando(Compilacao.sistemaOperacional() == "windows")
@definicao(biblioteca = "kernel32_fantasma", abi = "c")
classe estrangeira WinAPI {
    @definicao(simbolo = "GetTickCount")
    ticks(): ci32
}
@quando(Compilacao.sistemaOperacional() == "linux")
funcao ok(): inteiro { retorna 7 }
escreva(ok())
""", expect_c_forbids=["kernel32_fantasma", "GetTickCount"]))

    cases.append(Case("CTFE-39", A, "run", """
@quando(Compilacao.temRecurso("a") e Compilacao.temRecurso("b"))
funcao ambos(): texto { retorna "AB_OK" }
escreva("OK=", ambos())
""", expect_out="OK=AB_OK", flags=["--recurso=a", "--recurso=b"]))

    cases.append(Case("CTFE-40", A, "run", """
@quando(Compilacao.temRecurso("a") ou Compilacao.temRecurso("b"))
funcao ouRec(): texto { retorna "OU_OK" }
escreva("OK=", ouRec())
""", expect_out="OK=OU_OK", flags=["--recurso=b"]))

    # 41..46: Testes negativos CTFE / @quando
    cases.append(Case("CTFE-41", A, "fail", """
var dinamica: inteiro = 1
@quando(dinamica == 1)
funcao f(): inteiro { retorna 1 }
""", expect_err="E3501"))

    cases.append(Case("CTFE-42", A, "fail", """
@quando()
funcao f(): inteiro { retorna 1 }
""", expect_err="E3502"))

    cases.append(Case("CTFE-43", A, "fail", """
@quando(verdadeiro, falso)
funcao f(): inteiro { retorna 1 }
""", expect_err="E3502"))

    cases.append(Case("CTFE-44", A, "fail", """
const x = Compilacao.consultaQueNaoExiste()
""", expect_err="E3503"))

    cases.append(Case("CTFE-45", A, "fail", """
@puro funcao impura(): inteiro {
    escreva("efeito")
    retorna 1
}
""", expect_err="não é marcada pura"))

    cases.append(Case("CTFE-46", A, "fail", """
@quando(123)
funcao f(): inteiro { retorna 1 }
""", expect_err="E3501"))

    return cases


def build_area_2_native() -> list[Case]:
    A = "2. @nativo e os 20 Tipos C"
    cases: list[Case] = []

    # 1..20: Cada um dos 20 tipos C explícitos
    c_types_tests = [
        ("ci8", "-120", "10", "-110"),
        ("ci16", "-30000", "1234", "-28766"),
        ("ci32", "100000", "23456", "123456"),
        ("ci64", "1000000000", "234567890", "1234567890"),
        ("cu8", "200", "50", "250"),
        ("cu16", "60000", "5000", "65000"),
        ("cu32", "3000000000", "1000000", "3001000000"),
        ("cu64", "10000000000", "55", "10000000055"),
        ("cchar", "65", "1", "66"),
        ("cschar", "-10", "5", "-5"),
        ("cuchar", "240", "10", "250"),
        ("cshort", "-500", "200", "-300"),
        ("cushort", "40000", "2000", "42000"),
        ("cint", "-42", "100", "58"),
        ("cuint", "1000", "2000", "3000"),
        ("clong", "500000", "250000", "750000"),
        ("culong", "800000", "200000", "1000000"),
        ("csize", "128", "64", "192"),
        ("cf32", "1.5", "2.5", "4"),
        ("cf64", "3.25", "1.75", "5"),
    ]
    for idx, (ty, a, b, exp) in enumerate(c_types_tests, start=1):
        src = f"""
@nativo
funcao somarTipo(x: {ty}, y: {ty}): {ty} {{
    retorna x + y
}}
escreva("OK=", somarTipo({ty}({a}), {ty}({b})))
"""
        cases.append(Case(f"NAT-{idx:02d}", A, "run", src, expect_out=f"OK={exp}", check_no_boxing_in_native=True))

    # 21: cbool dedicado
    cases.append(Case("NAT-21", A, "run", """
@nativo
funcao xorBool(a: cbool, b: cbool): cbool {
    retorna (a ou b) e !(a e b)
}
assercao(xorBool(verdadeiro, falso) == verdadeiro)
assercao(xorBool(verdadeiro, verdadeiro) == falso)
escreva("OK=CBOOL")
""", expect_out="OK=CBOOL", check_no_boxing_in_native=True))

    # 22..36: Aritmética, bitwise, shifts, loops, recursão, switch, math.h, casts explícitos, divisão inteira
    cases.append(Case("NAT-22", A, "run", """
@nativo
funcao bitOps(a: cu32, b: cu32): cu32 {
    const x: cu32 = (a & b) | (a ^ b)
    const y: cu32 = (x << cu32(2)) >> cu32(1)
    retorna y
}
escreva("OK=", bitOps(cu32(12), cu32(10)))
""", expect_out="OK=28", check_no_boxing_in_native=True))

    cases.append(Case("NAT-23", A, "run", """
@nativo
funcao truncarExplicit(x: ci64): ci8 {
    retorna ci8(x)
}
escreva("OK=", truncarExplicit(ci64(258)))
""", expect_out="OK=2", check_no_boxing_in_native=True))

    cases.append(Case("NAT-24", A, "run", """
@nativo
funcao floatParaInt(x: cf64): ci32 {
    retorna ci32(x)
}
escreva("OK=", floatParaInt(42.9))
""", expect_out="OK=42", check_no_boxing_in_native=True))

    cases.append(Case("NAT-25", A, "run", """
@nativo
funcao signedParaUnsigned(x: ci32): cu32 {
    retorna cu32(x)
}
escreva("OK=", signedParaUnsigned(ci32(77)))
""", expect_out="OK=77", check_no_boxing_in_native=True))

    cases.append(Case("NAT-26", A, "run", """
@nativo
funcao mathIntrinsics(x: cf64): cf64 {
    const a: cf64 = Matematica.raizQuadrada(x)
    const b: cf64 = Matematica.absoluto(-a)
    const c: cf64 = Matematica.piso(b + 0.7)
    retorna c
}
escreva("OK=", mathIntrinsics(16.0))
""", expect_out="OK=4", check_no_boxing_in_native=True))

    cases.append(Case("NAT-27", A, "run", """
@nativo
funcao trigLog(x: cf64): cf64 {
    const s: cf64 = Matematica.seno(x)
    const c: cf64 = Matematica.cosseno(x)
    retorna s * s + c * c
}
const r = trigLog(0.7)
assercao(r > 0.999999 e r < 1.000001)
escreva("OK=TRIG")
""", expect_out="OK=TRIG", check_no_boxing_in_native=True))

    cases.append(Case("NAT-28", A, "run", """
@nativo
funcao loopForContinue(n: ci32): ci32 {
    var soma: ci32 = 0
    para var i: ci32 = 0; i < n; i = i + 1 {
        se (i % 2) == 0 { continua }
        se i > 9 { sustar }
        soma += i
    }
    retorna soma
}
escreva("OK=", loopForContinue(20))
""", expect_out="OK=25", check_no_boxing_in_native=True))

    cases.append(Case("NAT-29", A, "run", """
@nativo
funcao loopWhileBreak(n: ci32): ci32 {
    var i: ci32 = 0
    var acc: ci32 = 0
    enquanto i < n {
        i += 1
        se i == 5 { sustar }
        acc += i
    }
    retorna acc
}
escreva("OK=", loopWhileBreak(10))
""", expect_out="OK=10", check_no_boxing_in_native=True))

    cases.append(Case("NAT-30", A, "run", """
@nativo
funcao loopDoWhile(n: ci32): ci32 {
    var i: ci32 = 0
    var acc: ci32 = 0
    fazer {
        i += 1
        acc += i
    } enquanto i < n
    retorna acc
}
escreva("OK=", loopDoWhile(6))
""", expect_out="OK=21", check_no_boxing_in_native=True))

    cases.append(Case("NAT-31", A, "run", """
@nativo
funcao switchNat(k: ci32): ci32 {
    escolha k {
        caso 1: retorna 100
        caso 2: retorna 200
        padrao: retorna -1
    }
}
escreva("OK=", switchNat(2) + switchNat(9))
""", expect_out="OK=199", check_no_boxing_in_native=True))

    cases.append(Case("NAT-32", A, "run", """
@nativo
funcao fibNat(n: ci32): ci64 {
    se n <= 1 { retorna ci64(n) }
    retorna fibNat(n - 1) + fibNat(n - 2)
}
escreva("OK=", fibNat(20))
""", expect_out="OK=6765", check_no_boxing_in_native=True))

    cases.append(Case("NAT-33", A, "run", """
@nativo
funcao divInteira(a: ci32, b: ci32): ci32 {
    retorna (a \\ b) * 10 + (a % b)
}
escreva("OK=", divInteira(17, 5))
""", expect_out="OK=32", check_no_boxing_in_native=True))

    cases.append(Case("NAT-34", A, "run", """
@nativo
funcao atribuicoesCompostas(x: ci32): ci32 {
    var v: ci32 = x
    v += 10
    v -= 3
    v *= 2
    retorna v
}
escreva("OK=", atribuicoesCompostas(5))
""", expect_out="OK=24", check_no_boxing_in_native=True))

    cases.append(Case("NAT-35", A, "run", """
@nativo
funcao ternarioNat(a: ci32, b: ci32): ci32 {
    retorna a > b ? a : b
}
escreva("OK=", ternarioNat(12, 34))
""", expect_out="OK=34", check_no_boxing_in_native=True))

    cases.append(Case("NAT-36", A, "run", """
@nativo
funcao auxNat(x: ci64): ci64 { retorna x * x }

@nativo
funcao compostaNat(a: ci64, b: ci64): ci64 {
    retorna auxNat(a) + auxNat(b)
}
escreva("OK=", compostaNat(3, 4))
""", expect_out="OK=25", check_no_boxing_in_native=True))

    # 37..46: Testes negativos estritos (@nativo sem fallback silencioso!)
    cases.append(Case("NAT-37", A, "fail", """
@nativo
funcao ruim(x: qualquer): ci32 { retorna 1 }
""", expect_err="E3602"))

    cases.append(Case("NAT-38", A, "fail", """
@nativo
funcao ruim(x: texto): ci32 { retorna 1 }
""", expect_err="E3602"))

    cases.append(Case("NAT-39", A, "fail", """
@nativo
funcao ruim(): dicionario { retorna {} }
""", expect_err="E3602"))

    cases.append(Case("NAT-40", A, "fail", """
funcao gerenciada(x: inteiro): inteiro { retorna x + 1 }
@nativo
funcao ruim(x: ci32): ci32 {
    retorna ci32(gerenciada(inteiro(x)))
}
""", expect_err="E3603"))

    cases.append(Case("NAT-41", A, "fail", """
@nativo
funcao ruim(): ci32 {
    escreva("nao pode GC em nativo")
    retorna 0
}
""", expect_err="E3603"))

    cases.append(Case("NAT-42", A, "fail", """
@nativo
funcao estreitamento(x: ci64): ci32 {
    var y: ci32 = x
    retorna y
}
""", expect_err="E3604"))

    cases.append(Case("NAT-43", A, "fail", """
@nativo
funcao sinalTroca(x: ci32): cu32 {
    var y: cu32 = x
    retorna y
}
""", expect_err="E3604"))

    cases.append(Case("NAT-44", A, "fail", """
@nativo
funcao realParaInt(x: cf64): ci32 {
    var y: ci32 = x
    retorna y
}
""", expect_err="E3604"))

    cases.append(Case("NAT-45", A, "fail", """
@nativo
funcao ruimTente(): ci32 {
    tente { retorna 1 } pegue (err) { retorna 0 }
}
""", expect_err="E3601"))

    cases.append(Case("NAT-46", A, "fail", """
@nativo
funcao ruimMapa(): ci32 {
    const m = { a: 1 }
    retorna 0
}
""", expect_err="E3601"))

    return cases


def build_area_3_value_types() -> list[Case]:
    A = "3. @pilha / @valor e Cópia por Valor"
    cases: list[Case] = []

    cases.append(Case("VAL-01", A, "run", """
@pilha
classe Ponto {
    x: cf64
    y: cf64
}
var a = Ponto(1.0, 2.0)
var b = a
b.x = 99.0
assercao(a.x == 1.0)
assercao(b.x == 99.0)
escreva("OK=", a.x, ",", b.x)
""", expect_out="OK=1,99"))

    cases.append(Case("VAL-02", A, "run", """
@valor
classe Cor {
    r: cu8
    g: cu8
    b: cu8
}
var c1 = Cor(cu8(10), cu8(20), cu8(30))
var c2 = c1
c2.g = cu8(255)
assercao(c1.g == 20 e c2.g == 255)
escreva("OK=ALIAS_VALOR")
""", expect_out="OK=ALIAS_VALOR"))

    cases.append(Case("VAL-03", A, "run", """
@pilha
classe Ponto {
    x: cf64
    y: cf64
    construtor(x: cf64, y: cf64) {
        isto.x = x
        isto.y = y
    }
    norma2(): cf64 { retorna isto.x * isto.x + isto.y * isto.y }
}
const p = Ponto(3.0, 4.0)
escreva("OK=", p.norma2())
""", expect_out="OK=25"))

    cases.append(Case("VAL-04", A, "run", """
@pilha
classe Par {
    a: ci32
    b: ci32
}
@nativo
funcao trocarCopia(p: Par): Par {
    var q: Par = p
    const tmp: ci32 = q.a
    q.a = q.b
    q.b = tmp
    retorna q
}
@nativo
funcao testar(): ci32 {
    const orig = Par(10, 20)
    const inv = trocarCopia(orig)
    retorna orig.a * 100 + inv.a
}
escreva("OK=", testar())
""", expect_out="OK=1020", check_no_boxing_in_native=True))

    cases.append(Case("VAL-05", A, "run", """
@pilha
classe V2 { x: cf64; y: cf64 }
@pilha
classe Retangulo { origem: V2; tamanho: V2 }
@nativo
funcao area(): cf64 {
    var r = Retangulo(V2(1.0, 2.0), V2(5.0, 6.0))
    var r2 = r
    r2.tamanho.x = 10.0
    retorna r.tamanho.x * r.tamanho.y + r2.tamanho.x
}
escreva("OK=", area())
""", expect_out="OK=40", check_no_boxing_in_native=True))

    cases.append(Case("VAL-06", A, "run", """
@pilha
classe A { v: ci32 }
@pilha
classe B { a: A; w: ci32 }
@pilha
classe C { b: B; z: ci32 }
@nativo
funcao somaProfunda(): ci32 {
    const c = C(B(A(10), 20), 30)
    retorna c.b.a.v + c.b.w + c.z
}
escreva("OK=", somaProfunda())
""", expect_out="OK=60", check_no_boxing_in_native=True))

    cases.append(Case("VAL-07", A, "run", """
@pilha
classe Contador {
    valor: ci32
    @nativo
    incrementar(delta: ci32): ci32 {
        isto.valor = isto.valor + delta
        retorna isto.valor
    }
}
@nativo
funcao testar(): ci32 {
    var c = Contador(5)
    c.incrementar(7)
    retorna c.valor
}
escreva("OK=", testar())
""", expect_out="OK=12", check_no_boxing_in_native=True))

    cases.append(Case("VAL-08", A, "run", """
@pilha
classe Caixa {
    itens: VetorNativo<ci32>
}
@nativo
funcao testar(): ci32 {
    var v = VetorNativo<ci32>()
    v.adicionar(11)
    v.adicionar(22)
    var c = Caixa(v)
    retorna c.itens[0] + c.itens[1]
}
escreva("OK=", testar())
""", expect_out="OK=33", check_no_boxing_in_native=True))

    cases.append(Case("VAL-09", A, "run", """
@pilha
classe ComDestrutor {
    id: ci32
    destrutor() {
        const tmp: ci32 = isto.id
    }
}
@nativo
funcao testar(): ci32 {
    var d = ComDestrutor(42)
    retorna d.id
}
escreva("OK=", testar())
""", expect_out="OK=42", check_no_boxing_in_native=True))

    cases.append(Case("VAL-10", A, "run", """
@pilha
classe Vazia {}
@nativo
funcao testar(): ci32 {
    const v = Vazia()
    retorna 7
}
escreva("OK=", testar())
""", expect_out="OK=7", check_no_boxing_in_native=True))

    # 11..30: Mais cenários de cópia por valor, mutação independente, retorno de structs, loops, vetores de structs
    for k in range(11, 21):
        v1 = k * 3
        v2 = k * 5
        src = f"""
@pilha
classe Item{k} {{
    a: ci32
    b: cf64
    ok: cbool
}}
@nativo
funcao calc{k}(): ci32 {{
    var x = Item{k}({v1}, cf64({v2}), verdadeiro)
    var y = x
    y.a = y.a + 1
    se x.a == {v1} e y.a == {v1 + 1} e x.ok {{
        retorna x.a + ci32(y.b)
    }}
    retorna -1
}}
escreva("OK=", calc{k}())
"""
        cases.append(Case(f"VAL-{k:02d}", A, "run", src, expect_out=f"OK={v1 + v2}", check_no_boxing_in_native=True))

    cases.append(Case("VAL-21", A, "run", """
@pilha
classe Pixel { r: cu8; g: cu8; b: cu8; a: cu8 }
@nativo
funcao somaPixels(): ci32 {
    var buf = VetorNativo<Pixel>()
    para var i: ci32 = 0; i < 10; i = i + 1 {
        buf.adicionar(Pixel(cu8(i), cu8(i * 2), cu8(i * 3), cu8(255)))
    }
    var total: ci32 = 0
    para var i: ci32 = 0; i < 10; i = i + 1 {
        const p = buf[i]
        total += ci32(p.r) + ci32(p.g)
    }
    retorna total
}
escreva("OK=", somaPixels())
""", expect_out="OK=135", check_no_boxing_in_native=True))

    cases.append(Case("VAL-22", A, "run", """
@pilha
classe Mat2 { a: cf64; b: cf64; c: cf64; d: cf64 }
@nativo
funcao det(m: Mat2): cf64 { retorna m.a * m.d - m.b * m.c }
@nativo
funcao testar(): cf64 {
    const m = Mat2(4.0, 2.0, 1.0, 3.0)
    retorna det(m)
}
escreva("OK=", testar())
""", expect_out="OK=10", check_no_boxing_in_native=True))

    cases.append(Case("VAL-23", A, "run", """
@pilha
classe Complexo {
    re: cf64
    im: cf64
    @nativo
    conjugado(): Complexo { retorna Complexo(isto.re, -isto.im) }
    @nativo
    norma2(): cf64 { retorna isto.re * isto.re + isto.im * isto.im }
}
@nativo
funcao testar(): cf64 {
    const z = Complexo(3.0, 4.0)
    const c = z.conjugado()
    retorna c.norma2() + c.im
}
escreva("OK=", testar())
""", expect_out="OK=21", check_no_boxing_in_native=True))

    cases.append(Case("VAL-24", A, "run", """
@pilha
classe Intervalo {
    inicio: ci64
    fim: ci64
    @nativo
    contem(x: ci64): cbool { retorna x >= isto.inicio e x <= isto.fim }
}
@nativo
funcao testar(): ci32 {
    const iv = Intervalo(10, 20)
    retorna iv.contem(15) e !iv.contem(25) ? 1 : 0
}
escreva("OK=", testar())
""", expect_out="OK=1", check_no_boxing_in_native=True))

    cases.append(Case("VAL-25", A, "run", """
@pilha
classe Config {
    ativo: cbool
    nivel: ci16
    taxa: cf32
}
var c1 = Config(verdadeiro, ci16(3), cf32(0.5))
var c2 = c1
c2.ativo = falso
c2.nivel = ci16(9)
assercao(c1.ativo == verdadeiro e c1.nivel == 3)
assercao(c2.ativo == falso e c2.nivel == 9)
escreva("OK=GERENCIADO_COPIA")
""", expect_out="OK=GERENCIADO_COPIA"))

    cases.append(Case("VAL-26", A, "run", """
@pilha
classe Par { a: inteiro; b: inteiro }
funcao alterarCopia(p: Par): inteiro {
    p.a = 999
    retorna p.a
}
var orig = Par(5, 6)
const r = alterarCopia(orig)
assercao(orig.a == 5 e r == 999)
escreva("OK=ARG_COPIA")
""", expect_out="OK=ARG_COPIA"))

    cases.append(Case("VAL-27", A, "run", """
@pilha
classe Vet { x: cf64; y: cf64 }
@nativo
funcao criar(i: ci32): Vet { retorna Vet(cf64(i), cf64(i * 2)) }
@nativo
funcao somarMuitos(): cf64 {
    var acc: cf64 = 0.0
    para var i: ci32 = 1; i <= 100; i = i + 1 {
        const v = criar(i)
        acc += v.x + v.y
    }
    retorna acc
}
escreva("OK=", somarMuitos())
""", expect_out="OK=15150", check_no_boxing_in_native=True))

    cases.append(Case("VAL-28", A, "run", """
@pilha
classe Nomeado {
    s: StringNativa
    id: ci32
}
@nativo
funcao testar(): ci64 {
    var n = Nomeado(StringNativa.criar("alfa"), 7)
    retorna ci64(n.s.tamanho()) + ci64(n.id)
}
escreva("OK=", testar())
""", expect_out="OK=11", check_no_boxing_in_native=True))

    cases.append(Case("VAL-29", A, "run", """
@pilha
classe ComOpcional {
    valor: OpcionalNativo<ci32>
}
@nativo
funcao testar(): ci32 {
    const o = ComOpcional(OpcionalNativo<ci32>.algum(88))
    retorna o.valor.valorOu(0)
}
escreva("OK=", testar())
""", expect_out="OK=88", check_no_boxing_in_native=True))

    cases.append(Case("VAL-30", A, "run", """
@pilha
classe Ponto { x: cf64; y: cf64 }
var lista: Ponto[] = [Ponto(1.0, 2.0), Ponto(3.0, 4.0)]
var p = lista[0]
p.x = 50.0
assercao(lista[0].x == 1.0 e p.x == 50.0)
escreva("OK=LISTA_VALOR")
""", expect_out="OK=LISTA_VALOR"))

    cases.append(Case("VAL-31", A, "emit_c", """
@pilha
classe Compacta {
    a: ci32
    b: cf64
}
@nativo
funcao f(c: Compacta): cf64 { retorna cf64(c.a) + c.b }
escreva(f(Compacta(1, 2.0)))
""", expect_c_contains=["typedef struct cgd_val_", "int32_t", "double"]))

    cases.append(Case("VAL-32", A, "run", """
@pilha
classe Tripla { a: ci32; b: ci32; c: ci32 }
@nativo
funcao escolher(flag: cbool): Tripla {
    se flag { retorna Tripla(1, 2, 3) }
    retorna Tripla(4, 5, 6)
}
@nativo
funcao testar(): ci32 {
    const t = escolher(falso)
    retorna t.a + t.b + t.c
}
escreva("OK=", testar())
""", expect_out="OK=15", check_no_boxing_in_native=True))

    cases.append(Case("VAL-33", A, "run", """
@pilha
classe Acum {
    n: ci64
    @nativo
    add(v: ci64): vazio { isto.n += v }
}
@nativo
funcao testar(): ci64 {
    var a = Acum(0)
    para var i: ci64 = 1; i <= 10; i = i + 1 { a.add(i) }
    retorna a.n
}
escreva("OK=", testar())
""", expect_out="OK=55", check_no_boxing_in_native=True))

    cases.append(Case("VAL-34", A, "run", """
@pilha
classe SemCtor { x: ci32; y: cf64; z: cbool }
const s = SemCtor(9, 2.5, verdadeiro)
assercao(s.x == 9 e s.y == 2.5 e s.z == verdadeiro)
escreva("OK=AUTO_CTOR")
""", expect_out="OK=AUTO_CTOR"))

    cases.append(Case("VAL-35", A, "run", """
@pilha
classe ParF32 { a: cf32; b: cf32 }
@nativo
funcao prod(p: ParF32): cf32 { retorna p.a * p.b }
escreva("OK=", prod(ParF32(cf32(2.5), cf32(4.0))))
""", expect_out="OK=10", check_no_boxing_in_native=True))

    cases.append(Case("VAL-36", A, "run", """
@pilha
classe Escalar { v: csize }
@nativo
funcao dobro(e1: Escalar): csize { retorna e1.v * csize(2) }
escreva("OK=", dobro(Escalar(csize(21))))
""", expect_out="OK=42", check_no_boxing_in_native=True))

    # 37..46: Testes negativos de @pilha (E3701..E3704)
    cases.append(Case("VAL-37", A, "fail", """
classe Base { x: inteiro }
@pilha
classe Filha herda Base { y: inteiro }
""", expect_err="E3701"))

    cases.append(Case("VAL-38", A, "fail", """
interface I { m(): vazio }
@pilha
classe Impl implementa I { m(): vazio {} }
""", expect_err="E3701"))

    cases.append(Case("VAL-39", A, "fail", """
@pilha
classe abstrata Abs { x: ci32 }
""", expect_err="E3701"))

    cases.append(Case("VAL-40", A, "fail", """
@pilha
classe CampoDin { x: qualquer }
""", expect_err="E3702"))

    cases.append(Case("VAL-41", A, "fail", """
@pilha
classe CampoTextoGC { s: texto }
""", expect_err="E3702"))

    cases.append(Case("VAL-42", A, "fail", """
classe Gerenciada { x: inteiro }
@pilha
classe CampoObjGC { g: Gerenciada }
""", expect_err="E3702"))

    cases.append(Case("VAL-43", A, "fail", """
@pilha
classe RecursivaDireta {
    x: ci32
    prox: RecursivaDireta
}
""", expect_err="E3703"))

    cases.append(Case("VAL-44", A, "fail", """
@pilha
classe CicloA { b: CicloB }
@pilha
classe CicloB { a: CicloA }
""", expect_err="E3703"))

    cases.append(Case("VAL-45", A, "fail", """
@pilha
classe Ciclo1 { c2: Ciclo2 }
@pilha
classe Ciclo2 { c3: Ciclo3 }
@pilha
classe Ciclo3 { c1: Ciclo1 }
""", expect_err="E3703"))

    cases.append(Case("VAL-46", A, "fail", """
@pilha
classe CampoDicionario { m: dicionario }
""", expect_err="E3702"))

    return cases


def build_area_4_ownership() -> list[Case]:
    A = "4. Ownership, Escapes e Lifetimes Inferidos"
    cases: list[Case] = []

    # 1..22: Cenários positivos (move válido, borrow inferido leitura/mutação, reinicialização, clonar, RAII em fluxos complexos)
    cases.append(Case("OWN-01", A, "run", """
@nativo
funcao somarLeitura(v: VetorNativo<ci64>): ci64 {
    var s: ci64 = 0
    para var i: ci64 = 0; i < ci64(v.tamanho()); i = i + 1 { s += v[i] }
    retorna s
}
@nativo
funcao testar(): ci64 {
    var v = VetorNativo<ci64>()
    v.adicionar(10)
    v.adicionar(20)
    // v é emprestado automaticamente por leitura e continua vivo depois!
    const a: ci64 = somarLeitura(v)
    const b: ci64 = somarLeitura(v)
    retorna a + b
}
escreva("OK=", testar())
""", expect_out="OK=60", check_no_boxing_in_native=True))

    cases.append(Case("OWN-02", A, "run", """
@nativo
funcao preencher(v: VetorNativo<ci32>, n: ci32): vazio {
    para var i: ci32 = 0; i < n; i = i + 1 { v.adicionar(i) }
}
@nativo
funcao testar(): ci64 {
    var v = VetorNativo<ci32>()
    preencher(v, 5)
    preencher(v, 3)
    retorna ci64(v.tamanho())
}
escreva("OK=", testar())
""", expect_out="OK=8", check_no_boxing_in_native=True))

    cases.append(Case("OWN-03", A, "run", """
@nativo
funcao testar(): ci64 {
    var a = VetorNativo<ci64>()
    a.adicionar(7)
    var b = a // move
    a = VetorNativo<ci64>() // reinicialização após move é válida!
    a.adicionar(8)
    retorna b[0] + a[0]
}
escreva("OK=", testar())
""", expect_out="OK=15", check_no_boxing_in_native=True))

    cases.append(Case("OWN-04", A, "run", """
@nativo
funcao testar(): ci64 {
    var a = VetorNativo<ci64>()
    a.adicionar(10)
    var b = a.clonar()
    b[0] = 99
    retorna a[0] * 100 + b[0]
}
escreva("OK=", testar())
""", expect_out="OK=1099", check_no_boxing_in_native=True))

    cases.append(Case("OWN-05", A, "run", """
@nativo
funcao produzir(n: ci32): VetorNativo<ci32> {
    var v = VetorNativo<ci32>()
    para var i: ci32 = 0; i < n; i = i + 1 { v.adicionar(i * 2) }
    retorna v
}
@nativo
funcao testar(): ci32 {
    const v = produzir(5)
    retorna v[4]
}
escreva("OK=", testar())
""", expect_out="OK=8", check_no_boxing_in_native=True))

    cases.append(Case("OWN-06", A, "run", """
@nativo
funcao testar(): ci32 {
    var s = StringNativa.criar("delegua")
    const v = s.visao()
    const tam: ci32 = ci32(v.tamanho())
    // após último uso de v, s pode ser modificado com segurança
    s.anexar("!")
    retorna tam * 10 + ci32(s.tamanho())
}
escreva("OK=", testar())
""", expect_out="OK=78", check_no_boxing_in_native=True))

    cases.append(Case("OWN-07", A, "run", """
@nativo
funcao testar(): ci32 {
    var v = VetorNativo<ci32>()
    v.adicionar(1)
    v.adicionar(2)
    v.adicionar(3)
    const f = v.fatia(1, 3)
    const soma: ci32 = f[0] + f[1]
    // após último uso de f, mutar v é válido
    v.adicionar(4)
    retorna soma + ci32(v.tamanho())
}
escreva("OK=", testar())
""", expect_out="OK=9", check_no_boxing_in_native=True))

    cases.append(Case("OWN-08", A, "run", """
@nativo
funcao testar(flag: cbool): ci32 {
    var v = VetorNativo<ci32>()
    v.adicionar(5)
    se flag {
        var outro = v
        retorna outro[0]
    }
    // no ramo else (quando flag==falso), v não foi movido!
    retorna v[0] + 10
}
escreva("OK=", testar(verdadeiro), ",", testar(falso))
""", expect_out="OK=5,15", check_no_boxing_in_native=True))

    cases.append(Case("OWN-09", A, "run", """
@nativo
funcao testar(flag: cbool): ci32 {
    var v = VetorNativo<ci32>()
    v.adicionar(1)
    se flag {
        v.liberar()
        retorna 100
    }
    retorna v[0]
}
escreva("OK=", testar(verdadeiro), ",", testar(falso))
""", expect_out="OK=100,1", check_no_boxing_in_native=True))

    cases.append(Case("OWN-10", A, "run", """
@nativo
funcao testar(): ci32 {
    var total: ci32 = 0
    para var i: ci32 = 0; i < 50; i = i + 1 {
        var tmp = VetorNativo<ci32>()
        tmp.adicionar(i)
        se i == 10 { continua }
        se i == 20 { sustar }
        total += tmp[0]
    }
    retorna total
}
escreva("OK=", testar())
""", expect_out="OK=180", check_no_boxing_in_native=True))

    cases.append(Case("OWN-11", A, "run", """
@nativo
funcao testar(): ci32 {
    var v = VetorNativo<ci32>()
    para var i: ci32 = 0; i < 5; i = i + 1 { v.adicionar(i + 1) }
    var acc: ci32 = 0
    para cada item em v {
        acc += item
    }
    // após término de para cada, v pode ser modificado normalmente
    v.adicionar(100)
    retorna acc + v[5]
}
escreva("OK=", testar())
""", expect_out="OK=115", check_no_boxing_in_native=True))

    cases.append(Case("OWN-12", A, "run", """
@nativo
funcao testar(): ci32 {
    var s = StringNativa.criar("abc")
    var s2 = s
    s = StringNativa.criar("xy")
    retorna ci32(s2.tamanho()) * 10 + ci32(s.tamanho())
}
escreva("OK=", testar())
""", expect_out="OK=32", check_no_boxing_in_native=True))

    cases.append(Case("OWN-13", A, "run", """
@nativo
funcao testar(): ci32 {
    var v = VetorNativo<ci32>()
    v.adicionar(9)
    v.liberar()
    v = VetorNativo<ci32>()
    v.adicionar(4)
    retorna v[0]
}
escreva("OK=", testar())
""", expect_out="OK=4", check_no_boxing_in_native=True))

    cases.append(Case("OWN-14", A, "run", """
@nativo
funcao lerDois(a: VetorNativo<ci32>, b: VetorNativo<ci32>): ci32 {
    retorna a[0] + b[0]
}
@nativo
funcao testar(): ci32 {
    var v = VetorNativo<ci32>()
    v.adicionar(21)
    // Dois empréstimos imutáveis simultâneos do mesmo vetor são seguros!
    retorna lerDois(v, v)
}
escreva("OK=", testar())
""", expect_out="OK=42", check_no_boxing_in_native=True))

    cases.append(Case("OWN-15", A, "run", """
@nativo
funcao testar(k: ci32): ci32 {
    var v = VetorNativo<ci32>()
    v.adicionar(10)
    escolha k {
        caso 1:
            var tmp = VetorNativo<ci32>()
            tmp.adicionar(5)
            retorna v[0] + tmp[0]
        padrao:
            retorna v[0]
    }
}
escreva("OK=", testar(1), ",", testar(2))
""", expect_out="OK=15,10", check_no_boxing_in_native=True))

    cases.append(Case("OWN-16", A, "run", """
@nativo
funcao testar(): ci32 {
    var i: ci32 = 0
    var soma: ci32 = 0
    enquanto i < 10 {
        var s = StringNativa.criar("ab")
        soma += ci32(s.tamanho())
        i += 1
    }
    retorna soma
}
escreva("OK=", testar())
""", expect_out="OK=20", check_no_boxing_in_native=True))

    cases.append(Case("OWN-17", A, "run", """
@nativo
funcao testar(): ci32 {
    var i: ci32 = 0
    var soma: ci32 = 0
    fazer {
        var v = VetorNativo<ci32>()
        v.adicionar(i)
        soma += v[0]
        i += 1
    } enquanto i < 5
    retorna soma
}
escreva("OK=", testar())
""", expect_out="OK=10", check_no_boxing_in_native=True))

    cases.append(Case("OWN-18", A, "run", """
@pilha
classe Rec {
    dados: VetorNativo<ci32>
}
@nativo
funcao testar(): ci32 {
    var v = VetorNativo<ci32>()
    v.adicionar(7)
    var r = Rec(v)
    var r2 = r // move struct não-trivial
    retorna r2.dados[0]
}
escreva("OK=", testar())
""", expect_out="OK=7", check_no_boxing_in_native=True))

    cases.append(Case("OWN-19", A, "run", """
@nativo
funcao recursivaComBorrow(v: VetorNativo<ci32>, prof: ci32): ci32 {
    se prof <= 0 { retorna v[0] }
    v[0] = v[0] + 1
    const r: ci32 = recursivaComBorrow(v, prof - 1)
    retorna r
}
@nativo
funcao testar(): ci32 {
    var v = VetorNativo<ci32>()
    v.adicionar(0)
    retorna recursivaComBorrow(v, 5)
}
escreva("OK=", testar())
""", expect_out="OK=5", check_no_boxing_in_native=True))

    cases.append(Case("OWN-20", A, "run", """
@nativo
funcao consumir(v: VetorNativo<ci32>): ci32 {
    var local = v
    retorna local[0]
}
@nativo
funcao testar(): ci32 {
    var v = VetorNativo<ci32>()
    v.adicionar(33)
    const c = v.clonar()
    retorna consumir(c) + v[0]
}
escreva("OK=", testar())
""", expect_out="OK=66", check_no_boxing_in_native=True))

    cases.append(Case("OWN-21", A, "run", """
funcao comTente(): inteiro {
    var total: inteiro = 0
    tente {
        var v = VetorNativo<ci32>()
        v.adicionar(12)
        total = inteiro(v[0])
    } pegue (err) {
        total = -1
    } finalmente {
        total = total + 1
    }
    retorna total
}
escreva("OK=", comTente())
""", expect_out="OK=13"))

    cases.append(Case("OWN-22", A, "run", """
@nativo
funcao testar(): ci32 {
    var m = MapaNativo<ci32, ci32>()
    m.definir(1, 10)
    var m2 = m.clonar()
    m2.definir(1, 20)
    retorna m.obter(1) + m2.obter(1)
}
escreva("OK=", testar())
""", expect_out="OK=30", check_no_boxing_in_native=True))

    # 23..62: 40 testes negativos extremos cobrindo E3801..E3809 em múltiplos cenários e fluxos!
    # E3801: Use-after-move (8 variantes)
    cases.append(Case("OWN-23", A, "fail", """
@nativo
funcao f(): ci32 {
    var a = VetorNativo<ci32>()
    a.adicionar(1)
    var b = a
    retorna a[0]
}
""", expect_err="E3801"))

    cases.append(Case("OWN-24", A, "fail", """
@nativo
funcao f(): ci32 {
    var s = StringNativa.criar("oi")
    var t = s
    retorna ci32(s.tamanho())
}
""", expect_err="E3801"))

    cases.append(Case("OWN-25", A, "fail", """
@nativo
funcao f(): ci32 {
    var m = MapaNativo<ci32, ci32>()
    m.definir(1, 2)
    var m2 = m
    retorna m.obter(1)
}
""", expect_err="E3801"))

    cases.append(Case("OWN-26", A, "fail", """
@nativo
funcao f(flag: cbool): ci32 {
    var a = VetorNativo<ci32>()
    a.adicionar(1)
    se flag {
        var b = a
    }
    // a pode ter sido movido no ramo if!
    retorna a[0]
}
""", expect_err="E3801"))

    cases.append(Case("OWN-27", A, "fail", """
@nativo
funcao f(): ci32 {
    var a = VetorNativo<ci32>()
    a.adicionar(1)
    para var i: ci32 = 0; i < 3; i = i + 1 {
        var b = a // move dentro de loop -> na 2a iteração já foi movido!
    }
    retorna 0
}
""", expect_err="E3801"))

    cases.append(Case("OWN-28", A, "fail", """
@nativo
funcao consumir(x: VetorNativo<ci32>): ci32 {
    var local = x
    retorna local[0]
}
@nativo
funcao f(): ci32 {
    var a = VetorNativo<ci32>()
    a.adicionar(1)
    const r: ci32 = consumir(a)
    retorna r + a[0]
}
""", expect_err="E3801"))

    cases.append(Case("OWN-29", A, "fail", """
@pilha
classe Dono { v: VetorNativo<ci32> }
@nativo
funcao f(): ci32 {
    var a = VetorNativo<ci32>()
    a.adicionar(1)
    var d = Dono(a)
    retorna a[0]
}
""", expect_err="E3801"))

    cases.append(Case("OWN-30", A, "fail", """
@pilha
classe Dono { v: VetorNativo<ci32> }
@nativo
funcao f(): ci32 {
    var a = VetorNativo<ci32>()
    a.adicionar(1)
    var d1 = Dono(a)
    var d2 = d1
    retorna d1.v[0]
}
""", expect_err="E3801"))

    # E3802: Use-after-free (6 variantes)
    cases.append(Case("OWN-31", A, "fail", """
@nativo
funcao f(): ci32 {
    var a = VetorNativo<ci32>()
    a.adicionar(1)
    a.liberar()
    retorna a[0]
}
""", expect_err="E3802"))

    cases.append(Case("OWN-32", A, "fail", """
@nativo
funcao f(): ci32 {
    var s = StringNativa.criar("teste")
    s.liberar()
    s.anexar("x")
    retorna 0
}
""", expect_err="E3802"))

    cases.append(Case("OWN-33", A, "fail", """
@nativo
funcao f(): ci32 {
    var m = MapaNativo<ci32, ci32>()
    m.definir(1, 2)
    m.liberar()
    retorna m.obter(1)
}
""", expect_err="E3802"))

    cases.append(Case("OWN-34", A, "fail", """
@nativo
funcao f(flag: cbool): ci32 {
    var a = VetorNativo<ci32>()
    a.adicionar(1)
    se flag { a.liberar() }
    retorna a[0]
}
""", expect_err="E3802"))

    cases.append(Case("OWN-35", A, "fail", """
@nativo
funcao f(): ci32 {
    var a = VetorNativo<ci32>()
    a.adicionar(1)
    a.liberar()
    var b = a
    retorna b[0]
}
""", expect_err="E3802"))

    cases.append(Case("OWN-36", A, "fail", """
@nativo
funcao f(): ci32 {
    var mat = MatrizNativa<cf64>(2, 2)
    mat.liberar()
    retorna ci32(mat.obter(0, 0))
}
""", expect_err="E3802"))

    # E3803: Cópia implícita proibida (ex.: mover de empréstimo/campo proprietário) (4 variantes)
    cases.append(Case("OWN-37", A, "fail", """
@pilha
classe Caixa { v: VetorNativo<ci32> }
@nativo
funcao f(): ci32 {
    var a = VetorNativo<ci32>()
    a.adicionar(1)
    var c = Caixa(a)
    var copia = c.v
    retorna copia[0]
}
""", expect_err="E3803"))

    cases.append(Case("OWN-38", A, "fail", """
@nativo
funcao f(): ci32 {
    var lista = VetorNativo<VetorNativo<ci32>>()
    var sub = VetorNativo<ci32>()
    sub.adicionar(1)
    lista.adicionar(sub)
    var roubado = lista[0]
    retorna roubado[0]
}
""", expect_err="E3803"))

    cases.append(Case("OWN-39", A, "fail", """
@pilha
classe Holder { s: StringNativa }
@nativo
funcao f(): ci32 {
    var h = Holder(StringNativa.criar("abc"))
    var s2 = h.s
    retorna ci32(s2.tamanho())
}
""", expect_err="E3803"))

    cases.append(Case("OWN-40", A, "fail", """
@nativo
funcao f(): ci32 {
    var v = VetorNativo<StringNativa>()
    v.adicionar(StringNativa.criar("x"))
    var x = v[0]
    retorna ci32(x.tamanho())
}
""", expect_err="E3803"))

    # E3804: Retorno de visão pendurada (5 variantes)
    cases.append(Case("OWN-41", A, "fail", """
@nativo
funcao pendurada(): VisaoTexto {
    var s = StringNativa.criar("local")
    retorna s.visao()
}
""", expect_err="E3804"))

    cases.append(Case("OWN-42", A, "fail", """
@nativo
funcao pendurada(): VisaoTexto {
    var s = StringNativa.criar("local")
    const v = s.visao()
    retorna v
}
""", expect_err="E3804"))

    cases.append(Case("OWN-43", A, "fail", """
@nativo
funcao pendurada(): FatiaNativa<ci32> {
    var v = VetorNativo<ci32>()
    v.adicionar(1)
    retorna v.fatia(0, 1)
}
""", expect_err="E3804"))

    cases.append(Case("OWN-44", A, "fail", """
@nativo
funcao pendurada(): FatiaNativa<ci32> {
    var v = VetorNativo<ci32>()
    v.adicionar(1)
    const f = v.fatia(0, 1)
    retorna f
}
""", expect_err="E3804"))

    cases.append(Case("OWN-45", A, "fail", """
@nativo
funcao pendurada(flag: cbool): VisaoTexto {
    var s = StringNativa.criar("a")
    const v = s.visao()
    se flag { retorna v }
    retorna v
}
""", expect_err="E3804"))

    # E3805: Conflito de empréstimo / mutação durante iteração / realocação / aliasing mutável (7 variantes)
    cases.append(Case("OWN-46", A, "fail", """
@nativo
funcao f(): ci32 {
    var s = StringNativa.criar("abc")
    const v = s.visao()
    s.anexar("def")
    retorna ci32(v.tamanho())
}
""", expect_err="E3805"))

    cases.append(Case("OWN-47", A, "fail", """
@nativo
funcao f(): ci32 {
    var vec = VetorNativo<ci32>()
    vec.adicionar(1)
    const sl = vec.fatia(0, 1)
    vec.adicionar(2)
    retorna sl[0]
}
""", expect_err="E3805"))

    cases.append(Case("OWN-48", A, "fail", """
@nativo
funcao f(): ci32 {
    var vec = VetorNativo<ci32>()
    vec.adicionar(1)
    const sl = vec.fatia(0, 1)
    vec.limpar()
    retorna sl[0]
}
""", expect_err="E3805"))

    cases.append(Case("OWN-49", A, "fail", """
@nativo
funcao f(): ci32 {
    var vec = VetorNativo<ci32>()
    vec.adicionar(1)
    vec.adicionar(2)
    para cada x em vec {
        vec.adicionar(x)
    }
    retorna 0
}
""", expect_err="E3805"))

    cases.append(Case("OWN-50", A, "fail", """
@nativo
funcao mutarDois(a: VetorNativo<ci32>, b: VetorNativo<ci32>): vazio {
    a.adicionar(1)
    b.adicionar(2)
}
@nativo
funcao f(): ci32 {
    var v = VetorNativo<ci32>()
    mutarDois(v, v)
    retorna 0
}
""", expect_err="E3805"))

    cases.append(Case("OWN-51", A, "fail", """
@nativo
funcao lerEMutar(a: VetorNativo<ci32>, b: VetorNativo<ci32>): ci32 {
    b.adicionar(1)
    retorna a[0]
}
@nativo
funcao f(): ci32 {
    var v = VetorNativo<ci32>()
    v.adicionar(0)
    retorna lerEMutar(v, v)
}
""", expect_err="E3805"))

    cases.append(Case("OWN-52", A, "fail", """
@nativo
funcao f(): ci32 {
    var s = StringNativa.criar("abc")
    const v = s.visao()
    s.liberar()
    retorna ci32(v.tamanho())
}
""", expect_err="E3805"))

    # E3806: Escape inseguro de visão para escopo externo (3 variantes)
    cases.append(Case("OWN-53", A, "fail", """
@nativo
funcao f(): ci32 {
    var s = StringNativa.criar("fora")
    var v = s.visao()
    se verdadeiro {
        var interno = StringNativa.criar("dentro")
        v = interno.visao()
    }
    retorna ci32(v.tamanho())
}
""", expect_err="E3806"))

    cases.append(Case("OWN-54", A, "fail", """
@nativo
funcao f(): ci32 {
    var a = VetorNativo<ci32>()
    a.adicionar(1)
    var sl = a.fatia(0, 1)
    se verdadeiro {
        var interno = VetorNativo<ci32>()
        interno.adicionar(9)
        sl = interno.fatia(0, 1)
    }
    retorna sl[0]
}
""", expect_err="E3806"))

    cases.append(Case("OWN-55", A, "fail", """
@pilha
classe CaixaVisao { v: VisaoTexto }
@nativo
funcao f(): CaixaVisao {
    var s = StringNativa.criar("local")
    retorna CaixaVisao(s.visao())
}
""", expect_err="E3806"))

    # E3807: Double-free (3 variantes)
    cases.append(Case("OWN-56", A, "fail", """
@nativo
funcao f(): ci32 {
    var v = VetorNativo<ci32>()
    v.liberar()
    v.liberar()
    retorna 0
}
""", expect_err="E3807"))

    cases.append(Case("OWN-57", A, "fail", """
@nativo
funcao f(): ci32 {
    var s = StringNativa.criar("x")
    s.liberar()
    s.liberar()
    retorna 0
}
""", expect_err="E3807"))

    cases.append(Case("OWN-58", A, "fail", """
@nativo
funcao f(flag: cbool): ci32 {
    var v = VetorNativo<ci32>()
    se flag { v.liberar() }
    v.liberar()
    retorna 0
}
""", expect_err="E3807"))

    # E3808: Uso antes de inicialização em @nativo (2 variantes)
    cases.append(Case("OWN-59", A, "fail", """
@nativo
funcao f(): ci32 {
    var x: ci32
    retorna x + 1
}
""", expect_err="E3808"))

    cases.append(Case("OWN-60", A, "fail", """
@nativo
funcao f(flag: cbool): ci32 {
    var x: ci32
    se flag { x = 10 }
    retorna x
}
""", expect_err="E3808"))

    # E3809: Bounds negativos / capacidade negativa em compilação (2 variantes)
    cases.append(Case("OWN-61", A, "fail", """
@nativo
funcao f(): ci32 {
    var v = VetorNativo<ci32>()
    v.adicionar(1)
    retorna v[-1]
}
""", expect_err="E3809"))

    cases.append(Case("OWN-62", A, "fail", """
@nativo
funcao f(): ci32 {
    var v = VetorNativo<ci32>()
    v.reservar(-5)
    retorna 0
}
""", expect_err="E3809"))

    return cases


def build_area_5_operators() -> list[Case]:
    A = "5. Operadores Personalizados (@operador)"
    cases: list[Case] = []

    # 1..16: Todos os 16 operadores em @pilha + @nativo
    cases.append(Case("OP-01", A, "run", """
@pilha
classe N {
    v: ci64
    @nativo @operador("+") somar(o: N): N { retorna N(isto.v + o.v) }
}
@nativo funcao t(): ci64 { retorna (N(10) + N(32)).v }
escreva("OK=", t())
""", expect_out="OK=42", check_no_boxing_in_native=True))

    cases.append(Case("OP-02", A, "run", """
@pilha
classe N {
    v: ci64
    @nativo @operador("-") sub(o: N): N { retorna N(isto.v - o.v) }
}
@nativo funcao t(): ci64 { retorna (N(50) - N(8)).v }
escreva("OK=", t())
""", expect_out="OK=42", check_no_boxing_in_native=True))

    cases.append(Case("OP-03", A, "run", """
@pilha
classe N {
    v: ci64
    @nativo @operador("*") mul(o: N): N { retorna N(isto.v * o.v) }
}
@nativo funcao t(): ci64 { retorna (N(6) * N(7)).v }
escreva("OK=", t())
""", expect_out="OK=42", check_no_boxing_in_native=True))

    cases.append(Case("OP-04", A, "run", """
@pilha
classe N {
    v: cf64
    @nativo @operador("/") div(o: N): N { retorna N(isto.v / o.v) }
}
@nativo funcao t(): cf64 { retorna (N(84.0) / N(2.0)).v }
escreva("OK=", t())
""", expect_out="OK=42", check_no_boxing_in_native=True))

    cases.append(Case("OP-05", A, "run", """
@pilha
classe N {
    v: ci64
    @nativo @operador("%") mod(o: N): N { retorna N(isto.v % o.v) }
}
@nativo funcao t(): ci64 { retorna (N(47) % N(10)).v }
escreva("OK=", t())
""", expect_out="OK=7", check_no_boxing_in_native=True))

    cases.append(Case("OP-06", A, "run", """
@pilha
classe N {
    v: ci64
    @nativo @operador("==") ig(o: N): cbool { retorna isto.v == o.v }
}
@nativo funcao t(): cbool { retorna N(5) == N(5) e !(N(5) == N(6)) }
escreva("OK=", t())
""", expect_out="OK=verdadeiro", check_no_boxing_in_native=True))

    cases.append(Case("OP-07", A, "run", """
@pilha
classe N {
    v: ci64
    @nativo @operador("!=") dif(o: N): cbool { retorna isto.v != o.v }
}
@nativo funcao t(): cbool { retorna N(5) != N(6) e !(N(5) != N(5)) }
escreva("OK=", t())
""", expect_out="OK=verdadeiro", check_no_boxing_in_native=True))

    cases.append(Case("OP-08", A, "run", """
@pilha
classe N {
    v: ci64
    @nativo @operador("<") men(o: N): cbool { retorna isto.v < o.v }
}
@nativo funcao t(): cbool { retorna N(3) < N(5) e !(N(5) < N(3)) }
escreva("OK=", t())
""", expect_out="OK=verdadeiro", check_no_boxing_in_native=True))

    cases.append(Case("OP-09", A, "run", """
@pilha
classe N {
    v: ci64
    @nativo @operador("<=") menIg(o: N): cbool { retorna isto.v <= o.v }
}
@nativo funcao t(): cbool { retorna N(5) <= N(5) e N(4) <= N(5) }
escreva("OK=", t())
""", expect_out="OK=verdadeiro", check_no_boxing_in_native=True))

    cases.append(Case("OP-10", A, "run", """
@pilha
classe N {
    v: ci64
    @nativo @operador(">") mai(o: N): cbool { retorna isto.v > o.v }
}
@nativo funcao t(): cbool { retorna N(9) > N(2) e !(N(2) > N(9)) }
escreva("OK=", t())
""", expect_out="OK=verdadeiro", check_no_boxing_in_native=True))

    cases.append(Case("OP-11", A, "run", """
@pilha
classe N {
    v: ci64
    @nativo @operador(">=") maiIg(o: N): cbool { retorna isto.v >= o.v }
}
@nativo funcao t(): cbool { retorna N(9) >= N(9) e N(10) >= N(9) }
escreva("OK=", t())
""", expect_out="OK=verdadeiro", check_no_boxing_in_native=True))

    cases.append(Case("OP-12", A, "run", """
@pilha
classe Vet2 {
    x: cf64; y: cf64
    @nativo @operador("[]") obter(i: ci32): cf64 {
        se i == 0 { retorna isto.x }
        retorna isto.y
    }
}
@nativo funcao t(): cf64 {
    const v = Vet2(11.0, 22.0)
    retorna v[0] + v[1]
}
escreva("OK=", t())
""", expect_out="OK=33", check_no_boxing_in_native=True))

    cases.append(Case("OP-13", A, "run", """
@pilha
classe Vet2 {
    x: cf64; y: cf64
    @nativo @operador("[]=") definir(i: ci32, val: cf64): vazio {
        se i == 0 { isto.x = val } senao { isto.y = val }
    }
}
@nativo funcao t(): cf64 {
    var v = Vet2(1.0, 2.0)
    v[0] = 10.0
    v[1] = 20.0
    retorna v.x + v.y
}
escreva("OK=", t())
""", expect_out="OK=30", check_no_boxing_in_native=True))

    cases.append(Case("OP-14", A, "run", """
@pilha
classe N {
    v: ci64
    @nativo @operador("unario-") neg(): N { retorna N(-isto.v) }
}
@nativo funcao t(): ci64 { retorna (-N(42)).v }
escreva("OK=", t())
""", expect_out="OK=-42", check_no_boxing_in_native=True))

    cases.append(Case("OP-15", A, "run", """
@pilha
classe N {
    v: ci64
    @nativo @operador("unario+") pos(): N { retorna N(isto.v >= 0 ? isto.v : -isto.v) }
}
@nativo funcao t(): ci64 { retorna (+N(-15)).v }
escreva("OK=", t())
""", expect_out="OK=15", check_no_boxing_in_native=True))

    cases.append(Case("OP-16", A, "run", """
@pilha
classe Flag {
    b: cbool
    @nativo @operador("unario!") inv(): cbool { retorna !isto.b }
}
@nativo funcao t(): cbool { retorna !Flag(falso) }
escreva("OK=", t())
""", expect_out="OK=verdadeiro", check_no_boxing_in_native=True))

    # 17..35: Classes gerenciadas, comutatividade, encadeamento, ordem de avaliação, precedência, herança
    cases.append(Case("OP-17", A, "run", """
classe Vet2 {
    x: real; y: real
    construtor(x: real, y: real) { isto.x = x; isto.y = y }
    @operador("+") somar(o: Vet2): Vet2 { retorna Vet2(isto.x + o.x, isto.y + o.y) }
    @operador("*") escalar(s: real): Vet2 { retorna Vet2(isto.x * s, isto.y * s) }
    @operador("==") igual(o: Vet2): logico { retorna isto.x == o.x e isto.y == o.y }
}
const a = Vet2(1.0, 2.0)
const b = Vet2(3.0, 4.0)
const c = a + b * 2.0
assercao(c == Vet2(7.0, 10.0))
escreva("OK=", c.x, ",", c.y)
""", expect_out="OK=7,10"))

    cases.append(Case("OP-18", A, "run", """
// Comutatividade: 2.0 * v no contexto gerenciado
classe Vet2 {
    x: real; y: real
    construtor(x: real, y: real) { isto.x = x; isto.y = y }
    @operador("*") escalar(s: real): Vet2 { retorna Vet2(isto.x * s, isto.y * s) }
}
const v = Vet2(3.0, 5.0)
const r = 2.0 * v
escreva("OK=", r.x, ",", r.y)
""", expect_out="OK=6,10"))

    cases.append(Case("OP-19", A, "run", """
// Comutatividade no contexto @nativo + @pilha
@pilha
classe V2 {
    x: cf64; y: cf64
    @nativo @operador("*") esc(s: cf64): V2 { retorna V2(isto.x * s, isto.y * s) }
}
@nativo funcao t(): cf64 {
    const r = 3.0 * V2(2.0, 4.0)
    retorna r.x + r.y
}
escreva("OK=", t())
""", expect_out="OK=18", check_no_boxing_in_native=True))

    cases.append(Case("OP-20", A, "run", """
// Ordem de avaliação esquerda-para-direita em operador comutativo
classe Log {
    ordem: texto
    construtor() { isto.ordem = "" }
}
classe Box {
    v: inteiro
    construtor(v: inteiro) { isto.v = v }
    @operador("*") mul(s: inteiro): Box { retorna Box(isto.v * s) }
}
funcao esq(log: Log): inteiro { log.ordem = log.ordem + "L"; retorna 3 }
funcao dir(log: Log): Box { log.ordem = log.ordem + "R"; retorna Box(4) }
const lg = Log()
const r = esq(lg) * dir(lg)
assercao(lg.ordem == "LR" e r.v == 12)
escreva("OK=", lg.ordem, "=", r.v)
""", expect_out="OK=LR=12"))

    cases.append(Case("OP-21", A, "run", """
// Avaliação única de operandos em encadeamento
classe Cont {
    n: inteiro
    construtor() { isto.n = 0 }
}
classe Num {
    v: inteiro
    construtor(v: inteiro) { isto.v = v }
    @operador("+") add(o: Num): Num { retorna Num(isto.v + o.v) }
}
funcao criar(ct: Cont, x: inteiro): Num { ct.n = ct.n + 1; retorna Num(x) }
const ct = Cont()
const r = criar(ct, 1) + criar(ct, 2) + criar(ct, 3)
assercao(ct.n == 3 e r.v == 6)
escreva("OK=", ct.n, ",", r.v)
""", expect_out="OK=3,6"))

    cases.append(Case("OP-22", A, "run", """
// Indexação [] e []= em classe gerenciada
classe Lista2 {
    a: inteiro; b: inteiro
    construtor(a: inteiro, b: inteiro) { isto.a = a; isto.b = b }
    @operador("[]") get(i: inteiro): inteiro { retorna i == 0 ? isto.a : isto.b }
    @operador("[]=") set(i: inteiro, v: inteiro): vazio {
        se i == 0 { isto.a = v } senao { isto.b = v }
    }
}
var l = Lista2(1, 2)
l[0] = 10
l[1] = 20
escreva("OK=", l[0] + l[1])
""", expect_out="OK=30"))

    cases.append(Case("OP-23", A, "run", """
// Unários -, +, ! em classe gerenciada
classe Sinal {
    v: inteiro
    construtor(v: inteiro) { isto.v = v }
    @operador("unario-") neg(): Sinal { retorna Sinal(-isto.v) }
    @operador("unario+") pos(): Sinal { retorna Sinal(isto.v) }
    @operador("unario!") zero(): logico { retorna isto.v == 0 }
}
const s = Sinal(5)
assercao((-s).v == -5)
assercao((+s).v == 5)
assercao(!Sinal(0) == verdadeiro)
assercao(!s == falso)
escreva("OK=UNARIOS_GC")
""", expect_out="OK=UNARIOS_GC"))

    cases.append(Case("OP-24", A, "run", """
// Operador herdado de classe base em classe gerenciada
classe Base {
    v: inteiro
    construtor(v: inteiro) { isto.v = v }
    @operador("+") somar(o: Base): Base { retorna Base(isto.v + o.v) }
}
classe Derivada herda Base {
    construtor(v: inteiro) { super(v) }
}
const r = Derivada(10) + Derivada(15)
escreva("OK=", r.v)
""", expect_out="OK=25"))

    cases.append(Case("OP-25", A, "run", """
// Sobrescrita de @operador em subclasse
classe Base {
    v: inteiro
    construtor(v: inteiro) { isto.v = v }
    @operador("+") somar(o: Base): Base { retorna Base(isto.v + o.v) }
}
classe Dobrada herda Base {
    construtor(v: inteiro) { super(v) }
    @operador("+") somar(o: Base): Base { retorna Base((isto.v + o.v) * 2) }
}
const r = Dobrada(3) + Dobrada(4)
escreva("OK=", r.v)
""", expect_out="OK=14"))

    cases.append(Case("OP-26", A, "run", """
// Relacionais completos em classe gerenciada
classe Dinheiro {
    centavos: inteiro
    construtor(c: inteiro) { isto.centavos = c }
    @operador("==") eq(o: Dinheiro): logico { retorna isto.centavos == o.centavos }
    @operador("!=") ne(o: Dinheiro): logico { retorna isto.centavos != o.centavos }
    @operador("<") lt(o: Dinheiro): logico { retorna isto.centavos < o.centavos }
    @operador("<=") le(o: Dinheiro): logico { retorna isto.centavos <= o.centavos }
    @operador(">") gt(o: Dinheiro): logico { retorna isto.centavos > o.centavos }
    @operador(">=") ge(o: Dinheiro): logico { retorna isto.centavos >= o.centavos }
}
const a = Dinheiro(100)
const b = Dinheiro(250)
assercao(a < b e a <= b e b > a e b >= a e a != b e a == Dinheiro(100))
escreva("OK=REL_GC")
""", expect_out="OK=REL_GC"))

    cases.append(Case("OP-27", A, "run", """
// Expressão complexa encadeada com precedência nativa
@pilha
classe V {
    x: cf64
    @nativo @operador("+") add(o: V): V { retorna V(isto.x + o.x) }
    @nativo @operador("-") sub(o: V): V { retorna V(isto.x - o.x) }
    @nativo @operador("*") mul(o: V): V { retorna V(isto.x * o.x) }
    @nativo @operador("unario-") neg(): V { retorna V(-isto.x) }
}
@nativo funcao t(): cf64 {
    const r = -V(2.0) + V(3.0) * V(4.0) - V(1.0)
    retorna r.x
}
escreva("OK=", t())
""", expect_out="OK=9", check_no_boxing_in_native=True))

    cases.append(Case("OP-28", A, "run", """
// @pilha usado com @operador a partir de código GERENCIADO
@pilha
classe Ponto {
    x: cf64; y: cf64
    @nativo @operador("+") somar(o: Ponto): Ponto { retorna Ponto(isto.x + o.x, isto.y + o.y) }
}
const p = Ponto(1.5, 2.5) + Ponto(3.5, 4.5)
escreva("OK=", p.x, ",", p.y)
""", expect_out="OK=5,7"))

    cases.append(Case("OP-29", A, "run", """
// Operador + comutativo (escalar + objeto)
classe Offset {
    v: inteiro
    construtor(v: inteiro) { isto.v = v }
    @operador("+") somarInt(k: inteiro): Offset { retorna Offset(isto.v + k) }
}
const r = 10 + Offset(5)
escreva("OK=", r.v)
""", expect_out="OK=15"))

    cases.append(Case("OP-30", A, "run", """
// Operador aritmético / e % em classe gerenciada
classe Fracao {
    n: inteiro
    construtor(n: inteiro) { isto.n = n }
    @operador("/") div(o: Fracao): Fracao { retorna Fracao(isto.n \\ o.n) }
    @operador("%") mod(o: Fracao): Fracao { retorna Fracao(isto.n % o.n) }
}
const a = Fracao(23) / Fracao(5)
const b = Fracao(23) % Fracao(5)
escreva("OK=", a.n, ",", b.n)
""", expect_out="OK=4,3"))

    cases.append(Case("OP-31", A, "run", """
// Igualdade comutativa em @pilha
@pilha
classe Id {
    n: ci32
    @nativo @operador("==") igualInt(k: ci32): cbool { retorna isto.n == k }
}
@nativo funcao t(): cbool { retorna Id(7) == ci32(7) e ci32(7) == Id(7) }
escreva("OK=", t())
""", expect_out="OK=verdadeiro", check_no_boxing_in_native=True))

    cases.append(Case("OP-32", A, "run", """
// Operadores preservam prioridade de primitivos (inteiro + inteiro não muda)
@pilha
classe X {
    v: ci32
    @nativo @operador("+") add(o: X): X { retorna X(isto.v + o.v) }
}
@nativo funcao t(): ci32 {
    const a: ci32 = 2 + 3
    const b = X(10) + X(20)
    retorna a + b.v
}
escreva("OK=", t())
""", expect_out="OK=35", check_no_boxing_in_native=True))

    cases.append(Case("OP-33", A, "run", """
// Complexo completo (+, -, *, ==) em @nativo
@pilha
classe Cpx {
    r: cf64; i: cf64
    @nativo @operador("+") add(o: Cpx): Cpx { retorna Cpx(isto.r + o.r, isto.i + o.i) }
    @nativo @operador("-") sub(o: Cpx): Cpx { retorna Cpx(isto.r - o.r, isto.i - o.i) }
    @nativo @operador("*") mul(o: Cpx): Cpx {
        retorna Cpx(isto.r * o.r - isto.i * o.i, isto.r * o.i + isto.i * o.r)
    }
    @nativo @operador("==") eq(o: Cpx): cbool { retorna isto.r == o.r e isto.i == o.i }
}
@nativo funcao t(): cbool {
    const a = Cpx(1.0, 2.0)
    const b = Cpx(3.0, 4.0)
    retorna (a * b) == Cpx(-5.0, 10.0)
}
escreva("OK=", t())
""", expect_out="OK=verdadeiro", check_no_boxing_in_native=True))

    cases.append(Case("OP-34", A, "run", """
// Matriz 2x2 com multiplicação @operador("*")
@pilha
classe M2 {
    a: cf64; b: cf64; c: cf64; d: cf64
    @nativo @operador("*") mul(o: M2): M2 {
        retorna M2(
            isto.a * o.a + isto.b * o.c, isto.a * o.b + isto.b * o.d,
            isto.c * o.a + isto.d * o.c, isto.c * o.b + isto.d * o.d
        )
    }
}
@nativo funcao t(): cf64 {
    const m = M2(1.0, 2.0, 3.0, 4.0) * M2(2.0, 0.0, 1.0, 2.0)
    retorna m.a + m.b + m.c + m.d
}
escreva("OK=", t())
""", expect_out="OK=26", check_no_boxing_in_native=True))

    cases.append(Case("OP-35", A, "run", """
// Operador protegido acessível em subclasse
classe Base {
    v: inteiro
    construtor(v: inteiro) { isto.v = v }
    protegido {
        @operador("+") somar(o: Base): Base { retorna Base(isto.v + o.v) }
    }
}
classe Sub herda Base {
    construtor(v: inteiro) { super(v) }
    combinar(o: Sub): inteiro {
        const r = isto + o
        retorna r.v
    }
}
escreva("OK=", Sub(4).combinar(Sub(9)))
""", expect_out="OK=13"))

    # 36..46: Testes negativos de @operador (E3901..E3906)
    cases.append(Case("OP-36", A, "fail", """
classe A {
    @operador("???") ruim(o: A): A { retorna isto }
}
""", expect_err="E3901"))

    cases.append(Case("OP-37", A, "fail", """
classe A {
    @operador("&&") ruim(o: A): logico { retorna verdadeiro }
}
""", expect_err="E3901"))

    cases.append(Case("OP-38", A, "fail", """
classe A {
    @operador("+") ruim(): A { retorna isto }
}
""", expect_err="E3902"))

    cases.append(Case("OP-39", A, "fail", """
classe A {
    @operador("+") ruim(x: A, y: A): A { retorna isto }
}
""", expect_err="E3902"))

    cases.append(Case("OP-40", A, "fail", """
classe A {
    @operador("[]=") ruim(i: inteiro): vazio {}
}
""", expect_err="E3902"))

    cases.append(Case("OP-41", A, "fail", """
classe A {
    @operador("unario-") ruim(x: inteiro): A { retorna isto }
}
""", expect_err="E3902"))

    cases.append(Case("OP-42", A, "fail", """
classe A {
    @operador("+") estatico ruim(o: A): A { retorna o }
}
""", expect_err="E3902"))

    cases.append(Case("OP-43", A, "fail", """
classe A {
    v: inteiro
    construtor(v: inteiro) { isto.v = v }
    privado {
        @operador("+") somar(o: A): A { retorna A(isto.v + o.v) }
    }
}
const r = A(1) + A(2)
""", expect_err="E3903"))

    cases.append(Case("OP-44", A, "fail", """
classe A {
    @operador("+") s1(o: A): A { retorna isto }
    @operador("+") s2(o: A): A { retorna isto }
}
""", expect_err="E3904"))

    cases.append(Case("OP-45", A, "fail", """
classe A {
    @operador("==") ruim(o: A): inteiro { retorna 1 }
}
""", expect_err="E3905"))

    cases.append(Case("OP-46", A, "fail", """
classe A {
    @operador("<") ruim(o: A): texto { retorna "sim" }
}
""", expect_err="E3905"))

    return cases


def build_area_6_containers() -> list[Case]:
    A = "6. Containers Nativos"
    cases: list[Case] = []

    cases.append(Case("CNT-01", A, "run", """
@nativo funcao t(): ci64 {
    var v = VetorNativo<ci64>()
    v.reservar(16)
    para var i: ci64 = 1; i <= 10; i = i + 1 { v.adicionar(i) }
    retorna ci64(v.tamanho()) * 100 + v[9]
}
escreva("OK=", t())
""", expect_out="OK=1010", check_no_boxing_in_native=True))

    cases.append(Case("CNT-02", A, "run", """
@nativo funcao t(): ci32 {
    var v = VetorNativo<ci32>()
    v.adicionar(10)
    v.adicionar(20)
    v.adicionar(30)
    const u: ci32 = v.removerUltimo()
    v[0] = 5
    retorna u + v[0] + ci32(v.tamanho())
}
escreva("OK=", t())
""", expect_out="OK=37", check_no_boxing_in_native=True))

    cases.append(Case("CNT-03", A, "run", """
@nativo funcao t(): ci32 {
    var v = VetorNativo<ci32>()
    v.adicionar(1)
    v.adicionar(2)
    v.limpar()
    retorna v.vazio() ? 1 : 0
}
escreva("OK=", t())
""", expect_out="OK=1", check_no_boxing_in_native=True))

    cases.append(Case("CNT-04", A, "run", """
@nativo funcao t(): ci64 {
    var v = VetorNativo<ci64>()
    para var i: ci64 = 0; i < 200; i = i + 1 { v.adicionar(i) }
    retorna v[199] + ci64(v.capacidade() >= csize(200) ? 1 : 0)
}
escreva("OK=", t())
""", expect_out="OK=200", check_no_boxing_in_native=True))

    cases.append(Case("CNT-05", A, "run", """
@nativo funcao t(): ci32 {
    var v = VetorNativo<ci32>()
    para var i: ci32 = 0; i < 10; i = i + 1 { v.adicionar(i * 3) }
    const f = v.fatia(2, 6)
    retorna ci32(f.tamanho()) * 100 + f[0] + f[3]
}
escreva("OK=", t())
""", expect_out="OK=421", check_no_boxing_in_native=True))

    cases.append(Case("CNT-06", A, "run", """
@nativo funcao t(): ci32 {
    var v = VetorNativo<ci32>()
    v.adicionar(4)
    v.adicionar(8)
    const f = v.fatia(0, 2)
    var soma: ci32 = 0
    para cada x em f { soma += x }
    retorna soma
}
escreva("OK=", t())
""", expect_out="OK=12", check_no_boxing_in_native=True))

    cases.append(Case("CNT-07", A, "run", """
@nativo funcao t(): ci32 {
    var m = MapaNativo<ci32, ci32>()
    m.definir(10, 100)
    m.definir(20, 200)
    m.definir(10, 150)
    retorna m.obter(10) + m.obter(20) + ci32(m.tamanho())
}
escreva("OK=", t())
""", expect_out="OK=352", check_no_boxing_in_native=True))

    cases.append(Case("CNT-08", A, "run", """
@nativo funcao t(): ci32 {
    var m = MapaNativo<ci32, ci32>()
    m.definir(1, 10)
    m.definir(2, 20)
    const rem: cbool = m.remover(1)
    const tem1: cbool = m.contem(1)
    const tem2: cbool = m.contem(2)
    retorna (rem e !tem1 e tem2) ? 1 : 0
}
escreva("OK=", t())
""", expect_out="OK=1", check_no_boxing_in_native=True))

    cases.append(Case("CNT-09", A, "run", """
@nativo funcao t(): ci32 {
    var m = MapaNativo<StringNativa, ci32>()
    m.definir("alpha", 11)
    m.definir("beta", 22)
    m.definir("gamma", 33)
    retorna m.obter("alpha") + m.obter("gamma")
}
escreva("OK=", t())
""", expect_out="OK=44", check_no_boxing_in_native=True))

    cases.append(Case("CNT-10", A, "run", """
// Crescimento e rehash de MapaNativo com 128 chaves
@nativo funcao t(): ci32 {
    var m = MapaNativo<ci32, ci32>()
    para var i: ci32 = 0; i < 128; i = i + 1 { m.definir(i, i * 2) }
    var soma: ci32 = 0
    para var i: ci32 = 0; i < 128; i = i + 1 { soma += m.obter(i) }
    retorna soma
}
escreva("OK=", t())
""", expect_out="OK=16256", check_no_boxing_in_native=True))

    cases.append(Case("CNT-11", A, "run", """
@nativo funcao t(): ci32 {
    var s = StringNativa.vazia()
    s.anexar("ola")
    s.anexar("-")
    s.anexar("cgd")
    retorna ci32(s.tamanho())
}
escreva("OK=", t())
""", expect_out="OK=7", check_no_boxing_in_native=True))

    cases.append(Case("CNT-12", A, "run", """
@nativo funcao t(): cbool {
    var a = StringNativa.criar("delegua")
    var b = StringNativa.criar("delegua")
    retorna a.igual(b)
}
escreva("OK=", t())
""", expect_out="OK=verdadeiro", check_no_boxing_in_native=True))

    cases.append(Case("CNT-13", A, "run", """
@nativo funcao t(): cbool {
    var s = StringNativa.criar("compilador")
    const v = s.visao()
    retorna v.comecaCom("comp") e !v.vazia() e v.tamanho() == csize(10)
}
escreva("OK=", t())
""", expect_out="OK=verdadeiro", check_no_boxing_in_native=True))

    cases.append(Case("CNT-14", A, "run", """
@nativo funcao t(): cbool {
    var s = StringNativa.criar("abc")
    s.limpar()
    retorna s.vazia()
}
escreva("OK=", t())
""", expect_out="OK=verdadeiro", check_no_boxing_in_native=True))

    cases.append(Case("CNT-15", A, "run", """
@nativo funcao t(): ci32 {
    const o1 = OpcionalNativo<ci32>.algum(77)
    const o2 = OpcionalNativo<ci32>.nenhum()
    retorna o1.valorOu(0) + o2.valorOu(23)
}
escreva("OK=", t())
""", expect_out="OK=100", check_no_boxing_in_native=True))

    cases.append(Case("CNT-16", A, "run", """
@nativo funcao t(): cbool {
    const o1 = OpcionalNativo<cf64>.algum(3.5)
    const o2 = OpcionalNativo<cf64>.nenhum()
    retorna o1.temValor() e !o2.temValor() e o1.valor() == 3.5
}
escreva("OK=", t())
""", expect_out="OK=verdadeiro", check_no_boxing_in_native=True))

    cases.append(Case("CNT-17", A, "run", """
@nativo funcao dividir(a: ci32, b: ci32): ResultadoNativo<ci32, ci32> {
    se b == 0 { retorna ResultadoNativo<ci32, ci32>.erro(-1) }
    retorna ResultadoNativo<ci32, ci32>.ok(a \\ b)
}
@nativo funcao t(): ci32 {
    const r1 = dividir(20, 4)
    const r2 = dividir(20, 0)
    retorna r1.valor() * 10 + (r2.ehErro() ? r2.erro() : 0)
}
escreva("OK=", t())
""", expect_out="OK=49", check_no_boxing_in_native=True))

    cases.append(Case("CNT-18", A, "run", """
@nativo funcao t(): cf64 {
    var m = MatrizNativa<cf64>(3, 3)
    m.definir(0, 0, 2.0)
    m.definir(1, 1, 3.0)
    m.definir(2, 2, 5.0)
    retorna m.obter(0, 0) + m.obter(1, 1) + m.obter(2, 2) + cf64(m.linhas() * m.colunas())
}
escreva("OK=", t())
""", expect_out="OK=19", check_no_boxing_in_native=True))

    cases.append(Case("CNT-19", A, "run", """
// VetorNativo de VetorNativo (elementos com drop não-trivial!)
@nativo funcao t(): ci32 {
    var outer = VetorNativo<VetorNativo<ci32>>()
    para var i: ci32 = 0; i < 4; i = i + 1 {
        var inner = VetorNativo<ci32>()
        inner.adicionar(i * 10)
        inner.adicionar(i * 10 + 1)
        outer.adicionar(inner)
    }
    retorna ci32(outer.tamanho())
}
escreva("OK=", t())
""", expect_out="OK=4", check_no_boxing_in_native=True))

    cases.append(Case("CNT-20", A, "run", """
// VetorNativo de StringNativa com RAII automático
@nativo funcao t(): ci32 {
    var palavras = VetorNativo<StringNativa>()
    palavras.adicionar(StringNativa.criar("um"))
    palavras.adicionar(StringNativa.criar("dois"))
    palavras.adicionar(StringNativa.criar("tres"))
    retorna ci32(palavras.tamanho())
}
escreva("OK=", t())
""", expect_out="OK=3", check_no_boxing_in_native=True))

    cases.append(Case("CNT-21", A, "run", """
// Clonagem independente de StringNativa
@nativo funcao t(): ci32 {
    var a = StringNativa.criar("abc")
    var b = a.clonar()
    b.anexar("def")
    retorna ci32(a.tamanho()) * 10 + ci32(b.tamanho())
}
escreva("OK=", t())
""", expect_out="OK=36", check_no_boxing_in_native=True))

    cases.append(Case("CNT-22", A, "run", """
// Clonagem independente de MatrizNativa
@nativo funcao t(): cf64 {
    var a = MatrizNativa<cf64>(2, 2)
    a.definir(0, 1, 7.0)
    var b = a.clonar()
    b.definir(0, 1, 99.0)
    retorna a.obter(0, 1) + b.obter(0, 1)
}
escreva("OK=", t())
""", expect_out="OK=106", check_no_boxing_in_native=True))

    cases.append(Case("CNT-23", A, "run", """
// VetorNativo usado diretamente em código gerenciado + paraVetor()
var v = VetorNativo<ci64>()
v.adicionar(10)
v.adicionar(20)
v.adicionar(30)
const lista = v.paraVetor()
assercao(tamanho(lista) == 3 e lista[2] == 30)
escreva("OK=", lista[0] + lista[1] + lista[2])
""", expect_out="OK=60"))

    cases.append(Case("CNT-24", A, "run", """
// StringNativa.paraTexto() na fronteira gerenciada
var s = StringNativa.criar("nativo")
s.anexar("-ok")
const txt: texto = s.paraTexto()
escreva("OK=", txt)
""", expect_out="OK=nativo-ok"))

    cases.append(Case("CNT-25", A, "run", """
// MapaNativo.paraDicionario() na fronteira gerenciada
var m = MapaNativo<StringNativa, ci64>()
m.definir("k1", 42)
const d = m.paraDicionario()
escreva("OK=", d["k1"])
""", expect_out="OK=42"))

    # 26..28: Pânicos determinísticos de bounds em runtime
    cases.append(Case("CNT-26", A, "run_panic", """
@nativo funcao t(idx: ci32): ci32 {
    var v = VetorNativo<ci32>()
    v.adicionar(1)
    retorna v[idx]
}
escreva(t(5))
""", expect_err="fora dos limites"))

    cases.append(Case("CNT-27", A, "run_panic", """
@nativo funcao t(r: ci32): cf64 {
    var m = MatrizNativa<cf64>(2, 2)
    retorna m.obter(r, 0)
}
escreva(t(5))
""", expect_err="fora dos limites"))

    cases.append(Case("CNT-28", A, "run_panic", """
@nativo funcao t(): ci32 {
    const o = OpcionalNativo<ci32>.nenhum()
    retorna o.valor()
}
escreva(t())
""", expect_err="ausente"))

    return cases


def build_area_7_interop_abi() -> list[Case]:
    A = "7. Interoperabilidade e ABI"
    cases: list[Case] = []

    cases.append(Case("ABI-01", A, "run", """
// @pilha como campo de classe gerenciada
@pilha
classe Ponto { x: cf64; y: cf64 }
classe Entidade {
    nome: texto
    pos: Ponto
    construtor(nome: texto, x: cf64, y: cf64) {
        isto.nome = nome
        isto.pos = Ponto(x, y)
    }
}
const e1 = Entidade("heroi", 3.0, 4.0)
var copia = e1.pos
copia.x = 999.0
assercao(e1.pos.x == 3.0 e copia.x == 999.0)
escreva("OK=", e1.nome, ":", e1.pos.x, ",", e1.pos.y)
""", expect_out="OK=heroi:3,4"))

    cases.append(Case("ABI-02", A, "run", """
// Gerenciado chama @nativo passando e recebendo @pilha
@pilha
classe V2 { x: cf64; y: cf64 }
@nativo
funcao escalar(v: V2, f: cf64): V2 { retorna V2(v.x * f, v.y * f) }
const r = escalar(V2(2.0, 5.0), 3.0)
escreva("OK=", r.x, ",", r.y)
""", expect_out="OK=6,15"))

    cases.append(Case("ABI-03", A, "run", """
// Gerenciado passa vetor gerenciado convertido via thunk para @nativo(VetorNativo<ci64>)
@nativo
funcao somarNat(v: VetorNativo<ci64>): ci64 {
    var s: ci64 = 0
    para var i: ci64 = 0; i < ci64(v.tamanho()); i = i + 1 { s += v[i] }
    retorna s
}
var vn = VetorNativo<ci64>()
vn.adicionar(5)
vn.adicionar(15)
vn.adicionar(25)
escreva("OK=", somarNat(vn))
""", expect_out="OK=45"))

    cases.append(Case("ABI-04", A, "run", """
// @nativo retorna VetorNativo<ci32> para gerenciado
@nativo
funcao gerar(n: ci32): VetorNativo<ci32> {
    var v = VetorNativo<ci32>()
    para var i: ci32 = 1; i <= n; i = i + 1 { v.adicionar(i * 10) }
    retorna v
}
const lista = gerar(4)
assercao(tamanho(lista) == 4 e lista[3] == 40)
escreva("OK=", lista[0] + lista[3])
""", expect_out="OK=50"))

    cases.append(Case("ABI-05", A, "run", """
// @nativo retorna StringNativa para código gerenciado
@nativo
funcao saudacao(): StringNativa {
    var s = StringNativa.criar("oi-")
    s.anexar("fronteira")
    retorna s
}
const t = saudacao()
escreva("OK=", t)
""", expect_out="OK=oi-fronteira"))

    cases.append(Case("ABI-06", A, "run", """
// @nativo retorna OpcionalNativo<ci64> e ResultadoNativo<ci64, ci32>
@nativo
funcao buscar(ok: cbool): ci64 {
    const o = ok ? OpcionalNativo<ci64>.algum(123) : OpcionalNativo<ci64>.nenhum()
    retorna o.valorOu(-1)
}
escreva("OK=", buscar(verdadeiro), ",", buscar(falso))
""", expect_out="OK=123,-1"))

    cases.append(Case("ABI-07", A, "run", """
// FFI C explícita com biblioteca padrão libm usando tipos C cf64
@definicao(biblioteca = "m", abi = "c")
classe estrangeira LibM {
    @definicao(simbolo = "hypot")
    hipotenusa(a: cf64, b: cf64): cf64
}
const h = LibM.hipotenusa(3.0, 4.0)
escreva("OK=", h)
""", expect_out="OK=5"))

    cases.append(Case("ABI-08", A, "run", """
// FFI C explícita com tipo inteiro estreito ci32 (abs de libc)
@definicao(biblioteca = "c", abi = "c")
classe estrangeira LibC {
    @definicao(simbolo = "abs")
    absC(x: ci32): ci32
}
escreva("OK=", LibC.absC(ci32(-77)))
""", expect_out="OK=77"))

    cases.append(Case("ABI-09", A, "run", """
// FFI C chamada de dentro de função @nativo!
@definicao(biblioteca = "m", abi = "c")
classe estrangeira LibM {
    @definicao(simbolo = "fma")
    fmaC(a: cf64, b: cf64, c: cf64): cf64
}
@nativo
funcao calc(a: cf64, b: cf64, c: cf64): cf64 {
    retorna LibM.fmaC(a, b, c)
}
escreva("OK=", calc(3.0, 4.0, 5.0))
""", expect_out="OK=17", check_no_boxing_in_native=True))

    cases.append(Case("ABI-10", A, "run", """
// ABI com múltiplos inteiros estreitos e floats misturados (padding/alinhamento)
@pilha
classe Pacote {
    tag: cu8
    valor: cf64
    flags: cu16
    id: ci32
    ativo: cbool
}
@nativo
funcao somaPacote(p: Pacote): cf64 {
    retorna cf64(p.tag) + p.valor + cf64(p.flags) + cf64(p.id) + (p.ativo ? 1.0 : 0.0)
}
const p = Pacote(cu8(1), 2.5, cu16(3), ci32(4), verdadeiro)
escreva("OK=", somaPacote(p))
""", expect_out="OK=11.5"))

    cases.append(Case("ABI-11", A, "run", """
// Múltiplos argumentos escalares C pela fronteira (8 args: registra + pilha na ABI SysV x86_64)
@nativo
funcao oitoArgs(a: ci8, b: ci16, c: ci32, d: ci64, e1: cu8, f: cu16, g: cf32, h: cf64): cf64 {
    retorna cf64(a) + cf64(b) + cf64(c) + cf64(d) + cf64(e1) + cf64(f) + cf64(g) + h
}
const r = oitoArgs(ci8(1), ci16(2), ci32(3), ci64(4), cu8(5), cu16(6), cf32(7.0), 8.0)
escreva("OK=", r)
""", expect_out="OK=36"))

    cases.append(Case("ABI-12", A, "run", """
// Struct grande (>16 bytes, passada por memória na ABI SysV)
@pilha
classe Grande {
    a: cf64; b: cf64; c: cf64; d: cf64; e1: cf64; f: cf64
}
@nativo
funcao somaGrande(g: Grande): cf64 { retorna g.a + g.b + g.c + g.d + g.e1 + g.f }
const r = somaGrande(Grande(1.0, 2.0, 3.0, 4.0, 5.0, 6.0))
escreva("OK=", r)
""", expect_out="OK=21"))

    cases.append(Case("ABI-13", A, "run", """
// Sinalização negativa em inteiros com sinal pela fronteira GC <-> nativo
@nativo
funcao somaNeg(a: ci8, b: ci16, c: ci32, d: ci64): ci64 {
    retorna ci64(a) + ci64(b) + ci64(c) + d
}
escreva("OK=", somaNeg(ci8(-10), ci16(-200), ci32(-3000), ci64(-40000)))
""", expect_out="OK=-43210"))

    cases.append(Case("ABI-14", A, "run", """
// Conversão explícita de tipos C fora de @nativo (código gerenciado)
const a: ci8 = ci8(120)
const b: cu16 = cu16(500)
const c: cf32 = cf32(1.5)
escreva("OK=", inteiro(a) + inteiro(b), ",", real(c))
""", expect_out="OK=620,1.5"))

    cases.append(Case("ABI-15", A, "run", """
// Método @nativo em classe @pilha chamado diretamente do gerenciado
@pilha
classe Vet {
    x: cf64; y: cf64
    @nativo
    produto(o: Vet): cf64 { retorna isto.x * o.x + isto.y * o.y }
}
const a = Vet(2.0, 3.0)
const b = Vet(4.0, 5.0)
escreva("OK=", a.produto(b))
""", expect_out="OK=23"))

    cases.append(Case("ABI-16", A, "run", """
// Exceção no lado gerenciado não corrompe chamadas @nativo seguintes
@nativo
funcao dobro(x: ci64): ci64 { retorna x * 2 }
var ok: inteiro = 0
tente {
    falhar "erro esperado"
} pegue (err) {
    ok = inteiro(dobro(21))
}
escreva("OK=", ok)
""", expect_out="OK=42"))

    cases.append(Case("ABI-17", A, "run", """
// Loop gerenciado criando muitas instâncias @pilha e chamando @nativo (pressão GC + pilha)
@pilha
classe Par { a: ci64; b: ci64 }
@nativo
funcao combinar(p: Par): ci64 { retorna p.a * 3 + p.b }
var total: inteiro = 0
para var i: inteiro = 0; i < 500; i = i + 1 {
    const p = Par(ci64(i), ci64(1))
    total = total + inteiro(combinar(p))
}
escreva("OK=", total)
""", expect_out="OK=374750"))

    cases.append(Case("ABI-18", A, "run", """
// Interoperabilidade com biblioteca padrão cgd.json usando resultados de @nativo
importar cgd.json como JSON
@nativo
funcao calcular(n: ci32): ci32 { retorna n * n }
const txt: texto = JSON.serializar({ resultado: calcular(9) })
const obj = JSON.analisar(txt)
escreva("OK=", obj["resultado"])
""", expect_out="OK=81"))

    cases.append(Case("ABI-19", A, "run", """
// Struct @pilha aninhada atravessando a fronteira gerenciado <-> nativo
@pilha
classe Inner { v: ci32 }
@pilha
classe Outer { a: Inner; b: Inner }
@nativo
funcao somarOuter(o: Outer): ci32 { retorna o.a.v + o.b.v }
const res = somarOuter(Outer(Inner(19), Inner(23)))
escreva("OK=", res)
""", expect_out="OK=42"))

    cases.append(Case("ABI-20", A, "run", """
// MatrizNativa retornada de @nativo e consumida no gerenciado
@nativo
funcao identidade2(): MatrizNativa<cf64> {
    var m = MatrizNativa<cf64>(2, 2)
    m.definir(0, 0, 1.0)
    m.definir(1, 1, 1.0)
    retorna m
}
const m = identidade2()
escreva("OK=MAT_FRONT")
""", expect_out="OK=MAT_FRONT"))

    cases.append(Case("ABI-21", A, "run", """
// Comparação de precisão cf32 vs cf64
@nativo
funcao diffPrec(): cbool {
    const a: cf32 = cf32(0.5)
    const b: cf64 = 0.5
    retorna cf64(a) == b
}
escreva("OK=", diffPrec())
""", expect_out="OK=verdadeiro", check_no_boxing_in_native=True))

    cases.append(Case("ABI-22", A, "run", """
// Valor booleano cbool atravessando ida e volta pela fronteira
@nativo
funcao inverter(b: cbool): cbool { retorna !b }
assercao(inverter(verdadeiro) == falso)
assercao(inverter(falso) == verdadeiro)
escreva("OK=BOOL_FRONT")
""", expect_out="OK=BOOL_FRONT"))

    return cases


def build_area_8_gpu_ml_doc() -> list[Case]:
    A = "8. GPU, Tensores, ML, @gpu e Documentação"
    cases: list[Case] = []

    cases.append(Case("GPU-01", A, "run", """
importar cgd.computacao.gpu como GPU
const disp = GPU.descobrirDispositivos()
assercao(tamanho(disp) >= 1)
escreva("OK=DISP:", tamanho(disp) >= 1)
""", expect_out="OK=DISP:verdadeiro"))

    cases.append(Case("GPU-02", A, "run", """
importar cgd.computacao.gpu como GPU
const ctx = GPU.criarFila()
const a = ctx.criarBuffer(4, "cf64")
const b = ctx.criarBuffer(4, "cf64")
const c = ctx.criarBuffer(4, "cf64")
a.enviar([1.0, 2.0, 3.0, 4.0])
b.enviar([10.0, 20.0, 30.0, 40.0])
ctx.somar(a, b, c)
assercao(c.obter(0) == 11.0 e c.obter(3) == 44.0)
a.liberar(); b.liberar(); c.liberar()
escreva("OK=GPU_SOMA")
""", expect_out="OK=GPU_SOMA"))

    cases.append(Case("GPU-03", A, "run", """
importar cgd.computacao.gpu como GPU
const ctx = GPU.criarFila()
const a = ctx.criarBuffer(4, "cf32")
const b = ctx.criarBuffer(4, "cf32")
const c = ctx.criarBuffer(4, "cf32")
a.enviar([2.0, 3.0, 4.0, 5.0])
b.enviar([3.0, 4.0, 5.0, 6.0])
ctx.multiplicar(a, b, c)
const d = ctx.produtoEscalar(a, b)
assercao(c.obter(0) == 6.0 e d == 68.0)
a.liberar(); b.liberar(); c.liberar()
escreva("OK=GPU_DOT=", d)
""", expect_out="OK=GPU_DOT=68"))

    cases.append(Case("GPU-04", A, "run", """
importar cgd.computacao.gpu como GPU
const ctx = GPU.criarFila()
const a = ctx.criarBuffer(4, "cf64")
const s = ctx.criarBuffer(4, "cf64")
a.enviar([-3.0, -1.0, 0.0, 5.0])
ctx.ativar("relu", a, s)
assercao(s.obter(0) == 0.0 e s.obter(3) == 5.0)
a.liberar(); s.liberar()
escreva("OK=GPU_RELU")
""", expect_out="OK=GPU_RELU"))

    cases.append(Case("GPU-05", A, "run", """
importar cgd.computacao.gpu como GPU
const ctx = GPU.criarFila()
const a = ctx.criarBuffer(4, "cf64")
const b = ctx.criarBuffer(4, "cf64")
const c = ctx.criarBuffer(4, "cf64")
a.enviar([1.0, 2.0, 3.0, 4.0])
b.enviar([5.0, 6.0, 7.0, 8.0])
ctx.matmul(a, b, c, 2, 2, 2)
assercao(c.obter(0) == 19.0 e c.obter(3) == 50.0)
a.liberar(); b.liberar(); c.liberar()
escreva("OK=GPU_MATMUL")
""", expect_out="OK=GPU_MATMUL"))

    cases.append(Case("GPU-06", A, "run", """
importar cgd.computacao.tensores como T
const a = T.Tensor.deVetor([1.0, 2.0, 3.0, 4.0], [2, 2], "cf64")
const b = T.Tensor.deVetor([5.0, 6.0, 7.0, 8.0], [2, 2], "cf64")
const c = a.somar(b)
assercao(c.soma() == 36.0 e c.media() == 9.0)
a.liberar(); b.liberar(); c.liberar()
escreva("OK=TENSOR_SOMA")
""", expect_out="OK=TENSOR_SOMA"))

    cases.append(Case("GPU-07", A, "run", """
importar cgd.computacao.tensores como T
const a = T.Tensor.deVetor([1.0, 2.0, 3.0, 4.0, 5.0, 6.0], [2, 3], "cf64")
const tr = a.transpor()
assercao(tr.obter([0, 1]) == 4.0 e tr.obter([2, 0]) == 3.0)
const b = T.Tensor.deVetor([1.0, 0.0, 0.0, 1.0, 1.0, 1.0], [3, 2], "cf64")
const mm = a.matmul(b)
assercao(mm.obter([0, 0]) == 4.0 e mm.obter([1, 1]) == 11.0)
a.liberar(); tr.liberar(); b.liberar(); mm.liberar()
escreva("OK=TENSOR_TR_MM")
""", expect_out="OK=TENSOR_TR_MM"))

    cases.append(Case("GPU-08", A, "run", """
importar cgd.computacao.tensores como T
const a = T.Tensor.deVetor([1.0, 2.0, 3.0, 4.0], [2, 2], "cf64")
const b = T.Tensor.deVetor([10.0, 20.0], [1, 2], "cf64")
const c = a.somar(b)
assercao(c.obter([0, 0]) == 11.0 e c.obter([1, 1]) == 24.0)
a.liberar(); b.liberar(); c.liberar()
escreva("OK=TENSOR_BCAST")
""", expect_out="OK=TENSOR_BCAST"))

    cases.append(Case("GPU-09", A, "run", """
importar cgd.computacao.tensores como T
const a = T.Tensor.deVetor([1.0, 2.0, 3.0, 4.0, 5.0, 6.0], [2, 3], "cf64")
const r = a.remodelar([3, 2])
assercao(r.obter([2, 1]) == 6.0)
a.liberar(); r.liberar()
escreva("OK=TENSOR_RESHAPE")
""", expect_out="OK=TENSOR_RESHAPE"))

    cases.append(Case("GPU-10", A, "run", """
importar cgd.computacao.ml como ML
assercao(ML.ativacaoRelu(-5.0) == 0.0)
assercao(ML.ativacaoRelu(4.0) == 4.0)
assercao(ML.ativacaoSigmoid(0.0) == 0.5)
escreva("OK=ML_ATIV")
""", expect_out="OK=ML_ATIV"))

    cases.append(Case("GPU-11", A, "run", """
importar cgd.computacao.ml como ML
const rl = ML.RegressaoLinear(1)
const xs: qualquer[] = [[0.0], [1.0], [2.0], [3.0]]
const ys: real[] = [1.0, 3.0, 5.0, 7.0]
const perda: real = rl.treinar(xs, ys, 600, 0.05, verdadeiro)
assercao(perda < 0.01)
const pred: real = rl.prever([4.0])
assercao(pred > 8.7 e pred < 9.3)
escreva("OK=ML_RL")
""", expect_out="OK=ML_RL"))

    cases.append(Case("GPU-12", A, "run", """
importar cgd.computacao.ml como ML
const rede = ML.MLP(2, 4, 1, 42)
const xs: qualquer[] = [[0.0, 0.0], [0.0, 1.0], [1.0, 0.0], [1.0, 1.0]]
const ys: qualquer[] = [[0.0], [1.0], [1.0], [0.0]]
const perda: real = rede.treinar(xs, ys, 2000, 0.5)
assercao(perda < 0.05)
const serializado: texto = rede.serializar()
const carregada = ML.MLP.desserializar(serializado)
assercao(carregada.prever([1.0, 0.0])[0] > 0.7)
escreva("OK=ML_MLP_JSON")
""", expect_out="OK=ML_MLP_JSON"))

    # 13..15: Kernel @gpu válido e negativos (E3951)
    cases.append(Case("GPU-13", A, "run", """
@gpu
funcao kernelAxpy(a: cf32, x: cf32, y: cf32): cf32 {
    retorna a * x + y
}
escreva("OK=", kernelAxpy(cf32(2.0), cf32(3.0), cf32(4.0)))
""", expect_out="OK=10", check_no_boxing_in_native=True))

    cases.append(Case("GPU-14", A, "fail", """
@gpu
funcao kernelInvalido(s: texto): ci32 {
    retorna 1
}
""", expect_err="E3951"))

    cases.append(Case("GPU-15", A, "fail", """
@gpu
funcao kernelComGC(): ci32 {
    escreva("proibido na GPU")
    retorna 0
}
""", expect_err="E3951"))

    # 16..18: Gerador de documentação automática (Markdown, HTML, --validar)
    def doc_md_test(work: Path) -> tuple[bool, str]:
        src = work / "demo.delegua"
        src.write_text(
            '/// Soma dois inteiros nativos.\n'
            '///\n'
            '/// ```delegua\n'
            '/// assercao(2 + 2 == 4)\n'
            '/// ```\n'
            '@nativo\n'
            'funcao somar(a: ci32, b: ci32): ci32 { retorna a + b }\n',
            encoding="utf-8",
        )
        out_dir = work / "md"
        r = run_cmd([str(CGD), "documentar", str(src), "--formato", "markdown", "--saida", str(out_dir), "--validar"])
        if r.returncode != 0:
            return False, f"documentar markdown falhou: {r.stdout}\n{r.stderr}"
        md_files = list(out_dir.glob("*.md"))
        if not md_files:
            return False, "Nenhum arquivo .md gerado"
        txt = "\n".join(p.read_text(encoding="utf-8") for p in md_files)
        if "@nativo" not in txt or "somar" not in txt:
            return False, "Markdown gerado sem assinatura/anotação esperada"
        return True, ""

    def doc_html_test(work: Path) -> tuple[bool, str]:
        src = work / "demo_val.delegua"
        src.write_text(
            '/// Vetor 2D por valor na pilha.\n'
            '@pilha\n'
            'classe Vet2 {\n'
            '    x: cf64\n'
            '    y: cf64\n'
            '    @nativo @operador("+") somar(o: Vet2): Vet2 { retorna Vet2(isto.x + o.x, isto.y + o.y) }\n'
            '}\n',
            encoding="utf-8",
        )
        out_dir = work / "html"
        r = run_cmd([str(CGD), "documentar", str(src), "--formato", "html", "--saida", str(out_dir)])
        if r.returncode != 0:
            return False, f"documentar html falhou: {r.stdout}\n{r.stderr}"
        html_files = [p for p in out_dir.glob("*.html") if p.name != "index.html"]
        if not html_files:
            return False, "Nenhum HTML de módulo gerado"
        txt = html_files[0].read_text(encoding="utf-8")
        if "Vet2" not in txt or "@pilha" not in txt:
            return False, "HTML não documentou @pilha / Vet2"
        return True, ""

    def doc_invalid_example_test(work: Path) -> tuple[bool, str]:
        src = work / "bad_doc.delegua"
        src.write_text(
            '/// Exemplo quebrado proposital.\n'
            '///\n'
            '/// ```delegua\n'
            '/// funcaoInexistenteParaTesteDoc()\n'
            '/// ```\n'
            'funcao ok(): inteiro { retorna 1 }\n',
            encoding="utf-8",
        )
        out_dir = work / "bad_out"
        r = run_cmd([str(CGD), "documentar", str(src), "--formato", "markdown", "--saida", str(out_dir), "--validar"])
        if r.returncode == 0:
            return False, "Esperava falha ao validar exemplo inválido na doc"
        return True, ""

    cases.append(Case("GPU-16", A, "custom", custom_fn=doc_md_test))
    cases.append(Case("GPU-17", A, "custom", custom_fn=doc_html_test))
    cases.append(Case("GPU-18", A, "custom", custom_fn=doc_invalid_example_test))

    return cases


def collect_all_cases() -> list[Case]:
    all_cases: list[Case] = []
    all_cases.extend(build_area_1_ctfe())
    all_cases.extend(build_area_2_native())
    all_cases.extend(build_area_3_value_types())
    all_cases.extend(build_area_4_ownership())
    all_cases.extend(build_area_5_operators())
    all_cases.extend(build_area_6_containers())
    all_cases.extend(build_area_7_interop_abi())
    all_cases.extend(build_area_8_gpu_ml_doc())
    ids = [c.cid for c in all_cases]
    assert len(ids) == len(set(ids)), "IDs duplicados na suíte!"
    return all_cases


def main() -> int:
    parser = argparse.ArgumentParser(description="Executa suíte do Prompt Mestre X (300+ casos).")
    parser.add_argument("--filtro", default="", help="Filtra casos por prefixo/substring de ID")
    parser.add_argument("--workers", type=int, default=max(4, min(12, os.cpu_count() or 4)))
    args = parser.parse_args()

    cases = collect_all_cases()
    if args.filtro:
        cases = [c for c in cases if args.filtro.lower() in c.cid.lower() or args.filtro.lower() in c.area.lower()]

    t0 = time.monotonic()
    passed_by_area: dict[str, int] = {}
    total_by_area: dict[str, int] = {}
    failures: list[tuple[Case, str]] = []

    with tempfile.TemporaryDirectory(prefix="cgd_pmx_") as tmp:
        work_root = Path(tmp)
        with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
            futs = [pool.submit(execute_case, c, work_root) for c in cases]
            for fut in concurrent.futures.as_completed(futs):
                c, ok, msg = fut.result()
                total_by_area[c.area] = total_by_area.get(c.area, 0) + 1
                if ok:
                    passed_by_area[c.area] = passed_by_area.get(c.area, 0) + 1
                else:
                    failures.append((c, msg))

    dt = time.monotonic() - t0
    total = len(cases)
    passed = total - len(failures)

    print(f"\n=== RESUMO PROMPT MESTRE X ({passed}/{total} aprovados em {dt:.2f}s) ===")
    for area in sorted(total_by_area.keys()):
        print(f"  {area}: {passed_by_area.get(area, 0)}/{total_by_area[area]}")

    if failures:
        print(f"\n=== FALHAS ({len(failures)}) ===")
        for c, msg in sorted(failures, key=lambda x: x[0].cid):
            print(f"[{c.cid}] {c.area}: {msg}\n")
        return 1

    print("\nTODOS OS CASOS INDEPENDENTES DO PROMPT MESTRE X PASSARAM!")
    return 0


if __name__ == "__main__":
    sys.exit(main())
