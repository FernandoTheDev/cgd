#!/usr/bin/env python3
"""Verifica a instalação sem tocar no prefixo do usuário."""

import hashlib
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="cgd instalacao ") as temporary:
    folder = Path(temporary)
    prefix, binaries = folder / "prefixo com espacos", folder / "bin com espacos"
    result = subprocess.run(
        [str(ROOT / "instalar"), "--no-build", "--prefix", str(prefix), "--bin-dir", str(binaries)],
        cwd=folder,
        text=True,
        capture_output=True,
        timeout=60,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert (binaries / "cgd").is_symlink()
    assert (
        hashlib.sha256((ROOT / "lib/libdelegua_rt.o").read_bytes()).digest()
        == hashlib.sha256((prefix / "lib/libdelegua_rt.o").read_bytes()).digest()
    )
    source = folder / "ola.delegua"
    source.write_text("classe A{x:numero construtor(){isto.x=7}}escreva(A().x)")
    result = subprocess.run(
        [str(binaries / "cgd"), str(source), "-s", str(folder / "ola")],
        cwd=folder,
        text=True,
        capture_output=True,
        timeout=60,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    result = subprocess.run(
        [str(folder / "ola")], cwd=folder, text=True, capture_output=True, timeout=10
    )
    assert result.returncode == 0 and result.stdout == "7\n", result
print("Instalação isolada validada, incluindo execução fora do checkout e caminhos com espaços.")
