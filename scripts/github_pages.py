#!/usr/bin/env python3
"""Consulta/publica o Pages de dev/docs com a credencial do Git, somente em memória."""

import argparse
import json
import os
from pathlib import Path
import subprocess
import time
from urllib.error import HTTPError
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
REPOSITORY = "FernandoTheDev/cgd"
BASE = "https://api.github.com/repos/" + REPOSITORY
parser = argparse.ArgumentParser()
parser.add_argument("--publish", action="store_true")
parser.add_argument("--timeout", type=int, default=300)
args = parser.parse_args()
result = subprocess.run(
    [
        "git",
        "-c",
        "credential.interactive=false",
        "-c",
        "core.askPass=/bin/false",
        "credential",
        "fill",
    ],
    cwd=ROOT,
    input="protocol=https\nhost=github.com\npath=" + REPOSITORY + "\n\n",
    text=True,
    capture_output=True,
    env={**os.environ, "GIT_TERMINAL_PROMPT": "0"},
)
credential = dict(line.split("=", 1) for line in result.stdout.splitlines() if "=" in line)
password = credential.get("password")
if not password:
    raise SystemExit("O helper do Git não disponibilizou uma credencial HTTPS para a API do Pages.")
headers = {
    "Authorization": "Bearer " + password,
    "Accept": "application/vnd.github+json",
    "User-Agent": "CGD-pages-publisher",
    "X-GitHub-Api-Version": "2022-11-28",
}


def api(path, method="GET", body=None):
    request = Request(
        BASE + path,
        method=method,
        headers=headers,
        data=json.dumps(body).encode() if body is not None else None,
    )
    try:
        with urlopen(request, timeout=30) as response:
            data = response.read()
            return json.loads(data) if data else {}
    except HTTPError as error:
        raise SystemExit(
            f"GitHub Pages API: HTTP {error.code} em {method} {path}; nenhuma credencial foi registrada."
        ) from None


site = api("/pages")
if args.publish:
    local = subprocess.check_output(
        ["git", "rev-parse", "refs/heads/dev"], cwd=ROOT, text=True
    ).strip()
    remote = subprocess.check_output(
        ["git", "ls-remote", "origin", "refs/heads/dev"], cwd=ROOT, text=True
    ).split()[0]
    if local != remote:
        raise SystemExit("Publique o commit de dev antes de configurar o Pages.")
    if site.get("build_type") != "legacy":
        raise SystemExit(
            "O Pages usa workflow próprio; este utilitário não substitui workflows existentes."
        )
    source = {"branch": "dev", "path": "/docs"}
    if site.get("source") != source:
        api("/pages", "PUT", {"source": source})
    api("/pages/builds", "POST")
    deadline = time.monotonic() + args.timeout
    while time.monotonic() < deadline:
        build = api("/pages/builds/latest")
        print(
            "Pages:", build.get("status"), "commit", str(build.get("commit", ""))[:12], flush=True
        )
        if build.get("status") == "built" and build.get("commit") == local:
            break
        if build.get("status") == "errored":
            raise SystemExit(
                "O build do Pages falhou: "
                + str(build.get("error", {}).get("message", "sem mensagem"))
            )
        time.sleep(10)
    else:
        raise SystemExit("Publicação ainda pendente; consulte o Pages antes de informar sucesso.")
    site = api("/pages")
    summary = {key: site.get(key) for key in ["html_url", "source", "build_type", "status"]}
    summary["commit"] = local
    out = ROOT / "out/pages.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(summary, ensure_ascii=False))
else:
    print(
        json.dumps(
            {key: site.get(key) for key in ["html_url", "source", "build_type", "status"]},
            ensure_ascii=False,
        )
    )
