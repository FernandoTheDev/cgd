module frontend.natives;
immutable dstring[] cgdNativeNames = [
    "cgdCurlCriar"d, "cgdCurlFechar"d, "cgdCurlResetar"d, "cgdCurlOpcao"d, "cgdCurlExecutar"d,
    "cgdCurlLote"d, "cgdCurlOpcoes"d, "cgdCurlVersao"d, "cgdCurlEscapar"d, "cgdCurlDecodificar"d,
    "cgdCurlMultipart"d, "cgdCurlEnviar"d, "cgdCurlReceber"d, "cgdCurlEsperar"d,
    "cgdCurlWsEnviar"d, "cgdCurlWsReceber"d, "cgdCurlInfo"d, "cgdCurlUrl"d, "cgdCurlDetalhes"d,
    "cgdCurlErro"d, "cgdCurlData"d, "cgdCurlManter"d, "cgdCodigoUnicode"d,
    "cgdCaractereUnicode"d, "cgdNumeroFinito"d, "cgdNumeroTexto"d
];
immutable size_t[] cgdNativeArities = [
    0, 1, 1, 3, 1, 1, 0, 0, 1, 1, 2, 2, 2, 3, 3, 2, 2, 3, 0, 1, 1, 1, 1, 1, 1, 1
];
static assert(cgdNativeNames.length == cgdNativeArities.length);

immutable dstring[] cgdNativeReturns = [
    "qualquer"d, "vazio"d, "qualquer"d, "qualquer"d, "dicionario"d, "dicionario[]"d,
    "dicionario[]"d, "texto"d, "texto"d,
    "texto"d, "qualquer"d, "dicionario"d, "dicionario"d, "logico"d, "dicionario"d, "dicionario"d,
    "qualquer"d, "texto"d, "dicionario"d, "texto"d, "inteiro"d, "vazio"d, "inteiro"d, "texto"d,
    "logico"d, "texto"d
];
immutable dstring[][] cgdNativeParameters = [
    [], ["sessao:qualquer"d], ["sessao:qualquer"d],
    ["sessao:qualquer"d, "nome:texto"d, "valor:qualquer"d], ["sessao:qualquer"d],
    ["sessoes:qualquer[]"d], [], [], ["valor:texto"d], ["valor:texto"d],
    ["sessao:qualquer"d, "partes:dicionario[]"d], ["sessao:qualquer"d, "dados:texto"d],
    ["sessao:qualquer"d, "limite:inteiro"d],
    ["sessao:qualquer"d, "milisegundos:inteiro"d, "escrita:logico"d],
    ["sessao:qualquer"d, "dados:texto"d, "flags:inteiro"d], ["sessao:qualquer"d, "limite:inteiro"d],
    ["sessao:qualquer"d, "nome:texto"d], ["url:texto"d, "parte:texto"d, "valor:qualquer"d], [],
    ["codigo:inteiro"d], ["data:texto"d], ["sessao:qualquer"d], ["caractere:texto"d],
    ["codigo:inteiro"d], ["valor:qualquer"d], ["valor:qualquer"d]
];
static assert(cgdNativeReturns.length == cgdNativeNames.length);
static assert(cgdNativeParameters.length == cgdNativeNames.length);
static foreach (size_t i, size_t arity; cgdNativeArities)
    static assert(cgdNativeParameters[i].length == arity);
