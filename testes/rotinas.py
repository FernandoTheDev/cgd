#!/usr/bin/env python3
"""Regressões de rotinas paralelas, Tarefa<T>, auditoria de efeitos, Canal e GrupoTarefas."""

from pathlib import Path
import json
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
CGD = str(ROOT / "cgd")
checks = 0


def run_program(source, expected, opt=False):
    global checks
    with tempfile.TemporaryDirectory(prefix="cgd-rotinas-") as tmp:
        src = Path(tmp) / "programa.delegua"
        exe = Path(tmp) / "programa"
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
    with tempfile.TemporaryDirectory(prefix="cgd-rotinas-err-") as tmp:
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
    # 1. Paralelismo real com Tarefa<T>, recursão, texto UTF-8, estático e Promessa.todas
    run_program(
        """
enum Fator { Dobro = 2 }

funcao fib(n: inteiro): inteiro {
    se n <= 1 { retorna n }
    retorna fib(n - 1) + fib(n - 2)
}

funcao saudar(nome: texto, vezes: inteiro): texto {
    var acc: texto = ""
    para var i: inteiro = 0; i < vezes; i++ {
        acc = acc + nome + "!"
    }
    retorna acc
}

classe MatematicaLocal {
    estatico dobroFib(n: inteiro): inteiro {
        retorna fib(n) * Fator.Dobro
    }
}

assincrona funcao principal(): vazio {
    const t1: Tarefa<inteiro> = rotina fib(15)
    const t2: Tarefa<inteiro> = rotina MatematicaLocal.dobroFib(10)
    const t3: Tarefa<texto> = rotina saudar("Olá", 3)
    const r1: inteiro = aguardar t1
    const r2: inteiro = aguardar t2
    const r3: texto = aguardar t3
    escreva(r1)
    escreva(r2)
    escreva(r3)
    escreva(t1.concluida())
    escreva(t1.cancelada())
    escreva(tipo de t1)
    const lote: qualquer[] = aguardar Promessa.todas([rotina fib(8), rotina fib(9), rotina fib(10)])
    escreva("${lote[0]} ${lote[1]} ${lote[2]}")
}

principal()
""",
        "610\n110\nOlá!Olá!Olá!\nverdadeiro\nfalso\ntarefa\n21 34 55",
        opt=optimized,
    )

    # 2. Exceção em worker é propagada e capturável na thread principal + objetos locais no worker
    run_program(
        """
classe Acumulador {
    total: inteiro = 0
    somar(x: inteiro): vazio {
        isto.total = isto.total + x
    }
}

funcao somarAte(limite: inteiro): inteiro {
    se limite < 0 {
        falhar "limite negativo"
    }
    var acc: Acumulador = Acumulador()
    para var i: inteiro = 1; i <= limite; i++ {
        acc.somar(i)
    }
    retorna acc.total
}

assincrona funcao principal(): vazio {
    const ok: Tarefa<inteiro> = rotina somarAte(100)
    escreva(aguardar ok)
    const ruim: Tarefa<inteiro> = rotina somarAte(-5)
    tente {
        aguardar ruim
        escreva("NAO")
    } pegue (erro: Excecao) {
        escreva(erro.mensagem)
    }
}

principal()
""",
        "5050\nlimite negativo",
        opt=optimized,
    )

    # 3. Cancelamento de Tarefa e encadeamento entao/capturar
    run_program(
        """
funcao quadrado(x: inteiro): inteiro {
    retorna x * x
}

funcao falharSempre(): inteiro {
    falhar "boom"
}

assincrona funcao principal(): vazio {
    const p1: Promessa<qualquer> = (rotina quadrado(7)).entao(funcao(v: inteiro): inteiro {
        retorna v + 1
    })
    escreva(aguardar p1)
    const p2: Promessa<qualquer> = (rotina falharSempre()).capturar(funcao(erro: Excecao): texto {
        retorna "recuperado:" + erro.mensagem
    })
    escreva(aguardar p2)
}

principal()
""",
        "50\nrecuperado:boom",
        opt=optimized,
    )

    # 4. Canal com backpressure, tentarEnviar/tentarReceber, fechamento e GrupoTarefas
    run_program(
        """
funcao dobro(n: inteiro): inteiro {
    retorna n * 2
}

assincrona funcao produtor(canal: qualquer): vazio {
    para var i: inteiro = 1; i <= 5; i++ {
        aguardar canal.enviar(i * 10)
    }
    canal.fechar()
}

assincrona funcao consumidor(canal: qualquer): inteiro {
    var soma: inteiro = 0
    enquanto verdadeiro {
        tente {
            const v: inteiro = aguardar canal.receber()
            soma = soma + v
        } pegue (erro: Excecao) {
            sustar
        }
    }
    retorna soma
}

assincrona funcao principal(): vazio {
    const Async: qualquer = importar("cgd:assincrono")
    const ch: qualquer = Async.Canal(2)
    escreva(ch.capacidade())
    escreva(ch.tentarEnviar(100))
    const r: dicionario = ch.tentarReceber()
    escreva("${r[\"ok\"]} ${r[\"valor\"]}")
    const p: Promessa<vazio> = produtor(ch)
    const c: Promessa<inteiro> = consumidor(ch)
    aguardar p
    escreva(aguardar c)
    escreva(ch.fechado())

    const grupo: qualquer = Async.GrupoTarefas()
    grupo.adicionar(rotina dobro(3))
    grupo.adicionar(rotina dobro(4))
    grupo.adicionar(rotina dobro(5))
    const resultados: qualquer[] = aguardar grupo.aguardarTodas()
    escreva("${resultados[0]} ${resultados[1]} ${resultados[2]}")
}

principal()
""",
        "2\nverdadeiro\nverdadeiro 100\n150\nverdadeiro\n6 8 10",
        opt=optimized,
    )

# 5. Rejeições estáticas da auditoria de efeitos e transferibilidade
expect_error("funcao f(): inteiro { retorna 1 }\nvar x: qualquer = rotina 123", "E3401")
expect_error(
    "funcao f(): vazio { escreva(1) }\nvar t: Tarefa<vazio> = rotina f()",
    "E3402",
)
expect_error(
    "funcao aux(): inteiro { escreva(1); retorna 1 }\nfuncao f(): inteiro { retorna aux() }\nvar t: Tarefa<inteiro> = rotina f()",
    "E3402",
)
expect_error(
    "funcao f(): real { retorna aleatorio() }\nvar t: Tarefa<real> = rotina f()",
    "E3402",
)
expect_error(
    "funcao f(xs: inteiro[]): inteiro { retorna xs.tamanho() }\nvar t: Tarefa<inteiro> = rotina f([1, 2])",
    "E3403",
)
expect_error(
    "funcao f(): inteiro[] { retorna [1, 2] }\nvar t: Tarefa<inteiro[]> = rotina f()",
    "E3403",
)
expect_error(
    "assincrona funcao f(): inteiro { retorna 1 }\nvar t: Tarefa<inteiro> = rotina f()",
    "E3404",
)

print(f"Rotinas paralelas e canais: {checks} verificações passaram (com/sem otimização).")
