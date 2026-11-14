# Contexto do CGD

O CGD (Compilador Geral Delégua) é escrito em D e traduz o perfil seguro de
Delégua para C99. O runtime gerenciado em C está no submódulo
`vendor/delegua-runtime` (repositório FernandoTheDev/delegua-runtime, branch dev).
A linguagem de referência é https://github.com/DesignLiquido/delegua e sua wiki.
Preserve autoria, licença Apache-2.0 e referências ao projeto original.

## Direção e contratos

- A branch de integração é `dev`. Preserve alterações preexistentes. Faça commits
  coerentes e publique em `dev` quando a tarefa autorizar publicação.
- Segurança é um contrato: capturas/upvalues, FFI arbitrária, eval, importação
  dinâmica/NPM e ponteiros crus não são expostos. Detecte capturas com aviso e erro.
- Classes, herança, exceções, callbacks sem captura, módulos estáticos, coleções,
  Unicode e biblioteca nativa já existem. Consulte `docs/compatibilidade.md` para
  limites reais. Ausência de implementação não implica insegurança.
- Preserve ordem de avaliação, efeitos observáveis, exceções, contratos de tipos,
  aliasing e escopos em qualquer otimização. Nunca descarte inicializadores ou
  escritas apenas porque seu resultado não é usado.
- A plataforma validada é Linux x86_64. Prepare a arquitetura para outros alvos,
  mas não declare suporte a Windows/cross sem toolchain e runtime validados.
- Não invoque compiladores com shell: passe argumentos separados. Credenciais
  permanecem no helper do Git e na memória; não grave nem exiba tokens.
- Não delegue a subagentes sem solicitação explícita do usuário.

## Mapa do código

`src/frontend/lexer` e `parser`: tokens e AST; `semantic`: resolução e tipos;
`src/frontend/modules.d`: carregamento estático; `src/opt`: otimizações;
`src/ctfe`: execução limitada em compilação; `src/middle`: lowering;
`src/backend/c`: geração C; `src/driver`: pipeline/toolchain; `src/errors.d`:
diagnósticos. `testes/unit`: testes em D. As suítes Python e os contratos nos
exemplos verificam execução com e sem otimização.

## Build e validação

```sh
git submodule update --init --recursive
./build-runtime
dub build --compiler=ldc2 --build=release
dub test --compiler=dmd --config=unittest
dub test --compiler=ldc2 --config=unittest
python3 testes/integracao.py
python3 testes/exemplos.py
python3 scripts/validar.py
python3 scripts/sanitizadores.py
python3 testes/site.py
```

Dependências: DMD ou LDC2, DUB, Clang/GCC, pkg-config, headers/lib Boehm GC e
Python 3. Testes web usam Chrome e a dependência opcional `requirements-site.txt`.
A matriz cobre DMD/LDC2 × debug/release × Clang/GCC, instalações isoladas e todos
os exemplos. Relatórios/artefatos ficam em `out/`, ignorado pelo Git.
Adicione regressões que distingam o comportamento correto para cada novo passe,
otimização, diagnóstico e recurso. Não repita a matriz sem alterações relevantes.

## Documentação e apresentação

A comunicação e a documentação são em português. README é a porta de entrada do
repositório: instalação, build, contribuição e links. A documentação web é a
referência de uso da linguagem: sintaxe, exemplos, recursos e limites. Preserve o
layout verde/escuro existente. O website usa GitHub Pages a partir de `dev/docs`;
não migre de hospedagem. `scripts/github_pages.py --publish` publica a revisão
já enviada. Não afirme equivalência completa com o interpretador oficial.

## Formatação

Use formatadores próprios: dfmt para D, clang-format para C/headers, Ruff para
Python, Prettier para HTML/CSS/JS/JSON/Markdown, shfmt para shell e Taplo para TOML. Não aplique
formatadores de JavaScript a `.delegua`: interpolação, sintaxe e comentários de
contratos têm significado. Não altere arquivos gerados, binários, fontes externas
ou stashes do vendor. Versione configurações e ofereça um comando de verificação.

## Atualização de arquitetura (14/11/2026)

- `frontend/validation.d` valida limites da AST antes dos passes recursivos.
- `frontend/flow.d` analisa caudas inalcançáveis e retornos implícitos.
- `middle/rewrite.d` centraliza a travessia de slots da AST com cache por execução.
- `opt/pass_manager.d` mede mudanças e busca ponto fixo; não restaure 20 passes fixos.
- `driver/toolchain.d` separa descoberta, flags, alvo e vínculo do pipeline.
- `--verificar`, `--emitir-c` e `--diagnosticos=json` servem integração com ferramentas.
- `docs/linguagem.json` e os exemplos alimentam `scripts/gerar_referencia.py`;
  regenere `docs/linguagem.html` em vez de editar o HTML gerado manualmente.
- Leia `docs/desenvolvimento.md` para códigos de diagnóstico, limites e contratos.
