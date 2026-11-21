<p align="center"><img src="docs/assets/logo.png" width="120" alt="CGD"></p>

# CGD — Compilador Geral Delégua

Escreva em Delégua e gere um programa nativo. O CGD analisa o seu código,
traduz para C99 e deixa a compilação final com Clang ou GCC. O runtime cuida da
memória, das coleções e das operações da biblioteca padrão.

A linguagem vem de [Delégua, da Design Líquido](https://github.com/DesignLiquido/delegua).
Este compilador segue um recorte próprio, descrito no livro: você encontra ali o
que funciona, exemplos para experimentar e os limites que precisa conhecer.

**[Website](https://fernandothedev.github.io/cgd/)** ·
**[Guia da linguagem e compatibilidade](https://fernandothedev.github.io/cgd/livro/)** ·
**[DCC (compilador C em Delégua)](https://github.com/FernandoTheDev/dcc)** ·
[Exemplos executáveis](exemplos/README.md) ·
[Desenvolvimento e passes](docs/desenvolvimento.md) ·
[Contexto para agentes](AGENTS.md)

## Prova de uso real — DCC (Delégua C Compiler)

O maior projeto construído sobre o CGD é o **[DCC — Delégua C Compiler](https://github.com/FernandoTheDev/dcc)** (`FernandoTheDev/dcc`), um compilador **ISO C99 / GNU99** nativo para Linux x86-64 escrito em Delégua e compilado pelo CGD.

- **Pipeline completo em Delégua**: pré-processador compatível com cabeçalhos reais da glibc (`/usr/include`), lexer, parser, análise semântica LP64, IR SSA com otimizador e verificador, backend x86-64 (System V AMD64 ABI), emissor ELF64 (`.o`) e **linker nativo próprio** (interoperável nos dois sentidos com GCC e Clang).
- **Bootstrap indireto comprovado**: o DCC compila o próprio código C99 gerado pelo CGD (~71 mil linhas, >1,3 milhão de tokens, 1.048 funções) em objeto ELF64 nativo (`dcc-self.o`), gerando um binário auto-compilado funcional capaz de compilar programas C reais.
- **Estresse real da biblioteca padrão e do runtime**: usa em produção `cgd:memoria` (`Arena`, `FatiaBytes`, `FatiaInt64`, controle fino de Boehm GC), `cgd:bytes` (incluindo buffers congelados *zero-copy*), `cgd:assincrono` (`rotina`/`Rotinas`), `cgd:processo` (`Processo.executarLote` para paralelismo multi-TU), `cgd:arquivos`, `cgd:json`, `cgd:tempo` e FFI POSIX direta, com determinismo bit a bit entre GCC, Clang e TinyCC.

## Instalar as dependências

Ambiente validado: **Linux x86_64**. São necessários DMD ou LDC2, DUB, Clang ou
GCC, pkg-config, Boehm GC e libcurl >= 7.86 com headers. Python 3 é usado no build
do runtime, nos testes e ferramentas; não é necessário para executar o programa gerado.

```sh
# Debian / Ubuntu
sudo apt-get update
sudo apt-get install git build-essential clang pkg-config libgc-dev libcurl4-openssl-dev ldc dub python3

# Fedora
sudo dnf install git gcc clang pkgconf-pkg-config gc-devel libcurl-devel ldc dub python3

# Arch Linux
sudo pacman -S --needed git gcc clang pkgconf gc curl ldc dub python
```

Alternativas: [DMD](https://dlang.org/download.html),
[LDC](https://github.com/ldc-developers/ldc),
[Boehm GC](https://github.com/bdwgc/bdwgc). Os nomes dos pacotes podem variar.
Os binários gerados dependem das bibliotecas nativas vinculadas; não são binários
estáticos automaticamente portáveis entre sistemas.

## Build do zero

```sh
git clone --branch dev --recurse-submodules https://github.com/FernandoTheDev/cgd.git
cd cgd

# Em checkouts existentes:
git submodule update --init --recursive

./build-runtime
dub build --compiler=ldc2 --build=release
# Alternativa: dub build --compiler=dmd --build=release
```

`CC=gcc ./build-runtime` seleciona GCC para o runtime. O script usa o commit local
do vendor e não faz pull automaticamente. O vendor já possui Git próprio como submódulo; pode ser editado e commitado
daqui com `git -C vendor/delegua-runtime`. Veja o [fluxo de trabalho](docs/desenvolvimento.md#editar-o-runtime-a-partir-deste-checkout).
O runtime é desenvolvido em
[FernandoTheDev/delegua-runtime](https://github.com/FernandoTheDev/delegua-runtime).

## Instalar no usuário

```sh
./instalar --compiler ldc2 --release
export PATH="$HOME/.local/bin:$PATH"
cgd --versao
```

A instalação copia executável, headers e runtime para `~/.local/share/cgd` e cria
um link em `~/.local/bin/cgd`, sem sudo. Use `--prefix DIRETORIO` e
`--bin-dir DIRETORIO` para outros destinos; `--no-build` reutiliza um build existente.
Para remover a instalação padrão: apague o link `~/.local/bin/cgd` e o diretório
`~/.local/share/cgd`. Não há instalação automática de pacotes do sistema.

## Primeiro programa

```sh
mkdir -p out
./cgd exemplos/linguagem/14_classes.delegua -o -s out/classes
./out/classes

# Análise sem toolchain C e diagnósticos consumíveis por ferramentas:
./cgd exemplos/linguagem/14_classes.delegua --verificar --diagnosticos=json

# C intermediário, sem link:
./cgd exemplos/linguagem/14_classes.delegua --emitir-c -o -s out/classes
./cgd --explicar E3101
./cgd --ajuda
```

**`-o` ativa otimizações; `-s` define o destino.** Crie o diretório de saída antes.
O `.c` fica ao lado do executável. `CC=gcc` ou `--cc gcc` seleciona o backend C.
Opções de alvo, sysroot e runtime estão no [guia de desenvolvimento](docs/desenvolvimento.md).
A configuração de cross compilation está separada do hospedeiro; Windows e
executáveis cruzados ainda não foram validados.

## Trabalhar no projeto

```sh
dub test --compiler=dmd --config=unittest
dub test --compiler=ldc2 --config=unittest
python3 testes/driver.py
python3 testes/integracao.py
python3 testes/exemplos.py
python3 testes/lsp.py
python3 testes/bibliotecas.py
python3 testes/formatador.py
python3 scripts/verificar_tipos.py
python3 scripts/validar.py         # matriz DMD/LDC2 × debug/release × Clang/GCC
python3 scripts/sanitizadores.py   # ASan/UBSan; restaura o runtime normal
python3 scripts/formatar.py --check
python3 scripts/gerar_referencia.py --check
python3 testes/site.py --static-only
```

Detalhes de formatadores, contratos de otimização, diagnósticos e novos passes:
[Desenvolvimento](docs/desenvolvimento.md). O mapa do código e a ABI estão em
[Arquitetura](docs/arquitetura.md); evidências e limitações dos testes estão em
[Validação](docs/validacao.md). Relatórios e artefatos são gravados em `out/`.
O QA de navegador usa Chrome/Chromium e `requirements-site.txt`.

A branch de integração é `dev`. Atualize o runtime explicitamente, preservando
alterações locais. Quando houver mudanças no submódulo, publique seu commit
antes de atualizar a referência no CGD. Evite versionar executáveis e C gerado.
Mantenha testes com e sem otimização e acrescente regressões para cada mudança
observável. Rode `git diff --check` nos dois repositórios.

Capturas/upvalues e carregamento dinâmico continuam excluídos. A FFI C por classes
estrangeiras foi introduzida por solicitação explícita; seus contratos e limites
estão em [Evolução da linguagem](docs/evolucao-linguagem.md).
Outros limites de implementação são descritos separadamente em
[Compatibilidade](docs/compatibilidade.md) e [Segurança](docs/seguranca.md).

Licença [Apache-2.0](LICENSE). Autoria e referências ao projeto Delégua devem ser
preservadas. [Apoie o desenvolvimento](https://www.patreon.com/fernandothedev).

## Editor e bibliotecas

A [extensão VS Code própria](extensao-vscode/README.md) usa o LSP local do CGD,
com tokens semânticos, navegação, completion contextual e formatação com quatro
espaços (Ctrl+Shift+I). Compile o CGD uma vez e instale com
`python3 scripts/instalar_extensao.py --associate`. Não há compilação por edição.

Consulte [bibliotecas e ferramentas](docs/ferramentas.md) para JSON em Delégua puro,
rede com libcurl gerenciada, coleções, instalação da extensão e limites reais.
O [registro de continuidade](docs/CONTINUIDADE.md) distingue entregas e pendências.

A [referência web própria](docs/linguagem.html) cobre instalação, linguagem, editor,
runtime e biblioteca padrão. [Bibliotecas e ferramentas](docs/ferramentas.md)
detalha APIs e limites. Compatibilidade JS, herança de interfaces e múltiplos
dialetos são exclusões definitivas do projeto.

## Cuidar da documentação

O [livro](https://fernandothedev.github.io/cgd/livro/) usa mdBook, como os livros
do Rust, com um tema verde/escuro e destaque próprio para Delégua.

```sh
cargo install mdbook --version 0.4.52 --locked
python3 scripts/gerar_referencia.py
python3 scripts/gerar_livro.py
```

O conteúdo vem de `docs/linguagem.json`, dos guias Markdown e dos exemplos reais.
Edite essas fontes; o comando gera `docs/livro` para o GitHub Pages de `dev/docs`.
A página `linguagem.html` continua disponível para links antigos.

## Argumentos, processos e ferramentas de terminal

`cgd:processo` lê argc/argv reais e executa programas com argumentos separados,
stdin, stdout/stderr, timeout e limites. `cgd:ambiente`, `cgd:sistema`, `cgd:tempo`
e `cgd:io` completam a base de sistema. CLI, Logger e Algoritmos ajudam a montar
aplicações por cima dela. Veja [APIs e exemplos](docs/stdlib-sistema.md), incluindo
a diferença entre execução direta e shell e os limites Linux/glibc desta etapa.

O CGD também pode receber HTTP diretamente no executável com `cgd:servidor` e
abrir conexões TCP com `cgd:sockets`. Veja o [guia do servidor](docs/servidor-http.md)
para rotas, middleware, limites e encerramento. Esta versão atende um cliente por
vez, usa HTTP/1.1 com fechamento por requisição e não oferece TLS ou HTTP/2.

O [assincronismo experimental](docs/assincronismo.md) já possui assincrona/aguardar,
Promessa<T>, microtasks, cancelamento e tratamento de suspensão na mesma thread.
`cgd:assincrono` acrescenta timers, HTTP e TCP por reactor Linux. As mudanças
mais recentes aguardam testes; [rotinas paralelas](docs/rotinas.md) estão na fase
de contrato e transferência interna de valores.
