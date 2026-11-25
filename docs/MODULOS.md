# Módulos, Importações e Tipos Qualificados

O CGD suporta organização modular inspirada na ergonomia de módulos de D, preservando 100% de compatibilidade com `const Mod = importar("...")`.

## Declaração de módulo

No topo de um arquivo `.delegua`, declare opcionalmente o nome lógico do módulo:

```delegua
modulo aplicativo.modelos.usuario
```

`modulo` (ou `módulo`) é uma palavra-chave contextual: só atua como declaração de módulo no topo do arquivo, mantendo variáveis existentes chamadas `modulo` totalmente válidas.

O compilador valida a coerência entre o nome declarado (`aplicativo.modelos.usuario`) e o caminho físico relativo às raízes de módulo (`fontes/aplicativo/modelos/usuario.delegua` ou `fontes/aplicativo/modelos/usuario/mod.delegua`).

## Formas de importação

```delegua
// 1. Importação qualificada (estilo D)
importar aplicativo.modelos.usuario

// 2. Importação qualificada com alias contextual
importar aplicativo.servicos.auth como Auth

// 3. Importação da biblioteca padrão com pontos ou com cgd:
importar cgd.interface.tui como TUI
const Arquivos = importar("cgd:sistema/arquivos")

// 4. Importação relativa clássica
const Util = importar("./util.delegua")
```

### Resolução de módulos

1. **Bibliotecas padrão (`cgd:...` e `cgd.*`)**: resolvidas em `CGD_LIBS_DIR`, `~/.delegua/cgd` e `bibliotecas/` ao lado do executável, aceitando `<nome>.delegua`, `<nome>/mod.delegua`, `<nome>/indice.delegua` e aliases hierárquicos sem duplicação de identidade.
2. **Módulos de projeto**: descobertos a partir de `fontes/`, `src/`, `pacotes/` e da raiz do `projeto.json` ancestral mais próximo.
3. **Proteções**: ciclos de importação, caminhos inexistentes e tentativas de travessia de diretório (`..` fora da raiz) são detectados estaticamente com diagnósticos claros.

## Tipos qualificados e herança entre módulos

Classes e enums definidos em módulos importados podem ser usados diretamente em anotações de variáveis, parâmetros, retornos e herança:

```delegua
modulo aplicativo.servicos.auth
importar aplicativo.modelos.usuario
importar aplicativo.modelos.base como Base

classe Admin herda Base.Entidade {
    titular: aplicativo.modelos.usuario.Usuario

    construtor(titular: aplicativo.modelos.usuario.Usuario) {
        super()
        isto.titular = titular
    }
}

funcao saudar(u: aplicativo.modelos.usuario.Usuario): texto {
    retorna u.saudacao()
}
```

## Segurança preservada

- Nomes de módulos importados (`SymbolModule`) são namespaces estáticos: podem ser acessados dentro de funções sem disparar captura/upvalue (`W4001`/`E4001`), enquanto a captura de variáveis locais continua proibida.
- Dentro de `rotina`, o acesso a módulos continua validado pelas regras de isolamento e pureza (`E3402`/`E3403`).
- Dobramento constante de `enum` só ocorre em receptores estáticos sem efeitos colaterais, preservando a ordem de avaliação em expressões como `criar(efeitos).Estado.Fim`.
