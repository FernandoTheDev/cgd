#!/usr/bin/env python3
"""Impede regressões de estilo: auto/foreach inferido em D e variáveis sem tipo nas libs."""

from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
failures = []
for folder in (ROOT / "src", ROOT / "testes/unit"):
    for file in folder.rglob("*.d"):
        source = file.read_text()
        # Strings dos testes contêm programas Delégua; não são declarações D.
        code = re.sub(
            r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|//[^\n]*|/\*.*?\*/', " ", source, flags=re.S
        )
        if re.search(r"\bauto\b", code):
            failures.append(f"{file.relative_to(ROOT)}: auto não permitido")
        for match in re.finditer(r"\bforeach(?:_reverse)?\s*\(([^;]*);", code):
            for binding in match[1].split(","):
                if len(binding.strip().replace("ref ", "").split()) < 2:
                    failures.append(
                        f"{file.relative_to(ROOT)}: binding sem tipo: {binding.strip()}"
                    )
for file in (ROOT / "bibliotecas").glob("*.delegua"):
    code = re.sub(r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|//[^\n]*', " ", file.read_text())
    if re.search(r"\b(?:var|const)\s+\w+\s*=", code):
        failures.append(f"{file.relative_to(ROOT)}: variável sem tipo")
    if re.search(r"\bpara\s+cada\s+\w+\s+em\b", code):
        failures.append(f"{file.relative_to(ROOT)}: iteração sem tipo")
    for signature in re.finditer(
        r"(?m)^\s*(?:(?:estatico|estático|funcao|função)\s+)?(\w+)\(([^)]*)\)([^\n{]*)\{", code
    ):
        name, arguments, result = signature.groups()
        if name in {"se", "enquanto", "para", "pegue", "escolha"}:
            continue
        if name != "construtor" and not result.strip().startswith(":"):
            failures.append(f"{file.relative_to(ROOT)}: retorno sem tipo: {name}")
        for argument in arguments.split(","):
            if argument.strip() and ":" not in argument.partition("=")[0]:
                failures.append(
                    f"{file.relative_to(ROOT)}: argumento sem tipo: {name}({argument.strip()})"
                )
if failures:
    raise SystemExit("\n".join(failures))
print(
    "Tipos: fontes/testes D sem auto ou foreach inferido; bibliotecas Delégua com variáveis, argumentos e retornos explícitos."
)
