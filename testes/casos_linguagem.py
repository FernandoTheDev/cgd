"""Casos de linguagem para a suíte de integração, sem dependências externas."""

CASES = [
    (
        "campo_tipo_capturado",
        'classe A{x:inteiro}var a=A();tente{a.x="texto"}pegue(erro){escreva("capturado")}',
        "capturado",
    ),
    ("funcao_valor", "funcao f(x){retorna x*2} var g=f;escreva(g(3))", "6"),
    ("anonima", "var f=funcao(x){retorna x+1};escreva(f(2))", "3"),
    ("retorna_funcao", "funcao criar(){retorna funcao(x){retorna x+4}} escreva(criar()(5))", "9"),
    (
        "aninhada_segura",
        "funcao criar(){retorna f;funcao f(x){retorna x+4}}escreva(criar()(5))",
        "9",
    ),
    ("funcao_bloco", "se verdadeiro{funcao f(){retorna 7}escreva(f())}", "7"),
    ("padrao_dependente", "funcao f(a,b=a+2){retorna a+b}var g=f;escreva(g(3))", "8"),
    ("mapear", "escreva(mapear([1,2,3],funcao(x){retorna x*3}))", "[3, 6, 9]"),
    ("filtrar", "escreva(filtrar([1,2,3,4],funcao(x){retorna x%2==0}))", "[2, 4]"),
    ("para_cada", "paraCada([1,2],funcao(x){escreva(x*2)})", "2\n4"),
    (
        "todos",
        "escreva(todosEmCondicao([1,2],funcao(x){retorna x<3}),todosEmCondicao([1,4],funcao(x){retorna x<3}))",
        "verdadeirofalso",
    ),
    ("metodo_valor", "var v=[1];var f=v.adicionar;f(2);escreva(v,v.tamanho())", "[1, 2]2"),
    (
        "classe",
        "classe P{x:numero construtor(x){isto.x=x} dobro(){retorna isto.x*2}}var p=P(3);escreva(p.x,p.dobro());p.x=4;escreva(p.dobro())",
        "36\n8",
    ),
    (
        "classe_heranca",
        "classe A{x:numero construtor(x){isto.x=x}valor(){retorna isto.x}}classe B herda A{construtor(x){super(x+1)}valor(){retorna super.valor()*2}}var b=B(3);var f=b.valor;escreva(f(),b.x)",
        "84",
    ),
    (
        "construtor_herdado",
        "classe A{x:numero construtor(x){isto.x=x}}classe B herda A{}escreva(B(5).x)",
        "5",
    ),
    (
        "privado_interno",
        "classe A{privado{x:numero}construtor(){isto.x=7}obter(){retorna isto.x}}escreva(A().obter())",
        "7",
    ),
    (
        "protegido_subclasse",
        "classe A{protegido{x:numero}construtor(){isto.x=7}}classe B herda A{valor(){retorna isto.x}}escreva(B().valor())",
        "7",
    ),
    (
        "metodo_privado_capacidade",
        "classe A{privado{segredo(){retorna 9}}obter(){retorna isto.segredo}}escreva(A().obter()())",
        "9",
    ),
    (
        "acessor",
        "classe A{privado{_x:numero}x:numero{obter(){retorna isto._x}definir(valor){isto._x=valor*2}}construtor(){isto._x=1}}var a=A();a.x=3;escreva(a.x)",
        "6",
    ),
    (
        "objeto_basico",
        'classe A{}classe B herda A{}var b=B();escreva(b.tipo(),b.eInstanciaDe(A),b.eInstanciaDe(Objeto),b.respondeA("ausente"))',
        "Bverdadeiroverdadeirofalso",
    ),
    (
        "para_texto",
        'classe A{paraTexto(){retorna "customizado"}}escreva(A(),texto(A()))',
        "customizadocustomizado",
    ),
    (
        "excecao",
        'tente{falhar "erro"}pegue(erro){escreva(erro,erro.mensagem)}finalmente{escreva("fim")}',
        "erroerro\nfim",
    ),
    (
        "erro_operador_capturado",
        "var x=0;tente{x=8;escreva(1/0)}pegue(erro){escreva(x,erro.mensagem)}",
        "8Divisão por zero.",
    ),
    (
        "erro_indice_capturado",
        'tente{escreva([1][3])}pegue(erro){escreva("capturado")}',
        "capturado",
    ),
    (
        "finalmente_retorno",
        'funcao f(){tente{retorna 3}finalmente{escreva("fim")}}escreva(f())',
        "fim\n3",
    ),
    (
        "retorno_finalmente_prevalece",
        "funcao f(){tente{retorna 3}finalmente{retorna 9}}escreva(f())",
        "9",
    ),
    (
        "finalmente_erro_substitui",
        'tente{tente{falhar "original"}finalmente{falhar "novo"}}pegue(erro){escreva(erro)}',
        "novo",
    ),
    (
        "finalmente_retorno_erro",
        'funcao f(){tente{retorna 3}finalmente{falhar "novo"}}tente{f()}pegue(erro){escreva(erro)}',
        "novo",
    ),
    (
        "erro_pegue_limpeza",
        'tente{tente{falhar "um"}pegue(erro){falhar "dois"}finalmente{escreva("fim")}}pegue(erro){escreva(erro)}',
        "fim\ndois",
    ),
    (
        "pegue_tipado",
        'classe A herda Excecao{}classe B herda Excecao{}tente{falhar A("a")}pegue(erro:B){escreva("errado")}pegue(erro:A){escreva(erro)}',
        "a",
    ),
    (
        "finally_continue_break",
        'para(var i=0;i<4;i++){tente{se i==1{continua}se i==2{sustar}escreva(i)}finalmente{escreva("fim")}}escreva("depois")',
        "0\nfim\nfim\nfim\ndepois",
    ),
    (
        "clonar_ciclo",
        "var a=[];a.adicionar(a);var b=clonar(a);escreva(a!=b,b[0]==b)",
        "verdadeiroverdadeiro",
    ),
    (
        "clonar_profundo",
        "var a={'x':[1]};var b=clonar(a);b.x.adicionar(2);escreva(a.x,b.x)",
        "[1][1, 2]",
    ),
    (
        "clonar_objeto",
        "classe A{privado{x:numero}construtor(x){isto.x=x}set(x){isto.x=x}get(){retorna isto.x}}var a=A(1);var b=clonar(a);b.set(2);escreva(a.get(),b.get())",
        "12",
    ),
    (
        "unicode",
        "escreva(tamanho('ação'),'ação'[1],'ação'[1:3],'ação'.encontrar('ã'),'áÇ'.maiusculo(),'ÁÇ'.minusculo())",
        "4ççã2ÁÇáç",
    ),
    ("aparar", "escreva('  á  '.aparar(),'  á'.apararInicio(),'á  '.apararFim())", "ááá"),
    (
        "texto_metodos",
        "escreva('a,b,c'.dividir(','),'ação'.substituir('ç','s'),'ab'.concatenar(1,'c'))",
        "[a, b, c]asãoab1c",
    ),
    (
        "vetor_metodos",
        'var a=[3,1,2];escreva(ordenar(a),a.somar(),a.juntar("-"));escreva(a.encaixar(1,1,7,8),a);escreva(a.removerPrimeiro(),a.removerUltimo(),a.inverter())',
        "[1, 2, 3]61-2-3\n[2][1, 7, 8, 3]\n13[8, 7]",
    ),
    (
        "ordenacao_callback",
        "var a=[1,3,2];escreva(ordenar(a,funcao(x,y){retorna y-x}))",
        "[3, 2, 1]",
    ),
    (
        "map_metodos",
        "var d={'x':1};escreva(d.chaves(),d.valores(),d.contem('x'),d.remover('x'),tamanho(d))",
        "[x][1]verdadeiroverdadeiro0",
    ),
    (
        "interpolacao",
        "var n=2;escreva('valor ${n+1}, texto ${\"á\".maiusculo()}')",
        "valor 3, texto Á",
    ),
    ("interpolacao_literal", r"escreva('literal \${ausente}')", "literal ${ausente}"),
    (
        "spread_rest",
        "funcao f(x,...resto){retorna [x,...resto]}escreva(f(1,...[2,3]))",
        "[1, 2, 3]",
    ),
    ("spread_texto", "escreva([... 'áç'])", "[á, ç]"),
    (
        "slicing",
        "var v=[1,2,3,4,5];escreva(v[::-1],v[::2],v[-3:],v[:100],'ação'[::2])",
        "[5, 4, 3, 2, 1][1, 3, 5][3, 4, 5][1, 2, 3, 4, 5]aã",
    ),
    ("compreensao", "var v=[1,2,3,4];escreva([x*3 para cada x em v se x%2==0])", "[6, 12]"),
    ("ternario_efeito", "var x=0;escreva(verdadeiro ? x++ : 1/0,x)", "01"),
    (
        "escolha",
        'escolha 2{caso "2":escreva("errado")caso 1:caso 2:escreva("certo");sustar;padrao:escreva("errado")}',
        "certo",
    ),
    (
        "coleta_para",
        "var v=para(var i=0;i<5;i++){se i==3{sustar}retorna i*i}escreva(v)",
        "[0, 1, 4]",
    ),
    (
        "coleta_enquanto",
        'var i=0;var v=enquanto i<3{i++;tente{retorna i}finalmente{escreva("fim")}}escreva(v)',
        "fim\nfim\nfim\n[1, 2, 3]",
    ),
    (
        "assercoes",
        'assercao verdadeiro;tente{asserção(falso,"falhou")}pegue(erro){escreva(erro)}',
        "falhou",
    ),
    ("multipla", "var a,b=1,2;a,b=b,a;escreva(a,b)", "21"),
    (
        "desestruturar",
        "var d={'a':1,'b':2};const {a,b}=d;escreva(a,b);para cada {chave,valor} em {'x':7}{escreva(chave,valor)}",
        "12\nx7",
    ),
    ("sombreamento", "var x=1;se verdadeiro{var x=2;escreva(x)}escreva(x)", "2\n1"),
    ("tipo_dinamico", 'funcao f(){retorna "texto"}escreva(tipo de f())', "texto"),
]
ERRORS = [
    ("captura_anonima", "var x=1;var f=funcao(){retorna x}", "upvalues"),
    ("captura_parametro", "funcao f(x){retorna funcao(){retorna x}}", "upvalues"),
    ("captura_isto", "classe A{valor(){retorna funcao(){retorna isto}}}", "upvalues"),
    ("captura_padrao", "var x=1;funcao f(a=x){retorna a}", "upvalues"),
    ("ciclo_heranca", "classe A herda B{}classe B herda A{}", "Ciclo"),
    ("rest_invalido", "funcao f(...a,b){retorna a}", "último"),
    ("classe_estrangeira", "classe estrangeira A{}", "FFI C exige @definicao"),
    ("import_dinamico", "var nome='a.delegua';var m=importar(nome)", "literal"),
    ("import_nativo", "var m=importar('libc.so')", "segurança"),
]
RUNTIME_ERRORS = [
    ("privado", "classe A{privado{x:numero}construtor(){isto.x=1}}escreva(A().x)"),
    ("protegido", "classe A{protegido{x:numero}construtor(){isto.x=1}}escreva(A().x)"),
    ("campo_tipo", 'classe A{x:inteiro}var a=A();a.x="texto"'),
    ("campo_nao_declarado", "classe A{}var a=A();a.x=1"),
    ("contrato_indireto", 'funcao f(x:inteiro){retorna x}var g=f;g("texto")'),
    ("retorno_dinamico", 'funcao f(x):inteiro{retorna x}f("texto")'),
    ("aridade_indireta", "funcao f(x){retorna x}var g=f;g()"),
    ("setter_bloqueado", "classe A{x:numero{obter;}}var a=A();a.x=1"),
    ("passo_zero", "escreva([1,2][::0])"),
    ("tuple_method", "var t=tupla([1,2]);t.adicionar(3)"),
]
CASES += [
    (
        "identidade_funcao",
        "funcao f(){retorna 1}var g=f;escreva(f==f,g==f,escreva==escreva)",
        "verdadeiroverdadeiroverdadeiro",
    ),
    (
        "identidade_anonima",
        "var a=funcao(){retorna 1};var b=funcao(){retorna 1};escreva(a!=b,a==a)",
        "verdadeiroverdadeiro",
    ),
    ("interpolacao_intrinseca", 'var texto=1;escreva("${2}")', "2"),
    (
        "formatacao",
        "escreva(1234.5689.formatar(),1234.5689.formatar({minimoCasasDecimais:2,maximoCasasDecimais:3}))",
        "1.234,561.234,568",
    ),
    ("parametro_rest_tipado", "funcao f(...n:inteiro){retorna n.somar()}escreva(f(1,2,3))", "6"),
    (
        "while_continue_final",
        "var i=0;enquanto i<2{tente{i++;continua}finalmente{escreva(i)}}",
        "1\n2",
    ),
    (
        "for_each_variavel_excecao",
        'para cada x em [1]{tente{x=7;falhar "erro"}pegue(erro){escreva(x)}}',
        "7",
    ),
]
ERRORS += [
    (
        "metodo_sombreia_privado",
        "classe A{privado{x:numero}}classe B herda A{x(){retorna 1}}",
        "herdada",
    ),
    ("captura_sombra_builtin", "var texto=1;funcao f(){retorna texto}", "upvalues"),
]
RUNTIME_ERRORS += [
    ("array_contrato", 'funcao f(v:inteiro[]){retorna 1}var g=f;g(["texto"])'),
    ("parametro_rest_contrato", 'funcao f(...v:inteiro){retorna 1}var g=f;g(1,"texto")'),
    ("anotacao_sem_retorno", "funcao f():inteiro{}f()"),
]
MODULE_CASES = [
    (
        "modulo_cache",
        {
            "m.delegua": 'escreva("load");funcao soma(a,b=2){retorna a+b}var valor=7;classe P{x:numero construtor(x){isto.x=x}}',
            "main.delegua": "var m=importar('m.delegua');var n=importar('./m.delegua');escreva(m.soma(3),n.valor,m.P(4).x)",
        },
        "load\n574",
    ),
    (
        "modulo_transitivo",
        {
            "a.delegua": "funcao f(){retorna 4}",
            "b.delegua": "var a=importar('a.delegua');var valor=a.f()+1",
            "main.delegua": "var b=importar('b.delegua');escreva(b.valor)",
        },
        "5",
    ),
    (
        "modulo_inicializacao_falha",
        {
            "a.delegua": 'escreva("load");falhar "erro"',
            "main.delegua": "tente{var a=importar('a.delegua')}pegue(erro){escreva(erro)}tente{var a=importar('a.delegua')}pegue(erro){escreva(erro)}",
        },
        "load\nerro\nload\nerro",
    ),
]
MODULE_ERRORS = [
    (
        "modulo_ciclo",
        {
            "a.delegua": "var b=importar('b.delegua')",
            "b.delegua": "var a=importar('a.delegua')",
            "main.delegua": "var a=importar('a.delegua')",
        },
        "Ciclo",
    ),
    (
        "modulo_captura",
        {
            "a.delegua": "var segredo=1;funcao f(){retorna segredo}",
            "main.delegua": "var a=importar('a.delegua')",
        },
        "upvalues",
    ),
    ("modulo_ausente", {"main.delegua": "var a=importar('ausente.delegua')"}, "encontrado"),
]
CASES += [
    ("tupla_literal", 'var t=[(1,"a")];escreva(t[0],t.segundo)', "1a"),
    ("tupla_tipagem", 'var t:(numero,texto)=[(1,"a")];escreva(t)', "(1, a)"),
    ("map_spread", "var d={a:1};var b={...d,b:2};escreva(b.a,b.b)", "12"),
    (
        "unicode_expansao",
        "escreva('straße'.maiusculo(),'ΟΣ'.minusculo(),'İ'.minusculo())",
        "STRASSEοςi̇",
    ),
    ("unicode_trim", "escreva('  texto  '.aparar())", "texto"),
    (
        "responde_primitiva",
        "escreva('a'.respondeA('tamanho'),1.respondeA('adicionar'),[1].respondeA('somar'))",
        "verdadeirofalsoverdadeiro",
    ),
    (
        "decoradores_metadados",
        "@minimo(valor=0) classe A{@maximo(valor=10) x:numero}escreva(decoradores(A).classe[0].nome,decoradores(A).propriedades.x[0].argumentos.valor)",
        "minimo10",
    ),
    (
        "decoradores_funcao",
        '@documentado(nome="teste") funcao f(){retorna 1}escreva(decoradores(f)[0].nome)',
        "documentado",
    ),
    (
        "envelope_seguro",
        "funcao replacement(){retorna 9}funcao de decorador trocar(original){retorna replacement}@trocar funcao teste(){retorna 1}escreva(teste())",
        "9",
    ),
]
ERRORS += [
    (
        "envelope_captura",
        "funcao de decorador wrap(f){retorna funcao(){retorna f()}}@wrap funcao f(){retorna 1}",
        "upvalues",
    ),
    ("metadado_executa", "funcao f(){retorna 1}@atributo(valor=f())classe A{}", "constantes"),
]
RUNTIME_ERRORS += [
    ("tupla_tipagem_invalida", "funcao f(t:(numero,texto)){retorna 1}var g=f;g([(1,2)])"),
]
CASES += [
    (
        "campos_classe_forward",
        "classe A{b:B construtor(b){isto.b=b}}classe B{x:numero construtor(){isto.x=3}}escreva(A(B()).b.x)",
        "3",
    ),
    (
        "classe_tipo_base",
        "classe A{}classe B herda A{}classe C herda A{}var a:A=B();a=C();escreva(a.tipo())",
        "C",
    ),
    ("tipado_sem_inicializador", "var x:inteiro;escreva(x);x=3;escreva(x)", "0\n3"),
]
MODULE_CASES += [
    (
        "modulos_identidade_nominal",
        {
            "a.delegua": "classe P{}funcao aceitar(p:P){retorna 1}",
            "b.delegua": "classe P{}",
            "main.delegua": "var a=importar('a.delegua');var b=importar('b.delegua');var x:qualquer=b.P();tente{a.aceitar(x)}pegue(erro){escreva('bloqueado')}",
        },
        "bloqueado",
    ),
]
MODULE_ERRORS += [
    (
        "modulos_identidade_nominal_estatica",
        {
            "a.delegua": "classe P{}funcao aceitar(p:P){retorna 1}",
            "b.delegua": "classe P{}",
            "main.delegua": "var a=importar('a.delegua');var b=importar('b.delegua');a.aceitar(b.P())",
        },
        "E3002",
    ),
]
CASES += [
    (
        "array_tipado_alias",
        'var a:inteiro[]=[1];var b:qualquer=a;tente{b.adicionar("erro")}pegue(erro){escreva("bloqueado")}escreva(a)',
        "bloqueado\n[1]",
    ),
    ("array_tipado_encaixar", "var a:inteiro[]=[1];a.encaixar(1,0,2,3);escreva(a)", "[1, 2, 3]"),
    (
        "array_tipo_alias_encaixar",
        'var a:inteiro[]=[1];var b:qualquer=a;tente{b.encaixar(0,1,"erro")}pegue(erro){escreva("bloqueado")}escreva(a)',
        "bloqueado\n[1]",
    ),
    (
        "literais_numericos_expandidos",
        "/* comentário em bloco */\n"
        "const h: inteiro = 0xFF; const m: inteiro = 0xFFFF_FFFF; "
        "const b: inteiro = 0b101010; const f: inteiro = 0b1111_0000; "
        "const o: inteiro = 0o755; const p: inteiro = 1_000_000; "
        "const r: real = 3_141.592_653; const hf: real = 0x1.fp+3; "
        "const e1: real = 1.25e-2; "
        "escreva(h, m, b, f, o, p, inteiro(r * 1000), hf, e1)",
        "2554294967295422404931000000314159215.50.0125",
    ),
    (
        "dobramento_constantes_bits_identidades",
        "funcao calc(x: inteiro): inteiro { "
        "const mask: inteiro = (0xF0 & 0x3F) | (1 << 4) ^ (32 >> 2); "
        "const divp: inteiro = (2 ** 10) \\ 10; "
        "retorna ((((x + 0) * 1 - 0) | 0) ^ 0) + (0 + mask) + (divp \\ 1) "
        "} escreva(calc(5))",
        "163",
    ),
    (
        "ordem_avaliacao_argumentos_mutados",
        "var i: inteiro = 10; escreva(i, i++, i, ++i, i)",
        "1010111212",
    ),
    (
        "lvalue_indice_pos_incremento",
        'var v = [10, 20, 30]; var i = 0; v[i] = i++; var j = 0; var w = [10, 20, 30]; w[j] = ++j; escreva("${v[0]},${v[1]},${i};${w[0]},${w[1]},${j}")',
        "0,20,1;1,20,1",
    ),
    (
        "cursor_utf8_reverso_multibyte",
        'var s = "abcáéíóúxyz😀fim"; var l = "0123456789abcdef0123456789abcdefçãõ"; escreva("${s[0]}:${s[5]}:${s[10]}:${s[11]}:${s[10]}:${s[3]}:${s.fatiar(3, 8)}:${s.fatiar(-4, -1)}:${tamanho(s)}|${l[5]}:${l[32]}:${l[34]}:${l[33]}:${l[10]}:${tamanho(l)}")',
        "a:í:z:😀:z:á:áéíóú:😀fi:15|5:ç:õ:ã:a:35",
    ),
    (
        "literais_numericos_expandidos_ciclo2",
        '@puro\nfuncao dobro(n: inteiro): inteiro { retorna n * 2 }\nconst a: inteiro = 0x1_0; const b: inteiro = 0b1010_0101; const c: inteiro = 0o7_7; const d: real = 1_000.5e-1; const hx: real = 0x1.fp+3; const d2: inteiro = dobro(0x0A); escreva("${a}:${b}:${c}:${d}:${hx}:${d2}:${0xFF.paraTexto()}:${inteiro(0b1111)}")',
        "16:165:63:100.05:15.5:20:255:15",
    ),
    (
        "promessa_nao_corrompe_descr_vetor",
        'assincrona funcao f(): texto { retorna "ok" }\nassincrona funcao g(): vazio { var p: Promessa<texto> = f(); var v: texto[] = "a/b".dividir("/"); escreva("${aguardar p}:${v[0]}:${v[1]}") }\ng()',
        "ok:a:b",
    ),
]
ERRORS += [
    ("hex_vazio", "const x = 0x", "E1005"),
    ("bin_digito_invalido", "const x = 0b102", "E1005"),
    ("oct_digito_invalido", "const x = 0o89", "E1005"),
    ("sep_duplo", "const x = 1__000", "E1005"),
    ("sep_final", "const x = 100_", "E1005"),
    ("exp_incompleto", "const x = 1e+", "E1005"),
    ("hex_digito_invalido", "const x = 0xGG", "E1005"),
    ("identificador_nao_declarado_sublinhado", "const x = _100", "declarado"),
]
