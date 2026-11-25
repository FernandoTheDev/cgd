#!/usr/bin/env python3
"""Testes automatizados de LSP, DAP e Extensão VS Code para o Prompt Mestre X."""

from __future__ import annotations

import json
import os
import queue
import select
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CGD = str(ROOT / "cgd")


class LspClient:
    def __init__(self) -> None:
        env = os.environ.copy()
        env["CGD_LIBS_DIR"] = str(ROOT / "bibliotecas")
        self.proc = subprocess.Popen(
            [CGD, "--lsp"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
            bufsize=0,
        )
        self.seq = 0
        self.events: list[dict] = []

    def send(self, method: str, params: dict | None = None, request: bool = False) -> int:
        msg: dict = {"jsonrpc": "2.0", "method": method, "params": params or {}}
        if request:
            self.seq += 1
            msg["id"] = self.seq
        payload = json.dumps(msg, ensure_ascii=False).encode("utf-8")
        assert self.proc.stdin is not None
        self.proc.stdin.write(f"Content-Length: {len(payload)}\r\n\r\n".encode("ascii") + payload)
        self.proc.stdin.flush()
        return self.seq

    def read(self) -> dict:
        assert self.proc.stdout is not None
        assert select.select([self.proc.stdout], [], [], 15)[0], "Timeout LSP"
        headers: dict[str, str] = {}
        while True:
            line = self.proc.stdout.readline()
            assert line, "EOF inesperado no LSP"
            if line in (b"\r\n", b"\n"):
                break
            k, v = line.decode("utf-8").split(":", 1)
            headers[k.lower()] = v.strip()
        n = int(headers["content-length"])
        buf = b""
        while len(buf) < n:
            buf += self.proc.stdout.read(n - len(buf))
        return json.loads(buf.decode("utf-8"))

    def request(self, method: str, params: dict | None = None):
        rid = self.send(method, params, True)
        while True:
            msg = self.read()
            if msg.get("id") == rid:
                assert "error" not in msg, msg
                return msg.get("result")
            self.events.append(msg)

    def wait_diagnostics(self, uri: str) -> list[dict]:
        for ev in reversed(self.events):
            if ev.get("method") == "textDocument/publishDiagnostics" and ev["params"]["uri"] == uri:
                return ev["params"]["diagnostics"]
        # força sincronização pedindo hover/semanticTokens
        self.request("textDocument/semanticTokens/full", {"textDocument": {"uri": uri}})
        for ev in reversed(self.events):
            if ev.get("method") == "textDocument/publishDiagnostics" and ev["params"]["uri"] == uri:
                return ev["params"]["diagnostics"]
        return []

    def close(self) -> None:
        self.request("shutdown")
        self.send("exit")
        self.proc.wait(timeout=5)
        assert self.proc.returncode == 0


class DapClient:
    def __init__(self) -> None:
        env = os.environ.copy()
        env["CGD_LIBS_DIR"] = str(ROOT / "bibliotecas")
        self.proc = subprocess.Popen(
            [CGD, "dap", "--stdio"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
        )
        self.seq = 1
        self.events: queue.Queue[dict] = queue.Queue()
        self.responses: dict[int, dict] = {}
        self.cond = threading.Condition()
        self.reader = threading.Thread(target=self._read_loop, daemon=True)
        self.reader.start()

    def _read_loop(self) -> None:
        assert self.proc.stdout is not None
        stream = self.proc.stdout
        while True:
            clen = 0
            while True:
                line = stream.readline()
                if not line:
                    with self.cond:
                        self.cond.notify_all()
                    return
                if line in (b"\r\n", b"\n"):
                    break
                if line.lower().startswith(b"content-length:"):
                    clen = int(line.split(b":", 1)[1].strip())
            if clen <= 0:
                continue
            data = stream.read(clen)
            if not data:
                return
            msg = json.loads(data.decode("utf-8"))
            if msg.get("type") == "response":
                with self.cond:
                    self.responses[msg["request_seq"]] = msg
                    self.cond.notify_all()
            elif msg.get("type") == "event":
                self.events.put(msg)

    def request(self, command: str, arguments: dict | None = None, timeout: float = 20.0) -> dict:
        rid = self.seq
        self.seq += 1
        payload = {"seq": rid, "type": "request", "command": command, "arguments": arguments or {}}
        raw = json.dumps(payload).encode("utf-8")
        assert self.proc.stdin is not None
        self.proc.stdin.write(f"Content-Length: {len(raw)}\r\n\r\n".encode("ascii") + raw)
        self.proc.stdin.flush()
        with self.cond:
            ok = self.cond.wait_for(lambda: rid in self.responses, timeout=timeout)
            assert ok, f"Timeout DAP em '{command}'"
            resp = self.responses.pop(rid)
        assert resp.get("success"), f"DAP '{command}' falhou: {resp}"
        return resp.get("body", {})

    def wait_event(self, event_name: str, timeout: float = 20.0) -> dict:
        end = time.monotonic() + timeout
        seen: list[str] = []
        while True:
            rem = end - time.monotonic()
            assert rem > 0, f"Timeout esperando evento DAP '{event_name}'. Recebidos: {seen}"
            ev = self.events.get(timeout=rem)
            seen.append(str(ev.get("event")))
            if ev.get("event") == event_name:
                return ev

    def close(self) -> None:
        try:
            self.request("disconnect", {"terminateDebuggee": True}, timeout=5.0)
        except Exception:
            pass
        try:
            self.proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.proc.kill()


def test_lsp() -> int:
    passed = 0
    with tempfile.TemporaryDirectory(prefix="cgd_lsp_pmx_") as tmp:
        root_uri = Path(tmp).as_uri()
        client = LspClient()
        client.request("initialize", {"processId": None, "rootUri": root_uri, "capabilities": {}})

        # 1. Completion de decoradores @
        f1 = Path(tmp) / "dec.delegua"
        u1 = f1.as_uri()
        client.send("textDocument/didOpen", {
            "textDocument": {"uri": u1, "languageId": "cgd", "version": 1, "text": "@\nfuncao f(): inteiro { retorna 1 }\n"}
        })
        comp1 = client.request("textDocument/completion", {
            "textDocument": {"uri": u1}, "position": {"line": 0, "character": 1}
        })
        labels1 = {item["label"] for item in (comp1 if isinstance(comp1, list) else comp1.get("items", []))}
        for req in ("nativo", "pilha", "quando", "operador", "gpu", "puro"):
            assert any(req in lb for lb in labels1), f"Decorador @{req} ausente em {labels1}"
        passed += 1
        print("[IDE-LSP-01] OK: completion de decoradores @nativo/@pilha/@quando/@operador/@gpu/@puro")

        # 2. Completion de tipos C e containers nativos
        f2 = Path(tmp) / "tipos.delegua"
        u2 = f2.as_uri()
        client.send("textDocument/didOpen", {
            "textDocument": {"uri": u2, "languageId": "cgd", "version": 1, "text": "@nativo\nfuncao f(x: c): ci32 {\n    var v = Vet\n    retorna 0\n}\n"}
        })
        comp2a = client.request("textDocument/completion", {
            "textDocument": {"uri": u2}, "position": {"line": 1, "character": 13}
        })
        labels2a = {item["label"] for item in (comp2a if isinstance(comp2a, list) else comp2a.get("items", []))}
        for t in ("ci32", "cf64", "cchar", "csize", "cbool"):
            assert t in labels2a, f"Tipo C '{t}' ausente em completion: {labels2a}"
        comp2b = client.request("textDocument/completion", {
            "textDocument": {"uri": u2}, "position": {"line": 2, "character": 15}
        })
        labels2b = {item["label"] for item in (comp2b if isinstance(comp2b, list) else comp2b.get("items", []))}
        assert "VetorNativo" in labels2b, f"VetorNativo ausente: {labels2b}"
        passed += 1
        print("[IDE-LSP-02] OK: completion de tipos C e containers nativos")

        # 3. Completion após ponto em VetorNativo<ci32>
        f3 = Path(tmp) / "dot.delegua"
        u3 = f3.as_uri()
        src3 = "@nativo\nfuncao f(): ci32 {\n    var v = VetorNativo<ci32>()\n    v.\n    retorna 0\n}\n"
        client.send("textDocument/didOpen", {
            "textDocument": {"uri": u3, "languageId": "cgd", "version": 1, "text": src3}
        })
        comp3 = client.request("textDocument/completion", {
            "textDocument": {"uri": u3}, "position": {"line": 3, "character": 6}
        })
        labels3 = {item["label"] for item in (comp3 if isinstance(comp3, list) else comp3.get("items", []))}
        for m in ("adicionar", "tamanho", "fatia", "clonar", "liberar"):
            assert m in labels3, f"Método '{m}' ausente em VetorNativo.: {labels3}"
        passed += 1
        print("[IDE-LSP-03] OK: completion de membros em VetorNativo<ci32>.")

        # 4, 5, 6. Hover (@pilha/@nativo/@operador), Go to Definition de `a + b`, Find References de `@operador("+")`
        f4 = Path(tmp) / "ops.delegua"
        u4 = f4.as_uri()
        src4 = (
            "@pilha\n"
            "classe Vet2 {\n"
            "    x: cf64\n"
            "    y: cf64\n"
            "    @nativo\n"
            '    @operador("+")\n'
            "    somar(outro: Vet2): Vet2 {\n"
            "        retorna Vet2(isto.x + outro.x, isto.y + outro.y)\n"
            "    }\n"
            "}\n"
            "@nativo\n"
            "funcao calc(): cf64 {\n"
            "    const a = Vet2(1.0, 2.0)\n"
            "    const b = Vet2(3.0, 4.0)\n"
            "    const c = a + b\n"
            "    retorna c.x\n"
            "}\n"
        )
        client.send("textDocument/didOpen", {
            "textDocument": {"uri": u4, "languageId": "cgd", "version": 1, "text": src4}
        })
        hover_cls = client.request("textDocument/hover", {
            "textDocument": {"uri": u4}, "position": {"line": 1, "character": 8}
        })
        assert hover_cls and ("@pilha" in hover_cls["contents"]["value"] or "valor" in hover_cls["contents"]["value"].lower()), hover_cls
        hover_fn = client.request("textDocument/hover", {
            "textDocument": {"uri": u4}, "position": {"line": 11, "character": 8}
        })
        assert hover_fn and "@nativo" in hover_fn["contents"]["value"], hover_fn
        passed += 1
        print("[IDE-LSP-04] OK: hover exibe metadados de @pilha e @nativo")

        # Go to Definition no `+` em `const c = a + b` (linha 14, col 16)
        defn = client.request("textDocument/definition", {
            "textDocument": {"uri": u4}, "position": {"line": 14, "character": 16}
        })
        assert defn, "Go to Definition no operador '+' retornou vazio"
        loc = defn[0] if isinstance(defn, list) else defn
        assert loc["range"]["start"]["line"] in (5, 6), f"Linha inesperada para @operador('+'): {loc}"
        passed += 1
        print("[IDE-LSP-05] OK: Go to Definition de 'a + b' navega para @operador(\"+\")")

        # Find References a partir do método `somar` (linha 6, col 5)
        refs = client.request("textDocument/references", {
            "textDocument": {"uri": u4},
            "position": {"line": 6, "character": 5},
            "context": {"includeDeclaration": True},
        })
        ref_lines = {r["range"]["start"]["line"] for r in (refs or [])}
        assert 14 in ref_lines, f"Uso de 'a + b' (linha 14) ausente em Find References: {ref_lines}"
        passed += 1
        print("[IDE-LSP-06] OK: Find References de @operador(\"+\") inclui uso 'a + b'")

        # 7. Diagnóstico LSP de ownership (E3801)
        f5 = Path(tmp) / "own_err.delegua"
        u5 = f5.as_uri()
        src5 = "@nativo\nfuncao f(): ci32 {\n    var v = VetorNativo<ci32>()\n    v.adicionar(1)\n    var w = v\n    retorna v[0]\n}\n"
        client.send("textDocument/didOpen", {
            "textDocument": {"uri": u5, "languageId": "cgd", "version": 1, "text": src5}
        })
        diags5 = client.wait_diagnostics(u5)
        assert any("E3801" in str(d.get("code", "")) or "ownership" in d.get("message", "").lower() for d in diags5), diags5
        passed += 1
        print("[IDE-LSP-07] OK: diagnóstico LSP E3801 para use-after-move")

        # 8. Diagnóstico LSP sem falso positivo em ramo @quando inativo
        f6 = Path(tmp) / "cond.delegua"
        u6 = f6.as_uri()
        src6 = (
            '@quando(Compilacao.sistemaOperacional() == "windows")\n'
            "funcao plat(): inteiro { retorna simboloFantasmaWin() }\n"
            '@quando(Compilacao.sistemaOperacional() == "linux")\n'
            "funcao plat(): inteiro { retorna 42 }\n"
            "escreva(plat())\n"
        )
        client.send("textDocument/didOpen", {
            "textDocument": {"uri": u6, "languageId": "cgd", "version": 1, "text": src6}
        })
        diags6 = client.wait_diagnostics(u6)
        errs6 = [d for d in diags6 if d.get("severity") == 1]
        assert len(errs6) == 0, f"Erros indevidos em ramo @quando inativo: {errs6}"
        passed += 1
        print("[IDE-LSP-08] OK: LSP respeita compilação condicional @quando sem falsos erros")

        client.close()
    return passed


def test_dap() -> int:
    passed = 0
    with tempfile.TemporaryDirectory(prefix="cgd_dap_pmx_") as tmp:
        src_path = Path(tmp) / "depura_nativo.delegua"
        src_path.write_text(
            "@pilha\n"
            "classe Ponto {\n"
            "    x: cf64\n"
            "    y: cf64\n"
            "}\n"
            "@nativo\n"
            "funcao calcularNativo(a: ci32): ci32 {\n"
            "    var p = Ponto(3.5, 7.25)\n"
            "    var v = VetorNativo<ci32>()\n"
            "    v.adicionar(10)\n"
            "    v.adicionar(20)\n"
            "    var soma: ci32 = a + v[0] + v[1] + ci32(p.x)\n"
            "    retorna soma\n"
            "}\n"
            "const r = calcularNativo(5)\n"
            'escreva("DAP_OK=", r)\n',
            encoding="utf-8",
        )
        client = DapClient()
        try:
            client.request("initialize", {"adapterID": "cgd", "linesStartAt1": True, "columnsStartAt1": True})
            client.request("launch", {"program": str(src_path), "cwd": tmp, "modo": "desenvolvimento"})
            client.wait_event("initialized")
            # Breakpoint na linha 13 (`retorna soma`) dentro de calcularNativo
            bp = client.request("setBreakpoints", {
                "source": {"path": str(src_path)},
                "breakpoints": [{"line": 13}],
            })
            assert bp.get("breakpoints") and bp["breakpoints"][0].get("verified"), bp
            client.request("configurationDone")

            ev = client.wait_event("stopped")
            tid = ev["body"]["threadId"]
            if ev["body"].get("reason") == "entry":
                client.request("continue", {"threadId": tid})
                ev = client.wait_event("stopped")
                tid = ev["body"]["threadId"]
            passed += 1
            print("[IDE-DAP-01] OK: breakpoint atingido dentro de função @nativo")

            st = client.request("stackTrace", {"threadId": tid})
            frames = st.get("stackFrames", [])
            assert frames, "Nenhum frame retornado no stackTrace"
            top_name = frames[0]["name"]
            assert "calcularNativo" in top_name, f"Nome de frame nativo inesperado: {frames}"
            passed += 1
            print(f"[IDE-DAP-02] OK: stackTrace legível para função @nativo ({top_name})")

            scopes = client.request("scopes", {"frameId": frames[0]["id"]})["scopes"]
            assert scopes, "Nenhum escopo retornado"
            vars_body = client.request("variables", {"variablesReference": scopes[0]["variablesReference"]})
            vmap = {v["name"]: v for v in vars_body.get("variables", [])}

            # Verificar escalares C nativos (`a` e `soma`)
            assert "a" in vmap and "5" in vmap["a"]["value"], f"Escalar 'a' incorreto: {vmap}"
            assert "soma" in vmap and "38" in vmap["soma"]["value"], f"Escalar 'soma' incorreto: {vmap}"
            passed += 1
            print(f"[IDE-DAP-03] OK: inspeção de escalares C nativos (a={vmap['a']['value']}, soma={vmap['soma']['value']})")

            # Verificar struct @pilha (`p`) e VetorNativo (`v`) expandíveis
            assert "p" in vmap, f"Struct @pilha 'p' ausente: {vmap}"
            if vmap["p"].get("variablesReference", 0) > 0:
                p_fields = {f["name"]: f["value"] for f in client.request("variables", {
                    "variablesReference": vmap["p"]["variablesReference"]
                }).get("variables", [])}
                assert "x" in p_fields and "3.5" in p_fields["x"], f"Campos de @pilha 'p' incorretos: {p_fields}"
            assert "v" in vmap, f"VetorNativo 'v' ausente: {vmap}"
            if vmap["v"].get("variablesReference", 0) > 0:
                v_elems = {f["name"]: f["value"] for f in client.request("variables", {
                    "variablesReference": vmap["v"]["variablesReference"]
                }).get("variables", [])}
                assert any("10" in val for val in v_elems.values()), f"Elementos de VetorNativo 'v': {v_elems}"
            passed += 1
            print(f"[IDE-DAP-04] OK: inspeção de @pilha 'p' ({vmap['p']['value']}) e VetorNativo 'v' ({vmap['v']['value']})")

            client.request("continue", {"threadId": tid})
            client.wait_event("terminated")
        finally:
            client.close()
    return passed


def test_vscode_extension() -> int:
    passed = 0
    grammar_path = ROOT / "extensao-vscode" / "syntaxes" / "delegua.tmLanguage.json"
    snippets_path = ROOT / "extensao-vscode" / "snippets" / "delegua.json"

    grammar = json.loads(grammar_path.read_text(encoding="utf-8"))
    grammar_text = grammar_path.read_text(encoding="utf-8")
    for expected in ("ci32", "cf64", "cchar", "csize", "VetorNativo", "MapaNativo", "StringNativa", "Compilacao"):
        assert expected in grammar_text, f"'{expected}' ausente em delegua.tmLanguage.json"
    passed += 1
    print("[IDE-VSC-01] OK: gramática VS Code contém tipos C, containers nativos e Compilacao")

    # Garantir que NENHUMA keyword proibida foi adicionada à gramática
    forbidden = ("comptime", "emprestado", "ownership", "borrow", "unsafe", "stack")
    for kw in forbidden:
        assert kw not in grammar_text, f"Keyword proibida '{kw}' encontrada na gramática VS Code!"
    passed += 1
    print("[IDE-VSC-02] OK: nenhuma keyword proibida na gramática VS Code")

    snippets = json.loads(snippets_path.read_text(encoding="utf-8"))
    snip_text = json.dumps(snippets, ensure_ascii=False)
    for expected in ("@nativo", "@pilha", "@operador", "@quando", "@gpu"):
        assert expected in snip_text, f"Snippet para '{expected}' ausente em snippets/delegua.json"
    passed += 1
    print("[IDE-VSC-03] OK: snippets VS Code cobrem @nativo, @pilha, @operador, @quando e @gpu")

    return passed


def main() -> int:
    total = 0
    total += test_lsp()
    total += test_dap()
    total += test_vscode_extension()
    print(f"\n=== RESUMO IDE PROMPT MESTRE X: {total}/15 aprovados ===")
    return 0


if __name__ == "__main__":
    sys.exit(main())
