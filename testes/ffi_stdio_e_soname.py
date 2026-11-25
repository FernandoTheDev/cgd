#!/usr/bin/env python3
"""Testes permanentes de regressão para FFI C: cponteiro, símbolos de <stdio.h>/<stdlib.h>, e soname versionado."""

import os
import subprocess
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


def compile_and_run(src: str, extra_flags=None, run_env=None):
    with tempfile.TemporaryDirectory() as td:
        td_path = Path(td)
        src_path = td_path / "prog.delegua"
        bin_path = td_path / "prog_bin"
        src_path.write_text(src, encoding="utf-8")
        cmd = [str(CGD), str(src_path), "--saida", str(bin_path)]
        if extra_flags:
            cmd.extend(extra_flags)
        comp = run_cmd(cmd)
        assert comp.returncode == 0, f"Falha na compilação ({cmd}):\nSTDOUT:\n{comp.stdout}\nSTDERR:\n{comp.stderr}"
        exe = run_cmd([str(bin_path)], env=run_env)
        return comp, exe


def test_stdio_cponteiro_4k_roundtrip():
    src = """
@definicao(biblioteca = "c", abi = "c")
classe estrangeira CStdIO {
    @definicao(simbolo = "fopen")
    estatico abrir(caminho: texto, modo: texto): cponteiro;
    @definicao(simbolo = "fclose")
    estatico fechar(fp: cponteiro): cint;
    @definicao(simbolo = "fseek")
    estatico buscar(fp: cponteiro, desloc: ci64, origem: cint): cint;
    @definicao(simbolo = "ftell")
    estatico posicao(fp: cponteiro): ci64;
    @definicao(simbolo = "fgetc")
    estatico lerByte(fp: cponteiro): cint;
    @definicao(simbolo = "fputc")
    estatico gravarByte(ch: cint, fp: cponteiro): cint;
    @definicao(simbolo = "fflush")
    estatico sincronizar(fp: cponteiro): cint;
    @definicao(simbolo = "fread")
    estatico lerBloco(ptr: cponteiro, tam: cu64, qtd: cu64, fp: cponteiro): cu64;
    @definicao(simbolo = "fwrite")
    estatico gravarBloco(ptr: cponteiro, tam: cu64, qtd: cu64, fp: cponteiro): cu64;
    @definicao(simbolo = "malloc")
    estatico alocar(tam: cu64): cponteiro;
    @definicao(simbolo = "memset")
    estatico preencher(ptr: cponteiro, valor: cint, tam: cu64): cponteiro;
    @definicao(simbolo = "free")
    estatico liberar(ptr: cponteiro): vazio;
    @definicao(simbolo = "remove")
    estatico remover(caminho: texto): cint;
}

var caminho: texto = "/tmp/cgd_ffi_stdio_regressao.bin"
var buf: inteiro = CStdIO.alocar(4096)
CStdIO.preencher(buf, 90, 4096)

var fp: inteiro = CStdIO.abrir(caminho, "wb")
se (fp == 0) { falhar "fopen wb falhou" }
var escritos: inteiro = CStdIO.gravarBloco(buf, 1, 4096, fp)
se (escritos != 4096) { falhar "fwrite retornou " + texto(escritos) }
CStdIO.gravarByte(33, fp)
CStdIO.sincronizar(fp)
se (CStdIO.fechar(fp) != 0) { falhar "fclose wb falhou" }

var fp2: inteiro = CStdIO.abrir(caminho, "rb")
se (fp2 == 0) { falhar "fopen rb falhou" }
CStdIO.buscar(fp2, 0, 2)
var tam: inteiro = CStdIO.posicao(fp2)
se (tam != 4097) { falhar "ftell esperado 4097, obtido " + texto(tam) }
CStdIO.buscar(fp2, 4096, 0)
var ultimo: inteiro = CStdIO.lerByte(fp2)
se (ultimo != 33) { falhar "fgetc esperado 33, obtido " + texto(ultimo) }
CStdIO.buscar(fp2, 0, 0)
var buf2: inteiro = CStdIO.alocar(4096)
var lidos: inteiro = CStdIO.lerBloco(buf2, 1, 4096, fp2)
se (lidos != 4096) { falhar "fread esperado 4096, obtido " + texto(lidos) }
CStdIO.fechar(fp2)
CStdIO.liberar(buf)
CStdIO.liberar(buf2)
CStdIO.remover(caminho)
escreva("ffi_stdio_cponteiro=OK")
"""
    for cc in ["gcc", "clang"]:
        _, exe = compile_and_run(src, extra_flags=["--cc", cc, "-o"])
        assert exe.returncode == 0, f"Falha em {cc}: {exe.stderr}"
        assert "ffi_stdio_cponteiro=OK" in exe.stdout, f"Saída inesperada em {cc}: {exe.stdout}"


def test_soname_versionado():
    if not Path("/lib64/libmariadb.so.3").exists():
        print("  [SKIP] /lib64/libmariadb.so.3 não disponível neste host")
        return
    src = """
@definicao(biblioteca = ":libmariadb.so.3", abi = "c")
classe estrangeira MariaTest {
    @definicao(simbolo = "mysql_get_client_info")
    estatico versaoCliente(): texto;
}
var v: texto = MariaTest.versaoCliente()
se (v.tamanho() == 0) { falhar "versão vazia" }
escreva("soname_ok=" + v)
"""
    _, exe = compile_and_run(src)
    assert exe.returncode == 0, f"Falha soname: {exe.stderr}"
    assert "soname_ok=" in exe.stdout, f"Saída inesperada: {exe.stdout}"


def main():
    print("[1/2] test_stdio_cponteiro_4k_roundtrip (gcc + clang -O2)...")
    test_stdio_cponteiro_4k_roundtrip()
    print("[2/2] test_soname_versionado (:libmariadb.so.3)...")
    test_soname_versionado()
    print("ffi_stdio_e_soname.py: ALL PASSED")


if __name__ == "__main__":
    main()
