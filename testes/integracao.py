#!/usr/bin/env python3
"""Regressões de semântica e segurança: executa o código com e sem otimização."""
from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
CASES = [
    ('negacao_pertencimento', "escreva('a' nao contem ['b'], 'b' não contém ['b'])", 'verdadeirofalso'),
    ('veracidade', "escreva(!0, !'', ![], !{}, !nulo)", 'falsofalsofalsofalsoverdadeiro'),
    ('igualdade', "escreva(1 == '1', 1 == 1.0, verdadeiro == 1)", 'falsoverdadeirofalso'),
    ('fracao', 'escreva(7 / 2)', '3.5'),
    ('precisao', 'escreva(0.0000001 > 0)', 'verdadeiro'),
    ('nomes', 'var int = 1; var cgd_tmp_0 = 2; funcao main(x) { retorna x + 1 } escreva(main(int) + cgd_tmp_0)', '4'),
    ('inc_indice', 'var a = [10, 20]; var i = 0; escreva(a[i++]++, i, a[0], a[1]); a[--i] += 5; escreva(a[0]);', '1011120\n16'),
    ('const_comparacao', 'const a = 2; escreva(a < 3, a == 2, a / 4)', 'verdadeiroverdadeiro0.5'),
    ('tipo_em_vetor', 'var v = [tipo de 1]; escreva(v[0]);', 'numero'),
    ('cada_dicionario', "para cada item em {'a': 7} { escreva(item[0], item[1]) }", 'a7'),
    ('efeitos_preservados', 'funcao f() { escreva(42); retorna 0 } var x = f()', '42'),
    ('chamada_aninhada', 'funcao dobro(x) { retorna x * 2 } funcao quadrado(x) { retorna x * x } var x = 5; escreva(quadrado(dobro(x)))', '100'),
    ('nulo', 'var x; escreva(x, nulo == nulo, 1 != 2)', 'nuloverdadeiroverdadeiro'),
    ('operadores', r'escreva(2 ** 3 ** 2, 100 \\ 3, -5, +7)'.replace('\\\\', '\\'), '51233-57'),
    ('curto_circuito', '''funcao falha() { retorna 1 / 0 }
        escreva(falso e falha(), verdadeiro ou falha(), nulo ?: 8, falso ?: 9)''', 'falsoverdadeiro8falso'),
    ('para', '''var total = 0
        para (var i = 0; i < 6; i++) { se i == 2 { continua; } se i == 5 { sustar; } total += i; }
        escreva(total)''', '8'),
    ('fazer', '''var i = 0; fazer { i++; se i < 3 { continua; } escreva(i); } enquanto i < 3''', '3'),
    ('condicao_com_efeito', '''var i = 0; enquanto i++ < 3 { escreva(i) } escreva(i)''', '1\n2\n3\n4'),
    ('senao_se', '''var i = 0; se verdadeiro { escreva(i) } senao se i++ == 0 { escreva(99) } escreva(i)''', '0\n0'),
    ('ordem', '''var i = 0; escreva(i++, i++, i); var a = [i + 1, -2]; escreva(a[0] + a[1])''', '012\n1'),
    ('dicionario', '''var d = {'a': 1 + 2, 'b': [4]}; d['a'] += 5; escreva(d['a'], 'a' em d, d['ausente']);
        escreva(d['b'][0]);''', '8verdadeironulo\n4'),
    ('cada', '''para cada item em [1, 2, 3] { se item == 2 { continua; } escreva(item * 2) }''', '2\n6'),
    ('tupla', '''var t = tupla([1, 2]); escreva(t[0], tamanho(t), 'bc' em 'abcd', 2 em [1, 2]);''', '12verdadeiroverdadeiro'),
    ('conversoes', '''escreva(inteiro('12'), real('1.5'), texto(nulo), tamanho('abc'));''', '121.5nulo3'),
    ('padrao', '''funcao soma(a: inteiro, b: inteiro = 2): inteiro { retorna a + b } escreva(soma(3));''', '5'),
    ('parametro', '''funcao inc(n) { n = n + 1; retorna n } escreva(inc(3));''', '4'),
    ('escapes', r'''escreva('a\'b', "c\"d", '\\', '\t');''', "a'bc\"d\\\t"),
    ('entrada', '''escreva(leia('nome: '));''', 'nome: Ana', 'Ana\n'),
    ('caminho', 'escreva(42)', '42'),
]
ERRORS = [
    ('chamada_antes_do_corpo', 'escreva(f()); funcao f() { retorna ausente }', 'declarado'),
    ('retorno_incompativel', "funcao f(): inteiro { retorna 'erro' } f()", 'Incompatibilidade'),
    ('parametro_duplicado', 'funcao f(x, x) { retorna x }', 'duplicado'),
    ('parametro_opcional', 'funcao f(x = 1, y) { retorna x }', 'obrigatório'),
    ('literal_overflow', 'escreva(9999999999999999999999999999999)', 'intervalo'),
    ('captura', 'var externo = 1; funcao f() { retorna externo + 1 } f()', 'upvalues'),
    ('captura_escrita', 'var externo = 1; funcao f() { externo = 2 } f()', 'upvalues'),
    ('aninhada', 'funcao f() { var externo=1; retorna funcao() { retorna externo } }', 'upvalues'),
    ('aridade_excesso', 'funcao f(x) { retorna x } escreva(f(1, 2))', 'argumentos'),
    ('aridade_falta', 'funcao f(x) { retorna x } escreva(f())', 'argumentos'),
    ('chamada_variavel', 'var x = 1; x()', 'função'),
    ('simbolo', 'escreva(inexistente + 1)', 'declarado'),
    ('tipo', 'var x: inexistente = 1', 'tipo'),
    ('delimitador', 'funcao f() { retorna 1', 'Fim inesperado'),
    ('sustar', 'sustar', 'fora'),
    ('continua', 'continua', 'fora'),
    ('retorno', 'retorna 1', 'fora'),
    ('constante', 'const x = 1; x++', 'constante'),
    ('const_sem_valor', 'const x;', 'inicializador'),
    ('escopo', 'se verdadeiro { var interno = 1 } escreva(interno)', 'declarado'),
]
RUNTIME_ERRORS = [
    ('soma_overflow_constante', 'const a = 9223372036854775807; escreva(a + 1)'),
    ('zero', 'escreva(1 / 0)'),
    ('potencia_overflow', 'escreva(2 ** 63)'),
    ('indice', 'var v = [1]; escreva(v[2])'),
    ('tupla_imutavel', 'var t = tupla([1, 2]); t[0] = 3'),
    ('conversao', "escreva(inteiro('12abc'))"),
]

def run(argv, **kwargs):
    return subprocess.run(argv, cwd=ROOT, text=True, capture_output=True, timeout=15, **kwargs)

from casos_linguagem import CASES as MORE_CASES, ERRORS as MORE_ERRORS, RUNTIME_ERRORS as MORE_RUNTIME_ERRORS
CASES += MORE_CASES
ERRORS += MORE_ERRORS
RUNTIME_ERRORS += MORE_RUNTIME_ERRORS

count = 0
with tempfile.TemporaryDirectory(prefix='cgd testes ') as directory:
    folder = Path(directory)
    for opt in (False, True):
        for case in CASES:
            name, source, expected, *stdin = case
            file = folder / (name + '.delegua')
            output = folder / (name + ' $(literal)')
            file.write_text(source)
            compiled = run([str(ROOT / 'cgd'), str(file), '-s', str(output)] + (['-o'] if opt else []))
            assert compiled.returncode == 0, (name, opt, compiled.stdout, compiled.stderr)
            result = run([str(output)], input=stdin[0] if stdin else '')
            assert result.returncode == 0, (name, opt, result.stderr)
            assert result.stdout.strip('\n') == expected, (name, opt, result.stdout, expected)
            count += 1
        for name, source, message in ERRORS:
            file = folder / (name + '.delegua'); file.write_text(source)
            output = folder / name
            compiled = run([str(ROOT / 'cgd'), str(file), '-s', str(output)] + (['-o'] if opt else []))
            assert compiled.returncode == 1, (name, opt, compiled.stdout, compiled.stderr)
            assert message in compiled.stderr, (name, opt, compiled.stderr)
            assert not output.exists(), name
            count += 1
        for name, source in RUNTIME_ERRORS:
            file = folder / (name + '.delegua'); file.write_text(source)
            output = folder / name
            compiled = run([str(ROOT / 'cgd'), str(file), '-s', str(output)] + (['-o'] if opt else []))
            assert compiled.returncode == 0, (name, opt, compiled.stdout, compiled.stderr)
            result = run([str(output)])
            assert result.returncode == 1 and 'Erro' in result.stderr and str(file) in result.stderr, (name, opt, result)
            count += 1
    from casos_linguagem import MODULE_CASES, MODULE_ERRORS
    for opt in (False, True):
        for name, files, expected in MODULE_CASES + MODULE_ERRORS:
            module_folder = folder / name
            module_folder.mkdir(exist_ok=True)
            for filename, source in files.items():
                (module_folder / filename).write_text(source)
            output = module_folder / 'programa'
            compiled = run([str(ROOT / 'cgd'), str(module_folder / 'main.delegua'), '-s', str(output)] + (['-o'] if opt else []))
            if any(name == case[0] for case in MODULE_ERRORS):
                assert compiled.returncode == 1 and expected in compiled.stderr, (name, opt, compiled)
            else:
                assert compiled.returncode == 0, (name, opt, compiled.stderr)
                result = run([str(output)])
                assert result.returncode == 0 and result.stdout.strip('\n') == expected, (name, opt, result)
            count += 1
    file = folder / 'backend.delegua'; file.write_text('escreva(1)')
    compiled = run([str(ROOT / 'cgd'), str(file), '-s', str(folder / 'backend')], env={**os.environ, 'CC': '/usr/bin/false'})
    assert compiled.returncode == 1 and 'compilador C falhou' in compiled.stdout + compiled.stderr
    count += 1
print(f'{count} verificações de integração passaram.')
