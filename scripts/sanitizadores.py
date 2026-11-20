#!/usr/bin/env python3
"""Valida a API C e todos os programas com ASan/UBSan; restaura o runtime normal."""

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument(
    "--rede",
    action="store_true",
    help="Valida API C, parser HTTP e contratos de rede; restaura o runtime normal.",
)
args = parser.parse_args()
ROOT = Path(__file__).resolve().parents[1]
flags = "-DNDEBUG -fsanitize=address,undefined -fno-omit-frame-pointer"
base = {
    key: value
    for key, value in os.environ.items()
    if key not in ["CC", "CFLAGS", "ASAN_OPTIONS", "UBSAN_OPTIONS"]
}
sanitized = {
    **base,
    "CC": "clang",
    "CFLAGS": flags,
    "ASAN_OPTIONS": "detect_leaks=0:detect_stack_use_after_return=0",
    "UBSAN_OPTIONS": "halt_on_error=1:print_stacktrace=1",
}
steps = []


def run(label, command, environment, cwd=ROOT):
    print(">>>", label, flush=True)
    result = subprocess.run(
        command,
        check=False,
        cwd=cwd,
        env=environment,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=1200,
    )
    print(result.stdout, flush=True)
    steps.append({"label": label, "status": result.returncode, "output": result.stdout})
    if result.returncode:
        raise subprocess.CalledProcessError(result.returncode, command)


passed = False
try:
    with tempfile.TemporaryDirectory(prefix="cgd asan ") as tmp:
        run(
            "API C com NDEBUG + ASan + UBSan",
            ["./tests/run.sh"],
            sanitized,
            ROOT / "vendor/delegua-runtime",
        )
        shutil.copy2(ROOT / "vendor/delegua-runtime/libdelegua_rt.o", ROOT / "lib/libdelegua_rt.o")
        wrapper = Path(tmp) / "cc-sanitizado"
        wrapper.write_text(
            '#!/usr/bin/env python3\nimport os, sys\nos.execvp("clang", ["clang", "-DNDEBUG", "-fsanitize=address,undefined", "-fno-omit-frame-pointer", *sys.argv[1:]])\n'
        )
        wrapper.chmod(0o755)
        environment = {**sanitized, "CC": str(wrapper)}
        if args.rede:
            run("Parser HTTP puro sanitizado", [sys.executable, "testes/http_parser.py"], sanitized)
            run("Servidor HTTP sanitizado", [sys.executable, "testes/servidor.py"], environment)
            run("Sockets sanitizados", [sys.executable, "testes/sockets.py"], environment)
        else:
            run(
                "Assincronismo sanitizado",
                [sys.executable, "testes/async_linguagem.py"],
                environment,
            )
            run("Integração sanitizada", [sys.executable, "testes/integracao.py"], environment)
            run(
                "Todos os exemplos sanitizados", [sys.executable, "testes/exemplos.py"], environment
            )
            run("Bibliotecas sanitizadas", [sys.executable, "testes/bibliotecas.py"], environment)
            run("Expansão sanitizada", [sys.executable, "testes/expansao.py"], environment)
            run(
                "Sistema e processos sanitizados",
                [sys.executable, "testes/processo.py"],
                environment,
            )
            run("Parser HTTP puro sanitizado", [sys.executable, "testes/http_parser.py"], sanitized)
            run("Servidor HTTP sanitizado", [sys.executable, "testes/servidor.py"], environment)
            run("Sockets sanitizados", [sys.executable, "testes/sockets.py"], environment)
            run("Enums sanitizados", [sys.executable, "testes/enums.py"], environment)
            run("Stdlib sanitizada", [sys.executable, "testes/stdlib.py"], environment)
            run(
                "Diagnósticos sanitizados",
                [sys.executable, "testes/runtime_diagnosticos.py"],
                environment,
            )
        passed = True
finally:
    restored = subprocess.run(
        ["./build-runtime"],
        check=False,
        cwd=ROOT,
        env={**base, "CC": "clang"},
        text=True,
        capture_output=True,
    )
    if restored.returncode:
        print(restored.stdout + restored.stderr, file=sys.stderr)
        passed = False
    out = ROOT / ("out/sanitizadores-rede.json" if args.rede else "out/sanitizadores.json")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(
        json.dumps(
            {
                "passed": passed,
                "escopo": "rede" if args.rede else "completo",
                "flags": flags,
                "asan_options": sanitized["ASAN_OPTIONS"],
                "steps": steps,
                "normal_runtime_restored": restored.returncode == 0,
            },
            ensure_ascii=False,
            indent=2,
        )
        + "\n"
    )
if not passed:
    raise SystemExit(1)
print("Sanitizadores passaram; runtime normal restaurado.")
