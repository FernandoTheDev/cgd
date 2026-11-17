# Compatibilidade com Delégua

Referência: [wiki oficial](https://github.com/DesignLiquido/delegua/wiki), revisão
`54eb4ae0b1489bbdef74dca4e2e9dc73c47855a0`. O CGD implementa um perfil compilado
com runtime gerenciado. A tabela descreve o código desta branch, não uma promessa
de equivalência com todos os ambientes, dialetos e extensões do interpretador.

| Área              | Recursos disponíveis                                                                                                                                |
| ----------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| Valores           | Nulo, lógicos, inteiros de 64 bits, reais de 64 bits, textos UTF-8, vetores, tuplas, dicionários, funções e objetos                                 |
| Variáveis         | Inferência, anotações, constantes, inicialização nula, atribuição múltipla e desestruturação de propriedades                                        |
| Operadores        | Aritmética, potência, divisão inteira, bits, comparações, curto-circuito, coalescência, pertencimento e atribuições compostas                       |
| Controle          | Se/senão, ternário, escolha/caso, enquanto, fazer/enquanto, para, para cada, sustar e continua                                                      |
| Coleções          | Literais, índices negativos, espalhamento, compreensão, fatiamento com passo e laços como expressões de vetores                                     |
| Funções           | Nomeadas/anônimas sem captura, funções como valores, callbacks, recursão, padrões dependentes de parâmetros anteriores e parâmetros variáveis       |
| Classes           | Campos tipados, construtores, herança, super, isto, métodos ligados/estáticos, público/privado/protegido e acessores automáticos/customizados       |
| Exceções          | Tente, pegue com/sem tipo, finalmente, falhar, Excecao e subclasses; limpeza em retornos e controles de laço                                        |
| Módulos           | Importação de fontes `.delegua` por caminho literal, cache, ciclos diagnosticados, inicialização única e exportações protegidas                     |
| Texto             | Interpolação, escapes, tamanho/indexação por pontos de código, divisão, substituição, busca, caixa Unicode e aparar                                 |
| Biblioteca global | Escreva, leia, conversões, tamanho, tupla, aleatório, aleatório entre, clonar, filtrar, mapear, ordenar, paraCada e todosEmCondicao                 |
| Métodos           | Métodos de texto/número/vetor/dicionário listados na referência local e propriedades ordinais das tuplas                                            |
| Metadados         | Decoradores de dados em funções/classes/campos/métodos e envelopes de funções livres sem captura                                                    |
| Asserções         | Asserção/assercao como declaração e função, com mensagem opcional e exceção tratável                                                                |
| Compilação        | C99, Clang/GCC/TCC, diagnósticos com códigos/JSON, análise sem geração de executável, emissão C isolada, CTFE limitada e otimizações até ponto fixo |

Veja os [exemplos executáveis](../exemplos/README.md) e o
[contrato de segurança](seguranca.md).

## Exclusões deliberadas

Upvalues e closures que capturam estado são bloqueados com aviso e erro. Ponteiros arbitrários, importação dinâmica, NPM e execução
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

## Ferramentas e limites de compilação

`--verificar` faz análise sem toolchain C. `--emitir-c` gera somente o C99.
`--diagnosticos=json` produz diagnósticos estruturados em stderr. O parser
recupera erros independentes e o frontend avisa sobre código inalcançável.
Os limites de tamanho/aninhamento e os códigos são descritos em
[Desenvolvimento](desenvolvimento.md). Opções de alvo, sysroot e runtime preparam
compilações cruzadas, mas executáveis Windows/macOS ainda não foram validados.

A [referência web](linguagem.html) reúne a sintaxe e exemplos testados de cada área,
com filtros por suporte, limitação e exclusão deliberada.

O frontend antecipa falhas locais comprovadas de operadores, índices e contratos
antes da emissão C; em regiões com pegue emite avisos para preservar tratamento.
Dados dinâmicos continuam validados pelo runtime. A localização usa metadados
estáticos em pontos falíveis, sem chamadas adicionais a cada linha.

## Bibliotecas e editor próprios

Os namespaces `cgd:json`, `cgd:rede`, `cgd:colecoes` e `cgd:arquivos` oferecem bibliotecas Delégua
tipadas. JSON tem métodos estáticos e instâncias; rede usa libcurl gerenciada
sem ponteiros/callbacks arbitrários. A API C completa de libcurl não é exposta.
Métodos estáticos são herdados, mas campos estáticos não estão implementados.
Iterações, compreensões e desestruturações aceitam anotações de tipo explícitas.

O formatador próprio usa quatro espaços, via CLI ou LSP. O servidor stdio local
oferece completion por tipo/escopo/namespace, hover, referências, definição,
rename, signature help, símbolos e semantic tokens. Não compila por edição; não
há DAP ou indexação irrestrita do disco. Consulte [Ferramentas](ferramentas.md)
para APIs, instalação, limites e comandos de teste.

Recursos acrescentados em 16/11/2026: destrutores
explícitos via `destruir`, novos métodos de dicionário, JSON navegável e classes
ClienteHTTP/RespostaHTTP/Arquivo. O hover tem prévia CTFE limitada sob demanda.
Esses recursos e seus contratos estão em [Ferramentas](ferramentas.md); a liberação
de recursos não depende da execução de código Delégua pelo GC.

A revisão 0.4.0 acrescenta classes abstratas, interfaces, enums numéricos, arrows e
FFI C/gerenciada. Veja [diferenças e motivos](evolucao-linguagem.md), incluindo
a lista de recursos da wiki que ainda não estão implementados. A validação atual está registrada em CONTINUIDADE.md.

Em 17/11/2026 o usuário excluiu definitivamente compatibilidade JavaScript, classes
de host JS, herança de interfaces e múltiplos dialetos. Esses recursos não são
planos futuros. Os testes da implementação foram autorizados nessa data; resultados
reais estão em [CONTINUIDADE.md](CONTINUIDADE.md).

A revisão 0.5.0 acrescenta defaults tipados, inicialização de atributos por
instância, comparação textual ordenada, dicas de inferência e diagnósticos
visuais do runtime. A stdlib inclui Textos, Estatistica e Caminhos, além das
expansões de Colecoes, Arquivo e Matematica.
