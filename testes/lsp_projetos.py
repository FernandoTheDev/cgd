#!/usr/bin/env python3
"""Testes avançados do LSP: projeto.json, módulos qualificados, typeDefinition, rangeFormatting e workspace/symbol."""

import json
import select
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class Client:
    def __init__(self, env=None):
        self.process = subprocess.Popen(
            [str(ROOT / "cgd"), "--lsp"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
            bufsize=0,
        )
        self.sequence = 0
        self.events = []

    def send(self, method, params=None, request=False):
        message = {"jsonrpc": "2.0", "method": method, "params": params or {}}
        if request:
            self.sequence += 1
            message["id"] = self.sequence
        payload = json.dumps(message, ensure_ascii=False).encode()
        self.process.stdin.write(f"Content-Length: {len(payload)}\r\n\r\n".encode() + payload)
        self.process.stdin.flush()
        return self.sequence

    def read(self):
        assert select.select([self.process.stdout], [], [], 15)[0], "Servidor LSP não respondeu"
        headers = {}
        while True:
            line = self.process.stdout.readline()
            assert line, self.process.stderr.read().decode()
            if line == b"\r\n":
                break
            key, value = line.decode().split(":", 1)
            headers[key.lower()] = value.strip()
        remaining = int(headers["content-length"])
        data = b""
        while len(data) < remaining:
            data += self.process.stdout.read(remaining - len(data))
        return json.loads(data)

    def request(self, method, params=None):
        identifier = self.send(method, params, True)
        while True:
            reply = self.read()
            if reply.get("id") == identifier:
                assert "error" not in reply, reply
                return reply.get("result")
            self.events.append(reply)

    def close(self):
        self.request("shutdown")
        self.send("exit")
        self.process.wait(timeout=5)
        assert self.process.returncode == 0, self.process.stderr.read().decode()


with tempfile.TemporaryDirectory(prefix="cgd_lsp_proj_") as tmp:
    proj = Path(tmp)
    (proj / "projeto.json").write_text(
        json.dumps(
            {
                "nome": "demo_lsp",
                "versao": "0.1.0",
                "entrada": "fontes/principal.delegua",
                "fontes": "fontes",
            },
            indent=2,
        ),
        encoding="utf-8",
    )
    modelos = proj / "fontes" / "aplicativo" / "modelos"
    servicos = proj / "fontes" / "aplicativo" / "servicos"
    modelos.mkdir(parents=True)
    servicos.mkdir(parents=True)

    usuario_path = modelos / "usuario.delegua"
    usuario_src = (
        "modulo aplicativo.modelos.usuario\n\n"
        "classe Usuario {\n"
        "    nome: texto\n\n"
        "    construtor(nome: texto) {\n"
        "        isto.nome = nome\n"
        "    }\n\n"
        "    saudacao(): texto {\n"
        "        retorna \"Ola, \" + isto.nome\n"
        "    }\n"
        "}\n\n"
        "funcao criarUsuario(nome: texto): Usuario {\n"
        "    retorna Usuario(nome)\n"
        "}\n"
    )
    usuario_path.write_text(usuario_src, encoding="utf-8")

    auth_path = servicos / "auth.delegua"
    auth_src = (
        "modulo aplicativo.servicos.auth\n"
        "importar aplicativo.modelos.usuario\n\n"
        "funcao autenticar(u: aplicativo.modelos.usuario.Usuario): logico {\n"
        "    retorna tamanho(u.nome) > 0\n"
        "}\n"
    )
    auth_path.write_text(auth_src, encoding="utf-8")

    principal_path = proj / "fontes" / "principal.delegua"
    principal_src = (
        "modulo principal\n"
        "importar aplicativo.modelos.usuario\n"
        "importar aplicativo.servicos.auth como Auth\n\n"
        "funcao executar(): inteiro {\n"
        "    var u: aplicativo.modelos.usuario.Usuario = aplicativo.modelos.usuario.criarUsuario(\"Ana\")\n"
        "    se Auth.autenticar(u) {\n"
        "        escreva(u.saudacao())\n"
        "        retorna 1\n"
        "    }\n"
        "    retorna 0\n"
        "}\n\n"
        "executar()\n"
    )
    principal_path.write_text(principal_src, encoding="utf-8")

    client = Client()
    init = client.request(
        "initialize",
        {"processId": None, "rootUri": proj.as_uri(), "capabilities": {}},
    )
    caps = init["capabilities"]
    assert caps.get("declarationProvider") is True, caps
    assert caps.get("typeDefinitionProvider") is True, caps
    assert caps.get("documentRangeFormattingProvider") is True, caps

    p_uri = principal_path.as_uri()
    u_uri = usuario_path.as_uri()
    a_uri = auth_path.as_uri()

    client.send(
        "textDocument/didOpen",
        {"textDocument": {"uri": p_uri, "languageId": "cgd", "version": 1, "text": principal_src}},
    )

    # 1. Definition e declaration cross-module em criarUsuario
    line5 = principal_src.splitlines()[5]
    col_criar = line5.index("criarUsuario") + 2
    defn = client.request(
        "textDocument/definition",
        {"textDocument": {"uri": p_uri}, "position": {"line": 5, "character": col_criar}},
    )
    assert defn is not None and defn["uri"] == u_uri, defn
    assert defn["range"]["start"]["line"] == 14, defn

    decl = client.request(
        "textDocument/declaration",
        {"textDocument": {"uri": p_uri}, "position": {"line": 5, "character": col_criar}},
    )
    assert decl == defn, (decl, defn)

    # 2. Definition no segmento do módulo "usuario" abre usuario.delegua
    col_mod = line5.index("usuario.criarUsuario") + 2
    mod_def = client.request(
        "textDocument/definition",
        {"textDocument": {"uri": p_uri}, "position": {"line": 5, "character": col_mod}},
    )
    assert mod_def is not None and mod_def["uri"] == u_uri, mod_def

    # 3. typeDefinition na variável `u` em `Auth.autenticar(u)` aponta para `classe Usuario` em usuario.delegua
    line6 = principal_src.splitlines()[6]
    col_u = line6.index("(u)") + 1
    tdef = client.request(
        "textDocument/typeDefinition",
        {"textDocument": {"uri": p_uri}, "position": {"line": 6, "character": col_u}},
    )
    assert tdef is not None and tdef["uri"] == u_uri, tdef
    assert tdef["range"]["start"]["line"] == 2, tdef

    # 4. Hover em criarUsuario mostra assinatura com Usuario
    hover = client.request(
        "textDocument/hover",
        {"textDocument": {"uri": p_uri}, "position": {"line": 5, "character": col_criar}},
    )
    assert hover is not None and "criarUsuario" in hover["contents"]["value"], hover

    # 5. Document links para statement imports (usuario.delegua e auth.delegua)
    links = client.request("textDocument/documentLink", {"textDocument": {"uri": p_uri}})
    targets = {lnk["target"] for lnk in links}
    assert u_uri in targets and a_uri in targets, links

    # 6. workspace/symbol descobre símbolos de arquivos do projeto mesmo sem didOpen em auth.delegua
    ws_syms = client.request("workspace/symbol", {"query": "autenticar"})
    assert any(s["name"] == "autenticar" and s["location"]["uri"] == a_uri for s in ws_syms), ws_syms

    # 7. Completion de instância cross-module (u.)
    line7 = principal_src.splitlines()[7]
    col_after_u_dot = line7.index("u.saudacao") + 2
    comp_u = client.request(
        "textDocument/completion",
        {"textDocument": {"uri": p_uri}, "position": {"line": 7, "character": col_after_u_dot}},
    )["items"]
    labels_u = {it["label"] for it in comp_u}
    assert {"saudacao", "nome"}.issubset(labels_u), labels_u
    assert "escreva" not in labels_u, f"Não deve poluir membro com globais: {labels_u}"

    # 8. Completion de namespaces, aliases e statement imports (com digitação incompleta)
    edit_src = principal_src + "\nfuncao rascunho() {\n    aplicativo.\n    aplicativo.modelos.\n    aplicativo.modelos.usuario.\n    Auth.\n}\nimportar aplicativo.\nimportar cgd.interface.\n"
    client.send(
        "textDocument/didChange",
        {
            "textDocument": {"uri": p_uri, "version": 2},
            "contentChanges": [{"text": edit_src}],
        },
    )
    lines_edit = edit_src.splitlines()
    for probe, expected in [
        ("    aplicativo.", {"modelos", "servicos"}),
        ("    aplicativo.modelos.", {"usuario"}),
        ("    aplicativo.modelos.usuario.", {"Usuario", "criarUsuario"}),
        ("    Auth.", {"autenticar"}),
        ("importar aplicativo.", {"aplicativo.modelos.usuario", "aplicativo.servicos.auth"}),
        ("importar cgd.interface.", {"cgd.interface.tui", "cgd.interface.terminal"}),
    ]:
        ln_idx = lines_edit.index(probe)
        res = client.request(
            "textDocument/completion",
            {"textDocument": {"uri": p_uri}, "position": {"line": ln_idx, "character": len(probe)}},
        )["items"]
        labels = {it["label"] for it in res}
        assert expected.issubset(labels), f"Para {probe!r}: esperado {expected}, obtido {labels}"

    # 9. Range formatting formata apenas o intervalo solicitado preservando indentação
    unfmt_src = (
        "funcao f(): inteiro {\n"
        "    var a:inteiro=1+2\n"
        "    var b:inteiro=3+4\n"
        "    retorna a+b\n"
        "}\n"
    )
    fmt_file = proj / "fontes" / "fmt.delegua"
    fmt_file.write_text(unfmt_src, encoding="utf-8")
    f_uri = fmt_file.as_uri()
    client.send(
        "textDocument/didOpen",
        {"textDocument": {"uri": f_uri, "languageId": "cgd", "version": 1, "text": unfmt_src}},
    )
    edits = client.request(
        "textDocument/rangeFormatting",
        {
            "textDocument": {"uri": f_uri},
            "range": {"start": {"line": 1, "character": 0}, "end": {"line": 1, "character": 21}},
            "options": {"tabSize": 4, "insertSpaces": True},
        },
    )
    assert edits and len(edits) == 1, edits
    assert edits[0]["newText"] == "    var a: inteiro = 1 + 2", edits

    # 10. Arquivo com erro sintático não derruba o servidor
    broken_uri = (proj / "fontes" / "quebrado.delegua").as_uri()
    client.send(
        "textDocument/didOpen",
        {
            "textDocument": {
                "uri": broken_uri,
                "languageId": "cgd",
                "version": 1,
                "text": "funcao quebrada( {\n    var x =\n",
            }
        },
    )
    st = client.request("cgd/status")
    assert st["analyses"] > 0, st

    client.close()

print("LSP projetos/módulos: definition, declaration, typeDefinition, completion qualificada, workspace/symbol, rangeFormatting e resiliência passaram.")
