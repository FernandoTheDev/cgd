#!/usr/bin/env python3
"""Regressões de campos estáticos, composição mescla e envelopes de decoradores em métodos."""

from pathlib import Path
import json
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
CGD = str(ROOT / "cgd")
checks = 0


def run_program(source, expected, opt=False):
    global checks
    with tempfile.TemporaryDirectory(prefix="cgd-lang-") as tmp:
        src = Path(tmp) / "prog.delegua"
        exe = Path(tmp) / "prog"
        src.write_text(source, encoding="utf-8")
        cmd = [CGD, str(src), "-s", str(exe)]
        if opt:
            cmd.append("-o")
        comp = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        assert comp.returncode == 0, f"Compilação falhou (opt={opt}):\n{comp.stderr}\n{comp.stdout}"
        proc = subprocess.run([str(exe)], capture_output=True, text=True, timeout=30)
        assert proc.returncode == 0, f"Execução falhou (opt={opt}):\n{proc.stderr}\n{proc.stdout}"
        assert proc.stdout.strip() == expected.strip(), (
            f"Saída inesperada (opt={opt}):\nesperado:\n{expected}\nrecebido:\n{proc.stdout}"
        )
        checks += 1


def expect_error(source, code):
    global checks
    with tempfile.TemporaryDirectory(prefix="cgd-lang-err-") as tmp:
        src = Path(tmp) / "erro.delegua"
        src.write_text(source, encoding="utf-8")
        comp = subprocess.run(
            [CGD, str(src), "--verificar", "--diagnosticos=json"],
            capture_output=True,
            text=True,
            timeout=20,
        )
        assert comp.returncode == 1, f"Esperado erro {code}, mas compilou:\n{source}"
        diags = [json.loads(line) for line in comp.stderr.splitlines() if line.strip()]
        assert any(d["code"] == code for d in diags), f"Esperado código {code}, recebido: {diags}"
        checks += 1


for optimized in (False, True):
    # 1. Campos estáticos (default tipado, inicializador, mutação, herança, visibilidade, contrato)
    run_program(
        """
classe Contador {
    estatico total: inteiro
    estatico prefixo: texto = "N="

    privado {
        estatico segredo: inteiro = 10
    }

    construtor() {
        Contador.total = Contador.total + 1
    }

    estatico lerSegredo(): inteiro {
        retorna Contador.segredo
    }

    estatico somarSegredo(v: inteiro): vazio {
        Contador.segredo = Contador.segredo + v
    }

    etiqueta(): texto {
        retorna isto.prefixo + texto(isto.total)
    }
}

classe SubContador herda Contador {
}

escreva(Contador.total)
const a: Contador = Contador()
const b: SubContador = SubContador()
escreva(Contador.total)
escreva(SubContador.total)
escreva(b.etiqueta())
Contador.somarSegredo(5)
escreva(Contador.lerSegredo())

var din: qualquer = Contador
tente {
    din.total = "invalido"
    escreva("NAO")
} pegue (erro: Excecao) {
    escreva("contrato_ok")
}
""",
        "0\n2\n2\nN=2\n15\ncontrato_ok",
        opt=optimized,
    )

    # 2. Composição mescla (múltiplos mixins, precedência, campos inicializados, interface, eInstanciaDe)
    run_program(
        """
interface Identificavel {
    id(): texto;
}

classe ComTag {
    tag: texto = "base"
    rotulo(): texto {
        retorna "tag:" + isto.tag
    }
}

classe Auditavel {
    privado {
        versaoInterna: inteiro = 7
    }

    rotulo(): texto {
        retorna "audit:" + texto(isto.versaoInterna)
    }

    id(): texto {
        retorna "ID-" + texto(isto.versaoInterna)
    }
}

classe Entidade {
    origem(): texto {
        retorna "entidade"
    }
}

classe Usuario herda Entidade mescla ComTag, Auditavel implementa Identificavel {
    nome: texto

    construtor(nome: texto) {
        isto.nome = nome
    }
}

const u: Usuario = Usuario("Ana")
escreva(u.nome)
escreva(u.tag)
escreva(u.origem())
escreva(u.rotulo())
escreva(u.id())
escreva(u.eInstanciaDe(ComTag))
escreva(u.eInstanciaDe(Auditavel))
escreva(u.eInstanciaDe(Identificavel))
escreva(u.eInstanciaDe(Entidade))
""",
        "Ana\nbase\nentidade\naudit:7\nID-7\nverdadeiro\nverdadeiro\nverdadeiro\nverdadeiro",
        opt=optimized,
    )

    # 3. Envelopes de decoradores em métodos (instância e estático)
    run_program(
        """
funcao de decorador envolverEstatico(original: funcao): funcao {
    retorna funcao(x: inteiro): inteiro {
        retorna x * 10
    }
}

funcao de decorador envolverInstancia(original: funcao): funcao {
    retorna funcao(alvo: qualquer, x: inteiro): inteiro {
        retorna alvo.base + x + 1
    }
}

classe Calc {
    base: inteiro = 100

    @envolverEstatico
    estatico dobrar(x: inteiro): inteiro {
        retorna x * 2
    }

    @envolverInstancia
    somar(x: inteiro): inteiro {
        retorna isto.base + x
    }
}

const c: Calc = Calc()
escreva(Calc.dobrar(4))
escreva(c.somar(5))
""",
        "40\n106",
        opt=optimized,
    )

# 4. Rejeições: acesso privado a campo estático e uso de campo estático mutável em rotina
expect_error(
    "classe A { privado { estatico x: inteiro = 1 } }\nescreva(A.x)",
    "E3014",
)
expect_error(
    "classe A { estatico x: inteiro = 1 }\nfuncao f(): inteiro { retorna A.x }\nvar t: Tarefa<inteiro> = rotina f()",
    "E3402",
)

print(f"Recursos de linguagem (estáticos/mescla/envelopes): {checks} verificações passaram.")
