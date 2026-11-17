#!/usr/bin/env python3
"""Enums lexicais e de classe: escopo, CTFE, visibilidade e efeitos do receptor."""

from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = """
enum Global { Zero, Valor=7 }
funcao global(): inteiro { retorna Global.Valor }
funcao local(): inteiro {
    enum Estado { Inicio, Fim=9 }
    funcao interna(): inteiro { retorna Estado.Fim }
    var atual: Estado=Estado.Inicio
    retorna interna()+atual
}
//>puro
funcao pura(x: inteiro): inteiro {
    enum Operacao { Dobro=2 }
    retorna x*Operacao.Dobro
}
classe Base {
    enum Estado { Inicio, Fim=4 }
    estado: Estado=isto.Estado.Fim
    privado { enum Segredo { Valor=8 } }
    valor(): inteiro { retorna isto.Segredo.Valor }
    local(): inteiro { enum E { Valor=5 } retorna E.Valor }
}
classe Filha herda Base {}
interface I { enum Constante { Valor=12 } }
classe Implementacao implementa I {}
assercao(global()==7 e local()==9)
assercao(pura(Global.Valor)==14)
assercao(Base.Estado.Fim==4 e Filha.Estado.Fim==4)
var objeto: Base=Base()
assercao(objeto.estado==4 e objeto.Estado.Inicio==0 e objeto.valor()==8 e objeto.local()==5)
assercao(I.Constante.Valor==12)
@definicao(biblioteca="m")
classe estrangeira LibM {
    enum Entrada { Zero }
    @definicao(simbolo="cos") cosseno(x: numero): numero;
}
assercao(LibM.cosseno(LibM.Entrada.Zero)==1)
var efeitos: qualquer[]=[]
funcao criar(eventos: qualquer[]): Base { eventos.adicionar(1); retorna Base() }
assercao(criar(efeitos).Estado.Fim==4 e tamanho(efeitos)==1)
para cada numero: inteiro em [1,2] {
    enum E { Valor=3 }
    var valor: E=E.Valor
    assercao(valor==3)
}
tente { falhar "teste" } pegue { enum E { Valor=6 } var valor: E=E.Valor; assercao(valor==6) }
se verdadeiro { enum E { A=1 } assercao(E.A==1) }
se verdadeiro { enum E { A=2 } assercao(E.A==2) }
var alias: qualquer=Base.Estado
var capturado: logico=falso
tente { alias.Fim=1 } pegue { capturado=verdadeiro }
assercao(capturado e Base.Estado.Fim==4)
var dinamico: qualquer=objeto
capturado=falso
tente { dinamico.Segredo } pegue { capturado=verdadeiro }
assercao(capturado)
escreva("enums OK")
"""
ERRORS = [
    "se verdadeiro { enum Local { A } } var x: Local=0",
    "classe C { enum E { A } } C.E={}",
    "classe C { privado { enum E { A } } } escreva(C.E.A)",
    "enum E { A } escreva(E.Inexistente)",
    "enum E { A } E.A=2",
    "enum E { A } enum E { B }",
    "funcao f() { enum E { A } retorna E.A } var x: E=0",
    "classe A { enum E { Valor } f() { retorna B() } } classe B { valor: E }",
    "//>puro\nfuncao f() { enum E { A } retorna E } f()",
]
with tempfile.TemporaryDirectory(prefix="cgd enums ") as temporary:
    folder = Path(temporary)
    source = folder / "contratos.delegua"
    binary = folder / "programa"
    source.write_text(SOURCE)
    for optimized in (False, True):
        result = subprocess.run(
            [
                str(ROOT / "cgd"),
                str(source),
                "-s",
                str(binary),
                "--cflag=-Wall",
                "--cflag=-Wextra",
                "--cflag=-Werror",
            ]
            + (["-o"] if optimized else []),
            capture_output=True,
            text=True,
            timeout=60,
        )
        assert result.returncode == 0, result.stdout + result.stderr
        result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=10)
        assert result.returncode == 0 and result.stdout == "enums OK\n", (
            result.stdout + result.stderr
        )
    for index, content in enumerate(ERRORS):
        source.write_text(content)
        result = subprocess.run(
            [str(ROOT / "cgd"), str(source), "--verificar"],
            capture_output=True,
            text=True,
            timeout=15,
        )
        assert result.returncode != 0, f"Caso inválido {index} aceito: {content}"
print(
    "Enums: escopos, classes/herança, CTFE, aliases, visibilidade e efeitos passaram nos dois modos; 9 casos inválidos rejeitados."
)
