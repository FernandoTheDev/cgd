#!/usr/bin/env python3
"""Contratos públicos da stdlib, sem rede e em ambos os modos de otimização."""

from pathlib import Path
import json
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
CASES = [
    'assercao(texto(C.intervalo(9223372036854775806, 9223372036854775807, 2))=="[9223372036854775806]")',
    'assercao(texto(C.intervalo(-9223372036854775807, -9223372036854775807-1, -2))=="[-9223372036854775807]")',
    'assercao(texto(C.intervalo(0, -1, -9223372036854775807-1))=="[0]")',
    'assercao(T.comecaCom("ação", "aç") e T.terminaCom("ação", "ção"))',
    'assercao(T.comecaCom("", "") e !T.terminaCom("a", "abc"))',
    'assercao(T.repetir("ç", 3)=="ççç" e T.repetir("a", 0)=="")',
    'assercao(T.preencherInicio("7", 3, "0")=="007")',
    'assercao(T.preencherFim("ç", 3, "💚")=="ç💚💚")',
    'assercao(T.preencherInicio("abc", 1)=="abc")',
    'assercao(texto(T.linhas("a\\r\\nb\\rc\\n"))=="[a, b, c, ]")',
    'assercao(T.digitos("0123456789") e !T.digitos("") e !T.digitos("１２"))',
    'assercao(T.juntar(["a", "b"], "-")=="a-b")',
    'assercao(T.inverter("aç💚")=="💚ça")',
    'assercao(T.contar("aaaaa", "aa")==2 e T.contar("a", "z")==0)',
    "assercao(E.soma([1,2,3])==6 e E.soma([])==0)",
    "assercao(E.media([1,2,3])==2 e E.minimo([3,1,2])==1 e E.maximo([3,1,2])==3)",
    "assercao(E.mediana([4,1,2,3])==2.5 e E.mediana([3,1,2])==2)",
    "assercao(E.variancia([1,2,3])>0.666 e E.variancia([1,2,3])<0.667)",
    "assercao(E.variancia([1,2,3], verdadeiro)==1 e E.desvioPadrao([1,2,3], verdadeiro)==1)",
    "assercao(E.variancia([7])==0)",
    'assercao(E.resumo([1,2,3])["quantidade"]==3)',
    "var amostra: numero[]=[3,1,2]; E.mediana(amostra); assercao(amostra[0]==3)",
    'assercao(P.normalizar("a/./b/../c")=="a/c")',
    'assercao(P.normalizar("/../../a//b/")=="/a/b")',
    'assercao(P.normalizar("../../a/..")=="../.." e P.normalizar("")==".")',
    'assercao(P.juntar(["a", "b", "..", "c"])=="a/c")',
    'assercao(P.juntar(["a", "/b", "c"])=="/b/c" e P.juntar([])==".")',
    'assercao(P.absoluto("/x") e !P.absoluto("x"))',
    'assercao(P.nome("/a/b.txt")=="b.txt" e P.diretorio("/a/b.txt")=="/a")',
    'assercao(P.nome("/")=="/" e P.diretorio("/a")=="/" e P.diretorio("a")==".")',
    'assercao(P.extensao(".perfil")=="" e P.extensao("a.tar.gz")==".gz")',
    'assercao(P.semExtensao("a/b.txt")=="a/b")',
    "assercao(C.primeiro([], 9)==9 e C.ultimo([1,2])==2)",
    "assercao(C.encontrar([1,2,3], par)==2 e C.contar([1,2,3,4], par)==2)",
    'assercao(texto(C.particionar([1,2,3,4], par))=="([2, 4], [1, 3])")',
    'assercao(texto(C.combinar([1,2], ["a"]))=="[(1, a)]")',
    'assercao(texto(C.blocos([1,2,3,4,5], 2))=="[[1, 2], [3, 4], [5]]")',
    'assercao(C.frequencias(["a","b","a"])["a"]==2)',
    "assercao(C.reduzir([1,2,3], somar, 0)==6)",
    "assercao(C.agrupar([1,2,3], par)[verdadeiro][0]==2)",
    'assercao(texto(C.achatar([[1,2],3]))=="[1, 2, 3]")',
    "assercao(M.hipotenusa(3,4)==5 e M.logaritmo10(100)==2)",
    "assercao(M.truncar(-2.9)==-2 e M.arredondar(2.5)==3)",
]
ERRORS = [
    'importar("cgd:textos").Textos.repetir("a", -1)',
    'importar("cgd:textos").Textos.repetir("ab", 1000000)',
    'importar("cgd:textos").Textos.preencherFim("a", 3, "")',
    'importar("cgd:textos").Textos.contar("a", "")',
    'importar("cgd:estatistica").Estatistica.media([])',
    'importar("cgd:estatistica").Estatistica.minimo([])',
    'importar("cgd:estatistica").Estatistica.mediana([])',
    'importar("cgd:estatistica").Estatistica.variancia([1], verdadeiro)',
    'importar("cgd:colecoes").Colecoes.blocos([1], 0)',
]
source = """
var T: qualquer = importar("cgd:textos").Textos
var E: qualquer = importar("cgd:estatistica").Estatistica
var P: qualquer = importar("cgd:caminhos").Caminhos
var C: qualquer = importar("cgd:colecoes").Colecoes
var M: qualquer = importar("cgd:matematica").Matematica
funcao par(x: inteiro): logico { retorna x % 2 == 0 }
funcao somar(a: inteiro, b: inteiro): inteiro { retorna a+b }
"""
source += "\n".join(CASES)
for index, expression in enumerate(ERRORS):
    source += f"\nvar capturado{index}: logico=falso\ntente {{ {expression} }} pegue {{ capturado{index}=verdadeiro }}\nassercao(capturado{index})\n"
IO_CASES = [
    'var arquivo: qualquer=importar("cgd:arquivos").Arquivo(alvo); arquivo.escreverJSON({"a":[1,2], "n":nulo})',
    'assercao(arquivo.lerJSON()["a"][1]==2 e arquivo.lerJSON()["n"]==nulo)',
    'var copiaArquivo: qualquer=arquivo.copiarPara(alvo+".copia"); assercao(copiaArquivo.ler()==arquivo.ler())',
    'arquivo.copiarPara(alvo); assercao(arquivo.lerJSON()["a"][0]==1)',
    "assercao(arquivo.remover() e copiaArquivo.remover())",
    'var B: qualquer=importar("cgd:bytes").Bytes; var buf: qualquer=B.criarReservado(8); buf.anexarByte(65); buf.anexarU16LE(0x4342); buf.anexarU32LE(0x47464544); buf.definirU32LE(3, 0x34333231); buf.anexarTexto("XY"); buf.anexarZeros(1); assercao(buf.tamanho()==10 e buf.fatiarTexto(0, 9)=="ABC1234XY")',
    'buf.gravarArquivo(alvo+".bin"); var lido: qualquer=B.lerArquivo(alvo+".bin"); assercao(lido.igual(buf)); importar("cgd:arquivos").Arquivo(alvo+".bin").remover()',
    'var S: qualquer=importar("cgd:sistema").Sistema; var mem: dicionario=S.memoria(); assercao(mem.contem("gc_heap") e mem.contem("gc_total") e mem.contem("rss_kb")); S.coletarGC(falso)',
    'var vl: inteiro[]=[1,2,3]; vl.limpar(); assercao(vl.tamanho()==0); vl.empilhar(9); assercao(vl.tamanho()==1 e vl[0]==9)',
]
source += "\n" + "\n".join(IO_CASES)
source += '\nescreva("stdlib OK")\n'
with tempfile.TemporaryDirectory(prefix="cgd stdlib ") as temporary:
    folder = Path(temporary)
    file = folder / "contratos.delegua"
    file.write_text("var alvo: texto = " + json.dumps(str(folder / "dados.json")) + "\n" + source)
    for optimized in (False, True):
        binary = folder / "contratos"
        compiled = subprocess.run(
            [
                str(ROOT / "cgd"),
                str(file),
                "-s",
                str(binary),
                "--cflag=-Wall",
                "--cflag=-Wextra",
                "--cflag=-Werror",
            ]
            + (["-o"] if optimized else []),
            capture_output=True,
            text=True,
            timeout=120,
        )
        assert compiled.returncode == 0, compiled.stdout + compiled.stderr
        executed = subprocess.run([str(binary)], capture_output=True, text=True, timeout=20)
        assert executed.returncode == 0 and executed.stdout == "stdlib OK\n", (
            executed.stdout + executed.stderr
        )
print(
    f"Stdlib: {2 * (len(CASES) + len(ERRORS) + len(IO_CASES))} contratos passaram em ambos os modos."
)
