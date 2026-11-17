#!/usr/bin/env python3
"""Renderer de erro real: Unicode/tabs, controles, fonte ausente e FIFO."""

from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="cgd diagnostico ") as temporary:
    folder = Path(temporary)
    source = folder / "ação.delegua"
    output = folder / "programa"
    source.write_text(
        "funcao dividir(z: inteiro): numero {\n\tvar ação: numero = 1\n\tretorna ação / z\n}\ndividir(0)\n"
    )
    compiled = subprocess.run(
        [str(ROOT / "cgd"), str(source), "-s", str(output)],
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert compiled.returncode == 0, compiled.stderr
    result = subprocess.run([str(output)], capture_output=True, text=True, timeout=5)
    assert result.returncode == 1 and result.stderr.startswith("error[R0001]:"), result
    assert "Divisão por zero" in result.stderr and f"{source}:3:" in result.stderr, result.stderr
    lines = result.stderr.splitlines()
    snippet = next(line for line in lines if "3 |" in line)
    marker = lines[lines.index(snippet) + 1]
    assert "\t" not in snippet and marker.index("^") == snippet.index("ação"), result.stderr
    for content in [
        "\n" * 10000 + "funcao dividir(z: inteiro): numero {\n    retorna 1 / z\n}\ndividir(0)\n",
        "funcao dividir(z: inteiro): numero {\n" + " " * 220 + "retorna 1 / z\n}\ndividir(0)\n",
    ]:
        source.write_text(content)
        compiled = subprocess.run(
            [str(ROOT / "cgd"), str(source), "-s", str(output)],
            capture_output=True,
            text=True,
            timeout=60,
        )
        assert compiled.returncode == 0, compiled.stderr
        large = subprocess.run([str(output)], capture_output=True, text=True, timeout=5)
        assert large.returncode == 1, large
        rendered = large.stderr.splitlines()
        snippet = next(line for line in rendered if "retorna 1 / z" in line)
        marker = rendered[rendered.index(snippet) + 1]
        assert marker.index("^") == snippet.index("1 / z"), large.stderr
    source.unlink()
    missing = subprocess.run([str(output)], capture_output=True, text=True, timeout=5)
    assert (
        missing.returncode == 1 and "R0001" in missing.stderr and str(source) in missing.stderr
    ), missing
    os.mkfifo(source)
    fifo = subprocess.run([str(output)], capture_output=True, text=True, timeout=5)
    assert fifo.returncode == 1 and "R0001" in fifo.stderr, fifo
    source.unlink()
    source.write_text('falhar "controle\\0fim"')
    compiled = subprocess.run(
        [str(ROOT / "cgd"), str(source), "-s", str(output)],
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert compiled.returncode == 0, compiled.stderr
    escaped = subprocess.run([str(output)], capture_output=True, text=True, timeout=5)
    assert escaped.returncode == 1 and "\\x00" in escaped.stderr and "\0" not in escaped.stderr, (
        escaped
    )
    source.write_text('tente { falhar "tratado" } pegue { escreva("ok") }')
    compiled = subprocess.run(
        [str(ROOT / "cgd"), str(source), "-s", str(output)],
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert compiled.returncode == 0, compiled.stderr
    caught = subprocess.run([str(output)], capture_output=True, text=True, timeout=5)
    assert caught.returncode == 0 and caught.stdout == "ok\n" and caught.stderr == "", caught
print(
    "Runtime: diagnóstico visual, Unicode/tabs, controles, fonte ausente/FIFO e captura passaram."
)
