#!/usr/bin/env python3
"""Confere páginas, recursos e links do livro gerado, sem acesso à rede."""

from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[1]
BOOK = ROOT / "docs/livro"


class Page(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links = []
        self.ids = set()

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if "id" in attrs:
            self.ids.add(attrs["id"])
        for key in ("href", "src"):
            if key in attrs:
                self.links.append(attrs[key])


pages = {}
for path in BOOK.rglob("*.html"):
    page = Page()
    page.feed(path.read_text())
    pages[path.resolve()] = page
assert len(pages) > 25
failures = []
for path, page in pages.items():
    for link in page.links:
        url = urlsplit(link)
        if url.scheme or url.netloc:
            continue
        if not url.path:
            target = path
        elif url.path.startswith("/cgd/"):
            target = (ROOT / "docs" / unquote(url.path)[len("/cgd/") :]).resolve()
        else:
            target = (path.parent / unquote(url.path)).resolve()
        if not target.exists():
            failures.append(f"{path.name}: {link}")
        elif url.fragment and target in pages and unquote(url.fragment) not in pages[target].ids:
            failures.append(f"{path.name}: âncora ausente em {link}")
assert not failures, "\n".join(failures)
assert (BOOK / "searchindex.js").exists()
assert "registerLanguage" in (BOOK / "tema/delegua.js").read_text()
print(f"Livro: {len(pages)} páginas, links locais, recursos e índice de busca conferidos.")
