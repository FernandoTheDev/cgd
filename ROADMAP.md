# CGD Roadmap — Implementação de Features da Linguagem

Baseado na especificação da wiki do Delégua. Organizado por ordem de dependência e complexidade.
Cada milestone depende das anteriores.

---

## ✅ Já Implementado

- `var` / variáveis simples
- Literais: inteiro, float, texto, booleano, nulo
- Operadores binários: `+`, `-`, `*`, `/`, `<=`, `>=`, `<`, `>`, `==`
- Funções com nome e retorno (`função f(x) { retorne x }`)
- Chamada de função e recursão
- `se` condicional simples (sem `senão`)
- `escreva()`
- Escopo léxico (pushScope/popScope)

---

## Milestone 1 — Fundamentos Completos

> Base sólida sem a qual nada mais funciona.

### 1.1 Tipos nativos faltando

- [ ] `CGD_ValueType_Bool` — tipo booleano real separado de int
  - Adicionar `CGD_Bool` no runtime
  - Atualizar `__cgd_binary_op_ee`, `__cgd_binary_op_lt`, `__cgd_binary_op_gt` para retornar `Bool`
  - Adicionar `cgd_bool(bool val)` inline helper

- [ ] `CGD_ValueType_Double` — já existe no runtime mas checar se codegen emite `cgd_double()`

### 1.2 Constantes

```delegua
const a = "1"
a = "2" // Erro
```

- Parser: reconhecer `const` / `constante` / `fixo`
- Sema: marcar símbolo como imutável, emitir erro em atribuição

### 1.3 Operadores faltando

- [ ] `!=` — diferente de
- [ ] `%` — módulo
- [ ] `**` — exponenciação
- [ ] `\` — divisão inteira
- [ ] `e` / `ou` — lógicos (AND/OR)
- [ ] `-` unário (negação)
- [ ] `++` / `--` pré e pós incremento
- [ ] `+=`, `-=`, `*=`, `/=`, `%=`

### 1.4 Atribuição depois de declaração

```delegua
var a = 1
a = 2
```

- Hoje provavelmente só declara, verificar se reatribuição funciona

### 1.5 `senão` / `senão se`

```delegua
se a == 1 {
    escreva("um")
} senao se a == 2 {
    escreva("dois")
} senao {
    escreva("outro")
}
```

- Parser: `senao` / `senão` como token
- Codegen: `else if` / `else` em C

### 1.6 `se` ternário

```delegua
var cat = idade < 18 ? "menor" : "adulto"
```

- Parser: expressão ternária `? :`
- Codegen: `(cond).i.val ? a : b`

---

## Milestone 2 — Fluxo de Controle

### 2.1 `enquanto`

```delegua
var a = 1
enquanto a <= 10 {
    escreva(a)
    a = a + 1
}
```

- Parser: `enquanto <expr> <bloco>`
- Codegen: `while (expr.i.val) { ... }`

### 2.2 `para` (for clássico)

```delegua
para var i = 0; i < 5; i = i + 1 {
    escreva(i)
}
```

- Parser: `para <init>; <cond>; <step> <bloco>`
- Codegen: `for (...)`

### 2.3 `fazer ... enquanto`

```delegua
fazer {
    escreva("sim")
} enquanto falso
```

- Parser: `fazer <bloco> enquanto <expr>`
- Codegen: `do { ... } while (expr.i.val)`

### 2.4 `sustar` / `continua` (break / continue)

```delegua
enquanto verdadeiro {
    sustar
}
```

- Parser: tokens `sustar`, `continua`
- Codegen: `break;`, `continue;`

### 2.5 `escolha` / `caso` (switch)

```delegua
escolha a {
    caso 1:
        escreva("um")
    caso 2:
        escreva("dois")
    padrao:
        escreva("outro")
}
```

- Parser: `escolha <expr> { caso <expr>: <stmts>... padrao: <stmts> }`
- Codegen: `switch` em C ou cadeia de `if/else if`

---

## Milestone 3 — Strings

> Strings hoje são `CGD_String` mas provavelmente sem operações.

### 3.1 Concatenação de strings

```delegua
var s = "olá" + " mundo"
```

- Runtime: `__cgd_binary_op_add` quando `type == String` → `strcat` / alocação

### 3.2 Interpolação de texto

```delegua
var nome = "Fernando"
escreva("Oi ${nome}")
```

- Lexer: detectar `${...}` dentro de string
- Codegen: quebrar string em partes e concatenar com `cgd_str_concat`
- Runtime: `cgd_str_interpolate` ou similar

### 3.3 Indexação de string

```delegua
escreva("abc"[0]) // a
escreva(texto[-1]) // último char
```

- Runtime: `cgd_str_index(CGD_Value s, CGD_Value i)`

### 3.4 Métodos de string (runtime)

Adicionar ao runtime como funções `cgd_str_*`:

- [ ] `aparar()` → `trim`
- [ ] `apararFim()` → `rtrim`
- [ ] `apararInicio()` → `ltrim`
- [ ] `maiusculo()` → `toupper` cada char
- [ ] `minusculo()` → `tolower`
- [ ] `tamanho()` → `strlen` / `s.len`
- [ ] `dividir(sep)` → split, retorna `CGD_Array`
- [ ] `encontrar(sub)` → `strstr` offset
- [ ] `inclui(sub)` → `strstr != NULL`
- [ ] `fatiar(ini, fim)` → substring
- [ ] `substituir(de, para)` → replace
- [ ] `concatenar(outro)` → concat
- [ ] `subtexto(ini, fim)` → alias fatiar
- [ ] `tudoMaiusculo()` → bool
- [ ] `tudoMinusculo()` → bool

### 3.5 Acesso a método via ponto no codegen

```delegua
texto.maiusculo()
```

- Parser: `expr.ident(args)` como `CallExpr` com receiver
- Codegen: despacha para `cgd_str_maiusculo(texto)`

---

## Milestone 4 — Arrays (Vetores)

### 4.1 Tipo CGD_Array no runtime

```c
typedef struct {
    size_t len;
    size_t cap;
    CGD_Value *data;
} CGD_Array;
```

- `cgd_array_new()` — cria array vazio
- `cgd_array_push(arr, val)` — adiciona
- `cgd_array_get(arr, idx)` — lê (suporte a índice negativo)
- `cgd_array_set(arr, idx, val)` — escreve (crescimento dinâmico)
- `cgd_array_len(arr)` → `CGD_Value` inteiro

### 4.2 Literal de array

```delegua
var v = [1, "2", verdadeiro]
```

- Parser: `[ expr, expr, ... ]`
- Codegen: cria `CGD_Array`, push cada elemento

### 4.3 Indexação

```delegua
v[0]
v[-1]
v[2] = 99
```

- Codegen: `cgd_array_get` / `cgd_array_set`

### 4.4 Crescimento automático além do tamanho

```delegua
var v = [1, 2]
v[3] = 3
// v == [1, 2, nulo, 3]
```

- Runtime: preenche com `CGD_ValueType_Null` entre o último e o novo índice

### 4.5 Métodos de array (runtime)

- [ ] `adicionar(val)` / `empilhar(val)` → push
- [ ] `removerUltimo()` → pop
- [ ] `removerPrimeiro()` → shift
- [ ] `remover(val)` → remove primeira ocorrência
- [ ] `tamanho()` → len
- [ ] `inverter()` → in-place reverse
- [ ] `inclui(val)` → linear search → bool
- [ ] `concatenar(outro)` → merge dois arrays
- [ ] `fatiar(ini, fim)` → slice, novo array
- [ ] `juntar(sep)` → join → string
- [ ] `ordenar()` → bubble sort / qsort
- [ ] `ordenar(fn)` → sort com comparador
- [ ] `mapear(fn)` → map
- [ ] `filtrarPor(fn)` → filter
- [ ] `somar()` → soma numérica
- [ ] `encaixar(pos, del, ...vals)` → splice

---

## Milestone 5 — Dicionários

### 5.1 Tipo CGD_Dict no runtime

```c
typedef struct {
    CGD_Value *keys;
    CGD_Value *vals;
    size_t len;
    size_t cap;
} CGD_Dict;
```

Chaves aceitas: Int, Float, String, Bool.

### 5.2 Literal de dicionário

```delegua
var d = {"a": 1, "b": 2}
var vazio = {}
```

- Parser: `{ expr: expr, ... }`
- Codegen: `cgd_dict_new()` + `cgd_dict_set()`

### 5.3 Acesso e atribuição

```delegua
d["a"]
d.a
d["c"] = 3
```

- Codegen: `cgd_dict_get` / `cgd_dict_set`
- `d.a` como açúcar sintático para `d["a"]`

### 5.4 Métodos de dicionário

- [ ] `chaves()` → array de chaves
- [ ] `valores()` → array de valores
- [ ] `contém(k)` / `contem(k)` → bool
- [ ] `remover(k)` → remove entrada

---

## Milestone 6 — Funções Avançadas

### 6.1 Funções anônimas

```delegua
var dobro = funcao(a) { retorna a * 2 }
escreva(dobro(5)) // 10
```

- Parser: `funcao (<params>) { <bloco> }` como expressão
- Codegen: emite função com nome gerado (`__cgd_lambda_N`)

### 6.2 Funções como valores (first-class)

```delegua
var fn = dobro
fn(3)
```

- Runtime: `CGD_ValueType_Func` com ponteiro de função
- Codegen: `cgd_func(void*)` e `cgd_call_func(val, args)`

### 6.3 Funções passadas como argumento

```delegua
v.mapear(funcao(n) { retorna n * 2 })
```

- Depende de 6.1 e 6.2

### 6.4 Argumento spread / rest

```delegua
funcao teste(...argumentos) {
    escreva(argumentos)
}
teste(1, 2, 3) // [1, 2, 3]
```

- Parser: `...param` como último argumento
- Codegen: coleta argumentos extras em `CGD_Array`

### 6.5 Spread em chamada

```delegua
var v = [3, 4, 5]
teste(1, 2, ...v)
```

- Parser: `...expr` em posição de argumento
- Codegen: expande o array

---

## Milestone 7 — Entrada / Saída

### 7.1 `leia()`

```delegua
var entrada = leia()
```

- Runtime: `fgets` ou `readline` → retorna `CGD_Value` string
- Codegen: `cgd_leia()`

### 7.2 `escreva()` com múltiplos args

```delegua
escreva(a, b, c) // separados por espaço
```

- Hoje provavelmente só aceita um. Iterar args e imprimir com espaço.

### 7.3 Interpolação em `escreva`

Depende de Milestone 3.2.

---

## Milestone 8 — Exceções

```delegua
tente {
    falhar "erro aqui"
} pegue (e) {
    escreva(e)
} finalmente {
    escreva("sempre executa")
}
```

### 8.1 `falhar`

- Parser: `falhar <expr>`
- Runtime: `cgd_falhar(CGD_Value msg)` → `longjmp` ou `exit` com mensagem

### 8.2 `tente ... pegue ... finalmente`

- Requer mecanismo de exceção em C: `setjmp` / `longjmp`
- Parser: bloco tente/pegue/finalmente
- Runtime: pilha de contextos `jmp_buf`
- Codegen: envolver bloco em `setjmp`, catch em `longjmp`

---

## Milestone 9 — Orientação a Objetos

> Esta é a milestone mais complexa. Depende de todas as anteriores.

### 9.1 Classes básicas

```delegua
classe Animal {
    construtor() { }
}
var a = Animal()
```

- Parser: `classe <nome> { <membros> }`
- Runtime: `CGD_Class`, `CGD_Instance`
- Codegen: emite struct + funções para cada método

### 9.2 Propriedades e `isto`

```delegua
classe Ponto {
    x: numero
    y: numero

    construtor(x, y) {
        isto.x = x
        isto.y = y
    }
}
```

- Runtime: `CGD_Instance` com `CGD_Dict` de propriedades
- Codegen: `cgd_get_prop(inst, "x")` / `cgd_set_prop(inst, "x", val)`

### 9.3 Métodos

```delegua
teste.testeFuncao()
```

- Codegen: `cgd_call_method(inst, "testeFuncao", args)`

### 9.4 Herança simples

```delegua
classe Cachorro herda Animal { }
```

- Runtime: copiar métodos do pai para o filho na criação da classe

### 9.5 `super`

```delegua
super.data(data)
super()
```

### 9.6 Níveis de acesso

- `público` (padrão)
- `privado { }` — só acessível dentro da classe
- `protegido { }` — acessível por subclasses

### 9.7 Classes abstratas

```delegua
classe abstrata Poligono { }
var p = Poligono() // Erro
```

### 9.8 Herança múltipla / composição (`mescla`)

```delegua
classe Servico mescla Logavel { }
```

### 9.9 Interfaces

```delegua
interface Identificavel {
    id: numero
    identificar(): texto
}
```

---

## Milestone 10 — Funções Nativas da Stdlib

Implementar no runtime como `cgd_*`:

### Aleatoriedade
- [ ] `aleatorio()` → `rand() / RAND_MAX`
- [ ] `aleatorioEntre(min, max)` → `rand() % (max-min) + min`

### Conversões de tipo
- [ ] `inteiro(v)` → cast para long
- [ ] `numero(v)` → cast para double
- [ ] `real(v)` → cast para float
- [ ] `texto(v)` → sprintf para string

### Funções de vetor globais
- [ ] `filtrar(v, fn)` → filter
- [ ] `mapear(v, fn)` → map
- [ ] `paraCada(v, fn)` → forEach
- [ ] `ordenar(v)` → sort
- [ ] `tamanho(v)` → len
- [ ] `todosEmCondicao(v, fn)` → all
- [ ] `tupla([...])` → CGD_Tuple com named fields (primeiro, segundo, ...)
- [ ] `clonar(v)` → deep copy

---

## Milestone 11 — Features Avançadas de Linguagem

### 11.1 Atribuição múltipla

```delegua
var a, b, c = 1, 2, 3
```

### 11.2 Desestruturação

```delegua
var { a, b } = dicionario
```

### 11.3 Operador de coalescência de nulo (Elvis)

```delegua
var x = nulo ?: 10 // x = 10
```

- Parser: `?:`
- Codegen: `(left.type != Null) ? left : right`

### 11.4 Operador `em` / `contém`

```delegua
'b' em ['a', 'b'] // verdadeiro
'chave' em {'chave': 1} // verdadeiro
```

### 11.5 `tipo de`

```delegua
escreva(tipo de a) // "numero"
```

### 11.6 Compreensão de listas

```delegua
var pares = [x para cada x em lista se x % 2 == 0]
```

- Parser: `[expr para cada ident em expr (se expr)?]`

### 11.7 `para cada`

```delegua
para cada elem de v {
    escreva(elem)
}
```

### 11.8 Loops retornando vetores (v0.53.0+)

```delegua
var resultado = enquanto a <= 5 {
    a++
    retorna a * 6
}
```

### 11.9 `tendo ... como` (RAII)

```delegua
tendo arquivo.abrir('f.txt') como f {
    f.escrever('123')
}
```

### 11.10 Tupla

```delegua
var t = tupla([1, 2])
escreva(t.primeiro) // 1
```

### 11.11 Asserções

```delegua
asserção 2 == 2
asserção(2 == 1, "mensagem de erro")
```

### 11.12 Decoradores

```delegua
@minimo(valor=0)
lado: número
```

---

## Milestone 12 — Módulos e Importação

```delegua
const arquivos = importar('arquivos')
```

- Sistema de módulos C: cada módulo é um `.so` / `.a` ou arquivo C linkado
- Runtime: `cgd_importar(char* nome)`
- API para extensões externas

---

## Ordem Sugerida de Implementação

```
M1 (fundamentos) → M2 (fluxo) → M3 (strings) → M7 (I/O)
     ↓
M4 (arrays) → M5 (dicts) → M10 (stdlib)
     ↓
M6 (funções avançadas) → M8 (exceções)
     ↓
M9 (OO) → M11 (features avançadas) → M12 (módulos)
```

---

## Notas de Implementação

**Runtime vs Codegen:**  
Sempre que possível, implementar a feature no runtime C e emitir apenas uma chamada de função no codegen. Isso mantém o compilador pequeno e o runtime extensível.

**Método via ponto:**  
`valor.metodo(args)` deve ser detectado no parser como `MethodCallExpr` com receiver e nome do método. No codegen, despacha para `cgd_TIPO_metodo(receiver, args)` baseado no tipo inferido (ou em runtime check no CGD_Value).

**Bool real:**  
Implementar antes de qualquer feature que dependa de condicionais para garantir semântica correta.

**GC / Memória:**  
Strings, arrays e dicionários alocam no heap. Considerar arena allocator por escopo ou reference counting simples antes de implementar GC completo.
