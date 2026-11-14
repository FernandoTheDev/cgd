# Desenvolvimento do compilador

Leia [AGENTS.md](../AGENTS.md) antes de alterar o pipeline. A linguagem original é
[Delégua, da Design Líquido](https://github.com/DesignLiquido/delegua).

## Pipeline e contratos

A ordem é: UTF-8/tokens → parsing recuperável → loading estático → validação da
estrutura → símbolos → tipos → resolução semântica → segurança estática → pureza → análise de fluxo →
otimizações opcionais → lowering → C99 → toolchain externa.

`--verificar` encerra após a análise, sem exigir runtime nem compilador C.
`--emitir-c` gera somente o C, inclusive com `-o`, sem vincular bibliotecas.
O backend não executa código da linguagem para descobrir tipos.

`AstRewriter` percorre os slots mutáveis da AST em pós-ordem e visita referências
compartilhadas a módulos/funções uma vez. Não segue links de resolução para
símbolos, superclasses ou donos de métodos. Nomes de propriedades e destinos de
atribuição não são expressões substituíveis.

O gerenciador de passes mede alterações e encerra ao atingir ponto fixo, com teto
defensivo de oito iterações. Uma árvore já estável passa apenas uma vez, em vez
das vinte repetições fixas anteriores. `-d -o` mostra os contadores.

| Otimização                           | Garantia                                                                                                                                                              |
| ------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Dobra de literais                    | Aritmética, comparações, concatenação, módulo inteiro e negação; overflow, divisão por zero e resultados reais não finitos ficam no runtime                           |
| Propagação de constantes             | Identidade da declaração resolvida, não busca pelo nome; somente constantes literais sem anotação que possa converter o valor                                         |
| Curto-circuito/coalescência/ternário | Elimina só lados que comprovadamente não executam; preserva os valores retornados pelos operadores                                                                    |
| Ramos e laços mortos                 | Remove ramos literais e `enquanto falso`; não antecipa condições nem efeitos de laços                                                                                 |
| Caudas inalcançáveis                 | Retorno, falha, sustar/continua e ambos os ramos terminantes; mantém funções/classes declaradas adiante e os blocos finalmente                                        |
| CTFE                                 | Função resolvida precisa ser exatamente a função registrada como pura, com aridade exata e argumentos literais; limites, falhas e contratos preservam execução nativa |

A VM usa slots distintos por declaração e por parâmetro, restaura vínculos ao
sair de blocos, implementa `senão`, atribuições compostas e incrementos e avalia
argumentos da esquerda para a direita. Contratos primitivos de parâmetros,
variáveis locais e retorno são validados antes de aceitar um resultado CTFE.
Não se substituem chamadas que falham, retornam nulo implicitamente, dependem de
conversão textual mista ou usam valores que a VM não representa: a chamada nativa
permanece e sua exceção pode ser tratada normalmente. Chamadas indiretas e funções
locais dentro de funções marcadas puras recebem diagnóstico de limitação da CTFE.

Não use identidades algébricas como `x * 0 → 0`: avaliar `x` pode lançar exceção ou
ter efeitos. Não remova variáveis apenas por contagem de usos. Não propague
coleções mutáveis ou remova validações de contratos.

## Diagnósticos e limites

`--diagnosticos=json` escreve um objeto JSON por linha em stderr. Cada objeto tem
`severity`, `code`, `message` e, quando existe posição, `file` e `range` com
`start/end`, `line/column`. Linhas e colunas começam em 1; as colunas contam
pontos de código Unicode, e o final é exclusivo. Falhas gerais usam `E9001` e
podem não ter intervalo. Mensagens permanecem em português.

Códigos: `E1001` sintaxe, `E1002` UTF-8, `E1003` aninhamento sintático,
`E1004` estrutura, `E2001` ciclo de módulos, `E2002` orçamento de loading,
`E2003` importação, `E3001/H3001` símbolo ausente/sugestão, `W3001` código
inalcançável e `W3002` possível retorno implícito em função tipada. Diagnósticos
legados conservam `E0001/W0001/H0001`. Os códigos são mais estáveis que o texto;
ainda não há protocolo LSP nem fix-its automáticos.

O parser sincroniza em declarações, comandos, ponto e vírgula e fechamento de
bloco. Ele não envia uma AST com erros para a semântica. Há limite de 256 níveis
sintáticos e de 512 níveis/500 mil nós antes dos passes recursivos; fontes têm
limite de 4 MiB, módulos têm orçamento acumulado de 64 MiB/1024 unidades e 64
níveis. O renderer limita o trecho a cinco linhas e evita repetir diagnósticos.

Os codificadores de nomes e textos C reservam buffers e escrevem dígitos hexadecimais/
octais diretamente, mantendo exatamente os bytes da versão anterior. O teste em D
compara ambas as codificações para Unicode, aspas, barra, newline e byte nulo.
O microbenchmark `rdmd -O -release -Isrc scripts/benchmark_codegen.d` mediu
362 ms antes e 51 ms depois nesta máquina. É uma medição desses codificadores,
não da compilação completa; o script não impõe limiares frágeis de tempo.

A análise de fluxo é conservadora: avisa sobre caudas inalcançáveis e possível
retorno implícito; não pretende provar terminação de laços ou ausência de falhas.
Os avisos não dependem de `-o` e não tornam uma compilação válida inválida.

## Toolchain e compilação cruzada

```sh
./cgd programa.delegua --verificar --diagnosticos=json
./cgd programa.delegua --emitir-c -o -s out/programa
./cgd programa.delegua --cc clang --target aarch64-linux-gnu \
  --sysroot /sdk --runtime-object /sdk/lib/libdelegua_rt.o \
  --runtime-root /sdk/cgd --pkg-config aarch64-linux-gnu-pkg-config \
  --cflag=-g --ldflag=-static -s out/programa
```

O último comando é um modelo de configuração, não um SDK fornecido pelo CGD.
O runtime, Boehm GC e todas as bibliotecas precisam ter sido compilados para o
mesmo alvo. `--target` usa a opção de Clang; para GCC cruzado selecione o
executável apropriado em `--cc` e omita essa opção. `PKG_CONFIG_LIBDIR` e
`PKG_CONFIG_SYSROOT_DIR` são herdados. Bibliotecas Linux não são injetadas em
triplas Windows. Nenhum executável cruzado foi validado nesta etapa.

A canonicalização POSIX mantém realpath e cache por identidade. A alternativa
Windows usa caminhos absolutos normalizados e comparação sem distinção de caixa;
junctions/symlinks e o runtime ainda exigem validação nativa. Os instaladores shell
continuam sendo destinados ao ambiente Linux validado.

## Formatação reproduzível

Instale [dfmt](https://github.com/dlang-community/dfmt),
[clang-format](https://clang.llvm.org/docs/ClangFormat.html),
[Ruff](https://docs.astral.sh/ruff/formatter/),
[Prettier](https://prettier.io/docs/install) e
[shfmt](https://github.com/mvdan/sh) e [Taplo](https://taplo.tamasfe.dev/) para TOML. As configurações estão na raiz.

```sh
python3 scripts/formatar.py
python3 scripts/formatar.py --check
```

Ferramentas usadas nesta revisão: dfmt `c65d1c8`, clang-format 22, Ruff 0.17.5,
Prettier 3.8.1, shfmt 3.12.0 e Taplo 0.9.0. O script também aceita ferramentas locais em
`out/tools/`, sem adicioná-las ao Git. Não baixa executáveis automaticamente.

Arquivos `.delegua` mantêm sua sintaxe e contratos: não há formatador Delégua
configurado e não se usa um parser JavaScript no lugar dele. Tabelas Unicode
geradas são reproduzidas pelo gerador e não reformatadas. Licenças e binários
não são entradas de formatadores de código.

## Verificar mudanças

Além da matriz e dos sanitizadores documentados no README, execute
`python3 testes/driver.py`, `python3 scripts/gerar_referencia.py --check` e os
testes do website. A referência web incorpora os próprios exemplos versionados;
edite os fontes e regenere com `python3 scripts/gerar_referencia.py`.

## Segurança estática e catálogo de mensagens

`frontend/static_safety.d` prova falhas locais antes do backend e funciona também
sem `-o`. Ele avalia expressões literais e constantes imutáveis, sem executar
funções ou presumir o conteúdo de vetores compartilhados. Divisão/módulo por
zero, overflow de 64 bits, índices de literais, passos zero, deslocamentos,
conversões textuais e contratos primitivos demonstravelmente incompatíveis
recebem E3101–E3108. Anotações de vetores/tuplas também verificam literais.

Ramos constantes descartados por se, ternário, curto-circuito e laços falsos
não recebem falsos erros dessa etapa. Em um corpo protegido por pegue, a falha
conhecida gera W31xx: o tratamento deliberado de exceções é preservado. Isso não
prova que um pegue tipado específico capturará a falha. Não há prova global de
programas: aliases mutáveis, entrada externa, chamadas indiretas e condições
não conhecidas continuam protegidos pelo runtime. A avaliação de constantes tem
limite de profundidade para não esgotar a pilha através de cadeias de símbolos.

O catálogo está em `src/diagnostics/catalog.d`: código, modelo da mensagem e
explicação ficam juntos. Lexer, fluxo, tipos, capturas e o novo passe usam esse
catálogo. O parser compartilha um modelo contextual para tokens esperados;
diagnósticos ainda não migrados conservam códigos genéricos. O renderer humano,
o JSON e `--explicar` consomem as mesmas referências. A tabela da referência web
é gerada diretamente desse catálogo, sem copiar as mensagens manualmente.

```sh
./cgd --explicar E3101
./cgd --explicar R0001
./cgd fonte.delegua --verificar --diagnosticos=json
```

## Localização sem chamadas no caminho normal

O C gerado contém uma tabela `static const delegua_local cgd_source_sites[]`.
Antes das operações que podem falhar, o compilador emite uma atribuição a
`delegua_local_atual`; não emite `delegua_localizar()` por expressão ou linha.
Literais numéricos, leitura simples de variáveis e declarações não falíveis não
fazem essa atualização. Há custo de uma escrita de ponteiro nos pontos falíveis;
a localização não é gratuita nem exige uma chamada adicional.

Formatação e impressão da localização ocorrem somente no caminho de erro do
runtime. O código R0001 identifica a categoria dinâmica genérica; ainda não há
um código distinto para cada mensagem nativa. A API C antiga `delegua_localizar`
continua compatível para consumidores nativos. Não há uma pilha completa de
chamadas ou reconstrução precisa de todos os auxiliares de coleções.

## Editar o runtime a partir deste checkout

O vendor já é um submódulo com seu próprio Git e remote; não execute git init.
Os commits de fonte pertencem primeiro ao repositório do runtime, e o CGD
registra o commit utilizado.

```sh
git -C vendor/delegua-runtime status
git -C vendor/delegua-runtime remote -v
# Edite vendor/delegua-runtime/src/...
(cd vendor/delegua-runtime && ./tests/run.sh)
git -C vendor/delegua-runtime add src tests
git -C vendor/delegua-runtime commit -m "fix(runtime): descrever a mudança"
git -C vendor/delegua-runtime push origin dev
./build-runtime
git add vendor/delegua-runtime
git commit -m "build: atualizar referencia do runtime"
```

Remote original: https://github.com/FernandoTheDev/delegua-runtime. Atualizações
explícitas usam `git -C vendor/delegua-runtime pull --ff-only origin dev`; preserve
alterações locais antes disso. Stashes existentes não são descartados.
