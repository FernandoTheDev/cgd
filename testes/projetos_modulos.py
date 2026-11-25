#!/usr/bin/env python3
"""Testes completos do Marco B: sistema de projetos, módulos qualificados e tipos entre módulos."""

from pathlib import Path
import json
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
CGD = str(ROOT / "cgd")
checks = 0


def run(args, cwd=None):
    return subprocess.run(
        [CGD, *args],
        cwd=cwd,
        capture_output=True,
        text=True,
        timeout=30,
    )


with tempfile.TemporaryDirectory(prefix="cgd_proj_") as tmp:
    base = Path(tmp)

    # 1. cgd iniciar + compilar + rodar + testar + verificar + formatar + projeto + limpar
    r = run(["iniciar", "meu-app"], cwd=base)
    assert r.returncode == 0, r.stderr
    app = base / "meu-app"
    assert (app / "projeto.json").is_file()
    assert (app / "fontes" / "principal.delegua").is_file()
    assert (app / "testes" / "principal_teste.delegua").is_file()
    checks += 1

    r = run(["projeto", "validar"], cwd=app)
    assert r.returncode == 0 and "válido" in r.stdout, r.stderr
    checks += 1

    r = run(["projeto", "informacoes"], cwd=app)
    assert r.returncode == 0 and "meu-app" in r.stdout, r.stderr
    checks += 1

    r = run(["verificar"], cwd=app)
    assert r.returncode == 0, r.stderr
    checks += 1

    r = run(["compilar"], cwd=app)
    assert r.returncode == 0 and (app / "compilacao" / "meu-app").is_file(), r.stderr
    checks += 1

    # Execução a partir de subdiretório interno (fora da raiz)
    r = run(["rodar"], cwd=app / "fontes")
    assert r.returncode == 0 and "Olá, meu-app!" in r.stdout, r.stderr + r.stdout
    checks += 1

    # Cache hit: segunda compilação sem alterações preserva mtime
    bin_path = app / "compilacao" / "meu-app"
    mtime1 = bin_path.stat().st_mtime_ns
    r = run(["compilar"], cwd=app)
    assert r.returncode == 0, r.stderr
    assert bin_path.stat().st_mtime_ns == mtime1, "Cache incremental deveria evitar recompilação"
    checks += 1

    # cgd testar
    r = run(["testar"], cwd=app)
    assert r.returncode == 0 and "1 aprovado(s)" in r.stdout, r.stderr + r.stdout
    checks += 1

    # cgd formatar
    r = run(["formatar"], cwd=app)
    assert r.returncode == 0, r.stderr
    r = run(["formatar", "--verificar"], cwd=app)
    assert r.returncode == 0, r.stderr
    checks += 1

    # cgd compilar --modo producao
    r = run(["compilar", "--modo", "producao"], cwd=app)
    assert r.returncode == 0, r.stderr
    checks += 1

    # cgd limpar
    r = run(["limpar"], cwd=app)
    assert r.returncode == 0 and not (app / "compilacao").exists(), r.stderr
    checks += 1

    # 2. Projeto multi-módulo com tipos qualificados, aliases, herança, enums, rotina e compatibilidade importar("...")
    multi = base / "multi"
    (multi / "fontes" / "aplicativo" / "modelos").mkdir(parents=True)
    (multi / "fontes" / "aplicativo" / "servicos").mkdir(parents=True)
    (multi / "projeto.json").write_text(
        json.dumps(
            {
                "nome": "multi",
                "versao": "1.0.0",
                "tipo": "aplicativo",
                "entrada": "fontes/principal.delegua",
                "saida": "compilacao/multi",
            }
        )
    )
    (multi / "fontes" / "aplicativo" / "modelos" / "usuario.delegua").write_text(
        """modulo aplicativo.modelos.usuario

enum Nivel {
    COMUM = 1,
    ADMIN = 2
}

classe Usuario {
    nome: texto
    nivel: Nivel

    construtor(nome: texto, nivel: Nivel = Nivel.COMUM) {
        isto.nome = nome
        isto.nivel = nivel
    }

    ehAdmin(): logico {
        retorna isto.nivel == Nivel.ADMIN
    }
}

funcao calcularHash(n: inteiro): inteiro {
    retorna n * 31 + 7
}
"""
    )
    (multi / "fontes" / "aplicativo" / "servicos" / "autenticacao.delegua").write_text(
        """modulo aplicativo.servicos.autenticacao

importar aplicativo.modelos.usuario

funcao validar(u: aplicativo.modelos.usuario.Usuario): logico {
    retorna u.nome.tamanho() > 0 e u.ehAdmin()
}
"""
    )
    (multi / "fontes" / "principal.delegua").write_text(
        """modulo principal

importar aplicativo.modelos.usuario
importar aplicativo.servicos.autenticacao como Auth
const Mod = importar("aplicativo/modelos/usuario.delegua")

classe Moderador herda aplicativo.modelos.usuario.Usuario {
    secao: texto
    construtor(nome: texto, secao: texto) {
        super(nome, aplicativo.modelos.usuario.Nivel.ADMIN)
        isto.secao = secao
    }
}

funcao checarAlias(u: Mod.Usuario): logico {
    retorna u.ehAdmin()
}

funcao tarefaParalela(x: inteiro): inteiro {
    retorna aplicativo.modelos.usuario.calcularHash(x)
}

assincrona funcao executar(): vazio {
    const u: aplicativo.modelos.usuario.Usuario = aplicativo.modelos.usuario.Usuario("Ana", aplicativo.modelos.usuario.Nivel.ADMIN)
    const m: Moderador = Moderador("Bia", "geral")
    const t: Tarefa<inteiro> = rotina tarefaParalela(10)
    const h: inteiro = aguardar t
    assercao(Auth.validar(u))
    assercao(Auth.validar(m))
    assercao(checarAlias(u))
    assercao(h == 317)
    escreva("MULTI-OK:", m.secao, ":", h)
}

executar()
"""
    )

    for mode in ["desenvolvimento", "producao"]:
        r = run(["rodar", "--modo", mode, "--forcar"], cwd=multi)
        assert r.returncode == 0 and "MULTI-OK:geral:317" in r.stdout, f"mode={mode}: {r.stderr}\n{r.stdout}"
        checks += 1

    # 3. Erro de tipo qualificado incorreto deve ser rejeitado na compilação
    bad_type = base / "bad_type"
    (bad_type / "fontes" / "a").mkdir(parents=True)
    (bad_type / "projeto.json").write_text('{"nome":"bad_type"}')
    (bad_type / "fontes" / "a" / "m.delegua").write_text(
        "modulo a.m\nclasse Item { x: inteiro }\n"
    )
    (bad_type / "fontes" / "principal.delegua").write_text(
        "importar a.m\nfuncao f(it: a.m.Item): inteiro { retorna it.x }\nf(123)\n"
    )
    r = run(["verificar"], cwd=bad_type)
    assert r.returncode != 0, "Deveria rejeitar passagem de inteiro para parâmetro a.m.Item"
    checks += 1

    # 4. Erro de incompatibilidade entre nome declarado `modulo` e caminho importado
    mismatch = base / "mismatch"
    (mismatch / "fontes" / "a").mkdir(parents=True)
    (mismatch / "projeto.json").write_text('{"nome":"mismatch"}')
    (mismatch / "fontes" / "a" / "m.delegua").write_text("modulo errado.nome\n")
    (mismatch / "fontes" / "principal.delegua").write_text("importar a.m\n")
    r = run(["verificar"], cwd=mismatch)
    assert r.returncode != 0 and "incompatível" in r.stderr, r.stderr
    checks += 1

    # 5. Segurança: path traversal em projeto.json deve ser bloqueado
    traversal = base / "traversal"
    traversal.mkdir()
    (traversal / "projeto.json").write_text('{"nome":"trav","entrada":"../fora.delegua"}')
    r = run(["projeto", "validar"], cwd=traversal)
    assert r.returncode != 0 and "escapa" in r.stderr, r.stderr
    checks += 1

    # 6. Ciclo de módulos qualificados detectado com E2001
    cyc = base / "cyc"
    (cyc / "fontes").mkdir(parents=True)
    (cyc / "projeto.json").write_text('{"nome":"cyc"}')
    (cyc / "fontes" / "a.delegua").write_text("modulo a\nimportar b\n")
    (cyc / "fontes" / "b.delegua").write_text("modulo b\nimportar a\n")
    (cyc / "fontes" / "principal.delegua").write_text("importar a\n")
    r = run(["verificar"], cwd=cyc)
    assert r.returncode != 0 and "E2001" in r.stderr, r.stderr
    checks += 1

print(f"Projetos e módulos: {checks} verificações passaram.")
