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

## Segurança estática e localização (solicitação adicional do usuário)

- `frontend/static_safety.d` antecipa falhas provadas mesmo sem otimização;
  preserve ramos descartados e tratamento deliberado com avisos W31xx em pegue.
- Mensagens/códigos/explicações ficam em `diagnostics/catalog.d`, usados também
  por `--explicar` e pela tabela gerada da referência web.
- O C gerado usa descritores estáticos e atribuição de ponteiro em operações
  falíveis. Não reintroduza chamadas a delegua_localizar por nó/linha.
- O runtime mantém compatibilidade da API C anterior. Formate/imprima localização
  apenas no caminho de erro. R0001 ainda é a categoria dinâmica genérica.
- O usuário confirmou o remote FernandoTheDev/delegua-runtime e pediu commits no
  vendor. Use o Git próprio do submódulo, publique-o primeiro e atualize a referência
  no CGD. Não inicialize outro repositório nem converta o vendor em cópia de arquivos.

## Continuidade obrigatória de novas tarefas

Mantenha `docs/CONTINUIDADE.md` atualizado com a solicitação ativa, decisões,
implementação concluída, testes realmente executados, pendências e próximos
comandos. O usuário pediu esse registro também para solicitações futuras, para
poder retomar após expiração do limite. A tarefa atual inclui libcurl por API
controlada, bibliotecas de rede/JSON em Delégua e extensão VS Code com LSP local
persistente e tokens semânticos. O depurador foi adiado; não confundir execução
com depuração. Não compilar/linkar por edição do documento.

## Estilo explícito e ferramentas (nova solicitação)

- Não introduzir `auto` em D; declarar tipos concretos. Bibliotecas Delégua devem
  anotar variáveis, argumentos e retornos, usando `qualquer` quando dinâmico.
- O formatador Delégua próprio está em frontend/formatter.d; quatro espaços são
  contrato. Preservar strings, comentários e contratos dos exemplos. A CLI tem
  --formatar/--verificar-formatacao e o LSP documentFormatting.
- Não oferecer métodos globais como fallback de completion após ponto. Módulos
  importados são namespaces; respeitar escopo, receptor, herança e visibilidade.
- Métodos estáticos possuem isStatic; não recebem isto. Campos estáticos continuam
  sem suporte. Bibliotecas JSON/rede/coleções e extensão estão em evolução; ler
  docs/CONTINUIDADE.md antes de retomar e registrar testes efetivamente executados.

## Evolução autorizada em 16/11/2026

- O usuário pediu FFI da wiki, revogando a exclusão anterior para assinaturas
  estrangeiras explícitas. Classes @definicao usam ABI C escalar ou ABI gerenciada
  delegua; não expor ponteiros/structs/callbacks por conversões presumidas.
- JSON/rede/arquivos usam cgd:nativo.Primitivas; entradas cgd\* antigas continuam
  por compatibilidade. Não remover antes de validar migração e API C anterior.
- Classes abstratas/interfaces, enums numéricos e arrows foram acrescentados.
  Leia docs/evolucao-linguagem.md para diferenças e pendências reais da wiki.
- **Não executar testes até ordem explícita do usuário.** Builds/formatação e
  instalação do LSP foram autorizados, mas não substituem validação funcional.

## Solicitação de 17/11/2026

- O usuário autorizou executar todos os testes necessários; a suspensão anterior
  foi revogada. Documentar testes e resultados reais em CONTINUIDADE.md.
- Compatibilidade JS, integração com classes de host JavaScript, herança de
  interfaces e múltiplos dialetos são exclusões definitivas, não pendências.
- Defaults tipados e inicializadores de atributos devem criar coleções por
  instância, respeitar herança, ordem, contratos e efeitos. Não construir classes
  implicitamente. Tipos inferidos aparecem como dicas virtuais, sem editar fontes.
