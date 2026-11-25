# Depuração Nativa, Protocolo DAP e Integração com Editores

Programas compilados pelo CGD podem ser depurados nativamente no nível do código-fonte Delégua (`.delegua`), tanto pela CLI quanto por editores compatíveis com o **Debug Adapter Protocol (DAP)**, como o VS Code.

## Como funciona por baixo dos panos

1. **Mapeamento de origem (`--depuracao`)**:
   - Quando `--depuracao` (`-g` / `-O0`) está ativo, `src/backend/c/codegen.d` emite diretivas `#line <linha> "<caminho_absoluto.delegua>"` em cada linha física dos statements gerados, fazendo o compilador C (Clang/GCC) produzir tabelas DWARF reais apontando para os arquivos `.delegua` originais.
   - Em `ReturnStmt`, o backend materializa o valor retornado para evitar que NRVO em `-O0` oculte variáveis locais do DWARF.
   - Um mapa auxiliar `<binario>.cgd.dbg.json` registra a correspondência `cName -> nomeDelégua` para variáveis, parâmetros e funções.
2. **Servidor DAP nativo (`src/dap/server.d`)**:
   - Invocado por `cgd dap --stdio`.
   - Orquestra o `gdb --interpreter=mi2` com thread leitora dedicada (sem *deadlock* de pipes), traduzindo comandos DAP (`launch`, `setBreakpoints`, `setFunctionBreakpoints`, `setExceptionBreakpoints`, `threads`, `stackTrace`, `scopes`, `variables`, `evaluate`, `continue`, `next`, `stepIn`, `stepOut`, `pause`, `disconnect`, `terminate`).
   - Decodifica nomes mangled (`cgd_user_*`) de volta para nomes Delégua originais e formata valores `delegua_value` (`inteiro`, `real`, `texto`, `logico`, `nulo`, vetores e tuplas expansíveis no painel de variáveis!).

## Uso pela CLI

```sh
# Depurar um projeto com projeto.json ou um arquivo isolado
cgd depurar
cgd depurar programa.delegua
```

## Uso no VS Code (F5)

A extensão oficial em `extensao-vscode/` registra automaticamente um `DebugAdapterDescriptorFactory` do tipo `"cgd"` que inicia `cgd dap --stdio`.

Exemplo de `.vscode/launch.json` (também disponível automaticamente sem arquivo de configuração ao pressionar F5 em um `.delegua` ou projeto `projeto.json`):

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "type": "cgd",
      "request": "launch",
      "name": "Depurar Delégua (CGD)",
      "program": "${file}",
      "stopOnEntry": false
    }
  ]
}
```

## Requisitos e limites

- Requer `gdb` instalado no ambiente Linux x86_64 (validado com GDB 17.2 + Clang/GCC `-g -O0`).
- Coberto ponta a ponta por `testes/dap.py` (arquivo simples com breakpoint/variáveis/vetor expansível/`evaluate`/`next`; projeto multi-módulo com `projeto.json`/recursão de 4 frames/`stepOut`; breakpoint em exceção `setExceptionBreakpoints`).
