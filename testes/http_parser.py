#!/usr/bin/env python3
"""Compila e executa apenas o parser HTTP puro com ASan/UBSan."""

import os
import shlex
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
flags = shlex.split(
    subprocess.check_output(
        [os.environ.get("PKG_CONFIG", "pkg-config"), "--cflags", "bdw-gc"], text=True
    )
)
output = ROOT / "out/http-parser-asan"
output.parent.mkdir(exist_ok=True)
subprocess.run(
    [
        os.environ.get("CC", "clang"),
        "-std=c99",
        "-Wall",
        "-Wextra",
        "-Werror",
        "-fsanitize=address,undefined",
        "-fno-omit-frame-pointer",
        "-I" + str(ROOT / "vendor/delegua-runtime/src"),
        *flags,
        str(ROOT / "testes/http_parser.c"),
        str(ROOT / "vendor/delegua-runtime/src/http_parser.c"),
        "-o",
        str(output),
    ],
    check=True,
)
subprocess.run([str(output)], check=True)
print("Parser HTTP: regressões e 50000 entradas limitadas passaram com ASan/UBSan.")
