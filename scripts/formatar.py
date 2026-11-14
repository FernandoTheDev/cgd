#!/usr/bin/env python3
"""Formata fontes versionadas e novas; --check verifica sem editar. Não toca artefatos."""

import argparse
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--check", action="store_true")
args = parser.parse_args()


def tool(name, local):
    found = shutil.which(name)
    if found:
        return found
    fallback = ROOT / "out/tools" / local
    if fallback.is_file():
        return str(fallback)
    raise SystemExit(f"Formatador ausente: {name}. Consulte docs/desenvolvimento.md.")


def files(folder):
    output = subprocess.check_output(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"], cwd=folder
    )
    return sorted(
        {
            folder / os.fsdecode(path)
            for path in output.split(b"\0")
            if path and (folder / os.fsdecode(path)).is_file()
        }
    )


sources = files(ROOT) + files(ROOT / "vendor/delegua-runtime")
groups = {
    "D": [p for p in sources if p.suffix == ".d"],
    "C": [p for p in sources if p.suffix in (".c", ".h") and p.name != "unicode_tables.h"],
    "Python": [p for p in sources if p.suffix == ".py"],
    "Web/docs": [
        p for p in sources if p.suffix in (".html", ".css", ".js", ".json", ".md", ".yml", ".yaml")
    ],
    "TOML": [p for p in sources if p.suffix == ".toml"],
    "Shell": [
        p for p in sources if p.suffix == ".sh" or p.name in ("instalar", "build-runtime", "build")
    ],
}
commands = {
    "D": lambda: [tool("dfmt", "dfmt/bin/dfmt"), "-i"],
    "C": lambda: (
        [tool("clang-format", "bin/clang-format"), "--dry-run", "--Werror"]
        if args.check
        else [tool("clang-format", "bin/clang-format"), "-i"]
    ),
    "Python": lambda: [
        tool("ruff", "python/bin/ruff"),
        "format",
        *(["--check"] if args.check else []),
    ],
    "Web/docs": lambda: [
        tool("prettier", "web/node_modules/.bin/prettier"),
        "--check" if args.check else "--write",
    ],
    "TOML": lambda: [
        tool("taplo", "web/node_modules/.bin/taplo"),
        "format",
        *(["--check"] if args.check else []),
    ],
    "Shell": lambda: [tool("shfmt", "bin/shfmt"), "-d" if args.check else "-w"],
}
for name, paths in groups.items():
    if paths:
        print(f"{name}: {len(paths)} arquivos", flush=True)
        if name == "D" and args.check:
            for path in paths:
                formatted = subprocess.check_output(
                    [tool("dfmt", "dfmt/bin/dfmt"), str(path)], cwd=ROOT
                )
                if formatted != path.read_bytes():
                    raise SystemExit(f"Formatação divergente: {path.relative_to(ROOT)}")
        else:
            subprocess.run(commands[name]() + list(map(str, paths)), cwd=ROOT, check=True)
print(
    "Formatação verificada."
    if args.check
    else "Formatação concluída. .delegua e tabelas geradas preservados."
)
