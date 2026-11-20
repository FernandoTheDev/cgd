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
summary = ["# Sumário", "", "- [Bem-vindo ao CGD](index.md)"]
(source / "index.md").write_text("""# Bem-vindo ao Livro do CGD

Este livro foi escrito para quem quer aprender a programar com o **CGD (Compilador Geral Delégua)** sem enrolação — desde instalar as ferramentas até criar servidores HTTP, usar SQLite e rodar tarefas em paralelo com `rotina`.

## Antes de tudo: qual é a relação com a Delégua original?

A linguagem **Delégua** foi criada pela [Design Líquido](https://github.com/DesignLiquido/delegua) (com sua [wiki oficial](https://github.com/DesignLiquido/delegua/wiki)) e roda originalmente sobre um interpretador em TypeScript/Node.js.

O **CGD** pega essa mesma base em português e compila seu código para **C99 e executável nativo** em Linux x86_64, usando um runtime próprio em C com coletor Boehm GC. Por causa disso, várias coisas mudam de comportamento e muitas funcionalidades — como `assincrona`/`aguardar`, `rotina`/`Tarefa<T>`, `Canal`, as 24 bibliotecas `cgd:*` instaladas em `~/.delegua/cgd`, o servidor LSP e o formatador — foram construídas do zero no CGD.

> Se você já conhece Delégua pelo interpretador, vale ler logo o capítulo [Delégua original vs. CGD](delegua-vs-cgd.md) para não se surpreender com as diferenças.

## Por onde começar?

- **Primeira vez aqui?** Vá direto para [Comece aqui: instalar, escrever e executar](inicio.md).
- **Quer configurar o VS Code?** Veja [Editor VS Code: cores, autocomplete e formatador](editor.md).
- **Quer explorar bibliotecas prontas?** Confira [Bibliotecas `cgd:*`](bibliotecas-cgd.md).
- **Quer contribuir com o compilador?** Leia o [Guia de desenvolvimento](desenvolvimento.md).

Use a busca no topo (tecla `S`) ou o menu lateral para pular direto para qualquer assunto.

[← Voltar para a página principal do CGD](../index.html) · [Abrir referência em página única](../linguagem.html)
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
            f"[Ver exemplo completo e contrato de teste no GitHub](https://github.com/FernandoTheDev/cgd/blob/dev/exemplos/{relative})",
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
        parts += ["> " + section["notes"], ""]
    (source / f"{identifier}.md").write_text("\n".join(parts))

summary += ["", "# Guias técnicos aprofundados", ""]
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
