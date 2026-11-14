<p align="center"><img src="docs/assets/logo.png" width="120" alt="CGD"></p>

# CGD — Compilador Geral Delégua

O CGD compila programas Delégua para C99 e, em seguida, gera executáveis nativos
com Clang, GCC ou TCC. O frontend é escrito em D. O runtime em C fornece valores
gerenciados, coleções, classes, chamadas de função e exceções.

A branch `dev` contém o perfil compilado em desenvolvimento. Capturas de ambientes
por upvalues, FFI e carregamento dinâmico de código não fazem parte desse perfil.
As diferenças e limitações estão na [matriz de compatibilidade](docs/compatibilidade.md).

[Website](https://fernandothedev.github.io/cgd/) ·
[Exemplos](exemplos/README.md) ·
[Arquitetura](docs/arquitetura.md) ·
[Segurança](docs/seguranca.md) ·
[Referência oficial de Delégua](https://github.com/DesignLiquido/delegua/wiki)

## Começar do zero

O ambiente validado é **Linux x86_64**. Para compilar o CGD, instale:

| Dependência | Uso |
| --- | --- |
| Git | Checkout do compilador e do submódulo do runtime |
| DMD **ou** LDC2 | Compilação do frontend em D |
| DUB | Build e testes unitários em D |
| Clang ou GCC | Build do runtime C99 e dos programas Delégua |
| `pkg-config` e Boehm GC com headers (`bdw-gc`) | Descoberta e vínculo do coletor de lixo |
| Python 3 | Suítes de integração, exemplos e matriz de validação |

TCC também pode gerar programas, mas o build do runtime usa Clang por padrão.
`CC=gcc ./build-runtime` seleciona GCC. Python não é necessário para executar
os binários gerados. Eles continuam dependendo das bibliotecas nativas vinculadas,
incluindo Boehm GC; não são binários estáticos portáveis entre sistemas.

Exemplos de dependências de desenvolvimento por distribuição:

```sh
# Debian / Ubuntu — LDC2 e DUB pelo gerenciador de pacotes
sudo apt-get update
sudo apt-get install git build-essential clang pkg-config libgc-dev ldc dub python3

# Fedora
sudo dnf install git gcc clang pkgconf-pkg-config gc-devel ldc dub python3

# Arch Linux
sudo pacman -S --needed git gcc clang pkgconf gc ldc dub python
```

Para DMD, consulte os [downloads oficiais de D](https://dlang.org/download.html).
LDC também disponibiliza instruções e binários em seu
[repositório oficial](https://github.com/ldc-developers/ldc).
O coletor usado é o [Boehm-Demers-Weiser GC](https://github.com/bdwgc/bdwgc).
Os nomes dos pacotes podem variar por distribuição.

```sh
git clone --branch dev --recurse-submodules https://github.com/FernandoTheDev/cgd.git
cd cgd

# Se o checkout já existia e ainda não tem o vendor:
git submodule update --init --recursive

./build-runtime
dub build --compiler=ldc2 --build=release

# Alternativa com DMD:
dub build --compiler=dmd --build=release
```

`build-runtime` compila o estado local do vendor e copia o objeto para `lib/`.
Ele não faz pulls silenciosos. Para atualizar o vendor explicitamente, preserve
suas alterações locais e execute `git -C vendor/delegua-runtime pull --ff-only origin dev`.

## Compilar um programa

Crie `ola.delegua`:

```js
classe Pessoa {
    nome: texto
    construtor(nome) { isto.nome = nome }
    apresentar() { retorna "Olá, ${isto.nome}!" }
}
escreva(Pessoa("Delégua").apresentar())
```

```sh
./cgd ola.delegua
./ola
# Olá, Delégua!

# Ativar as otimizações do CGD e escolher o destino:
mkdir -p out
./cgd ola.delegua -o -s out/ola
./out/ola
```

Crie o diretório de saída antes de usar `-s`. O compilador grava também o C
intermediário ao lado do executável, por exemplo `out/ola.c`.
A extensão de entrada deve ser `.delegua`.

| Opção | Efeito |
| --- | --- |
| `-a`, `--ajuda` | Exibe a ajuda |
| `-v`, `--versao` | Exibe a versão |
| `-s CAMINHO`, `--saida CAMINHO` | Define o executável de saída |
| `-o`, `--otimizar` | Ativa otimizações e usa `-O2` no compilador C |
| `-d`, `--depurar` | Mostra a AST, o C gerado e o comando de compilação |
| `-t`, `--tempo` | Mostra os tempos dos passes |

`-o` é uma opção booleana de otimização; o nome do executável é definido com
`-s`. Para selecionar o compilador C: `CC=gcc ./cgd ola.delegua`.
`CC` deve conter o caminho/nome de um executável, sem opções concatenadas.

## Instalar no usuário

```sh
./instalar --compiler ldc2 --release
# Ou: ./instalar --compiler dmd --release

export PATH="$HOME/.local/bin:$PATH"
cgd ola.delegua -s ola
```

O instalador não instala pacotes do sistema. Ele mantém uma cópia autocontida
do compilador, headers e objeto do runtime em `~/.local/share/cgd` e cria um
link em `~/.local/bin/cgd`. O layout corresponde aos caminhos procurados pelo
compilador, inclusive quando ele é chamado fora do checkout.

```sh
# Prefixos alternativos; útil para testes e ambientes isolados:
./instalar --prefix /caminho/cgd --bin-dir /caminho/bin --compiler dmd

# Reutilizar os artefatos já compilados e testados:
./instalar --no-build --prefix /caminho/cgd --bin-dir /caminho/bin
```

Variáveis equivalentes: `CGD_PREFIX`, `CGD_BIN_DIR` e `DC`. O instalador também
aceita `--debug`, `--release` e `--help`. Não exige `sudo` para o prefixo padrão.

## Recursos e exemplos

O catálogo em [exemplos/README.md](exemplos/README.md) cobre tipos, operadores,
atribuições múltiplas, escopos, condicionais, laços, compreensão de listas,
funções como valores, parâmetros variáveis, coleções, Unicode, classes,
herança, privacidade, acessores, exceções, módulos, decoradores e asserções.
Há também exemplos de padrões rejeitados e de erros verificados em execução.

```sh
./cgd exemplos/linguagem/08_funcoes_valores.delegua -s out/funcoes
./out/funcoes

./cgd exemplos/modulos/01_importacao.delegua -s out/modulos
./out/modulos
```

Importações de fontes usam caminhos literais relativos ao arquivo que importa:
`const calculos = importar("lib/calculos.delegua")`. Módulos são compilados no
mesmo executável, inicializados uma vez e expõem seus nomes públicos.

## Como o compilador funciona

```text
Fonte .delegua → tokens → AST → resolução de módulos e análise semântica
             → CTFE/otimizações opcionais → lowering → C99
             → compilador C + runtime + Boehm GC → executável nativo
```

A VM de CTFE funciona durante a compilação de funções marcadas `//>puro`.
Ela não é um interpretador embutido no programa final. O backend atual gera C;
o CGD não possui, nesta versão, um backend próprio de LLVM/assembly.
Veja os detalhes e o mapa dos diretórios em [Arquitetura](docs/arquitetura.md).

## Testar

```sh
# Testes unitários nativos de D:
dub test --compiler=dmd
dub test --compiler=ldc2

# Integração, incluindo execução com e sem otimização:
python3 testes/integracao.py

# Todos os arquivos de exemplos, incluindo entrada e erros esperados:
python3 testes/exemplos.py

# Runner histórico em D, também com suporte aos exemplos de entrada:
rdmd testes/unitario.d

# Website: validação estática, sem instalar dependências de navegador:
python3 testes/site.py --static-only
# QA visual opcional: Chrome/Chromium e websocket-client (requirements-site.txt).
python3 testes/site.py

# Runtime C:
(cd vendor/delegua-runtime && ./tests/run.sh)

# Instalação em diretórios temporários, sem alterar seu prefixo:
python3 scripts/validar_instalacao.py

# Runtime e todos os programas com ASan/UBSan (restaura o runtime normal):
python3 scripts/sanitizadores.py

# Matriz completa DMD/LDC2 × debug/release × Clang/GCC:
python3 scripts/validar.py
```

A matriz exige os dois compiladores D e os dois compiladores C. O relatório é
gravado em `out/validacao.json`; dependências ausentes são falhas explícitas.
Para um subconjunto: `python3 scripts/validar.py --compilers dmd --builds debug --c-compilers clang`.
Os contratos de cada exemplo estão nos comentários `//!`, `//#` e `//?`.

## Segurança e diferenças de linguagem

Funções sem captura e métodos com receptor explícito são suportados. Ao detectar
uma referência externa que exigiria upvalues, o compilador emite aviso e bloqueia
a compilação. Passe os valores necessários por parâmetros.

O runtime valida aridade, tipos, identidade nominal das classes, privacidade,
índices, imutabilidade das tuplas, contratos de vetores por aliases e overflow
inteiro. Erros de execução incluem localização e podem ser tratados com
`tente ... pegue`. Esses mecanismos não equivalem a uma prova formal de
segurança de toda a implementação.

FFI, ponteiros arbitrários, NPM, importação dinâmica e código avaliado em tempo
de execução não são expostos pela linguagem compilada. Limites numéricos,
restrições da CTFE e diferenças restantes estão em
[Compatibilidade](docs/compatibilidade.md) e [Segurança](docs/seguranca.md).

## Contribuir

Mudanças do compilador e do runtime devem ser testadas juntas. O runtime é um
submódulo: publique primeiro seu commit no repositório `delegua-runtime`, depois
atualize a referência no CGD. Evite registrar executáveis, objetos e arquivos
C gerados. Antes de enviar: rode a matriz e `git diff --check` nos dois repositórios.

O projeto usa a licença [Apache-2.0](LICENSE).
Se quiser apoiar o desenvolvimento, visite o [Patreon de Fernando](https://www.patreon.com/fernandothedev).
