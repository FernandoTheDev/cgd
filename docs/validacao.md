# Registro de validação

Validação local concluída em **13/11/2026**, em Linux x86_64. Os comandos abaixo
foram executados sobre a árvore de código preparada para a branch `dev`.
Não se trata de uma declaração de suporte a plataformas não testadas.

## Compiladores usados

| Ferramenta | Versão observada |
| --- | --- |
| dmd | DMD64 D Compiler v2.111.0 |
| ldc2 | LDC - the LLVM D compiler (1.42.0): |
| clang | clang version 22.1.8 (Fedora 22.1.8-4.fc44) |
| gcc | gcc (GCC) 16.2.1 20260819 (Red Hat 16.2.1-2) |

## Matriz do frontend e dos programas gerados

| Frontend D | Build | C gerado com | Integração | Catálogo | Instalação isolada |
| --- | --- | --- | --- | --- | --- |
| dmd | debug | Clang e GCC | 331 por compilador C | 87 exemplos, com/sem -o: 174 por compilador C | passou |
| dmd | release | Clang e GCC | 331 por compilador C | 87 exemplos, com/sem -o: 174 por compilador C | passou |
| ldc2 | debug | Clang e GCC | 331 por compilador C | 87 exemplos, com/sem -o: 174 por compilador C | passou |
| ldc2 | release | Clang e GCC | 331 por compilador C | 87 exemplos, com/sem -o: 174 por compilador C | passou |

São **4.040 verificações de integração e exemplos** nas oito combinações de
frontend/build/compilador C, além dos testes unitários e das quatro verificações
de instalação. Nenhum exemplo foi ignorado. Os exemplos de falha têm seus
status/diagnósticos esperados verificados.

Os **10 blocos de testes unitários em D** passaram com DMD e LDC2. Cobrem lexer,
parser, capturas, escopos, aridade, tipos nominais, classes, exceções, compreensão
e ciclos de módulos. O relatório detalhado é gerado em `out/validacao.json`.

```sh
python3 scripts/validar.py
```

## Runtime e sanitizadores

- A API C passou com Clang e GCC, usando as verificações estritas do build.
- ASan e UBSan, com NDEBUG, passaram na API C e nos programas gerados.
- A execução sanitizada validou 331 casos de integração e os 87 exemplos nos dois modos.
- O runtime normal foi restaurado após o teste.

```sh
python3 scripts/sanitizadores.py
```

O relatório fica em `out/sanitizadores.json`. As opções de ASan desabilitam a
pilha falsa e o detector de vazamentos para compatibilidade com o GC conservativo;
os demais diagnósticos permanecem ativos.

## Website

A página preserva o hero, as cores, a tipografia, o logo e o terminal existentes.
Foi verificada em Chrome headless em **1440×1000** e **390×844**:

- Assets, IDs e âncoras locais válidos.
- Sem overflow horizontal global nos dois tamanhos.
- Busca de recursos com/sem acentos e estado de busca vazia.
- Seleção de dependências por distribuição e interação de cópia.
- Navegação por âncoras e ausência de exceções JavaScript.

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
