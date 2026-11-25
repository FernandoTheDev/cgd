module diagnostics.catalog;

/// Mensagens e códigos públicos vivem juntos. Os parâmetros nunca são código.
struct MessageSpec
{
    string code, message, explanation;
}

enum MessageSpec runtimeError = MessageSpec("R0001", "%s", "Falha dinâmica do runtime; consulte a operação e a localização informadas. Tipos dinâmicos, aliases e entrada externa continuam validados em execução.");
enum MessageSpec genericError = MessageSpec("E0001", "%s", "Diagnóstico legado; consulte a mensagem e a posição.");
enum MessageSpec genericWarning = MessageSpec("W0001", "%s", "Aviso legado; consulte a mensagem e a posição.");
enum MessageSpec genericHint = MessageSpec("H0001", "%s", "Informação complementar de um diagnóstico.");
enum MessageSpec diagnosticLimit = MessageSpec("E0002",
            "Limite de diagnósticos atingido; corrija os erros anteriores.",
            "O limite protege contra uma cascata de erros.");
enum MessageSpec driverFailure = MessageSpec("E9001", "%s",
            "Verifique arquivos, opções, dependências e a toolchain configurada.");
enum MessageSpec moduleCycle = MessageSpec("E2001", "Ciclo de importação detectado: %s",
            "Quebre a dependência circular mostrada pela cadeia de importação.");
enum MessageSpec moduleBudget = MessageSpec("E2002", "Limite de recursos de carregamento de módulos excedido.",
            "Divida o grafo; os limites de tamanho e quantidade são documentados.");
enum MessageSpec moduleLoad = MessageSpec("E2003", "%s\nImportado por: %s",
            "Confira o caminho literal relativo ao módulo que importa.");
enum MessageSpec dynamicWarning = MessageSpec("W4002",
            "Carregamento dinâmico/NPM/FFI não é suportado por segurança.",
            "Use fontes .delegua conhecidas na compilação.");
enum MessageSpec dynamicError = MessageSpec("E4002", "Importe um módulo fonte .delegua.",
            "Importação de código nativo ou carregado dinamicamente é excluída.");
enum MessageSpec unexpectedEnd = MessageSpec("E1000",
            "Fim inesperado do arquivo; verifique delimitadores e expressões incompletas.",
            "Feche os delimitadores e complete a última expressão.");
enum MessageSpec expectedToken = MessageSpec("E1001", "%s",
            "A mensagem descreve o token ou expressão esperado; o parser tenta recuperar em outro comando.");
enum MessageSpec incompatibleTypes = MessageSpec("E3002",
            "Incompatibilidade de tipo: era esperado '%s' mas foi recebido '%s'.",
            "Use um tipo compatível com o contrato declarado.");
enum MessageSpec captureWarning = MessageSpec("W4001",
            "Captura externa de '%s' detectada: exigiria upvalues, recurso desabilitado por segurança.",
            "Passe estado por parâmetros ou receptor explícito.");
enum MessageSpec captureError = MessageSpec("E4001",
            "A captura foi bloqueada; passe o valor como parâmetro explícito.",
            "Capturas de ambiente são excluídas deliberadamente do perfil compilado.");
enum MessageSpec invalidUTF8 = MessageSpec("E1002", "Arquivo fonte não contém UTF-8 válido.",
            "Salve a fonte como UTF-8.");
enum MessageSpec syntaxDepth = MessageSpec("E1003", "Limite de aninhamento sintático excedido.",
            "Divida expressões ou blocos profundamente aninhados.");
enum MessageSpec invalidNumericLiteral = MessageSpec("E1005", "Literal numérico inválido ou fora do intervalo.",
            "Literais inteiros exigem 64 bits; literais reais precisam ser finitos e representáveis em 64 bits.");
enum MessageSpec astLimit = MessageSpec("E1004",
            "Limite estrutural da AST excedido; divida a expressão ou o módulo.",
            "O frontend limita profundidade e quantidade de nós antes dos passes recursivos.");
enum MessageSpec missingSymbol = MessageSpec("E3001", "O símbolo '%s' não foi declarado.",
            "Verifique escopo e grafia; funções não capturam ambientes externos.");
enum MessageSpec unsupportedStaticField = MessageSpec("E3011", "Campos estáticos ainda não são suportados; declare um método estático.",
            "Esta versão oferece campos de instância e métodos estáticos; a ausência de campos estáticos não é uma exclusão de segurança.");
enum MessageSpec staticConstructor = MessageSpec("E3012", "Construtor não pode ser estático.",
            "O construtor inicializa uma instância gerenciada e recebe isto; use outro nome para uma fábrica estática.");
enum MessageSpec suggestion = MessageSpec("H3001", "Você quis dizer '%s'?",
            "Sugestão determinística de nome visível no escopo.");
enum MessageSpec unreachable = MessageSpec("W3001", "Código inalcançável após transferência de controle.",
            "Remova ou reorganize a cauda que não executa.");
enum MessageSpec implicitReturn = MessageSpec("W3002",
            "Função com retorno tipado pode terminar sem retornar valor; o retorno implícito é nulo.",
            "Garanta um retorno nos caminhos relevantes.");
enum MessageSpec zeroDivision = MessageSpec("E3101", "Divisão ou módulo por zero demonstrável em compilação.",
            "O denominador é uma expressão constante igual a zero.");
enum MessageSpec integerOverflow = MessageSpec("E3102", "Resultado inteiro fora do intervalo de 64 bits.",
            "Altere o cálculo ou use valores reais quando apropriado.");
enum MessageSpec invalidIndex = MessageSpec("E3103", "Índice constante inválido: %s.",
            "Índices negativos são aceitos dentro dos limites da coleção.");
enum MessageSpec typeContract = MessageSpec("E3104",
            "Incompatibilidade de tipo demonstrável: esperado '%s', recebido '%s'.",
            "Contratos explícitos não são removidos pela otimização.");
enum MessageSpec invalidOperation = MessageSpec("E3105",
            "Operação demonstravelmente inválida: %s.", "Use os tipos e limites aceitos pelo runtime.");
enum MessageSpec invalidConversion = MessageSpec("E3106", "Conversão literal inválida para '%s'.",
            "Valide o texto de entrada ou trate dados recebidos em execução.");
enum MessageSpec invalidShift = MessageSpec("E3107", "Deslocamento constante fora do intervalo [0, 63].",
            "A quantidade de bits precisa estar dentro dos limites de 64 bits.");
enum MessageSpec invalidSlice = MessageSpec("E3108", "O passo constante de uma fatia não pode ser zero.",
            "Use um passo positivo ou negativo diferente de zero.");
enum MessageSpec unknownMember = MessageSpec("E3109", "Membro '%s' não existe em '%s'.",
            "Verifique o nome do método, campo ou exportação disponível para este tipo.");
enum MessageSpec immutableMutation = MessageSpec("E3110", "Não é possível modificar elemento de '%s' imutável.",
            "Textos e tuplas são imutáveis; crie um novo valor ou utilize um vetor.");
enum MessageSpec nullOperation = MessageSpec("E3111", "Operação '%s' inválida sobre valor comprovadamente nulo.",
            "Verifique se o valor não é nulo antes de acessar membros, indexar ou chamar.");
enum MessageSpec notCallable = MessageSpec("E3112", "O valor do tipo '%s' não pode ser chamado como função.",
            "Apenas funções, métodos e classes construtíveis podem ser invocados.");

enum MessageSpec inaccessibleMember = MessageSpec("E3014", "Membro '%s' não é acessível neste contexto.",
            "Respeite a visibilidade público, protegido ou privado da declaração que oculta as herdadas.");
enum MessageSpec instanceMember = MessageSpec("E3015", "Membro '%s' exige uma instância.",
            "Instancie a classe antes de acessar campos e métodos de instância.");
enum MessageSpec invalidArity = MessageSpec("E3016", "A função '%s' espera entre %s e %s argumentos; recebeu %s.",
            "Respeite argumentos obrigatórios, opcionais e variáveis da função ou método.");
enum MessageSpec invalidAssignment = MessageSpec("E3017", "%s",
            "O destino precisa ser modificável; funções, constantes e o receptor isto não podem ser reatribuídos.");
enum MessageSpec impureState = MessageSpec("E3201", "Função pura depende do estado externo '%s'.",
            "Passe o valor por parâmetro; a CTFE não lê nem modifica variáveis externas à função.");
enum MessageSpec invalidDestructor = MessageSpec("E3013",
            "Destrutor deve ser público, de instância, sem parâmetros e retornar vazio.",
            "Declare destrutor(): vazio e use destruir(objeto) em finalmente para liberar recursos explicitamente.");

enum MessageSpec asyncContext = MessageSpec("E3301", "Construção assíncrona fora de um contexto permitido.", "Aguardar exige corpo assincrono. Defaults, inicializadores, acessores, ciclo de vida e assinaturas FFI são síncronos.");
enum MessageSpec awaitOperand = MessageSpec("E3302", "Aguardar exige Promessa<T> ou Tarefa<T>; recebeu '%s'.",
            "Uma operação síncrona não se torna assíncrona por aguardar. Use uma função assincrona ou rotina.");
enum MessageSpec asyncPure = MessageSpec("E3303", "Função assíncrona não aceita avaliação pura/CTFE.",
            "O loop e as continuações só executam no programa nativo, nunca no compilador ou editor.");
enum MessageSpec asyncEffect = MessageSpec("E3304", "Método não preserva o efeito assíncrono do contrato.",
            "Implementação e override devem manter assincrona e o tipo de resultado declarado.");
enum MessageSpec asyncUnsupported = MessageSpec("E3305",
            "Construção ainda não suportada no lowering assíncrono: %s.",
            "A implementação incremental rejeita esta construção explicitamente; não há fallback bloqueante.");
enum MessageSpec asyncVoid = MessageSpec("E3306", "Resultado vazio de aguardar não pode ser usado como valor.",
            "Use aguardar como comando quando a Promise é Promessa<vazio>.");
enum MessageSpec asyncBudget = MessageSpec("E3307", "Limite de recursos da IR assíncrona excedido.", "Divida a função: até 100000 instruções/slots, 2000000 fatos de vivacidade e 50000000 visitas de instrução/fato por análise.");
enum MessageSpec routineTarget = MessageSpec("E3401",
            "Rotina exige chamada direta a função de topo ou método estático conhecido, sem captura.",
            "Chame diretamente uma função declarada no módulo ou método estático de classe gerenciada.");
enum MessageSpec routineEffect = MessageSpec("E3402",
            "Função '%s' não é segura para execução paralela em rotina: %s.",
            "Rotinas não podem acessar globais mutáveis, FFI, I/O síncrono ou chamadas indiretas sem contrato.");
enum MessageSpec routineTransfer = MessageSpec("E3403",
            "Rotina aceita apenas argumentos e retorno transferíveis (nulo, lógico, inteiro, real ou texto); recebeu '%s'.",
            "Transfira apenas valores escalares ou textos copiados; coleções e objetos mutáveis não atravessam threads.");
enum MessageSpec routineAsync = MessageSpec("E3404",
            "Função assíncrona não pode ser iniciada diretamente com rotina; use chamada normal e aguardar.",
            "Corrotinas assíncronas executam no loop cooperativo da thread principal, não no pool paralelo.");

// Compilação condicional e CTFE avançado (E35xx)
enum MessageSpec conditionalNonConstant = MessageSpec("E3501",
            "Condição de @quando deve ser uma expressão constante pura avaliável em compilação: %s.",
            "Use apenas constantes literais, operadores puros e consultas de Compilacao.* em @quando(...).");
enum MessageSpec conditionalArity = MessageSpec("E3502",
            "O decorador @quando exige exatamente uma expressão lógica constante.",
            "Escreva @quando(Compilacao.sistemaOperacional() == \"linux\") ou uma condição booleana constante.");
enum MessageSpec invalidCompileQuery = MessageSpec("E3503",
            "Consulta de compilação inválida ou desconhecida em Compilacao.%s.",
            "Consultas disponíveis: sistemaOperacional, arquitetura, tamanhoPonteiro, abi, compiladorC, modo, temRecurso.");

// Código nativo @nativo e tipos C (E36xx)
enum MessageSpec nativeUnsupportedOp = MessageSpec("E3601",
            "Operação incompatível com @nativo (sem fallback silencioso): %s.",
            "Funções @nativo operam diretamente sobre tipos C, structs @pilha e containers nativos sem GC.");
enum MessageSpec nativeInvalidType = MessageSpec("E3602",
            "Tipo '%s' incompatível com função @nativo.",
            "Use tipos C (ci8..ci64, cu8..cu64, cf32, cf64, csize, cbool, ...), structs @pilha ou containers nativos.");
enum MessageSpec nativeForbiddenCall = MessageSpec("E3603",
            "Chamada a '%s' proibida dentro de @nativo: exige runtime gerenciado/GC.",
            "Marque o alvo como @nativo ou cruze a fronteira gerenciada fora da região nativa.");
enum MessageSpec nativeUnsafeConversion = MessageSpec("E3604",
            "Conversão implícita potencialmente insegura entre '%s' e '%s' em @nativo.",
            "Use conversão explícita (ex.: ci32(valor), cf64(valor), csize(valor)) para deixar a intenção clara.");
enum MessageSpec nativeInvalidTarget = MessageSpec("E3605",
            "O decorador @nativo não pode ser aplicado neste alvo: %s.",
            "@nativo aplica-se a funções e métodos concretos síncronos sem envelopes dinâmicos.");

// Classes por valor @pilha / @valor (E37xx)
enum MessageSpec valueClassInvalidStructure = MessageSpec("E3701",
            "Classe @pilha '%s' incompatível com %s.",
            "Tipos @pilha possuem layout C estático plano e não suportam herança dinâmica, interfaces, mesclas ou classes estrangeiras.");
enum MessageSpec valueClassInvalidField = MessageSpec("E3702",
            "Campo '%s' da classe @pilha '%s' exige tipo com layout estático conhecido; recebeu '%s'.",
            "Use tipos C, escalares nativos (inteiro, real, logico), outros tipos @pilha ou containers nativos.");
enum MessageSpec valueClassRecursive = MessageSpec("E3703",
            "Recursão de layout detectada na classe @pilha '%s'.",
            "Uma struct por valor não pode conter diretamente a si mesma com tamanho infinito.");
enum MessageSpec valueClassInvalidFeature = MessageSpec("E3704",
            "Recurso não permitido em classe @pilha '%s': %s.",
            "Tipos @pilha exigem campos de instância concretos sem acessores dinâmicos nem campos estáticos.");

// Ownership, empréstimos, escapes e lifetimes inferidos (E38xx)
enum MessageSpec useAfterMove = MessageSpec("E3801",
            "Uso da variável '%s' após transferência de ownership.",
            "O recurso proprietário já foi movido; use .clonar() antes de transferir se precisar manter uma cópia.");
enum MessageSpec useAfterFree = MessageSpec("E3802",
            "Uso do recurso '%s' após liberação explícita.",
            "Não acesse nem modifique um container ou recurso nativo depois de chamar liberar()/destruir().");
enum MessageSpec forbiddenImplicitCopy = MessageSpec("E3803",
            "Cópia implícita proibida para o tipo proprietário '%s'.",
            "Recursos com ownership exclusivo não podem ser duplicados implicitamente; transfira ou chame .clonar().");
enum MessageSpec danglingReturn = MessageSpec("E3804",
            "Retorno de visão ou referência pendurada '%s' vinculada ao recurso local '%s'.",
            "O recurso local é destruído ao sair da função; retorne um valor proprietário em vez de uma visão.");
enum MessageSpec mutableBorrowConflict = MessageSpec("E3805",
            "Conflito de empréstimo em '%s': não é possível modificar ou realocar enquanto '%s' estiver ativo.",
            "Finalize o uso da visão/iteração ativa antes de alterar ou redimensionar o container proprietário.");
enum MessageSpec unsafeEscape = MessageSpec("E3806",
            "Escape inseguro de recurso ou visão '%s': %s.",
            "Visões emprestadas e recursos locais não podem escapar por closures ou campos que vivem além do dono.");
enum MessageSpec doubleFree = MessageSpec("E3807",
            "Liberação duplicada demonstrável do recurso '%s'.",
            "O recurso já foi liberado ou destruído neste caminho de execução.");
enum MessageSpec uninitializedNativeUse = MessageSpec("E3808",
            "Uso de variável ou recurso nativo '%s' antes de inicialização completa.",
            "Inicialize todos os campos ou atribua um valor antes da primeira leitura.");
enum MessageSpec nativeBoundsOrOverflow = MessageSpec("E3809",
            "Acesso fora dos limites ou overflow de capacidade demonstrável em '%s': %s.",
            "Garanta índices dentro de [0, tamanho) e capacidades positivas dentro do limite de 64 bits.");

// Operadores personalizados @operador (E39xx)
enum MessageSpec invalidOperatorSymbol = MessageSpec("E3901",
            "Operador '%s' não é suportado em @operador(...).",
            "Operadores suportados: +, -, *, /, %, ==, !=, <, <=, >, >=, [], []=, unario-, unario+, unario!.");
enum MessageSpec invalidOperatorSignature = MessageSpec("E3902",
            "Assinatura inválida para @operador(\"%s\") no método '%s': %s.",
            "Binários e [] exigem 1 parâmetro; []= exige 2 parâmetros; unários exigem 0 parâmetros; não podem ser estáticos.");
enum MessageSpec inaccessibleOperator = MessageSpec("E3903",
            "Operador '%s' da classe '%s' não é acessível neste contexto.",
            "Declare o método @operador como público (ou protegido quando usado em subclasse).");
enum MessageSpec ambiguousOrDuplicateOperator = MessageSpec("E3904",
            "Operador '%s' duplicado ou ambíguo: %s.",
            "Defina apenas uma sobrecarga inequívoca para cada combinação de operador e tipos.");
enum MessageSpec invalidOperatorReturn = MessageSpec("E3905",
            "Operador relacional/igualdade '%s' em '%s' deve retornar logico ou cbool; recebeu '%s'.",
            "Operadores ==, !=, <, <=, >, >= exigem retorno booleano para preservar coerência semântica.");
enum MessageSpec incompatibleNativeOperator = MessageSpec("E3906",
            "Operador '%s' de '%s' não pode ser invocado em contexto @nativo: %s.",
            "Marque o método operador de uma classe @pilha como @nativo ou elegível para compilação nativa.");

// GPU (E395x)
enum MessageSpec gpuUnsupportedFeature = MessageSpec("E3951",
            "Recurso incompatível com kernel @gpu: %s.",
            "Kernels @gpu aceitam apenas operações numéricas determinísticas sobre tipos C escalares e buffers.");

immutable MessageSpec[] messages = [
    routineTarget, routineEffect, routineTransfer, routineAsync, asyncBudget, asyncVoid,
    asyncContext, awaitOperand, asyncPure,
    asyncEffect, asyncUnsupported, runtimeError, genericError, genericWarning, genericHint,
    diagnosticLimit, driverFailure, moduleCycle, moduleBudget, moduleLoad, dynamicWarning,
    dynamicError, unexpectedEnd, expectedToken, incompatibleTypes, captureWarning, captureError,
    invalidUTF8, syntaxDepth, invalidNumericLiteral, astLimit, missingSymbol,
    unsupportedStaticField, staticConstructor, suggestion, unreachable,
    implicitReturn, zeroDivision, integerOverflow, invalidIndex, typeContract, invalidOperation,
    invalidConversion, invalidShift, invalidSlice, unknownMember, immutableMutation, nullOperation,
    notCallable, impureState, invalidDestructor, inaccessibleMember, instanceMember, invalidArity,
    invalidAssignment,
    conditionalNonConstant, conditionalArity, invalidCompileQuery,
    nativeUnsupportedOp, nativeInvalidType, nativeForbiddenCall, nativeUnsafeConversion, nativeInvalidTarget,
    valueClassInvalidStructure, valueClassInvalidField, valueClassRecursive, valueClassInvalidFeature,
    useAfterMove, useAfterFree, forbiddenImplicitCopy, danglingReturn, mutableBorrowConflict,
    unsafeEscape, doubleFree, uninitializedNativeUse, nativeBoundsOrOverflow,
    invalidOperatorSymbol, invalidOperatorSignature, inaccessibleOperator, ambiguousOrDuplicateOperator,
    invalidOperatorReturn, incompatibleNativeOperator, gpuUnsupportedFeature
];

const(MessageSpec)* lookupMessage(string code)
{
    foreach (ref immutable(MessageSpec) spec; messages)
        if (spec.code == code || (code.length == 5 && code[0] == 'W' && spec.code == "E" ~ code[1 .. $]))
            return &spec;
    return null;
}
