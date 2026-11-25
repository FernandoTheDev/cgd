#!/usr/bin/env python3
"""Cliente DAP automatizado: testa cgd dap --stdio com breakpoints em .delegua, stackTrace, variables, evaluate, step over e saída."""

from pathlib import Path
import json
import subprocess
import tempfile
import threading
import queue

ROOT = Path(__file__).resolve().parents[1]
CGD = str(ROOT / "cgd")


class DapClient:
    def __init__(self):
        self.proc = subprocess.Popen(
            [CGD, "dap", "--stdio"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        self.seq = 1
        self.events = queue.Queue()
        self.responses = {}
        self.cond = threading.Condition()
        self.reader = threading.Thread(target=self._read_loop, daemon=True)
        self.reader.start()

    def _read_loop(self):
        stream = self.proc.stdout
        while True:
            content_len = 0
            while True:
                line = stream.readline()
                if not line:
                    with self.cond:
                        self.cond.notify_all()
                    return
                if line in (b"\r\n", b"\n"):
                    break
                if line.lower().startswith(b"content-length:"):
                    content_len = int(line.split(b":", 1)[1].strip())
            if content_len <= 0:
                continue
            data = stream.read(content_len)
            if not data:
                return
            msg = json.loads(data.decode("utf-8"))
            if msg.get("type") == "response":
                with self.cond:
                    self.responses[msg["request_seq"]] = msg
                    self.cond.notify_all()
            elif msg.get("type") == "event":
                self.events.put(msg)

    def request(self, command, arguments=None, timeout=15.0):
        req_seq = self.seq
        self.seq += 1
        payload = {
            "seq": req_seq,
            "type": "request",
            "command": command,
            "arguments": arguments or {},
        }
        raw = json.dumps(payload).encode("utf-8")
        frame = f"Content-Length: {len(raw)}\r\n\r\n".encode("ascii") + raw
        self.proc.stdin.write(frame)
        self.proc.stdin.flush()

        with self.cond:
            deadline_ok = self.cond.wait_for(lambda: req_seq in self.responses, timeout=timeout)
            assert deadline_ok, f"Timeout esperando resposta DAP de '{command}'"
            resp = self.responses.pop(req_seq)
        assert resp.get("success"), f"DAP '{command}' falhou: {resp}"
        return resp.get("body", {})

    def wait_event(self, event_name, timeout=15.0):
        collected = []
        import time

        end = time.monotonic() + timeout
        while True:
            rem = end - time.monotonic()
            assert rem > 0, f"Timeout esperando evento DAP '{event_name}'. Recebidos: {[e.get('event') for e in collected]}"
            ev = self.events.get(timeout=rem)
            collected.append(ev)
            if ev.get("event") == event_name:
                return ev, collected

    def close(self):
        try:
            self.request("disconnect", {}, timeout=5.0)
        except Exception:
            pass
        try:
            self.proc.terminate()
            self.proc.wait(timeout=5)
        except Exception:
            self.proc.kill()


with tempfile.TemporaryDirectory(prefix="cgd_dap_test_") as tmp:
    src = Path(tmp) / "depuravel.delegua"
    src.write_text(
        """funcao calcular(n: inteiro): inteiro {
    var acumulado: inteiro = n * 2
    var titulo: texto = "CGD"
    var ativo: logico = verdadeiro
    var lista: inteiro[] = [10, 20, 30]
    acumulado = acumulado + lista[1]
    retorna acumulado
}

const resposta: inteiro = calcular(11)
escreva("DAP-RESULTADO=", resposta, "\\n")
"""
    )

    client = DapClient()
    try:
        # 1. Initialize
        caps = client.request("initialize", {"adapterID": "cgd", "linesStartAt1": True})
        assert caps.get("supportsConfigurationDoneRequest") is True

        # 2. Launch
        client.request("launch", {"program": str(src), "cwd": tmp, "modo": "desenvolvimento"})
        ev_init, _ = client.wait_event("initialized")
        assert ev_init["event"] == "initialized"

        # 3. Breakpoint na linha 6 (`acumulado = acumulado + lista[1]`)
        bp_body = client.request(
            "setBreakpoints",
            {"source": {"path": str(src)}, "breakpoints": [{"line": 6}]},
        )
        bps = bp_body["breakpoints"]
        assert len(bps) == 1 and bps[0]["verified"] is True, bps

        # 4. ConfigurationDone -> deve parar no breakpoint linha 6
        client.request("configurationDone")
        ev_stop, _ = client.wait_event("stopped")
        assert ev_stop["body"]["reason"] == "breakpoint", ev_stop

        # 5. Threads e StackTrace em Delégua
        threads_body = client.request("threads")
        assert len(threads_body["threads"]) >= 1

        st_body = client.request("stackTrace", {"threadId": 1})
        frames = st_body["stackFrames"]
        assert len(frames) >= 2, frames
        top = frames[0]
        assert top["name"] == "calcular", f"Nome de frame esperado 'calcular', veio: {top}"
        assert top["line"] == 6, f"Linha esperada 6, veio: {top}"
        assert top["source"]["path"].endswith("depuravel.delegua"), top

        # 6. Scopes e Variables (decodificação de nomes e valores Delégua!)
        scopes_body = client.request("scopes", {"frameId": top["id"]})
        local_ref = scopes_body["scopes"][0]["variablesReference"]
        vars_body = client.request("variables", {"variablesReference": local_ref})
        var_map = {v["name"]: v for v in vars_body["variables"]}
        assert "acumulado" in var_map and var_map["acumulado"]["value"] == "22" and var_map["acumulado"]["type"] == "inteiro", var_map
        assert "titulo" in var_map and "CGD" in var_map["titulo"]["value"] and var_map["titulo"]["type"] == "texto", var_map
        assert "ativo" in var_map and var_map["ativo"]["value"] == "verdadeiro" and var_map["ativo"]["type"] == "logico", var_map
        assert "lista" in var_map and var_map["lista"]["value"] == "vetor[3]" and var_map["lista"]["variablesReference"] > 0, var_map

        # Expansão dos elementos do vetor
        elem_body = client.request("variables", {"variablesReference": var_map["lista"]["variablesReference"]})
        elems = [v["value"] for v in elem_body["variables"]]
        assert elems == ["10", "20", "30"], elems

        # 7. Evaluate
        eval_body = client.request("evaluate", {"expression": "acumulado", "frameId": top["id"]})
        assert eval_body["result"] == "22", eval_body

        # 8. Step Over (`next`) -> linha 7, e `acumulado` agora deve valer 42!
        client.request("next", {"threadId": 1})
        ev_step, _ = client.wait_event("stopped")
        assert ev_step["body"]["reason"] == "step", ev_step
        st2 = client.request("stackTrace", {"threadId": 1})
        assert st2["stackFrames"][0]["line"] == 7, st2["stackFrames"][0]
        eval_after = client.request("evaluate", {"expression": "acumulado", "frameId": st2["stackFrames"][0]["id"]})
        assert eval_after["result"] == "42", eval_after

        # 9. Continue -> termina com código 0 e imprime DAP-RESULTADO=42
        client.request("continue", {"threadId": 1})
        ev_term, evs = client.wait_event("terminated")
        outputs = "".join(e["body"]["output"] for e in evs if e.get("event") == "output")
        assert "DAP-RESULTADO=42" in outputs, f"Saída esperada ausente: {outputs!r}"

    finally:
        client.close()

# Cenário 2: Projeto multi-módulo (sem `program`, só `cwd` com projeto.json) + breakpoint em módulo importado + stepIn/stepOut
with tempfile.TemporaryDirectory(prefix="cgd_dap_proj_") as tmp:
    p = Path(tmp)
    (p / "fontes" / "util").mkdir(parents=True)
    (p / "projeto.json").write_text(json.dumps({"nome": "dap-proj", "entrada": "fontes/principal.delegua"}))
    mod_file = p / "fontes" / "util" / "calc.delegua"
    mod_file.write_text(
        """modulo util.calc

funcao fatorial(k: inteiro): inteiro {
    se k <= 1 {
        retorna 1
    }
    var sub: inteiro = fatorial(k - 1)
    retorna k * sub
}
"""
    )
    (p / "fontes" / "principal.delegua").write_text(
        """modulo principal
importar util.calc

const r: inteiro = util.calc.fatorial(4)
escreva("FAT=", r, "\\n")
"""
    )
    c2 = DapClient()
    try:
        c2.request("initialize", {"adapterID": "cgd"})
        c2.request("launch", {"cwd": str(p), "modo": "desenvolvimento"})
        c2.wait_event("initialized")
        bp = c2.request(
            "setBreakpoints",
            {"source": {"path": str(mod_file)}, "breakpoints": [{"line": 5}]},
        )
        assert bp["breakpoints"][0]["verified"] is True, bp
        c2.request("configurationDone")
        ev_s, _ = c2.wait_event("stopped")
        assert ev_s["body"]["reason"] == "breakpoint"
        st = c2.request("stackTrace", {"threadId": 1})
        # Na base da recursão (k=1), deve haver 4 frames de `fatorial` + `<principal>`!
        fat_frames = [f for f in st["stackFrames"] if f["name"] == "fatorial"]
        assert len(fat_frames) == 4, st["stackFrames"]
        assert fat_frames[0]["source"]["path"].endswith("calc.delegua")
        c2.request("stepOut", {"threadId": 1})
        ev_out, _ = c2.wait_event("stopped")
        assert ev_out["body"]["reason"] == "step", ev_out
        c2.request("continue", {"threadId": 1})
        _, evs = c2.wait_event("terminated")
        out_txt = "".join(e["body"]["output"] for e in evs if e.get("event") == "output")
        assert "FAT=24" in out_txt, out_txt
    finally:
        c2.close()

# Cenário 3: Breakpoint em exceção (`setExceptionBreakpoints`)
with tempfile.TemporaryDirectory(prefix="cgd_dap_exc_") as tmp:
    src = Path(tmp) / "falha.delegua"
    src.write_text(
        """tente {
    falhar "boom-dap"
} pegue (erro: Excecao) {
    escreva("CAPTURADO:", erro, "\\n")
}
"""
    )
    c3 = DapClient()
    try:
        c3.request("initialize", {"adapterID": "cgd"})
        c3.request("launch", {"program": str(src), "cwd": tmp, "modo": "desenvolvimento"})
        c3.wait_event("initialized")
        c3.request("setExceptionBreakpoints", {"filters": ["all"]})
        c3.request("configurationDone")
        ev_exc, _ = c3.wait_event("stopped")
        assert ev_exc["body"]["reason"] == "breakpoint", ev_exc
        c3.request("continue", {"threadId": 1})
        _, evs = c3.wait_event("terminated")
        out_txt = "".join(e["body"]["output"] for e in evs if e.get("event") == "output")
        assert "CAPTURADO:boom-dap" in out_txt, out_txt
    finally:
        c3.close()

print("DAP (Marco F): todos os 3 cenários (simples + multi-módulo/recursão/stepOut + exceções) passaram.")
