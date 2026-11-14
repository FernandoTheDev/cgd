#!/usr/bin/env python3
"""Protocolo LSP real por stdio: frontend persistente, UTF-16, overlays e cache."""

import json
import subprocess
from pathlib import Path
import tempfile
import select

ROOT = Path(__file__).resolve().parents[1]


class Client:
    def __init__(self):
        self.process = subprocess.Popen(
            [str(ROOT / "cgd"), "--lsp"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
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


with tempfile.TemporaryDirectory(prefix="cgd lsp ") as directory:
    file = Path(directory) / "novo.delegua"
    # File deliberately does not exist: open document overlay must be enough.
    uri = file.as_uri()
    client = Client()
    capabilities = client.request(
        "initialize", {"processId": None, "rootUri": Path(directory).as_uri(), "capabilities": {}}
    )["capabilities"]
    assert (
        capabilities["positionEncoding"] == "utf-16"
        and capabilities["semanticTokensProvider"]["full"]
    )
    source = "funcao dobro(valor:inteiro){retorna valor*2}\nvar ação=dobro(3)\nescreva(ação) // comentário\n"
    client.send(
        "textDocument/didOpen",
        {"textDocument": {"uri": uri, "languageId": "cgd", "version": 1, "text": source}},
    )
    params = {"textDocument": {"uri": uri}, "position": {"line": 1, "character": 10}}
    hover = client.request("textDocument/hover", params)
    assert "dobro" in hover["contents"]["value"], hover
    definition = client.request("textDocument/definition", params)
    assert definition["range"]["start"] == {"line": 0, "character": 7}, definition
    references = client.request("textDocument/references", params)
    assert len(references) == 2, references
    tokens = client.request("textDocument/semanticTokens/full", params)["data"]
    assert tokens and len(tokens) % 5 == 0
    assert 9 in tokens[3::5], "Comentário não veio do lexer"
    completion = client.request("textDocument/completion", params)["items"]
    assert {"dobro", "ação", "escreva"}.issubset({entry["label"] for entry in completion})
    before = client.request("cgd/status")["analyses"]
    for _ in range(10):
        client.request("textDocument/hover", params)
    assert client.request("cgd/status")["analyses"] == before, "Hover refez análise"
    rename = client.request("textDocument/rename", {**params, "newName": "triplo"})
    assert len(rename["changes"][uri]) == 2
    symbols = client.request("textDocument/documentSymbol", params)
    assert any(symbol["name"] == "dobro" for symbol in symbols)
    client.send(
        "textDocument/didChange",
        {
            "textDocument": {"uri": uri, "version": 2},
            "contentChanges": [{"text": 'var x="💚"; escreva(ausente)\n'}],
        },
    )
    client.request("cgd/status")
    diagnostics = [
        event["params"]
        for event in client.events
        if event.get("method") == "textDocument/publishDiagnostics"
    ]
    last = diagnostics[-1]
    assert last["version"] == 2 and any(d["code"] == "E3001" for d in last["diagnostics"]), last
    # Absent identifier starts at UTF-16 column 20, not UTF-8 bytes/codepoints.
    expected = len('var x="💚"; escreva('.encode("utf-16-le")) // 2
    missing = next(d for d in last["diagnostics"] if d["code"] == "E3001")
    assert missing["range"]["start"]["character"] == expected, (missing, expected)
    # Unsaved imports and incomplete member access still resolve exports.
    module = Path(directory) / "modulo.delegua"
    module.write_text("funcao somar(a,b){retorna a+b}")
    module_uri = module.as_uri()
    client.send(
        "textDocument/didOpen",
        {
            "textDocument": {
                "uri": module_uri,
                "languageId": "cgd",
                "version": 1,
                "text": "funcao novo(a,b){retorna a+b}",
            }
        },
    )
    partial = 'var modulo=importar("modulo.delegua")\nmodulo.'
    client.send(
        "textDocument/didChange",
        {"textDocument": {"uri": uri, "version": 3}, "contentChanges": [{"text": partial}]},
    )
    members = client.request(
        "textDocument/completion",
        {"textDocument": {"uri": uri}, "position": {"line": 1, "character": 7}},
    )["items"]
    assert any(item["label"] == "novo" for item in members), members
    assert not any(item["label"] == "somar" for item in members), members
    client.send(
        "textDocument/didChange",
        {
            "textDocument": {"uri": uri, "version": 4},
            "contentChanges": [{"text": 'var modulo=importar("modulo.delegua")\nmodulo.novo(1,2)'}],
        },
    )
    definition = client.request(
        "textDocument/definition",
        {"textDocument": {"uri": uri}, "position": {"line": 1, "character": 8}},
    )
    assert definition["uri"] == module_uri, definition
    client.send(
        "textDocument/didChange",
        {
            "textDocument": {"uri": module_uri, "version": 2},
            "contentChanges": [{"text": "funcao novo(a,b,c){retorna a+b+c}"}],
        },
    )
    hover = client.request(
        "textDocument/hover",
        {"textDocument": {"uri": uri}, "position": {"line": 1, "character": 8}},
    )
    assert "c: qualquer" in hover["contents"]["value"], hover
    # Class members survive incomplete trailing dot.
    client.send(
        "textDocument/didChange",
        {
            "textDocument": {"uri": uri, "version": 5},
            "contentChanges": [
                {
                    "text": 'classe Pessoa{nome:texto construtor(){isto.nome="x"} saudar(){retorna isto.nome}} var pessoa=Pessoa()\npessoa.'
                }
            ],
        },
    )
    members = client.request(
        "textDocument/completion",
        {"textDocument": {"uri": uri}, "position": {"line": 1, "character": 7}},
    )["items"]
    assert {"nome", "saudar"}.issubset({item["label"] for item in members}), members
    # Receiver-specific completion must never mix text and collection methods.
    for version, source, required, forbidden in [
        (6, '"ação".', "maiusculo", "adicionar"),
        (7, 'var texto: texto="x"\ntexto.', "aparar", "chaves"),
        (8, "var itens: inteiro[]=[1]\nitens.", "adicionar", "maiusculo"),
    ]:
        client.send(
            "textDocument/didChange",
            {
                "textDocument": {"uri": uri, "version": version},
                "contentChanges": [{"text": source}],
            },
        )
        lines = source.splitlines()
        labels = {
            item["label"]
            for item in client.request(
                "textDocument/completion",
                {
                    "textDocument": {"uri": uri},
                    "position": {"line": len(lines) - 1, "character": len(lines[-1])},
                },
            )["items"]
        }
        assert required in labels and forbidden not in labels, (source, labels)
    source = "funcao somar(a: inteiro,b: inteiro): inteiro{retorna a+b}\nsomar(1, "
    client.send(
        "textDocument/didChange",
        {"textDocument": {"uri": uri, "version": 9}, "contentChanges": [{"text": source}]},
    )
    help = client.request(
        "textDocument/signatureHelp",
        {"textDocument": {"uri": uri}, "position": {"line": 1, "character": 9}},
    )
    assert help["activeParameter"] == 1 and len(help["signatures"][0]["parameters"]) == 2, help
    source = "funcao dobro(x: inteiro): inteiro{retorna x*2;}\n"
    client.send(
        "textDocument/didChange",
        {"textDocument": {"uri": uri, "version": 10}, "contentChanges": [{"text": source}]},
    )
    edits = client.request(
        "textDocument/formatting",
        {"textDocument": {"uri": uri}, "options": {"tabSize": 2, "insertSpaces": False}},
    )
    assert len(edits) == 1 and "\n    retorna x * 2;" in edits[0]["newText"], edits
    # Local symbols must not escape into unrelated functions or module scope.
    source = "funcao primeira(a: inteiro): inteiro{var segredo: inteiro=1;retorna segredo}\nfuncao segunda(b: inteiro): inteiro{retorna b}\n"
    client.send(
        "textDocument/didChange",
        {"textDocument": {"uri": uri, "version": 11}, "contentChanges": [{"text": source}]},
    )
    labels = {
        item["label"]
        for item in client.request(
            "textDocument/completion",
            {"textDocument": {"uri": uri}, "position": {"line": 2, "character": 0}},
        )["items"]
    }
    assert {"primeira", "segunda"}.issubset(labels) and not {"segredo", "a", "b"}.intersection(
        labels
    ), labels
    # Inherited static and instance members have distinct kinds/visibility.
    source = "classe Base{publico{nome:texto} privado{segredo:texto} estatico criar(): inteiro{retorna 1} metodo(): Base{retorna isto}} classe Filha herda Base{} var filha: Filha=Filha()\nfilha.metodo()."
    client.send(
        "textDocument/didChange",
        {"textDocument": {"uri": uri, "version": 12}, "contentChanges": [{"text": source}]},
    )
    members = client.request(
        "textDocument/completion",
        {
            "textDocument": {"uri": uri},
            "position": {"line": 1, "character": len("filha.metodo().")},
        },
    )["items"]
    kinds = {item["label"]: item["kind"] for item in members}
    assert kinds.get("nome") == 5 and kinds.get("metodo") == 2 and "segredo" not in kinds, members
    source = source.splitlines()[0] + "\nFilha."
    client.send(
        "textDocument/didChange",
        {"textDocument": {"uri": uri, "version": 13}, "contentChanges": [{"text": source}]},
    )
    labels = {
        item["label"]
        for item in client.request(
            "textDocument/completion",
            {"textDocument": {"uri": uri}, "position": {"line": 1, "character": 6}},
        )["items"]
    }
    assert "criar" in labels and "nome" not in labels and "metodo" not in labels, labels
    source = "var itens: qualquer[]=[]\nitens."
    client.send(
        "textDocument/didChange",
        {"textDocument": {"uri": uri, "version": 14}, "contentChanges": [{"text": source}]},
    )
    labels = {
        item["label"]
        for item in client.request(
            "textDocument/completion",
            {"textDocument": {"uri": uri}, "position": {"line": 1, "character": 6}},
        )["items"]
    }
    assert "adicionar" in labels and "maiusculo" not in labels, labels
    source = '\n"abc".substituir("a", '
    client.send(
        "textDocument/didChange",
        {"textDocument": {"uri": uri, "version": 15}, "contentChanges": [{"text": source}]},
    )
    help = client.request(
        "textDocument/signatureHelp",
        {
            "textDocument": {"uri": uri},
            "position": {"line": 1, "character": len(source.splitlines()[-1])},
        },
    )
    assert (
        help
        and help["activeParameter"] == 1
        and "substituto" in help["signatures"][0]["parameters"][1]["label"]
    ), help
    # Exercise the actual JSON library namespace and a chained typed method return.
    library = (ROOT / "bibliotecas/json.delegua").as_posix()
    source = f'var biblioteca: qualquer=importar({json.dumps(library)})\nvar documento: qualquer=biblioteca.JSON({{}})\ndocumento.definir("x",1).'
    client.send(
        "textDocument/didChange",
        {"textDocument": {"uri": uri, "version": 16}, "contentChanges": [{"text": source}]},
    )
    labels = {
        item["label"]
        for item in client.request(
            "textDocument/completion",
            {
                "textDocument": {"uri": uri},
                "position": {"line": 2, "character": len(source.splitlines()[-1])},
            },
        )["items"]
    }
    assert {"obter", "definir", "texto", "valor"}.issubset(labels) and "_valor" not in labels, (
        labels
    )
    source = source.splitlines()[0] + "\nbiblioteca.JSON."
    client.send(
        "textDocument/didChange",
        {"textDocument": {"uri": uri, "version": 17}, "contentChanges": [{"text": source}]},
    )
    labels = {
        item["label"]
        for item in client.request(
            "textDocument/completion",
            {
                "textDocument": {"uri": uri},
                "position": {"line": 1, "character": len("biblioteca.JSON.")},
            },
        )["items"]
    }
    assert labels == {"analisar", "serializar"}, labels
    # A private override hides a public base method instead of leaking its suggestion.
    source = "classe Base{agir(): inteiro{retorna 1}} classe Filha herda Base{privado{agir(): inteiro{retorna 2}}} var filha: Filha=Filha()\nfilha."
    client.send(
        "textDocument/didChange",
        {"textDocument": {"uri": uri, "version": 18}, "contentChanges": [{"text": source}]},
    )
    labels = {
        item["label"]
        for item in client.request(
            "textDocument/completion",
            {"textDocument": {"uri": uri}, "position": {"line": 1, "character": 6}},
        )["items"]
    }
    assert "agir" not in labels, labels
    # Unsaved untitled documents do not require a real filesystem entry.
    untitled = "untitled:Untitled-1"
    client.send(
        "textDocument/didOpen",
        {
            "textDocument": {
                "uri": untitled,
                "languageId": "cgd",
                "version": 1,
                "text": "var valor=1\nescreva(valor)",
            }
        },
    )
    hover = client.request(
        "textDocument/hover",
        {"textDocument": {"uri": untitled}, "position": {"line": 1, "character": 9}},
    )
    assert hover and "valor" in hover["contents"]["value"], hover
    assert not next(
        event["params"]["diagnostics"]
        for event in reversed(client.events)
        if event.get("method") == "textDocument/publishDiagnostics"
        and event["params"]["uri"] == untitled
    ), "Untitled recebeu erro de arquivo inexistente"
    definition = client.request(
        "textDocument/definition",
        {"textDocument": {"uri": untitled}, "position": {"line": 1, "character": 9}},
    )
    assert definition["uri"] == untitled, definition
    client.send("textDocument/didClose", {"textDocument": {"uri": untitled}})
    client.send("textDocument/didClose", {"textDocument": {"uri": uri}})
    client.close()
print("LSP: stdio, hover, definição, referências, rename, tokens, cache e UTF-16 passaram.")
