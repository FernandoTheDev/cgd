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
