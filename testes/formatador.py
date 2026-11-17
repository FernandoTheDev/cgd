#!/usr/bin/env python3
"""Formata cópias, exige idempotência e executa contratos com/sem otimização."""

from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
(ROOT / "out").mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(prefix="formatador-", dir=ROOT / "out") as directory:
    temporary = Path(directory)
    shutil.copytree(ROOT / "exemplos", temporary / "exemplos")
    shutil.copytree(ROOT / "bibliotecas", temporary / "bibliotecas")
    files = sorted(temporary.rglob("*.delegua"))
    for file in files:
        subprocess.run([str(ROOT / "cgd"), "--formatar", str(file)], check=True)
        first = file.read_bytes()
        subprocess.run([str(ROOT / "cgd"), "--formatar", str(file)], check=True)
        assert file.read_bytes() == first, f"Não idempotente: {file}"
        for line in first.decode().splitlines():
            if line.strip():
                spaces = len(line) - len(line.lstrip(" "))
                assert spaces % 4 == 0 and not line.startswith("\t"), file
    subprocess.run(
        ["python3", "testes/exemplos.py", "--examples-dir", str(temporary / "exemplos")],
        cwd=ROOT,
        check=True,
    )
    print(f"Formatador: {len(files)} arquivos idempotentes; contratos preservados.")
