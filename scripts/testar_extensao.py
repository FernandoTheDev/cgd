#!/usr/bin/env python3
"""Executa o Extension Host do VS Code já instalado, sem baixar outro Electron."""

import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
output = ROOT / "out/vscode"
output.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix="cgd vscode ") as temporary:
    folder = Path(temporary)
    workspace = folder / "workspace"
    workspace.mkdir()
    (workspace / ".vscode").mkdir()
    (workspace / ".vscode/settings.json").write_text(
        '{"cgd.executable":'
        + __import__("json").dumps(os.environ.get("CGD_TEST_COMPILER", str(ROOT / "cgd")))
        + "}"
    )
    command = [
        "/usr/share/code/code",
        "--no-sandbox",
        "--disable-gpu",
        "--disable-extensions",
        "--skip-welcome",
        "--skip-release-notes",
        "--disable-workspace-trust",
        "--user-data-dir",
        str(folder / "profile"),
        "--extensions-dir",
        str(folder / "extensions"),
        "--extensionDevelopmentPath=" + str(ROOT / "extensao-vscode"),
        "--extensionTestsPath=" + str(ROOT / "extensao-vscode/test/suite.js"),
        str(workspace),
    ]
    environment = {**os.environ, "CGD_TEST_REPORT_DIR": str(output)}
    environment.pop("ELECTRON_RUN_AS_NODE", None)
    result = subprocess.run(
        command,
        env=environment,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=180,
    )
    (output / "extension-host.log").write_text(result.stdout)
    print(
        result.stdout[-7000:]
        if result.returncode
        else "CGD: Extension Host concluiu os testes com sucesso."
    )
    assert result.returncode == 0, f"Extension Host falhou com status {result.returncode}"
    assert (output / "extensao.json").is_file(), "Relatório de teste não foi produzido"
print("Extensão validada no VS Code real, com perfil temporário isolado.")
