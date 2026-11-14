#!/usr/bin/env python3
"""Contratos da CLI, diagnósticos, loading e emissão independente de toolchain."""

from pathlib import Path
import json
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
checks = 0


def run(file, *flags, env=None):
    return subprocess.run(
        [str(ROOT / "cgd"), str(file), *flags],
        capture_output=True,
        text=True,
        timeout=20,
        env=env,
    )


with tempfile.TemporaryDirectory(prefix="cgd driver ") as tmp:
    folder = Path(tmp)
    source = folder / "a.delegua"
    source.write_text("escreva((2+3)*4)")
    environment = {**os.environ, "CC": "/compilador/inexistente", "PKG_CONFIG": "/pkg/inexistente"}
    for flags in [("--verificar",), ("--emitir-c", "-s", str(folder / "emitido"))]:
        result = run(source, *flags, env=environment)
        assert result.returncode == 0, result.stderr
        checks += 1
    assert not (folder / "emitido").exists()
    assert "delegua_main" in (folder / "emitido.c").read_text()
    checks += 1

    source.write_text("var a=; var b=; var c=3")
    result = run(source, "--verificar", "--diagnosticos=json")
    diagnostics = [json.loads(line) for line in result.stderr.splitlines()]
    assert result.returncode == 1 and len(diagnostics) == 2
    assert all(d["code"] == "E1001" and d["file"] == str(source) for d in diagnostics)
    checks += 1

    source.write_text("funcao f(){retorna 1;escreva(99)}")
    result = run(source, "--verificar", "--diagnosticos=json")
    assert result.returncode == 0, result.stderr
    assert any(json.loads(line)["code"] == "W3001" for line in result.stderr.splitlines())
    checks += 1

    source.write_text("var enorme=" + "+".join(["1"] * 600))
    result = run(source, "--verificar", "--diagnosticos=json")
    assert result.returncode == 1 and json.loads(result.stderr)["code"] == "E1004", result.stderr
    checks += 1

    source.write_bytes(b'var x="\xff"')
    result = run(source, "--verificar", "--diagnosticos=json")
    assert result.returncode == 1 and json.loads(result.stderr)["code"] == "E1002", result.stderr
    checks += 1
    result = run(source, "--verificar")
    assert result.returncode == 1 and "E1002" in result.stderr and "E9001" not in result.stderr
    checks += 1

    source.write_text("var b=importar('b.delegua')")
    (folder / "b.delegua").write_text("var c=importar('c.delegua')")
    (folder / "c.delegua").write_text("var a=importar('a.delegua')")
    result = run(source, "--verificar", "--diagnosticos=json")
    diagnostic = json.loads(result.stderr)
    assert diagnostic["code"] == "E2001"
    assert all(name in diagnostic["message"] for name in ["a.delegua", "b.delegua", "c.delegua"])
    checks += 1

    source.write_text("var b=importar('ausente.delegua')")
    result = run(source, "--verificar", "--diagnosticos=json")
    assert json.loads(result.stderr)["code"] == "E2003"
    checks += 1

    source.write_text("var valor=3; escreva(valro)")
    result = run(source, "--verificar", "--diagnosticos=json")
    diagnostics = [json.loads(line) for line in result.stderr.splitlines()]
    assert any(d["code"] == "H3001" and "valor" in d["message"] for d in diagnostics)
    checks += 1

    for flags in [
        ("--verificar", "--emitir-c"),
        ("--diagnosticos=xml",),
        ("--diagnosticos=json", "--depurar"),
    ]:
        assert run(source, *flags).returncode == 1
        checks += 1

    large = folder / "grande.delegua"
    with large.open("wb") as stream:
        stream.seek(4 * 1024 * 1024)
        stream.write(b" ")
    source.write_text("var grande=importar('grande.delegua')")
    result = run(source, "--verificar", "--diagnosticos=json")
    assert json.loads(result.stderr)["code"] == "E2002", result.stderr
    checks += 1
    result = run(large, "--verificar", "--diagnosticos=json")
    assert json.loads(result.stderr)["code"] == "E9001" and "4 MiB" in result.stderr
    checks += 1
    result = subprocess.run(
        [str(ROOT / "cgd"), "--verificar"], capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 1 and "exatamente um" in result.stderr
    checks += 1

    source.write_text('var valor=1; escreva("${valor}"); escreva(ausente)')
    result = run(source, "--verificar")
    assert (
        result.returncode == 1
        and "var valor=1;" in result.stderr
        and "escreva(ausente)" in result.stderr
    )
    checks += 1

    # Confere argv real sem exigir uma toolchain cruzada instalada.
    if os.name == "posix":
        source.write_text("escreva(42)")
        fake_cc = folder / "cc com espaços"
        fake_pkg = folder / "pkg com espaços"
        log = folder / "argv.json"
        fake_cc.write_text(
            '#!/usr/bin/env python3\nimport os,json,sys\nopen(os.environ["CGD_TEST_ARGV"],"w").write(json.dumps(sys.argv[1:]))\n'
        )
        fake_pkg.write_text('#!/bin/sh\nprintf "%s\\n" "-I\'/sdk com espaço/include\' -lgc"\n')
        fake_cc.chmod(0o755)
        fake_pkg.chmod(0o755)
        obj = folder / "runtime alvo.o"
        obj.write_bytes(b"")
        result = run(
            source,
            "--cc",
            str(fake_cc),
            "--pkg-config",
            str(fake_pkg),
            "--runtime-object",
            str(obj),
            "--target",
            "x86_64-w64-windows-gnu",
            "--sysroot",
            "/sdk",
            "--cflag=-DTESTE=1",
            "--ldflag=-static",
            "-s",
            str(folder / "programa $(literal)"),
            env={**os.environ, "CGD_TEST_ARGV": str(log)},
        )
        assert result.returncode == 0, result.stderr
        argv = json.loads(log.read_text())
        assert "--target=x86_64-w64-windows-gnu" in argv and "--sysroot=/sdk" in argv
        assert "-I/sdk com espaço/include" in argv and "-DTESTE=1" in argv and "-static" in argv
        assert "-ldl" not in argv and "-rdynamic" not in argv
        checks += 1

result = subprocess.run(
    [str(ROOT / "cgd"), "--explicar", "E3101"], capture_output=True, text=True, timeout=10
)
assert result.returncode == 0 and "denominador" in result.stdout
checks += 1

with tempfile.TemporaryDirectory(prefix="cgd localizacao ") as tmp:
    folder = Path(tmp)
    source = folder / "origem.delegua"
    output = folder / "programa"
    source.write_text("funcao dividir(a,b){\n retorna a/b\n}\nvar zero=0\ndividir(1,zero)")
    result = run(source, "-s", str(output))
    assert result.returncode == 0, result.stderr
    code = (folder / "programa.c").read_text()
    assert (
        "delegua_localizar(" not in code and "static const delegua_local cgd_source_sites[]" in code
    )
    result = subprocess.run([str(output)], capture_output=True, text=True, timeout=10)
    assert (
        result.returncode == 1 and f"{source}:2:" in result.stderr and "R0001" in result.stderr
    ), result.stderr
    checks += 1
    source.write_text("var primeiro=1;var segundo=2;var terceiro=3")
    result = run(source, "--emitir-c", "-s", str(output))
    assert (
        result.returncode == 0 and "delegua_local_atual=" not in (folder / "programa.c").read_text()
    )
    checks += 1

print(f"{checks} verificações de driver passaram.")
