#!/usr/bin/env python3
"""Gera a referência HTML a partir do índice e dos próprios exemplos executáveis."""

import argparse
from html import escape
import json
import re
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--check", action="store_true")
args = parser.parse_args()
sections = json.loads((ROOT / "docs/linguagem.json").read_text())
labels = {"suportado": "Disponível", "parcial": "Com limites", "excluido": "Fora do perfil"}
ids = set()
catalog_source = (ROOT / "src/diagnostics/catalog.d").read_text()
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
message_specs = [
    tuple(json.loads(value) for value in match) for match in re.findall(pattern, catalog_source)
]
assert len(message_specs) == len(re.findall(r"enum\s+MessageSpec\s+\w+", catalog_source)), (
    "Catálogo D não pôde ser extraído integralmente."
)
rows = "".join(
    f"<tr><td><code>{escape(code)}</code></td><td>{escape(message)}</td><td>{escape(explanation)}</td></tr>"
    for code, message, explanation in sorted(message_specs)
)
message_table = f'<h3>Catálogo de diagnósticos</h3><p>Gerado direto do catálogo central do compilador. No terminal, use <code>cgd --explicar E3109</code> para consultar qualquer código. Os códigos <code>W3101</code>–<code>W3112</code> são as versões em aviso dentro de blocos <code>tente/pegue</code>.</p><div class="table-wrap"><table><thead><tr><th>Código</th><th>Mensagem / modelo</th><th>Como resolver</th></tr></thead><tbody>{rows}</tbody></table></div>'


def narrative(section):
    parts = []
    for topic in section.get("topics", []):
        parts.append(f"<h3>{escape(topic['title'])}</h3>")
        for paragraph in topic.get("paragraphs", []):
            parts.append(f"<p>{escape(paragraph)}</p>")
        if "code" in topic:
            parts.append(f"<pre><code>{escape(topic['code'])}</code></pre>")
        if "rows" in topic:
            topic_rows = "".join(
                "<tr>" + "".join(f"<td>{escape(cell)}</td>" for cell in row) + "</tr>"
                for row in topic["rows"]
            )
            parts.append(
                f'<div class="table-wrap"><table><thead><tr><th>Recurso</th><th>Como funciona</th></tr></thead><tbody>{topic_rows}</tbody></table></div>'
            )
    return "".join(parts)


chapters = []
links = []
for section in sections:
    identifier = section["id"]
    assert identifier not in ids
    ids.add(identifier)
    status = section["status"]
    assert status in labels
    links.append(f'<a href="#{escape(identifier)}">{escape(section["title"])}</a>')
    examples = []
    for relative in section["examples"]:
        source = ROOT / "exemplos" / relative
        assert source.is_file(), source
        text = source.read_text()
        assert text.startswith(("//!", "//#", "//$")), source
        code = "\n".join(
            line for line in text.splitlines() if not line.startswith(("//!", "//#", "//?", "//$"))
        )
        examples.append(
            f'<details><summary>{escape(relative)}</summary><p><a href="https://github.com/FernandoTheDev/cgd/blob/dev/exemplos/{escape(relative)}">Abrir arquivo completo e contrato de teste no GitHub</a></p><pre><code>{escape(code)}</code></pre></details>'
        )
    notes_html = (
        f'<p class="callout">{escape(section["notes"])}</p>' if section.get("notes") else ""
    )
    chapters.append(f'''<section class="doc-section guide-chapter" id="{identifier}" data-status="{status}" aria-labelledby="title-{identifier}">
<span class="status-badge status-{status}">{labels[status]}</span>
<h2 id="title-{identifier}">{escape(section["title"])}</h2>
<p class="section-intro">{escape(section["description"])}</p>
{narrative(section)}
{"".join(examples)}
{message_table if identifier == "diagnosticos" else ""}
{notes_html}</section>''')

html = f"""<!DOCTYPE html>
<html lang="pt-br"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="description" content="Referência rápida do CGD (Compilador Geral Delégua): sintaxe, exemplos executáveis, bibliotecas cgd:* e diferenças para o Delégua original.">
<title>CGD — Referência da linguagem</title>
<link rel="icon" type="image/png" href="assets/logo.png">
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;500;700;800&amp;family=Inter:wght@400;500;600;700;800&amp;display=swap" rel="stylesheet">
<link rel="stylesheet" href="assets/style.css?v=docs-4"><script src="assets/guia.js?v=docs-4" defer></script>
</head><body><a href="#conteudo" class="skip-link">Pular para o conteúdo</a>
<header class="navbar"><a class="logo-container home-link" href="index.html" aria-label="CGD, início"><img src="assets/logo.png" alt="Logo do CGD" class="logo"><span class="brand">cgd<span class="brand-dim">.exe</span></span><span class="version-pill">v0.9.0</span></a>
<nav aria-label="Principal"><a class="link-source" href="index.html">início</a><a class="link-source" href="index.html#instalar">instalar</a><a class="link-source" href="livro/index.html">livro</a><a class="link-source" href="https://github.com/FernandoTheDev/cgd/tree/dev">github</a></nav></header>
<main class="docs-wrap guide" id="conteudo"><section class="doc-section"><span class="eyebrow">// referência em página única</span><h1>Guia completo da linguagem no CGD.</h1>
<p class="section-intro">Tudo o que você precisa para escrever, compilar e tirar dúvidas sem sair desta página — do primeiro programa até assincronismo, rotinas paralelas, bibliotecas em <code>~/.delegua/cgd</code> e o catálogo de diagnósticos. Prefere ler capítulo por capítulo? <a href="livro/index.html">Abra o livro do CGD</a>.</p>
<p class="callout"><strong>Transparência sobre a origem:</strong> a linguagem Delégua foi criada pela <a href="https://github.com/DesignLiquido/delegua">Design Líquido</a> (<a href="https://github.com/DesignLiquido/delegua/wiki">wiki oficial</a>). O CGD é um compilador nativo independente e documenta claramente <a href="#delegua-vs-cgd">o que muda e o que foi criado do zero</a>.</p>
<div class="guide-controls"><div><label for="guide-search">Buscar recurso, sintaxe, biblioteca ou erro</label><input type="search" id="guide-search" placeholder="Ex.: herança, rotinas, sqlite, E3109, mescla"></div>
<div><label for="guide-status">Situação</label><select id="guide-status"><option value="">Todos os capítulos</option><option value="suportado">Disponível</option><option value="parcial">Com limites</option><option value="excluido">Fora do perfil</option></select></div></div>
<p id="guide-count" role="status">{len(sections)} capítulos</p>
<nav class="section-nav" aria-label="Capítulos da linguagem">{"".join(links)}</nav></section>
<div id="guide-empty" hidden><p class="callout">Nenhum capítulo encontrado. Tente outro termo ou limpe o filtro.</p></div>
{"".join(chapters)}
<section class="doc-section" id="catalogo"><h2>Catálogo completo de exemplos</h2><p>Todos os 136 exemplos do repositório (incluindo entrada padrão, bibliotecas e erros esperados) fazem parte da suíte de testes no <a href="https://github.com/FernandoTheDev/cgd/blob/dev/exemplos/README.md">catálogo do GitHub</a>.</p>
<pre><code>mkdir -p out
cgd exemplos/linguagem/14_classes.delegua -o -s out/classes
./out/classes
python3 testes/exemplos.py</code></pre>
<p>Quer entender os passes internos do compilador? Leia o <a href="livro/desenvolvimento.html">guia de desenvolvimento</a>.</p></section></main>
<footer><div class="footer-inner"><p style="margin:0">CGD · Compilador Geral Delégua · Linguagem original por <a href="https://github.com/DesignLiquido/delegua">Design Líquido</a> · Apache-2.0.</p><div class="footer-links"><a href="index.html">Início</a><a href="livro/index.html">Livro</a><a href="https://github.com/FernandoTheDev/cgd/tree/dev">GitHub</a></div></div></footer></body></html>"""

formatter = shutil.which("prettier") or str(ROOT / "out/tools/web/node_modules/.bin/prettier")
formatted = subprocess.run(
    [formatter, "--stdin-filepath", str(ROOT / "docs/linguagem.html")],
    input=html,
    text=True,
    capture_output=True,
    check=True,
).stdout
output = ROOT / "docs/linguagem.html"
if args.check:
    if not output.exists() or output.read_text() != formatted:
        raise SystemExit("Referência desatualizada. Execute python3 scripts/gerar_referencia.py.")
    print(f"Referência sincronizada: {len(sections)} capítulos.")
else:
    output.write_text(formatted)
    print(f"Referência gerada: {len(sections)} capítulos com exemplos versionados.")
