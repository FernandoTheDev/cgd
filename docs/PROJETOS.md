# Projetos em Delégua (`projeto.json`)

O CGD oferece um sistema completo de projetos multi-arquivo sem quebrar a compilação direta de arquivos isolados (`cgd programa.delegua`).

## Estrutura padrão

```text
meu_projeto/
├── projeto.json
├── fontes/
│   └── principal.delegua
├── testes/
│   └── principal_teste.delegua
└── compilacao/          # gerado automaticamente (ignorado pelo Git)
```

## Manifesto `projeto.json`

```json
{
  "nome": "meu_projeto",
  "versao": "0.1.0",
  "tipo": "aplicacao",
  "entrada": "fontes/principal.delegua",
  "fontes": "fontes",
  "testes": "testes",
  "saida": "compilacao/meu_projeto",
  "otimizar": false,
  "depuracao": false,
  "compiladorC": "auto",
  "paralelismo": "auto",
  "dependencias": {},
  "bibliotecasNativas": []
}
```

### Validações de segurança

- Todos os caminhos (`entrada`, `fontes`, `testes`, `saida`) são validados contra *path traversal* (`..` escapando da raiz do projeto, caminhos absolutos indevidos ou caracteres nulos).
- Campos desconhecidos ou tipos inválidos geram erro explícito antes de invocar o compilador C.

## Comandos da CLI

| Comando | Descrição |
| --- | --- |
| `cgd iniciar <nome>` | Cria um novo projeto com `projeto.json`, `fontes/principal.delegua` e `testes/principal_teste.delegua`. |
| `cgd compilar [--otimizar] [--depuracao] [--forcar]` | Compila o projeto com cache incremental em `compilacao/.cgd-cache`. |
| `cgd rodar [-- args...]` | Compila (reaproveitando o cache quando não houve alterações) e executa o binário, repassando argumentos após `--`. |
| `cgd testar` | Descobre e executa todos os arquivos `*_teste.delegua` em `testes/`. |
| `cgd verificar` | Executa análise sintática, de módulos e semântica sem gerar código C. |
| `cgd formatar [--verificar]` | Formata os arquivos `.delegua` do projeto usando o formatador oficial (4 espaços). |
| `cgd limpar` | Remove artefatos gerados em `compilacao/`. |
| `cgd projeto` | Exibe metadados validados do manifesto `projeto.json` ativo. |
| `cgd depurar [arquivo]` | Compila com informações DWARF (`--depuracao`) e abre sessão interativa de depuração. |
| `cgd dap --stdio` | Inicia o servidor Debug Adapter Protocol (DAP) para integração com editores. |

## Cache incremental

O comando `cgd compilar` calcula o *hash* do manifesto, de todos os módulos importados (incluindo arquivos `.delegua` transitivos) e das flags de compilação. Quando nada mudou e o binário de saída já existe, a recompilação é pulada automaticamente (use `--forcar` para forçar rebuild).
