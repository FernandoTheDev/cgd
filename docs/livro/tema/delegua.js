/* Delégua tem gramática própria; não use JavaScript como aproximação. */
(function () {
  if (!window.hljs) return;
  hljs.registerLanguage('delegua', function (hljs) {
    return {
      name: 'Delégua',
      keywords: {
        $pattern: /[A-Za-z\u00c0-\uffff_][A-Za-z\u00c0-\uffff0-9_]*/,
        keyword:
          'var variavel variável const constante fixo assincrona aguardar rotina funcao função retorna retorne se senao senão enquanto para cada em de fazer escolha caso padrao padrão sustar continua classe herda mescla implementa interface abstrata abstrato estatico estático estrangeira construtor destrutor privado protegido publico público isto super tente pegue finalmente falhar importar enum enumeracao enumeração tipo e ou nao não',
        literal: 'verdadeiro falso nulo',
        type: 'numero número inteiro longo real decimal texto logico lógico booleano qualquer vazio tupla dicionario dicionário Promessa Tarefa',
      },
      contains: [
        hljs.C_LINE_COMMENT_MODE,
        { className: 'meta', begin: /@[A-Za-z\u00c0-\uffff_][A-Za-z\u00c0-\uffff0-9_]*/ },
        { className: 'string', begin: '"', end: '"', contains: [hljs.BACKSLASH_ESCAPE] },
        { className: 'string', begin: "'", end: "'", contains: [hljs.BACKSLASH_ESCAPE] },
        hljs.C_NUMBER_MODE,
      ],
    };
  });
  document.querySelectorAll('code.language-delegua').forEach(function (code) {
    code.removeAttribute('data-highlighted');
    code.classList.remove('hljs');
    code.textContent = code.textContent;
    if (hljs.highlightElement) hljs.highlightElement(code);
    else hljs.highlightBlock(code);
  });
})();
