# Bibliotecas e editor CGD

O CGD usa o frontend de D no servidor `cgd --lsp --stdio`, um processo local
persistente. Alterar um documento atualiza sua análise e os dependentes abertos;
hover, completion e tokens usam a revisão já analisada. Nenhum build, linker ou
código do programa é executado por edição. O editor não precisa de conexão de rede.

## VS Code e formatação

Após construir o CGD uma vez:

```sh
cd extensao-vscode
npm ci
cd ..
python3 scripts/instalar_extensao.py --associate
```

A extensão usa o CGD configurado, o do workspace confiável ou o binário incluído no
VSIX. `CGD: Reiniciar servidor de linguagem` reinicia o processo; após reinstalar,
use `Developer: Reload Window` para carregar a nova extensão. Os botões compilam,
verificam ou executam o documento salvo. F5 executa sem depuração; DAP foi adiado.

Ctrl+Shift+I e **Format Document** chamam o formatador do LSP. O estilo usa quatro
espaços, espaços entre operadores, separação de blocos e métodos e continuidade de
listas longas. Strings, comentários e contratos são preservados; literais longos
não são partidos. O formatador é lexical, não renomeia símbolos nem inventa tipos.
Na CLI, `cgd --formatar arquivo.delegua` grava o arquivo;
`cgd --verificar-formatacao arquivo.delegua` retorna 1 se houver divergência.

Completion diferencia métodos e campos, respeita o tipo conhecido, membros
públicos herdados e namespaces de módulos. Receptores `qualquer` sem informação
suficiente não recebem sugestões de métodos específicos inventados. Há hover,
definição, referências, rename, símbolos, signature help com parâmetro ativo,
semantic tokens, dobramento e hints opcionais. O índice abrange documentos abertos
mais suas importações estáticas; não indexa automaticamente todos os arquivos do
disco. Não existe garantia de inferência completa sobre dados dinâmicos.

## JSON em Delégua puro

```delegua
var biblioteca: qualquer = importar("cgd:json")
var dados: qualquer = biblioteca.JSON.analisar('{"nome":"CGD"}')
var documento: qualquer = biblioteca.JSON(dados)
documento.definir("versao", 1)
escreva(documento.texto())
```

`JSON.analisar(fonte, limite=128, maxNos=100000)` implementa gramática estrita,
escapes e pares substitutos Unicode. O limite máximo de entrada é 1048576 pontos
de código. `JSON.serializar(valor)` rejeita ciclos e reais não finitos. Inteiros
fora de 64 bits e expoentes fora da representação nativa são preservados como
`NumeroJSON`; `lexema()` devolve sua grafia. As funções soltas permanecem para
compatibilidade. O construtor JSON recebe o valor já analisado. `valor()`,
`obter(chave)`, `definir(chave,valor)` e `texto()` são métodos de instância.

`estatico`/`estático` declara métodos sem `isto`; eles são herdados e podem ser
chamados pela classe ou pela instância. Campos estáticos não estão implementados.

## Rede sobre libcurl

`importar("cgd:rede")` oferece `Sessao`, `obter`, `enviar`, `requisitar`, `lote`,
`versao`, `detalhes`, `opcoes`, escape/decodificação, URL API e datas/erros.
`Sessao.opcao(nome,valor)` aceita opções gerenciáveis anunciadas pela libcurl
instalada. Use `Sessao.info(nome)` para getinfo escalar, `multipart(partes)` para
partes em memória e `upload(dados)` para upload explícito. A sessão também oferece
reset/close, streams connect-only e espera de leitura/escrita. Feche sessões em
`finalmente`. Lotes usam curl_multi. As respostas trazem `codigo` (CURLcode, zero no sucesso), `status` HTTP, `corpo`,
`cabecalhos`, `url`, `segundos` e `erro`. Falhas de transporte ficam nesses campos;
configurações inválidas lançam exceções. HTTP 404 não é sucesso HTTP, mas pode ter
CURLcode zero. O corpo da resposta e os headers têm limite
padrão de 64 MiB cada, ajustável com `CGD_MAX_BYTES`.

Os defaults usam HTTP/HTTPS, TLS verificado, conexão de 10 segundos e tempo total
de 30 segundos. Os programas podem escolher outras opções/protocolos disponíveis.
A API não expõe ponteiros C, FILE\*, callbacks arbitrários, sockets crus nem opções
que substituam callbacks internos ou desliguem suas proteções. `POSTFIELDSIZE`
direto é recusado: o tamanho acompanha o corpo copiado. O upload nunca lê stdin
implicitamente. As opções dependem da libcurl instalada; `detalhes()` distingue
versão dos headers e versão carregada. Entry points WebSocket exigem uma libcurl
com os protocolos necessários; o ambiente validado não anuncia ws/wss.

A API controlada não replica toda a API C de libcurl. Consulte a lista real em
`opcoes()` e os testes de loopback em `testes/bibliotecas.py`.

## Coleções

`importar("cgd:colecoes")` expõe `Colecoes.unicos(valores)` e
`Colecoes.intervalo(inicio,fim,passo=1)`. O intervalo exclui o fim, aceita passo
negativo, recusa zero e limita a criação a um milhão de elementos. Comparação de
coleções/objetos segue a identidade do runtime. As operações nativas de vetores
continuam disponíveis, incluindo mapear e filtrar com callbacks sem captura.

## Validação de desenvolvimento

`testes/lsp.py` verifica protocolo, escopos, UTF-16, buffers em memória, completion,
assinaturas e cache. `testes/formatador.py` exige idempotência e executa os contratos
de todos os exemplos formatados, com/sem otimização. `testes/bibliotecas.py` usa
HTTP em loopback e verifica JSON, limites e opções recusadas. `scripts/verificar_tipos.py`
impede auto/foreach inferido em D e variáveis sem anotação nas bibliotecas.
`python3 scripts/testar_extensao.py` abre um Extension Host com perfil temporário
para testar a integração real, incluindo formatação e ausência de build por edição.

## APIs ampliadas em 16/11/2026

As mudanças desta seção foram incluídas nas suítes autorizadas em 17/11/2026.
Consulte CONTINUIDADE.md para os resultados efetivamente concluídos.

### JSON e HTTP por classes

```delegua
var json: qualquer = importar("cgd:json")
var documento: qualquer = json.JSON.deTexto('{"pessoa":{"nome":"Ana"}}')
escreva(documento.caminho(["pessoa", "nome"], "sem nome"))
escreva(documento.obter("ausente", "padrão"))
```

`JSON.contem` distingue ausência de um valor nulo. `obter` aceita chave ou índice,
inclusive índice negativo de vetor; `caminho` percorre uma lista de chaves/índices.
`definir` aceita chave ou índice para escrita. `copiar` cria um documento independente
por serialização e nova análise JSON.
`chaves` exige objeto JSON. Chaves como "chaves", "obter" e "itens" não impedem
a serialização; ela usa a enumeração controlada do runtime, sem despacho de propriedades. As funções soltas e `JSON.analisar/serializar`
continuam disponíveis. Profundidade: 1..512; orçamento de nós: 1..1.000.000.

```delegua
var rede: qualquer = importar("cgd:rede")
var cliente: qualquer = rede.ClienteHTTP("https://exemplo.com")
cliente.cabecalho("Accept", "application/json")
var resposta: qualquer = cliente.obter("/dados").exigirSucesso()
escreva(resposta.status())
escreva(resposta.json())
```

`ClienteHTTP` copia cabeçalhos/opções recebidos, oferece obter/enviar/enviarJSON/
atualizar/remover e cria uma sessão isolada por requisição. `RespostaHTTP`
oferece status/sucesso/texto/json/cabecalhos/url/erro/dados/exigirSucesso.
`dados` retorna uma cópia do dicionário. `sucesso` exige libcurl sem erro e status
200..299; falhas HTTP continuam inspecionáveis até chamar `exigirSucesso`.
As APIs anteriores de sessão, streaming, multipart e lote permanecem disponíveis.

### Arquivos e dicionários

```delegua
var arquivos: qualquer = importar("cgd:arquivos")
var arquivo: qualquer = arquivos.Arquivo("dados.txt")
arquivo.escrever("primeira linha\n").anexar("segunda linha\n")
escreva(arquivo.ler())
```

`Arquivo` oferece caminho/existe/informacoes/tamanho/ler/linhas/escrever/anexar/
remover. Cada chamada abre e fecha seu descritor; nenhum ponteiro ou descritor é
exposto. Leitura padrão: 16 MiB, configurável até 64 MiB; escrita: até 64 MiB por
chamada. Tamanhos/limites contam bytes. Textos de I/O preservam bytes nulos;
operações Unicode sobre dados que não são UTF-8 continuam sujeitas à validação
usual do runtime. `linhas` normaliza CRLF e preserva linhas vazias/quebra final.
`remover` devolve falso se ausente. Diretórios/dispositivos/FIFOs não servem para
ler/escrever; erros de I/O são exceções tratáveis. Escrita pode ser parcial se o
sistema falhar; não é transação nem gravação atômica. Implementação POSIX/Linux.

Dicionários oferecem `obter(chave, padrao = nulo)`, `definir(chave, valor)` (retorna
o valor), `contemChave(chave)`, `itens()` (snapshot de tuplas chave/valor) e
`limpar()` (muta a mesma coleção e retorna o dicionário). `obter` usa o padrão
somente quando a chave não existe; nulo armazenado permanece nulo. `itens` faz
cópia rasa, sem prometer ordem. Uma chave textual com o nome de um método continua
ocultando esse método; use índices para acessar esses dados.

### Ciclo de vida explícito

```delegua
classe Recurso {
    construtor() {}
    destrutor(): vazio {
        escreva("liberado")
    }
}
var recurso: Recurso = Recurso()
tente {
    escreva("usando")
} finalmente {
    destruir(recurso)
}
```

`construtor`, `destrutor` e `estatico/estático` são palavras-chave. Destrutores
são públicos, de instância, sem argumentos e com retorno vazio. Use
`destruir(instancia)` para acionar a cadeia da classe derivada até as bases, uma
vez por identidade; reentrada e chamadas repetidas são ignoradas. As bases ainda
executam se uma classe falhar; a primeira exceção é relançada ao final. A cadeia
é automática: não chame `super.destrutor()` dentro dela. Chamadas diretas ao método
não substituem esse protocolo. A memória continua gerenciada pelo GC; não há
execução de destrutores Delégua pelo coletor nem ao sair de escopos. `Sessao`
implementa destrutor que fecha sua sessão nativa; `fechar` continua disponível.

### Editor e prévia CTFE

A extensão 0.3.0 inclui gramática lexical para coloração antes de o LSP responder,
snippets e reconhecimento de executáveis com shebang cgd/delegua. Tokens semânticos
continuam prevalecendo. Completion usa o catálogo de palavras-chave do lexer e
membros do receptor respeitando escopo, herança, estáticos e visibilidade;
`isto.` incompleto preserva o contexto da classe. Não há sugestões de nomes
aleatórios do arquivo como fallback depois de ponto.

O hover pode exibir o resultado de chamadas puras com argumentos constantes e de
operações primitivas. A prévia trabalha sobre cópias, apenas sob demanda, com cache
por revisão, até 100.000 instruções de VM por documento e limites de nós/
profundidade. Constantes primitivas tipadas são aceitas se seu contrato passar.
Não executa rede, I/O, funções comuns ou código arbitrário, nem invoca compilador
C/linker. Falhas e limites omitem a prévia; variáveis mutáveis e recursos fora do
subconjunto CTFE não recebem valores presumidos. Isso não constitui depuração.

## Biblioteca padrão ampliada e erros visuais (0.5.0)

A referência principal de uso é o [guia web próprio](linguagem.html), do início
às APIs e decisões de escopo. Ela inclui os capítulos específicos de Textos,
Estatistica, Caminhos e diagnósticos do runtime, com exemplos e contratos.

`cgd:textos` oferece comecaCom, terminaCom, repetir, preencherInicio/preencherFim,
linhas, digitos, juntar, inverter e contar. Texto é Unicode; digitos é ASCII
explícito e inverter usa pontos de código, sem normalizar grafemas.

`cgd:estatistica` oferece soma, media, minimo, maximo, mediana, variancia,
desvioPadrao e resumo. A mediana copia antes de ordenar; a variância é incremental,
populacional por padrão, com opção amostral. Entradas insuficientes falham.

`cgd:caminhos` oferece absoluto, normalizar, juntar, nome, diretorio, extensao e
semExtensao. São operações POSIX lexicais, sem acessar disco ou resolver links.
Não use normalizar como garantia de confinamento de arquivos.

Colecoes ganhou primeiro, ultimo, encontrar, contar, particionar, combinar,
blocos e frequencias. Resultados novos preservam referências rasas aos elementos;
callbacks não capturam ambiente. Arquivo ganhou lerJSON, escreverJSON e
copiarPara. Matematica expõe funções trigonométricas inversas, logaritmos,
arredondar/truncar, hipotenusa e resto via libm.

Erros não capturados do runtime mostram `error[R0001]`, arquivo/linha/coluna,
linha de fonte e marcador `^`. Sem o arquivo, a localização permanece. O trecho
é lido do disco apenas ao reportar falha e pode divergir se o fonte foi modificado.
Controles são escapados; leitura/janela são limitadas e FIFO não bloqueia o
renderer. Exceções capturadas não são impressas automaticamente.
