#!/usr/bin/env python3
"""Contratos P0 reais: CGD compila os clientes, processos usam argv sem shell."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="cgd processo ação ") as temporary:
    folder = Path(temporary)
    helper = folder / "filho.py"
    binary = folder / "cliente"
    source = folder / "cliente.delegua"
    helper.write_text("""import os,sys,time,signal,json
mode=sys.argv[1]
if mode=='args': print(json.dumps(sys.argv[2:],ensure_ascii=False,separators=(',',':')))
elif mode=='env': print(os.getcwd()); print(os.environ.get('CGD_TEST_PROCESSO','ausente'))
elif mode=='exit': print('erro',file=sys.stderr); sys.exit(7)
elif mode=='volume':
 os.write(1,b'a'*200000);os.write(2,b'b'*200000)
elif mode=='input':
 os.write(1,b'x'*70000);os.write(2,b'y'*70000);print(len(sys.stdin.buffer.read()))
elif mode=='sleep': time.sleep(5)
elif mode=='signal': os.kill(os.getpid(),signal.SIGTERM)
elif mode=='closed': os.close(0);print('fechado')
elif mode=='fds': print(len(os.listdir('/proc/%d/fd'%os.getppid())));print(len(open('/proc/%d/task/%d/children'%(os.getppid(),os.getppid())).read().split()))
elif mode=='descendant':
 import subprocess
 subprocess.Popen([sys.executable,'-c','import time;time.sleep(30)']);time.sleep(30)
""")
    no_shell = folder / "sem-shebang"
    no_shell.write_text("touch " + str(folder / "INJECAO"))
    no_shell.chmod(0o755)
    denied = folder / "sem-permissao"
    denied.write_text("teste")
    denied.chmod(0o644)
    source.write_text(
        "var python: texto="
        + json.dumps(sys.executable)
        + "\nvar helper: texto="
        + json.dumps(str(helper), ensure_ascii=False)
        + "\nvar pasta: texto="
        + json.dumps(str(folder), ensure_ascii=False)
        + """\n
var P: qualquer=importar("cgd:processo").Processo
var A: qualquer=importar("cgd:ambiente").Ambiente
var S: qualquer=importar("cgd:sistema").Sistema
var T: qualquer=importar("cgd:tempo").Tempo
var IO: qualquer=importar("cgd:io").IO
var argumentos: texto[]=P.argumentos()
se tamanho(argumentos)==0 { assercao(P.argc()==1) }
senao { assercao(tamanho(argumentos)==4 e argumentos[0]=="" e argumentos[1]=="a b" e argumentos[2]=="ação 💚" e argumentos[3]=="$HOME;*") }
assercao(P.argc()==tamanho(P.argv()) e P.quantidadeArgumentos()==tamanho(argumentos))
var copia: texto[]=P.argv(); copia.adicionar("mudança"); assercao(tamanho(copia)==P.argc()+1)
assercao(P.executavel()!="" e P.identificador()>0)
var antes: texto=A.diretorioAtual()
var resultado: qualquer=P.executar(python,[helper,"args","", "a b", "ação 💚", "$(touch NUNCA);*;$HOME"])
assercao(resultado.sucesso() e resultado.saidaPadrao()=='["","a b","ação 💚","$(touch NUNCA);*;$HOME"]\\n')
resultado=P.executar(python,[helper,"env"],pasta,{CGD_TEST_PROCESSO:"valor ação"})
assercao(resultado.saidaPadrao()==pasta+"\\nvalor ação\\n" e A.diretorioAtual()==antes)
assercao(A.obter("CGD_TEST_PROCESSO")==nulo e A.obter("CGD_NAO_EXISTE","ok")=="ok")
assercao(!A.contem("CGD_NAO_EXISTE") e A.diretorioTemporario()!="")
resultado=P.executar(python,[helper,"exit"])
assercao(resultado.codigoSaida()==7 e resultado.sinal()==nulo e !resultado.sucesso() e resultado.saidaErro()=="erro\\n")
resultado=P.executar(python,[helper,"signal"])
assercao(resultado.codigoSaida()==nulo e resultado.sinal()==15)
resultado=P.executar(python,[helper,"volume"],"",{},30000,500000)
assercao(resultado.sucesso() e tamanho(resultado.saidaPadrao())==200000 e tamanho(resultado.saidaErro())==200000)
resultado=P.executar(python,[helper,"volume"],"",{},30000,1000)
assercao(resultado.excedeuLimite() e !resultado.sucesso() e tamanho(resultado.saidaPadrao())+tamanho(resultado.saidaErro())==1000)
var X: qualquer=importar("cgd:textos").Textos
resultado=P.executar(python,[helper,"input"],"",{},30000,500000,X.repetir("a",300000))
assercao(resultado.sucesso() e tamanho(resultado.saidaErro())==70000 e X.terminaCom(resultado.saidaPadrao(),"300000\\n"))
resultado=P.executar(python,[helper,"closed"],"",{},30000,1000,X.repetir("a",300000))
assercao(resultado.sucesso())
resultado=P.executar(python,[helper,"sleep"],"",{},50)
assercao(resultado.expirou() e !resultado.sucesso())
resultado=P.executar(python,[helper,"descendant"],"",{},100)
assercao(resultado.expirou())
assercao(P.executarShell("printf shell").saidaPadrao()=="shell")
var C: qualquer=importar("cgd:processo").Comando
var comando: qualquer=C(python,[helper,"env"]).diretorio(pasta).ambiente("CGD_TEST_PROCESSO","builder")
assercao(comando.executar().saidaPadrao()==pasta+"\\nbuilder\\n")
var referencia: texto=P.executar(python,[helper,"fds"]).saidaPadrao()
para (var i: inteiro=0;i<20;i++) { assercao(P.executar(python,[helper,"fds"]).saidaPadrao()==referencia) }
assercao(S.nome()=="Linux" e S.arquitetura()!="" e S.capacidades()["processos"])
A.definir("CGD_TEST_ALTERAR","ação"); assercao(A.obter("CGD_TEST_ALTERAR")=="ação" e A.variaveis()["CGD_TEST_ALTERAR"]=="ação"); A.remover("CGD_TEST_ALTERAR"); assercao(!A.contem("CGD_TEST_ALTERAR"))
var d: qualquer=importar("cgd:tempo").Duracao(1000); assercao(d.emSegundos()==1 e d.somar(d).emMilisegundos()==2000)
var busca: qualquer=importar("cgd:algoritmos").Algoritmos
assercao(busca.limiteInferior([1,2,2,3],2)==1 e busca.limiteSuperior([1,2,2,3],2)==3)
assercao(busca.buscaBinaria([],2)==-1 e busca.buscaBinaria([1,2],3)==-1)
assercao(busca.estaOrdenado([1,1,2]) e !busca.estaOrdenado([2,1]))
assercao(texto(busca.intercalar([1,3],[2,4]))=="[1, 2, 3, 4]")
var sequencia: numero[]=[3,1,2]; assercao(texto(busca.ordenado(sequencia))=="[1, 2, 3]" e sequencia[0]==3)
var parser: qualquer=importar("cgd:cli").CLI("Aplicação").opcao("ajuda","h",falso,"mostra ajuda").opcao("saida","s",verdadeiro,"arquivo")
var cli: qualquer=parser.analisar(["-h","--saida=ação=a.txt","--","-x",""])
assercao(cli.tem("ajuda") e cli.valor("saida")=="ação=a.txt" e cli.posicionais()[0]=="-x" e tamanho(cli.posicionais())==2)
assercao(parser.analisar(["-s","-2"]).valor("saida")=="-2" e parser.ajuda().contem("--saida <valor>"))
var logger: qualquer=importar("cgd:log").Logger("app",3,verdadeiro,falso)
logger.info("não exibir")
logger.erro("mensagem")
var inicio: real=T.monotonico();T.dormir(5);assercao(T.monotonico()>=inicio e T.unix()>1700000000)
var cronometro: qualquer=importar("cgd:tempo").Cronometro();assercao(cronometro.milisegundos()>=0)
assercao(IO.lerLinha()=="ação" e IO.lerLinha()=="" e IO.lerLinha()==nulo)
"""
    )
    errors = [
        'P.executar("cgd-inexistente-651385")',
        'P.executar(python,[helper],"/cgd/diretorio-inexistente")',
        'P.executar(python,[],"",{},0)',
        'P.executar(python,[],"",{},10,0)',
        'P.executar("x\\0y")',
        'P.executar(python,["x\\0y"])',
        'P.executar(python,[],"",{"x=y":"z"})',
        'P.executar(python,[],"",{"x":3})',
        'P.executar(python,[helper,"exit"]).exigirSucesso()',
        'A.obter("x=y")',
        "T.dormir(-1)",
        "IO.lerLinha(0)",
        'A.definir("x=y","valor")',
        "P.executar(" + json.dumps(str(no_shell), ensure_ascii=False) + ")",
        "P.executar(" + json.dumps(str(denied), ensure_ascii=False) + ")",
        'parser.analisar(["--nao-existe"])',
        'parser.analisar(["--saida"])',
        'parser.analisar(["--ajuda=sim"])',
        'parser.analisar(["-hh"])',
        'parser.analisar(["-h","-h"])',
        'parser.opcao("ajuda")',
        'importar("cgd:tempo").Duracao(-1)',
        'importar("cgd:log").Logger("app",5)',
    ]
    with source.open("a") as stream:
        for index, expression in enumerate(errors):
            stream.write(
                f"\nvar erro{index}: logico=falso\ntente {{ {expression} }} pegue {{ erro{index}=verdadeiro }}\nassercao(erro{index})\n"
            )
        stream.write('IO.escreverLinha("processo OK");IO.erroLinha("stderr OK")\n')
    for optimized in (False, True):
        compiled = subprocess.run(
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
        assert compiled.returncode == 0, compiled.stdout + compiled.stderr
        for args in ([], ["", "a b", "ação 💚", "$HOME;*"]):
            result = subprocess.run(
                [str(binary), *args], input="ação\n\n", capture_output=True, text=True, timeout=30
            )
            assert (
                result.returncode == 0
                and result.stdout == "processo OK\n"
                and result.stderr == "[ERRO] app: mensagem\nstderr OK\n"
            ), result.stdout + result.stderr
        assert not (ROOT / "NUNCA").exists()
    assert not (folder / "INJECAO").exists()
print(
    "Sistema P0: argc/argv, Unicode, execução direta/shell, ambiente/cwd, pipes, limites, timeout, sinais, stdin/IO, relógios, limpeza repetida e casos inválidos passaram nos dois modos."
)
