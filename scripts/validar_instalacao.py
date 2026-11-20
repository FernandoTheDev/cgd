#!/usr/bin/env python3
"""Verifica a instalação sem tocar no prefixo do usuário."""

import hashlib
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="cgd instalacao ") as temporary:
    folder = Path(temporary)
    prefix, binaries = folder / "prefixo com espacos", folder / "bin com espacos"
    libs_dir = folder / ".delegua/cgd"
    env = {**os.environ, "HOME": str(folder)}
    env.pop("CGD_LIBS_DIR", None)
    result = subprocess.run(
        [str(ROOT / "instalar"), "--no-build", "--prefix", str(prefix), "--bin-dir", str(binaries)],
        cwd=folder,
        env=env,
        text=True,
        capture_output=True,
        timeout=60,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert (binaries / "cgd").is_symlink()
    assert (libs_dir / "json.delegua").is_file(), (
        "Bibliotecas padrão não instaladas em ~/.delegua/cgd"
    )
    assert not (prefix / "bibliotecas").exists(), "Bibliotecas não devem ser duplicadas no prefixo"
    assert (
        hashlib.sha256((ROOT / "lib/libdelegua_rt.o").read_bytes()).digest()
        == hashlib.sha256((prefix / "lib/libdelegua_rt.o").read_bytes()).digest()
    )
    # Adiciona uma biblioteca personalizada diretamente em ~/.delegua/cgd sem recompilar o CGD.
    (libs_dir / "minha_lib.delegua").write_text('funcao saudar(): texto { retorna "ok-custom" }\n')
    source = folder / "ola.delegua"
    source.write_text(
        'const J: qualquer = importar("cgd:json").JSON\n'
        'const M: qualquer = importar("cgd:minha_lib")\n'
        "classe A{x:numero construtor(){isto.x=7}}\n"
        'escreva(A().x, J.analisar("{\\"v\\":3}")["v"], M.saudar())\n'
    )
    result = subprocess.run(
        [str(binaries / "cgd"), str(source), "-s", str(folder / "ola")],
        cwd=folder,
        env=env,
        text=True,
        capture_output=True,
        timeout=60,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    result = subprocess.run(
        [str(folder / "ola")], cwd=folder, env=env, text=True, capture_output=True, timeout=10
    )
    assert result.returncode == 0 and result.stdout == "73ok-custom\n", result
print("Instalação isolada validada (~/.delegua/cgd, cgd: dinâmico e caminhos com espaços).")
