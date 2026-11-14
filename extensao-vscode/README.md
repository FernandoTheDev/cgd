# CGD para VS Code

Extensão própria para o perfil compilado de Delégua. Usa `cgd --lsp`, um processo
local persistente com LSP por stdin/stdout. Não abre portas, não usa serviço de
IA, não envia o código para servidores e não compila programas enquanto você digita.

## Uso

Abra um `.delegua` com o modo **CGD / Delégua**. A coloração vem dos tokens
semânticos produzidos pelo lexer e pelo índice do compilador, sem gramática
TextMate/regex. Hover, definição, referências, rename, símbolos, completion,
assinaturas, folding, seleção, dicas de tipos e diagnósticos são locais.

- Botão ▶ ou **CGD: Compilar e executar arquivo**: compila o arquivo salvo e executa
  em uma tarefa com terminal, stdin e stdout normais.
- **CGD: Compilar arquivo** / Ctrl+Shift+B: compila sem executar.
- F5 com a configuração **CGD: compilar e executar (sem depuração)** executa o
  programa. Isso não é DAP: breakpoints e stepping foram adiados pelo usuário.
- **CGD: Reiniciar servidor de linguagem** reinicia apenas o processo LSP.

`cgd.executable` seleciona um binário já compilado. Em workspaces confiáveis,
`./cgd` é preferido; fora deles é usado o binário incluído no VSIX. A extensão
nunca executa DUB nem baixa compiladores ao iniciar. Build e execução exigem
confiança no workspace. O terminal só é criado mediante comando explícito.

## Desenvolvimento e instalação

No repositório do CGD, com compilador e runtime já preparados:

```sh
npm ci --prefix extensao-vscode --ignore-scripts
python3 scripts/instalar_extensao.py --associate
```

O instalador não recompila o CGD. Ele copia o binário existente e seus recursos,
empacota `out/cgd-0.2.0.vsix`, instala pelo CLI do VS Code e confirma a versão.
`--associate` altera apenas a associação de `*.delegua`, preservando o restante
do settings.json com JSONC. A extensão oficial de Delégua não é removida.

Para gerar sem instalar: `python3 scripts/instalar_extensao.py --package-only`.
O uso da extensão instalada é offline; npm só é necessário para preparar o pacote.

## Limites desta versão

Não há depurador/DAP ou indexação irrestrita de todo o disco.
Ctrl+Shift+I e Format Document usam o formatador nativo com quatro espaços.
A análise considera documentos abertos e seus módulos estáticos. Recursos fora
desse conjunto têm navegação limitada. Análise não executa CTFE nem código do
programa. Alguns diagnósticos de módulos podem ser menos precisos durante erros
sintáticos. Linux x86_64 é a plataforma validada do binário incluído.

Delégua original: https://github.com/DesignLiquido/delegua.
CGD: https://github.com/FernandoTheDev/cgd. Licença Apache-2.0.
