# Registro de validação

Validação local concluída em **14/11/2026**, em Linux x86_64. Os comandos abaixo
foram executados sobre a árvore de código preparada para a branch `dev`.
Não se trata de uma declaração de suporte a plataformas não testadas.

## Compiladores usados

| Ferramenta | Versão observada                             |
| ---------- | -------------------------------------------- |
| dmd        | DMD64 D Compiler v2.111.0                    |
| ldc2       | LDC - the LLVM D compiler (1.42.0):          |
| clang      | clang version 22.1.8 (Fedora 22.1.8-4.fc44)  |
| gcc        | gcc (GCC) 16.2.1 20260819 (Red Hat 16.2.1-2) |

## Matriz do frontend e dos programas gerados

| Frontend D | Build   | C gerado com | Integração           | Catálogo                                       | Instalação isolada |
| ---------- | ------- | ------------ | -------------------- | ---------------------------------------------- | ------------------ |
| dmd        | debug   | Clang e GCC  | 407 por compilador C | 107 exemplos, com/sem -o: 214 por compilador C | passou             |
| dmd        | release | Clang e GCC  | 407 por compilador C | 107 exemplos, com/sem -o: 214 por compilador C | passou             |
| ldc2       | debug   | Clang e GCC  | 407 por compilador C | 107 exemplos, com/sem -o: 214 por compilador C | passou             |
| ldc2       | release | Clang e GCC  | 407 por compilador C | 107 exemplos, com/sem -o: 214 por compilador C | passou             |

São **4.968 verificações de integração e exemplos** nas oito combinações de
frontend/build/compilador C, além dos testes unitários e das quatro verificações
de instalação. As 22 verificações de driver passaram em cada uma das quatro
combinações de frontend/build, totalizando mais 88 verificações. Nenhum exemplo foi ignorado. Os exemplos de falha têm seus
status/diagnósticos esperados verificados.

Os **55 blocos de testes unitários em D** passaram com DMD e LDC2. Cobrem lexer,
parser, capturas, escopos, aridade, tipos nominais, classes, exceções, compreensão
e ciclos de módulos, além de ponto fixo, preservação de efeitos, CTFE com contratos,
segurança estática, catálogo de diagnósticos e emissão de locais estáticos. O relatório detalhado é gerado em `out/validacao.json`.

```sh
python3 scripts/validar.py
```

## Runtime e sanitizadores

- A API C passou com Clang e GCC, usando as verificações estritas do build.
- ASan e UBSan, com NDEBUG, passaram na API C e nos programas gerados.
- A execução sanitizada validou 407 casos de integração, 342 verificações de bibliotecas e os 107 exemplos nos dois modos.
- O runtime normal foi restaurado após o teste.

```sh
python3 scripts/sanitizadores.py
```

O relatório fica em `out/sanitizadores.json`. As opções de ASan desabilitam a
pilha falsa e o detector de vazamentos para compatibilidade com o GC conservativo;
os demais diagnósticos permanecem ativos.

## Website

A página inicial e a referência de 19 capítulos preservam o hero, as cores, a tipografia, o logo e o terminal existentes.
Foi verificada em Chrome headless em **1440×1000** e **390×844**:

- Assets, IDs e âncoras locais válidos.
- Sem overflow horizontal global nos dois tamanhos.
- Busca de recursos com/sem acentos e estado de busca vazia.
- Seleção de dependências por distribuição e interação de cópia.
- Navegação por âncoras e ausência de exceções JavaScript.
- Busca/filtro de situação, exemplos expansíveis e catálogo gerado de diagnósticos na referência.

```sh
python3 testes/site.py --static-only
python3 testes/site.py
```

Capturas e relatório visual são gerados em `out/site/`; não são arquivos fonte
necessários para o website. O QA de navegador usa Chrome/Chromium e a dependência
opcional de `requirements-site.txt`.

## Reprodutibilidade

O build dos dois compiladores D e a instalação usam o mesmo objeto do runtime.
Os testes de instalação criam prefixos temporários com espaços e executam o
compilador instalado fora do checkout. Não alteram o prefixo real do usuário.

O submódulo do runtime deve ser inicializado no commit registrado pelo CGD.
Mudanças posteriores nos fontes, no runtime ou nas expectativas dos exemplos
exigem nova validação; este registro descreve a execução desta alteração.

## Mudanças verificadas nesta revisão

Os casos de falha conhecida agora verificam a fase de compilação e os códigos
E31xx, em vez de exigir geração de um executável inválido. Falhas dinâmicas e
tratamento deliberado com pegue continuam sendo executados. A localização foi
verificada no C emitido (ausência de delegua_localizar) e no erro real, com arquivo
e linha do operador. A API nativa também cobre o descritor estático e a localização
legada, incluindo o código R0001.

`python3 scripts/formatar.py --check` passou com dfmt, clang-format, Ruff,
Prettier, Taplo e shfmt. `python3 scripts/gerar_referencia.py --check` confirmou
que os exemplos e o catálogo central de mensagens correspondem ao HTML gerado.
Arquivos .delegua e tabelas geradas não foram passados a formatadores de outras
linguagens.

O microbenchmark reproduzível dos codificadores C mediu 362 ms com formatD por
caractere e 51 ms com emissão direta. Essa evidência se limita aos codificadores;
não representa o tempo total de compilação. O gerenciador de otimizações testa
convergência e visita uma árvore já estável uma vez, substituindo as vinte
repetições fixas anteriores.

## Bibliotecas, ferramentas e extensão

A matriz contém 39 etapas. As bibliotecas JSON/rede passaram em 342 verificações
por frontend/build, apenas com HTTP de loopback, além da execução sanitizada.
O formatador passou em 110 arquivos copiados, exigindo idempotência e execução
dos 214 contratos após formatação. O LSP passou por stdio e buffers reais em
memória, UTF-16, cache, namespaces, membros herdados/privados, encadeamento,
assinaturas e formatação. Refinamentos finais restritos ao LSP e à ajuda da CLI
foram verificados em DMD/LDC2 release; o driver ampliado passou em 26 casos.

A extensão 0.2.0 foi instalada e testada no Extension Host do VS Code existente
com perfil temporário. Hover, definição, completion, semantic tokens, rename,
diagnósticos, formatação aplicada, ausência de build por edição e compilação
explícita passaram. Relatórios locais: out/vscode/extensao.json,
out/validacao.json e out/sanitizadores.json. Não há DAP ou suporte Windows validado.
