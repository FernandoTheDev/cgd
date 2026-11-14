#!/usr/bin/env python3
"""Matriz reproduzível: DMD/LDC2, debug/release, GCC/Clang e todos os exemplos."""

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--compilers", nargs="+", default=["dmd", "ldc2"])
parser.add_argument("--builds", nargs="+", default=["debug", "release"])
parser.add_argument("--c-compilers", nargs="+", default=["clang", "gcc"])
parser.add_argument("--report", type=Path, default=ROOT / "out/validacao.json")
args = parser.parse_args()
for compiler in args.compilers + args.c_compilers + ["dub", "pkg-config"]:
    if not shutil.which(compiler):
        parser.error(f"Dependência obrigatória ausente: {compiler}")
report = {"started_utc": datetime.now(timezone.utc).isoformat(), "versions": {}, "steps": []}
for compiler in args.compilers + args.c_compilers:
    report["versions"][compiler] = subprocess.run(
        [compiler, "--version"], text=True, capture_output=True
    ).stdout.splitlines()[0]
args.report.parent.mkdir(parents=True, exist_ok=True)


def persist():
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")


def command(label, argv, env=None, timeout=900):
    print(f">>> {label}: {' '.join(argv)}", flush=True)
    started = time.monotonic()
    result = subprocess.run(
        argv,
        cwd=ROOT,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=timeout,
    )
    report["steps"].append(
        {
            "label": label,
            "command": argv,
            "status": result.returncode,
            "seconds": round(time.monotonic() - started, 3),
            "output": result.stdout,
        }
    )
    print(result.stdout, flush=True)
    persist()
    if result.returncode:
        raise SystemExit(result.returncode)


command("runtime", ["./build-runtime"])
for compiler in args.compilers:
    command(
        f"{compiler}/unittests D",
        ["dub", "test", f"--compiler={compiler}", "--config=unittest", "--force"],
    )
    for build in args.builds:
        command(
            f"{compiler}/{build}/build",
            [
                "dub",
                "build",
                f"--compiler={compiler}",
                f"--build={build}",
                "--config=application",
                "--force",
            ],
        )
        command(f"{compiler}/{build}/driver", [sys.executable, "testes/driver.py"])
        for cc in args.c_compilers:
            environment = {**os.environ, "CC": cc}
            command(
                f"{compiler}/{build}/{cc}/integração",
                [sys.executable, "testes/integracao.py"],
                environment,
            )
            command(
                f"{compiler}/{build}/{cc}/exemplos",
                [sys.executable, "testes/exemplos.py"],
                environment,
            )
        command(f"{compiler}/{build}/instalação", [sys.executable, "scripts/validar_instalacao.py"])
report["finished_utc"] = datetime.now(timezone.utc).isoformat()
report["passed"] = True
persist()
print(f"Matriz concluída. Relatório: {args.report}", flush=True)
