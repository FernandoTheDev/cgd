# Evolução do perfil CGD — 16/11/2026

Referência: [wiki oficial Delégua](https://github.com/DesignLiquido/delegua/wiki),
[orientação a objetos](https://github.com/DesignLiquido/delegua/wiki/Orienta%C3%A7%C3%A3o-a-objetos)
e [FFI](https://github.com/DesignLiquido/delegua/wiki/Interface-de-Funcionalidade-Estrangeira).
A cópia consultada está em `out/wiki-oficial`, revisão
`54eb4ae0b1489bbdef74dca4e2e9dc73c47855a0`; sua revisão pode ser obtida com
`git -C out/wiki-oficial rev-parse HEAD`. Autoria da linguagem original e licença
Apache-2.0 permanecem preservadas. Não se afirma equivalência completa.

## Recursos implementados nesta revisão

- `classe abstrata Nome`: não instanciável, inclusive através de referências
  dinâmicas. `abstrato metodo(...): Tipo;` declara obrigação a ser implementada
  pela classe concreta. Métodos abstratos privados/estáticos e de ciclo de vida
  são rejeitados. A classe derivada mantém a assinatura e a visibilidade exigidas.
- `interface Nome { campo: Tipo; metodo(...): Retorno; }` e
  `classe Nome implementa I, J`: resolução de contratos públicos e validação de
  campos, parâmetros, retornos e métodos herdados. Interfaces são tipos de
  contratos, reconhecidos nos descritores do runtime e em `eInstanciaDe`.
  Assinaturas de implementações são explícitas: diferentemente de exemplos
  inferidos do interpretador, o CGD exige correspondência com o contrato para
  manter o vínculo C verificável. Herança entre interfaces é excluída definitivamente por decisão do usuário.
- `enum Estado { Inicial, Final = 7 }`: constantes inteiras em namespace congelado.
  Incremento implícito, valores explícitos, duplicatas e overflow diagnosticados.
  `Estado` em anotações é alias de inteiro; não constitui enum nominal isolado,
  não restringe uma variável exclusivamente aos membros e não é união algébrica.
  Enums podem ser declarados em módulos, funções, métodos, blocos de controle
  e classes/interfaces. O alias tem escopo lexical. Na classe, `Classe.Enum` e
  `isto.Enum` respeitam visibilidade e herança, sem introduzir campos estáticos
  mutáveis. Membros escalares são constantes aptas a CTFE; capturas de valores
  continuam com as restrições anteriores. Mutar o namespace por aliases é bloqueado.
- `x => expressão`, `(x: T, y: U): R => expressão` e corpos `{ ... }`:
  reutilizam funções anônimas e suas regras de escopo. Capturas continuam
  diagnosticadas; arrow não concede acesso implícito a ambientes externos.
- `para cada elem: T em coleção` já existia e permanece disponível, incluindo
  contratos em runtime. Não é necessário remover a anotação para iterar.

Enums numéricos, arrows e destrutores explícitos são extensões do perfil CGD
solicitadas pelo usuário; não são apresentados como sintaxe comprovada dos
capítulos consultados da wiki. O objetivo é oferecer contratos e conveniência
sem exigir capturas, avaliação dinâmica ou mudanças no runtime de memória.

## FFI C e bibliotecas

A wiki define classes estrangeiras com `@definicao` e deixa o despachador a cargo
do ambiente. CGD implementa ligação C estática na geração do executável:

```delegua
@definicao(biblioteca="m", prefixo="")
classe estrangeira LibM {
    @definicao(simbolo="cos")
    cosseno(x: numero): numero;
}
escreva(LibM.cosseno(0))
```

`numero`/`real` correspondem a `double`; `inteiro`/`longo` a `int64_t`;
`logico` a `bool`; `texto` a cadeia C terminada em zero; retorno `vazio` a `void`.
Textos com zero interno são rejeitados nessa ABI. Valores retornados de texto
são copiados imediatamente; ponteiros nulos provocam falha tratável. Não há
inferência de assinatura a partir de símbolos: a declaração precisa corresponder
à biblioteca C. Declarações erradas e código nativo podem corromper o processo;
FFI não é sandbox. Isso substitui a exclusão anterior de FFI por decisão explícita
do usuário. Não há carregamento dinâmico por edição, avaliação no LSP ou CTFE.

`@definicao(biblioteca="cgd-runtime", abi="delegua")` usa a ABI gerenciada:
`delegua_value funcao(sz argc, delegua_value *argv)`. Ela representa coleções,
textos binários e handles gerenciados sem expor ponteiros na linguagem.
O retorno passa pelo descritor do contrato. `bibliotecas/nativo.delegua` define
as assinaturas dessa ponte; JSON, rede e arquivos usam a classe Primitivas.
As entradas `cgd*` anteriores permanecem como compatibilidade, não como requisito
sintático das bibliotecas novas. Removê-las antes de validar a migração quebraria
consumidores existentes. `pontes.c` é o ponto de exportação da ABI gerenciada.

`cgd:matematica` fornece Matematica sobre libm; Colecoes ganhou reduzir, agrupar e
achatar. JSON, ClienteHTTP/RespostaHTTP e Arquivo mantêm as APIs documentadas em
[ferramentas](ferramentas.md). As bibliotecas não devem substituir diretamente
libcurl por uma assinatura variádica presumida: adaptadores C precisam conservar
callbacks internos, ciclo de vida e buffers. Por isso a camada gerenciada continua
necessária mesmo com FFI.

## Diferenças e trabalho ainda necessário

A wiki descreve diversos ambientes, dialetos, tradução e integração JavaScript.
Esses capítulos não são suporte automático em um compilador C99. Permanecem pendentes composição `mescla`, enums nominais,
structs/variádicos/callbacks na ABI C e equivalência integral de bibliotecas.
Capturas/upvalues, eval e importação dinâmica continuam excluídos pelo contrato
de segurança; não são habilitados por arrows ou FFI.
DAP continua adiado. Linux x86_64 é o único alvo previamente validado.

Na etapa de 16/11 as suítes estavam suspensas por solicitação do usuário.
A autorização de 17/11 revogou essa suspensão: resultados reais, incluindo
regressões funcionais, ficam em CONTINUIDADE.md.

Em 17/11/2026 o usuário excluiu definitivamente compatibilidade JavaScript, classes
de host JS, herança de interfaces e múltiplos dialetos. Esses recursos não são
planos futuros. Os testes da implementação foram autorizados nessa data; resultados
reais estão em [CONTINUIDADE.md](CONTINUIDADE.md).
