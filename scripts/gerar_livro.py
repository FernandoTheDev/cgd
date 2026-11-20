#!/usr/bin/env python3
"""Prepara o livro a partir da referência e exemplos, depois chama mdBook 0.4.52."""

import argparse
import json
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument(
    "--check", action="store_true", help="Confere o livro publicado sem regravar docs/livro."
)
args = parser.parse_args()
source = ROOT / "out/livro-src"
if source.exists():
    shutil.rmtree(source)
source.mkdir(parents=True, exist_ok=True)
sections = json.loads((ROOT / "docs/linguagem.json").read_text())
summary = ["# Sumário", "", "- [Antes de começar](index.md)"]
(source / "index.md").write_text("""# Vamos escrever Delégua

Este livro acompanha você do primeiro programa às bibliotecas e às ferramentas do
compilador. Comece pela instalação, rode os exemplos e avance no seu ritmo.

O CGD compila Delégua para C99 e usa um runtime com memória gerenciada. Hoje,
Linux x86_64 é a plataforma validada. A linguagem vem do projeto
[Delégua, da Design Líquido](https://github.com/DesignLiquido/delegua); aqui você
vai encontrar a sintaxe que este compilador aceita, com suas escolhas e limites.

Se já conhece a linguagem, use a busca ou o sumário para ir direto ao assunto.
Para construir o compilador, consulte o [guia de desenvolvimento](desenvolvimento.md).

[Voltar ao site do projeto](../index.html)
""")
for section in sections:
    identifier = section["id"]
    summary.append(f"- [{section['title']}]({identifier}.md)")
    parts = [f"# {section['title']}", "", section["description"], ""]
    for topic in section.get("topics", []):
        parts += [f"## {topic['title']}", "", *[p + "\n" for p in topic.get("paragraphs", [])]]
        if "code" in topic:
            first_line = topic["code"].strip().splitlines()[0]
            language = (
                "sh"
                if first_line.startswith(
                    ("npm ", "python3 ", "git ", "./", "mkdir ", "cargo ", "cgd ", "dub ", "sudo ")
                )
                else "delegua"
            )
            parts += [f"```{language}", topic["code"], "```", ""]
        if "rows" in topic:
            parts += ["| Recurso | Como funciona |", "| --- | --- |"]
            parts += [
                "| " + " | ".join(cell.replace("|", "\\|") for cell in row) + " |"
                for row in topic["rows"]
            ]
            parts.append("")
    for relative in section["examples"]:
        text = (ROOT / "exemplos" / relative).read_text()
        code = "\n".join(
            line for line in text.splitlines() if not line.startswith(("//!", "//#", "//?", "//$"))
        )
        parts += [
            f"## Experimente: {Path(relative).stem}",
            "",
            "```delegua",
            code,
            "```",
            "",
            f"[Ver exemplo completo e teste](https://github.com/FernandoTheDev/cgd/blob/dev/exemplos/{relative})",
            "",
        ]
    if identifier == "diagnosticos":
        quoted = r'("(?:[^"\\]|\\.)*")'
        pattern = (
            r"enum\s+MessageSpec\s+\w+\s*=\s*MessageSpec\(\s*"
            + quoted
            + r"\s*,\s*"
            + quoted
            + r"\s*,\s*"
            + quoted
            + r"\s*\)"
        )
        catalog = (ROOT / "src/diagnostics/catalog.d").read_text()
        parts += [
            "## Códigos de diagnóstico",
            "",
            "| Código | Mensagem | O que fazer |",
            "| --- | --- | --- |",
        ]
        for match in re.findall(pattern, catalog):
            parts.append(
                "| " + " | ".join(json.loads(value).replace("|", "\\|") for value in match) + " |"
            )
        parts.append("")
    if section.get("notes"):
        parts += [section["notes"], ""]
    (source / f"{identifier}.md").write_text("\n".join(parts))
for name in (
    "desenvolvimento",
    "arquitetura",
    "compatibilidade",
    "seguranca",
    "ferramentas",
    "evolucao-linguagem",
    "stdlib-sistema",
    "servidor-http",
    "assincronismo",
    "rotinas",
):
    text = (ROOT / "docs" / f"{name}.md").read_text()
    text = text.replace("(linguagem.html)", "(index.md)")
    text = re.sub(
        r"\]\((CONTINUIDADE\.md|\.\./[^)]+)\)",
        lambda match: (
            "](https://github.com/FernandoTheDev/cgd/blob/dev/"
            + ("docs/" + match[1] if not match[1].startswith("../") else match[1][3:])
            + ")"
        ),
        text,
    )
    (source / f"{name}.md").write_text(text)
    summary.append(f"- [{name.replace('-', ' ').capitalize()}]({name}.md)")
(source / "SUMMARY.md").write_text("\n".join(summary) + "\n")
mdbook = shutil.which("mdbook")
if not mdbook:
    raise SystemExit("Instale mdBook: cargo install mdbook --version 0.4.52 --locked")
version = subprocess.check_output([mdbook, "--version"], text=True).strip()
if version != "mdbook v0.4.52":
    raise SystemExit("Esta documentação usa mdBook 0.4.52; instale a versão indicada no README.")
if args.check:
    with tempfile.TemporaryDirectory(prefix="cgd-livro-") as temporary:
        destination = Path(temporary) / "livro"
        subprocess.run(
            [mdbook, "build", str(ROOT / "livro"), "--dest-dir", str(destination)], check=True
        )

        def contents(folder):
            return {
                str(path.relative_to(folder)): path.read_bytes()
                for path in folder.rglob("*")
                if path.is_file()
            }

        if contents(destination) != contents(ROOT / "docs/livro"):
            raise SystemExit("Livro desatualizado. Execute python3 scripts/gerar_livro.py")
    print("Livro sincronizado com suas fontes.")
else:
    subprocess.run([mdbook, "build", str(ROOT / "livro")], check=True)
    print("Livro gerado em docs/livro, pronto para o GitHub Pages.")
