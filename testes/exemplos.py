#!/usr/bin/env python3
"""Compila e executa todo .delegua em exemplos, sem ignorar arquivos sem contrato."""

from pathlib import Path
import argparse
import os
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def escapes(text):
    result = []
    index = 0
    while index < len(text):
        char = text[index]
        index += 1
        if char == "\\" and index < len(text):
            next_char = text[index]
            if next_char in {"n", "r", "t", "\\"}:
                char = {"n": "\n", "r": "\r", "t": "\t", "\\": "\\"}[next_char]
                index += 1
        result.append(char)
    return "".join(result)


def run(args, *, cwd=ROOT, **kwargs):
    return subprocess.run(args, cwd=cwd, capture_output=True, text=True, timeout=40, **kwargs)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--compiler", type=Path, default=ROOT / "cgd")
    parser.add_argument("--once", action="store_true", help="Usa somente o modo sem -o.")
    parser.add_argument("--examples-dir", type=Path, default=ROOT / "exemplos")
    args = parser.parse_args()
    project_manifests = sorted(args.examples_dir.rglob("projeto.json"))
    project_dirs = [m.parent.resolve() for m in project_manifests]

    def in_project(path: Path) -> bool:
        resolved = path.resolve()
        return any(resolved.is_relative_to(pdir) for pdir in project_dirs)

    files = [f for f in sorted(args.examples_dir.rglob("*.delegua")) if not in_project(f)]
    failures = []
    checks = 0
    for manifest in project_manifests:
        pdir = manifest.parent
        env = dict(os.environ)
        env.setdefault("SDL_VIDEODRIVER", "dummy")
        data = manifest.read_text()
        if '"gtk4"' in data and not (env.get("DISPLAY") or env.get("WAYLAND_DISPLAY")):
            compiled = run([str(args.compiler.resolve()), "compilar", "--forcar"], cwd=pdir, env=env)
            if compiled.returncode != 0:
                failures.append(f"{pdir.relative_to(ROOT)}: compilar falhou: {compiled.stderr}")
            checks += 1
            continue
        executed = run([str(args.compiler.resolve()), "rodar", "--forcar", "--", "--teste"], cwd=pdir, env=env)
        if executed.returncode != 0:
            failures.append(f"{pdir.relative_to(ROOT)}: rodar --teste falhou: {executed.stderr}{executed.stdout}")
        checks += 1
        if (pdir / "testes").is_dir():
            tested = run([str(args.compiler.resolve()), "testar"], cwd=pdir, env=env)
            if tested.returncode != 0:
                failures.append(f"{pdir.relative_to(ROOT)}: testar falhou: {tested.stderr}{tested.stdout}")
            checks += 1
    with tempfile.TemporaryDirectory(prefix="cgd exemplos ") as tmp:
        for index, file in enumerate(files):
            lines = file.read_text().splitlines()
            header_index = 1 if lines and lines[0].strip() == "//$" else 0
            header = lines[header_index] if len(lines) > header_index else ""
            if not header.startswith(("//!", "//#")):
                failures.append(f"{file.relative_to(ROOT)}: falta contrato //! ou //#")
                continue
            expected_output = escapes(header[3:].strip()) if header.startswith("//!") else None
            expected_status = int(header[3:].strip()) if header.startswith("//#") else 0
            options = {}
            for line in lines:
                if line.startswith("//? ") and ":" in line:
                    key, value = line[4:].split(":", 1)
                    options[key.strip()] = value.strip()
            for opt in [False] if args.once else [False, True]:
                output = Path(tmp) / f"exemplo-{index}-{int(opt)}"
                try:
                    compiled = run(
                        [str(args.compiler.resolve()), str(file), "-s", str(output)]
                        + (["-o"] if opt else [])
                    )
                    stage = "compilacao"
                    result = compiled
                    if compiled.returncode == 0 and options.get("fase") != "compilacao":
                        stage = "execucao"
                        if options.get("diretorio", "raiz") not in {"raiz", "fonte"}:
                            raise ValueError("diretorio deve ser raiz ou fonte")
                        runtime_directory = (
                            file.parent.resolve() if options.get("diretorio") == "fonte" else ROOT
                        )
                        result = run(
                            [str(output)],
                            cwd=runtime_directory,
                            input=escapes(options.get("entrada", "")),
                        )
                    details = result.stdout + result.stderr
                    valid = result.returncode == expected_status
                    if expected_output is not None:
                        valid = (
                            valid
                            and stage == "execucao"
                            and result.stdout.strip() == expected_output.strip()
                        )
                    if options.get("fase"):
                        valid = valid and stage == options["fase"]
                    if options.get("erro"):
                        valid = valid and options["erro"] in details
                    if options.get("saida"):
                        valid = (
                            valid
                            and stage == "execucao"
                            and re.search(options["saida"], result.stdout, re.MULTILINE) is not None
                        )
                    if options.get("ausente"):
                        valid = (
                            valid and re.search(options["ausente"], details, re.MULTILINE) is None
                        )
                    if not valid:
                        failures.append(
                            f"{file.relative_to(ROOT)} opt={opt}: fase={stage}, status={result.returncode}, saída={details!r}"
                        )
                    checks += 1
                except (subprocess.TimeoutExpired, OSError, ValueError) as error:
                    failures.append(f"{file.relative_to(ROOT)} opt={opt}: {error}")
    for failure in failures:
        print("FAIL", failure)
    print(
        f"{len(files)} exemplos; {checks} verificações; {len(failures)} falhas; nenhum arquivo ignorado."
    )
    return bool(failures)


if __name__ == "__main__":
    raise SystemExit(main())
