module frontend.lexer.keywords;

import frontend.lexer.token;

immutable TokenKind[dstring] keywords = [
    "var": TokenKind.Var, "variavel": TokenKind.Var, "variável": TokenKind.Var,

    "const": TokenKind.Const, "fixo": TokenKind.Const, "constante": TokenKind.Const,

    "assincrona": TokenKind.Async, "aguardar": TokenKind.Await, "rotina": TokenKind.Routine,
    "funcao": TokenKind.Fn, "função": TokenKind.Fn, "se": TokenKind.If,
    "senao": TokenKind.Else, "senão": TokenKind.Else, "enquanto": TokenKind.While,
    "para": TokenKind.For, "escolha": TokenKind.Switch, "caso": TokenKind.Case,
    "padrao": TokenKind.Default, "padrão": TokenKind.Default, "assercao": TokenKind.Assert,
    "asserção": TokenKind.Assert, "importar": TokenKind.Import, "tente": TokenKind.Try,
    "pegue": TokenKind.Catch, "finalmente": TokenKind.Finally, "falhar": TokenKind.Fail,
    "construtor": TokenKind.Constructor, "destrutor": TokenKind.Destructor,
    "estatico": TokenKind.Static, "estático": TokenKind.Static, "abstrata": TokenKind.Abstract,
    "abstrato": TokenKind.Abstract, "estrangeira": TokenKind.Foreign, "enum": TokenKind.Enum,
    "enumeracao": TokenKind.Enum, "enumeração": TokenKind.Enum, "interface": TokenKind.Interface,
    "implementa": TokenKind.Implements, "mescla": TokenKind.Mixins, "classe": TokenKind.Class,
    "herda": TokenKind.Extends, "isto": TokenKind.This, "super": TokenKind.Super,
    "publico": TokenKind.Public, "público": TokenKind.Public, "privado": TokenKind.Private,
    "protegido": TokenKind.Protected, "cada": TokenKind.Each, "fazer": TokenKind.Do,
    "sustar": TokenKind.Break, "continua": TokenKind.Continue, "e": TokenKind.And,
    "ou": TokenKind.Or, "em": TokenKind.In, "contem": TokenKind.In, "contém": TokenKind.In,
    "nao": TokenKind.Bang, "não": TokenKind.Bang, "nulo": TokenKind.Null,
    "verdadeiro": TokenKind.True, "falso": TokenKind.False, "tipo": TokenKind.Type,
    "de": TokenKind.Of, "retorne": TokenKind.Return, "retorna": TokenKind.Return,
];
