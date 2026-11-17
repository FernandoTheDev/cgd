# Perfil de segurança

O perfil compilado mantém os valores em memória gerenciada e verifica operações
que dependem de tipos conhecidos apenas em execução. Ele não oferece uma prova
formal de segurança nem isolamento de processos.

## Sem captura de ambientes

```js
funcao criar(valor) {
    retorna funcao() { retorna valor } // Aviso sobre upvalues e erro.
}
```

Passe o estado por parâmetro ou mantenha-o em uma instância explícita:

```js
funcao somar(valor, incremento) { retorna valor + incremento }
var operacao = somar
escreva(operacao(10, 2))
```

Funções nomeadas sem captura, funções anônimas sem captura, callbacks e métodos
ligados a instâncias são permitidos. Capturas de variáveis locais, parâmetros,
variáveis globais e de `isto` por funções internas são bloqueadas. Isso também
vale para variáveis que contêm referências a outras funções.

## Capacidades ausentes por decisão de segurança

- Ponteiros crus, structs e callbacks arbitrários na ABI C ainda não têm representação na linguagem.
- Importação de `.so`, `.dll`, pacotes NPM e caminhos calculados em execução.
- Ponteiros arbitrários, acesso à representação interna dos valores e avaliação dinâmica de código.
- Ambientes capturados implicitamente por closures/upvalues.

A revisão 0.4.0 autoriza classes estrangeiras C por pedido explícito do usuário.
A FFI exige assinatura correta e código nativo confiável; não é sandbox. Veja
[evolução e ABIs](evolucao-linguagem.md). O contrato anterior de exclusão de FFI
foi substituído. O vendor também conserva a API C de FFI para consumidores nativos. Essa
API não é exposta aos programas Delégua compilados pelo CGD.

## Verificações

Aridade e contratos de parâmetros/retornos são verificados também em chamadas
indiretas. Tipos nominais de classes não se confundem por terem o mesmo nome em
módulos distintos. Visibilidade, propriedades declaradas, getters/setters,
índices, imutabilidade de tuplas e overflow inteiro possuem verificações no
runtime; elas continuam ativas com `NDEBUG`.

Vetores tipados mantêm contratos de escrita no heap. Obter um alias `qualquer`
não permite inserir um texto em um vetor já validado como `inteiro[]`. Esses
contratos são conservados e podem ser estreitados por novos vínculos tipados;
não são enfraquecidos por aliases.

O driver não interpola nomes de arquivos em comandos de shell e usa símbolos
internos inacessíveis pela sintaxe dos identificadores do usuário. Módulos
fonte são canonicalizados e seus ciclos são rejeitados.

## Recursos e limites

A VM de CTFE limita a profundidade a 128 chamadas e o trabalho a 10 milhões de
instruções por tentativa. Ao atingir esses limites, a otimização preserva a
chamada nativa. A execução nativa limita chamadas encadeadas a 1024 níveis e
restaura esse contador ao desenrolar exceções.

Inteiros usam 64 bits assinados e operações verificadas. `longo` não fornece
inteiros arbitrariamente grandes neste perfil. Reais usam precisão dupla.
Textos são UTF-8; operações por caracteres validam as sequências. As tabelas de
conversão de caixa são estáticas e podem ser regeneradas pelo utilitário do
runtime, sem depender do locale da máquina.

O runtime é projetado para execução em uma thread. Não há sincronização para
compartilhar seus estados globais de exceção, inicialização e GC entre threads.
Não há suporte de sandbox para executar programas não confiáveis: permissões
do processo e limites de recursos devem ser definidos pelo ambiente hospedeiro.

## Reproduzir verificações

Os exemplos em `exemplos/seguranca/` declaram tanto a fase da falha quanto o texto
do diagnóstico esperado. `testes/integracao.py` acrescenta casos de aliases,
nominalidade, capturas, acesso a membros, importação e limpeza de exceções.

O README do runtime documenta a execução de ASan/UBSan. Com o GC conservativo,
a pilha falsa de ASan e seu detector de vazamentos precisam ser desabilitados;
isso não desativa os demais diagnósticos de acesso inválido e UB.
