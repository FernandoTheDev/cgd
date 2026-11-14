"""Regressões das otimizações: efeitos, contratos, escopos e fronteiras numéricas."""

CASES = [
    ("composta_promocao_logica", "var x:inteiro=1; x+=verdadeiro; escreva(x)", "2"),
    ("ctfe_senao", "//>puro\nfuncao f(x){se x{retorna 1}senao{retorna 2}} escreva(f(falso))", "2"),
    (
        "ctfe_escopo",
        "//>puro\nfuncao f(){var x=1;se verdadeiro{var x=2}retorna x} escreva(f())",
        "1",
    ),
    (
        "ctfe_inicializador_sombra",
        "//>puro\nfuncao f(){var x=1;se verdadeiro{var x=x+2;retorna x}retorna 0} escreva(f())",
        "3",
    ),
    ("ctfe_parametro_mutavel", "//>puro\nfuncao f(x){x+=2;retorna x} escreva(f(3))", "5"),
    (
        "ctfe_ordem_argumentos",
        "//>puro\nfuncao combinar(a,b){retorna a*10+b} //>puro\nfuncao f(){var x=1;retorna combinar(x++,x++)} escreva(f())",
        "12",
    ),
    (
        "ctfe_loop_composto",
        "//>puro\nfuncao f(x){var soma=0;enquanto x>0{soma+=x;x--}retorna soma} escreva(f(4))",
        "10",
    ),
    (
        "ctfe_erro_tratavel",
        "//>puro\nfuncao f(x){retorna 1/x} tente{f(0)}pegue(erro){escreva('tratado')}",
        "tratado",
    ),
    ("ctfe_ramo_descartado", "//>puro\nfuncao f(x){retorna 1/x} escreva(falso e f(0))", "falso"),
    (
        "ctfe_igualdade_mista",
        "//>puro\nfuncao f(x,y){retorna x==y} escreva(f(1,'1'),f(1,verdadeiro),f(1,1.0))",
        "falsofalsoverdadeiro",
    ),
    ("ctfe_texto_misto", "//>puro\nfuncao f(x){retorna 'valor='+x} escreva(f(1.5))", "valor=1.5"),
    (
        "ctfe_default_indireto",
        "//>puro\nfuncao g(x=7){retorna x} //>puro\nfuncao f(){retorna g()} escreva(f())",
        "7",
    ),
    ("ctfe_retorno_implicito", "//>puro\nfuncao f(x){se x{retorna 1}} escreva(f(falso))", "nulo"),
    ("ctfe_unario_positivo", "//>puro\nfuncao f(x){retorna +x} escreva(f(2))", "2"),
    (
        "opt_ctfe_sombra",
        "//>puro\nfuncao calcular(x){retorna x+1} funcao criar(){funcao calcular(x){retorna x+10} retorna calcular(2)} escreva(calcular(2),criar())",
        "312",
    ),
    (
        "opt_escopos",
        "const valor=2; se verdadeiro {const valor=9; escreva(valor+1)} escreva(valor+1)",
        "10\n3",
    ),
    ("opt_literais", "escreva((2+3)*4,7%3,'a'+'b',1!=2,verdadeiro==falso)", "201abverdadeirofalso"),
    (
        "opt_ramos",
        "funcao efeito(){escreva(99);retorna 1} escreva(verdadeiro?7:efeito(),falso e efeito(),verdadeiro ou efeito(),nulo?:8)",
        "7falsoverdadeiro8",
    ),
    ("opt_multiplica_zero", "funcao efeito(){escreva(4);retorna 2} escreva(efeito()*0)", "4\n0"),
    (
        "opt_finalmente",
        "funcao f(){tente{retorna 1;escreva(99)}finalmente{escreva(2)}} escreva(f())",
        "2\n1",
    ),
    (
        "opt_efeito_const",
        "funcao efeito(){escreva(4);retorna 2} const x=efeito(); escreva(x+x)",
        "4\n4",
    ),
    ("opt_laços", "var x=0; enquanto falso{x++} para(var i=0;i<2+1;i++){x+=1+1} escreva(x)", "6"),
    (
        "opt_dentro_colecoes",
        'escreva([1+2,3+4],{"x":4+5},[(2+3) para cada x em [1,2]])',
        "[3, 7]{x: 9}[5, 5]",
    ),
    ("opt_defaults", "funcao f(x=1+2){retorna x*2} escreva(f())", "6"),
    ("opt_metodo", "classe A{f(){retorna (2+3)*4}} escreva(A().f())", "20"),
    (
        "opt_excecao_inalcancavel",
        'funcao f(){se verdadeiro{retorna 3}senao{falhar "x"} escreva(99)} escreva(f())',
        "3",
    ),
    ("opt_curto_valor", "escreva(2 e 3,0 ou 8,nulo e 9)", "30nulo"),
    ("opt_padroes_chamada", "funcao f(x=7){retorna x} escreva(f(),f(2+3))", "75"),
]

RUNTIME_ERRORS = [
    ("ctfe_modulo_real", "//>puro\nfuncao f(x){retorna x%2.0} escreva(f(2.5))"),
    ("ctfe_contrato_parametro", "//>puro\nfuncao f(x:inteiro){retorna x+1} escreva(f(2.5))"),
    ("ctfe_contrato_local", "//>puro\nfuncao f(){var x:inteiro=2.5;retorna x} escreva(f())"),
    ("ctfe_contrato_retorno", "//>puro\nfuncao f():inteiro{retorna 2.5} escreva(f())"),
    ("ctfe_bit_not_real", "//>puro\nfuncao f(x){retorna ~x} escreva(f(2.5))"),
    ("ctfe_shift_real", "//>puro\nfuncao f(x){retorna x<<1} escreva(f(2.5))"),
    ("opt_const_tipado", "const valor:inteiro=2.5; escreva(valor)"),
    ("opt_overflow_aninhado", "escreva((9223372036854775806+1)+1)"),
    ("opt_modulo_zero", "escreva(4%0)"),
]

# Casos que agora falham antes de gerar C, com o código público esperado.
STATIC_ERRORS = {
    "soma_overflow_constante": "E3102",
    "zero": "E3101",
    "potencia_overflow": "E3102",
    "conversao": "E3106",
    "passo_zero": "E3108",
    "ctfe_modulo_real": "E3105",
    "ctfe_contrato_parametro": "E3104",
    "ctfe_contrato_local": "E3104",
    "ctfe_contrato_retorno": "E3104",
    "opt_const_tipado": "E3104",
    "opt_overflow_aninhado": "E3102",
    "opt_modulo_zero": "E3101",
}
