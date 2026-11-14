# Compatibilidade com Delégua

Referência: [wiki oficial](https://github.com/DesignLiquido/delegua/wiki), revisão
`54eb4ae0b1489bbdef74dca4e2e9dc73c47855a0`. O CGD implementa um perfil compilado
com runtime gerenciado. A tabela descreve o código desta branch, não uma promessa
de equivalência com todos os ambientes, dialetos e extensões do interpretador.

| Área | Recursos disponíveis |
| --- | --- |
| Valores | Nulo, lógicos, inteiros de 64 bits, reais de 64 bits, textos UTF-8, vetores, tuplas, dicionários, funções e objetos |
| Variáveis | Inferência, anotações, constantes, inicialização nula, atribuição múltipla e desestruturação de propriedades |
| Operadores | Aritmética, potência, divisão inteira, bits, comparações, curto-circuito, coalescência, pertencimento e atribuições compostas |
| Controle | Se/senão, ternário, escolha/caso, enquanto, fazer/enquanto, para, para cada, sustar e continua |
| Coleções | Literais, índices negativos, espalhamento, compreensão, fatiamento com passo e laços como expressões de vetores |
| Funções | Nomeadas/anônimas sem captura, funções como valores, callbacks, recursão, padrões dependentes de parâmetros anteriores e parâmetros variáveis |
| Classes | Campos tipados, construtores, herança, super, isto, métodos ligados, público/privado/protegido e acessores automáticos/customizados |
| Exceções | Tente, pegue com/sem tipo, finalmente, falhar, Excecao e subclasses; limpeza em retornos e controles de laço |
| Módulos | Importação de fontes `.delegua` por caminho literal, cache, ciclos diagnosticados, inicialização única e exportações protegidas |
| Texto | Interpolação, escapes, tamanho/indexação por pontos de código, divisão, substituição, busca, caixa Unicode e aparar |
| Biblioteca global | Escreva, leia, conversões, tamanho, tupla, aleatório, aleatório entre, clonar, filtrar, mapear, ordenar, paraCada e todosEmCondicao |
| Métodos | Métodos de texto/número/vetor/dicionário descritos na wiki e propriedades ordinais das tuplas |
| Metadados | Decoradores de dados em funções/classes/campos/métodos e envelopes de funções livres sem captura |
| Asserções | Asserção/assercao como declaração e função, com mensagem opcional e exceção tratável |
| Compilação | C99, Clang/GCC/TCC, diagnósticos com posição, CTFE limitada e otimizações opcionais |

Veja os [exemplos executáveis](../exemplos/README.md) e o
[contrato de segurança](seguranca.md).

## Exclusões deliberadas

Upvalues e closures que capturam estado são bloqueados com aviso e erro. FFI,
classes estrangeiras, ponteiros arbitrários, importação dinâmica, NPM e execução
dinâmica de código não são expostos. Bibliotecas do ambiente `delegua-node` não
são automaticamente bibliotecas do CGD.

## Limites atuais

- O ambiente validado é Linux x86_64. Windows/macOS e compilação cruzada não são garantidos.
- `longo` usa o limite inteiro de 64 bits do runtime; não implementa a precisão arbitrária do interpretador. `decimal` é um alias do perfil real.
- Importações precisam ser caminhos literais de fontes. Herança por alias dinâmico de uma classe importada não é resolvida pelo frontend.
- Envelopes de decoradores em métodos ainda são rejeitados; metadados em métodos são suportados. Os envelopes de funções livres executam na inicialização das funções.
- Declarações de classes devem ser feitas no nível do módulo. O suporte a tipos locais e a sombreamento de nomes de tipos não é completo.
- A CTFE aceita um subconjunto da linguagem. Recursos sem bytecode equivalente recebem diagnóstico em funções `//>puro`, em vez de serem executados incorretamente.
- Não há backends próprios LLVM/assembly, protocolo de depuração ou dialetos adicionais. O modo `-d` mostra a AST e o C intermediário.
- Iteração de dicionários não promete ordem de inserção. Modificar uma coleção durante sua própria iteração não oferece semântica de snapshot.
- Contratos de vetores compartilhados são monotônicos: novos vínculos tipados podem restringir as escritas possíveis por aliases anteriores.
- A localização de erro pode refletir a operação auxiliar mais recente; não há uma pilha completa de chamadas em Delégua.

Esses limites são separados das exclusões de segurança: não se deve classificar
um recurso ausente como inseguro apenas por ainda não estar implementado.
