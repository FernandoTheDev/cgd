module driver.project;

import core.stdc.stdlib : exit;
import std.algorithm : canFind, sort;
import std.array : array, join, replace;
import std.conv : to;
import std.datetime.systime : SysTime;
import std.file;
import std.format : format;
import std.json;
import std.path;
import std.process : Pid, spawnProcess, wait;
import std.stdio : stderr, writefln, writeln;
import std.string : endsWith, startsWith, strip;

import driver.args;
import driver.compile;
import env : VERSION;
import errors;
import frontend.formatter : formatDelegua;
import frontend.modules : cgdLibraryRoots;
import utils;

struct ProjectConfig
{
    string rootDir;
    string manifestPath;
    string nome;
    string versao = "0.1.0";
    string tipo = "aplicativo";
    string entrada = "fontes/principal.delegua";
    string saida;
    string modo = "desenvolvimento";
    int otimizacao = 0;
    bool depuracao = true;
    string compiladorC = "auto";
    string paralelismo = "auto";
    string[string] dependencias;
    string[] bibliotecasNativas;
    string diretorioTestes = "testes";
    string diretorioFontes = "fontes";
}

private immutable string[] VALID_TYPES = [
    "aplicativo", "servidor", "tui", "gtk", "sdl", "biblioteca"
];

private immutable string[] VALID_MODES = [
    "desenvolvimento", "producao"
];

/// Localiza a raiz do projeto subindo a partir de `startDir` até encontrar `projeto.json`.
string findProjectRoot(string startDir = ".")
{
    string cursor = absolutePath(startDir).asNormalizedPath.to!string;
    for (size_t i = 0; i < 32; i++)
    {
        string manifest = buildPath(cursor, "projeto.json");
        if (exists(manifest) && isFile(manifest))
            return cursor;
        string parent = dirName(cursor);
        if (parent == cursor || !parent.length)
            break;
        cursor = parent;
    }
    return null;
}

/// Garante que um caminho declarado em `projeto.json` é relativo e permanece contido na raiz do projeto.
string validateProjectPath(string rootDir, string relPath, string fieldName)
{
    if (!relPath.length)
        cgd_erro(format("projeto.json: campo '%s' não pode estar vazio.", fieldName));
    if (isAbsolute(relPath) || relPath.canFind('\0') || relPath.canFind('\\'))
        cgd_erro(format("projeto.json: caminho inválido em '%s': '%s' (use caminho relativo).", fieldName, relPath));
    string normRoot = absolutePath(rootDir).asNormalizedPath.to!string;
    string resolved = absolutePath(buildPath(normRoot, relPath)).asNormalizedPath.to!string;
    if (resolved != normRoot && !resolved.startsWith(normRoot ~ dirSeparator))
        cgd_erro(format("projeto.json: caminho em '%s' escapa da raiz do projeto: '%s'.", fieldName, relPath));
    return resolved;
}

private bool isValidProjectName(string name)
{
    if (!name.length || name.length > 64 || name == "." || name == "..")
        return false;
    foreach (char ch; name)
    {
        bool ok = (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z')
            || (ch >= '0' && ch <= '9') || ch == '_' || ch == '-';
        if (!ok)
            return false;
    }
    return true;
}

ProjectConfig loadProject(string rootDir)
{
    string manifestPath = buildPath(rootDir, "projeto.json");
    if (!exists(manifestPath) || !isFile(manifestPath))
        cgd_erro("projeto.json não encontrado em: " ~ rootDir);

    JSONValue root;
    try
        root = parseJSON(readText(manifestPath));
    catch (Exception e)
        cgd_erro("projeto.json inválido: " ~ e.msg);

    if (root.type != JSONType.object)
        cgd_erro("projeto.json deve ser um objeto JSON.");

    ProjectConfig cfg;
    cfg.rootDir = absolutePath(rootDir).asNormalizedPath.to!string;
    cfg.manifestPath = manifestPath;

    const(JSONValue)* pNome = "nome" in root;
    if (pNome is null || pNome.type != JSONType.string || !pNome.str.length)
        cgd_erro("projeto.json: campo obrigatório 'nome' ausente ou inválido.");
    cfg.nome = pNome.str;
    if (!isValidProjectName(cfg.nome))
        cgd_erro("projeto.json: 'nome' contém caracteres inválidos: " ~ cfg.nome);

    if (const(JSONValue)* pVersao = "versao" in root)
    {
        if (pVersao.type != JSONType.string || !pVersao.str.length)
            cgd_erro("projeto.json: 'versao' deve ser texto não vazio.");
        cfg.versao = pVersao.str;
    }

    if (const(JSONValue)* pTipo = "tipo" in root)
    {
        if (pTipo.type != JSONType.string || !VALID_TYPES.canFind(pTipo.str))
            cgd_erro("projeto.json: 'tipo' inválido. Use: " ~ VALID_TYPES.join(", ") ~ ".");
        cfg.tipo = pTipo.str;
    }

    if (const(JSONValue)* pEntrada = "entrada" in root)
    {
        if (pEntrada.type != JSONType.string)
            cgd_erro("projeto.json: 'entrada' deve ser texto.");
        cfg.entrada = pEntrada.str;
    }
    else if (!exists(buildPath(cfg.rootDir, "fontes", "principal.delegua"))
            && exists(buildPath(cfg.rootDir, "src", "principal.delegua")))
    {
        cfg.entrada = "src/principal.delegua";
        cfg.diretorioFontes = "src";
    }

    if (const(JSONValue)* pSaida = "saida" in root)
    {
        if (pSaida.type != JSONType.string)
            cgd_erro("projeto.json: 'saida' deve ser texto.");
        cfg.saida = pSaida.str;
    }
    else
        cfg.saida = buildPath("compilacao", cfg.nome);

    if (const(JSONValue)* pComp = "compilacao" in root)
    {
        if (pComp.type != JSONType.object)
            cgd_erro("projeto.json: 'compilacao' deve ser um objeto.");
        if (const(JSONValue)* pModo = "modo" in *pComp)
        {
            if (pModo.type != JSONType.string || !VALID_MODES.canFind(pModo.str))
                cgd_erro("projeto.json: 'compilacao.modo' deve ser 'desenvolvimento' ou 'producao'.");
            cfg.modo = pModo.str;
            if (cfg.modo == "producao")
            {
                cfg.otimizacao = 2;
                cfg.depuracao = false;
            }
        }
        if (const(JSONValue)* pOtim = "otimizacao" in *pComp)
        {
            if (pOtim.type != JSONType.integer && pOtim.type != JSONType.uinteger)
                cgd_erro("projeto.json: 'compilacao.otimizacao' deve ser inteiro (0..3).");
            long v = pOtim.type == JSONType.integer ? pOtim.integer : cast(long) pOtim.uinteger;
            if (v < 0 || v > 3)
                cgd_erro("projeto.json: 'compilacao.otimizacao' fora da faixa 0..3.");
            cfg.otimizacao = cast(int) v;
        }
        if (const(JSONValue)* pDep = "depuracao" in *pComp)
        {
            if (pDep.type != JSONType.true_ && pDep.type != JSONType.false_)
                cgd_erro("projeto.json: 'compilacao.depuracao' deve ser lógico.");
            cfg.depuracao = pDep.type == JSONType.true_;
        }
        if (const(JSONValue)* pCc = "compiladorC" in *pComp)
        {
            if (pCc.type != JSONType.string)
                cgd_erro("projeto.json: 'compilacao.compiladorC' deve ser texto.");
            cfg.compiladorC = pCc.str;
        }
        if (const(JSONValue)* pPar = "paralelismo" in *pComp)
        {
            if (pPar.type == JSONType.string)
                cfg.paralelismo = pPar.str;
            else if (pPar.type == JSONType.integer || pPar.type == JSONType.uinteger)
                cfg.paralelismo = pPar.toString();
            else
                cgd_erro("projeto.json: 'compilacao.paralelismo' deve ser texto ou inteiro.");
        }
    }

    if (const(JSONValue)* pDeps = "dependencias" in root)
    {
        if (pDeps.type != JSONType.object)
            cgd_erro("projeto.json: 'dependencias' deve ser um objeto.");
        foreach (string k, JSONValue v; pDeps.object)
        {
            if (v.type != JSONType.string)
                cgd_erro("projeto.json: valor de dependência '" ~ k ~ "' deve ser texto.");
            cfg.dependencias[k] = v.str;
        }
    }

    if (const(JSONValue)* pLibs = "bibliotecasNativas" in root)
    {
        if (pLibs.type != JSONType.array)
            cgd_erro("projeto.json: 'bibliotecasNativas' deve ser uma lista.");
        foreach (JSONValue item; pLibs.array)
        {
            if (item.type != JSONType.string || !item.str.length)
                cgd_erro("projeto.json: itens de 'bibliotecasNativas' devem ser textos não vazios.");
            cfg.bibliotecasNativas ~= item.str;
        }
    }

    if (const(JSONValue)* pTestes = "testes" in root)
    {
        if (pTestes.type != JSONType.object)
            cgd_erro("projeto.json: 'testes' deve ser um objeto.");
        if (const(JSONValue)* pDir = "diretorio" in *pTestes)
        {
            if (pDir.type != JSONType.string)
                cgd_erro("projeto.json: 'testes.diretorio' deve ser texto.");
            cfg.diretorioTestes = pDir.str;
        }
    }

    // Valida segurança de caminhos declarados.
    validateProjectPath(cfg.rootDir, cfg.entrada, "entrada");
    validateProjectPath(cfg.rootDir, cfg.saida, "saida");
    validateProjectPath(cfg.rootDir, cfg.diretorioTestes, "testes.diretorio");
    if (exists(buildPath(cfg.rootDir, "fontes")) && isDir(buildPath(cfg.rootDir, "fontes")))
        cfg.diretorioFontes = "fontes";
    else if (exists(buildPath(cfg.rootDir, "src")) && isDir(buildPath(cfg.rootDir, "src")))
        cfg.diretorioFontes = "src";
    return cfg;
}

private string[] projectModuleRoots(const ref ProjectConfig cfg)
{
    string[] roots;
    string fontesDir = buildPath(cfg.rootDir, cfg.diretorioFontes);
    if (exists(fontesDir) && isDir(fontesDir))
        roots ~= fontesDir;
    string pacotesDir = buildPath(cfg.rootDir, "pacotes");
    if (exists(pacotesDir) && isDir(pacotesDir))
        roots ~= pacotesDir;
    roots ~= cfg.rootDir;
    return roots;
}

private string computeBuildStamp(const ref ProjectConfig cfg, const ref CGDArguments args, string entryFile)
{
    string[] parts;
    parts ~= "v=" ~ VERSION;
    parts ~= "entry=" ~ entryFile;
    parts ~= "opt=" ~ (args.opt ? "1" : "0");
    parts ~= "dbg=" ~ (args.debugInfo ? "1" : "0");
    parts ~= "cc=" ~ args.cc;
    parts ~= "libs=" ~ cfg.bibliotecasNativas.join(",");
    void addFileStamp(string filePath)
    {
        if (!exists(filePath) || !isFile(filePath))
            return;
        SysTime mtime = timeLastModified(filePath);
        ulong sz = getSize(filePath);
        parts ~= format("%s:%d:%d", filePath, mtime.stdTime, sz);
    }

    addFileStamp(thisExePath());
    addFileStamp(cfg.manifestPath);
    addFileStamp(entryFile);
    string fontesDir = buildPath(cfg.rootDir, cfg.diretorioFontes);
    if (exists(fontesDir) && isDir(fontesDir))
    {
        string[] files;
        foreach (DirEntry entry; dirEntries(fontesDir, SpanMode.breadth))
            if (entry.isFile && extension(entry.name) == ".delegua")
                files ~= entry.name;
        files.sort();
        foreach (string f; files)
            addFileStamp(f);
    }
    foreach (string libRoot; cgdLibraryRoots())
    {
        if (!exists(libRoot) || !isDir(libRoot))
            continue;
        string[] libFiles;
        foreach (DirEntry entry; dirEntries(libRoot, SpanMode.breadth))
            if (entry.isFile && extension(entry.name) == ".delegua")
                libFiles ~= entry.name;
        libFiles.sort();
        foreach (string f; libFiles)
            addFileStamp(f);
        break;
    }
    return parts.join("\n");
}

private void applyNativeLibs(ref CGDArguments args, const(string)[] libs)
{
    foreach (string lib; libs)
    {
        if (lib == "gtk4" || lib == "sdl3" || lib == "ncursesw")
        {
            if (!args.nativePackages.canFind(lib))
                args.nativePackages ~= lib;
        }
        else if (lib.length)
        {
            string flag = lib.startsWith("-") ? lib : ("-l" ~ lib);
            if (!args.linkFlags.canFind(flag))
                args.linkFlags ~= flag;
        }
    }
}

private CGDArguments buildArgumentsForProject(const ref ProjectConfig cfg, string modeOverride,
        bool forceOpt, bool hasOptFlag, bool debugOverride, bool hasDebugFlag,
        string ccOverride, string outputOverride, bool showPerf, bool checkOnly)
{
    CGDArguments args;
    string mode = modeOverride.length ? modeOverride : cfg.modo;
    if (!VALID_MODES.canFind(mode))
        cgd_erro("Modo de compilação inválido: '" ~ mode ~ "'. Use desenvolvimento ou producao.");
    if (mode == "producao")
    {
        args.opt = true;
        args.debugInfo = false;
    }
    else
    {
        args.opt = cfg.otimizacao > 0;
        args.debugInfo = cfg.depuracao;
    }
    if (hasOptFlag)
        args.opt = forceOpt;
    if (hasDebugFlag)
        args.debugInfo = debugOverride;
    if (ccOverride.length)
        args.cc = ccOverride;
    else if (cfg.compiladorC.length && cfg.compiladorC != "auto")
        args.cc = cfg.compiladorC;
    args.showPerf = showPerf;
    args.checkOnly = checkOnly;
    args.output = outputOverride.length ? outputOverride : validateProjectPath(cfg.rootDir, cfg.saida, "saida");
    args.moduleRoots = projectModuleRoots(cfg);
    applyNativeLibs(args, cfg.bibliotecasNativas);
    return args;
}

private string compileProjectIfNeeded(const ref ProjectConfig cfg, CGDArguments args, string entryFile, bool forceRebuild)
{
    string outBin = args.output;
    string cacheDir = dirName(outBin);
    string cacheFile = buildPath(cacheDir, ".cgd-cache");
    string stamp = computeBuildStamp(cfg, args, entryFile);
    if (!forceRebuild && exists(outBin) && isFile(outBin) && exists(cacheFile) && isFile(cacheFile))
    {
        try
        {
            if (readText(cacheFile) == stamp)
                return outBin;
        }
        catch (Exception)
        {
        }
    }
    if (!exists(cacheDir))
        mkdirRecurse(cacheDir);
    compile(args, entryFile);
    try
        write(cacheFile, stamp);
    catch (Exception)
    {
    }
    return outBin;
}

private string templateMainSource(string name, string tipo)
{
    if (tipo == "servidor")
    {
        return "// Projeto servidor HTTP criado com `cgd iniciar`\n"
            ~ "const HTTP = importar(\"cgd:rede/http\")\n\n"
            ~ "const servidor: qualquer = HTTP.Servidor()\n"
            ~ "servidor.obter(\"/\", funcao(req: qualquer, res: qualquer) {\n"
            ~ "    res.texto(\"Olá do servidor " ~ name ~ "!\")\n"
            ~ "})\n"
            ~ "servidor.obter(\"/saude\", funcao(req: qualquer, res: qualquer) {\n"
            ~ "    res.json({ status: \"ok\", projeto: \"" ~ name ~ "\" })\n"
            ~ "})\n\n"
            ~ "escreva(\"Servidor " ~ name ~ " pronto em http://127.0.0.1:8080\\n\")\n"
            ~ "servidor.escutar(\"127.0.0.1\", 8080)\n";
    }
    if (tipo == "tui")
    {
        return "// Projeto TUI criado com `cgd iniciar`\n"
            ~ "const TUI = importar(\"cgd:interface/tui\")\n\n"
            ~ "const tela: qualquer = TUI.Tela()\n"
            ~ "tela.iniciar()\n"
            ~ "tente {\n"
            ~ "    tela.limpar()\n"
            ~ "    tela.caixa(2, 1, 44, 5, \"" ~ name ~ "\")\n"
            ~ "    tela.escrever(4, 3, \"Pressione 'q' para sair\")\n"
            ~ "    tela.apresentar()\n"
            ~ "    enquanto verdadeiro {\n"
            ~ "        const ev: qualquer = tela.lerEvento(250)\n"
            ~ "        se ev != nulo e ev[\"tecla\"] == \"q\" {\n"
            ~ "            sustar\n"
            ~ "        }\n"
            ~ "    }\n"
            ~ "} finalmente {\n"
            ~ "    tela.finalizar()\n"
            ~ "}\n";
    }
    if (tipo == "gtk")
    {
        return "// Projeto GTK4 criado com `cgd iniciar`\n"
            ~ "const GTK = importar(\"cgd:interface/gtk\")\n\n"
            ~ "const aplicativo: qualquer = GTK.Aplicacao(\"dev.cgd." ~ name.replace("-", "_") ~ "\")\n"
            ~ "aplicativo.aoAtivar(funcao() {\n"
            ~ "    const janela: qualquer = GTK.Janela(aplicativo)\n"
            ~ "    janela.definirTitulo(\"" ~ name ~ "\")\n"
            ~ "    janela.definirTamanho(640, 400)\n"
            ~ "    const caixa: qualquer = GTK.CaixaVertical(12)\n"
            ~ "    const rotulo: qualquer = GTK.Rotulo(\"Olá, Delégua com GTK4!\")\n"
            ~ "    const botao: qualquer = GTK.Botao(\"Clique aqui\")\n"
            ~ "    botao.aoClicar(funcao() {\n"
            ~ "        rotulo.definirTexto(\"Botão acionado!\")\n"
            ~ "    })\n"
            ~ "    caixa.adicionar(rotulo)\n"
            ~ "    caixa.adicionar(botao)\n"
            ~ "    janela.definirConteudo(caixa)\n"
            ~ "    janela.mostrar()\n"
            ~ "})\n"
            ~ "aplicativo.executar()\n";
    }
    if (tipo == "sdl")
    {
        return "// Projeto SDL3 criado com `cgd iniciar`\n"
            ~ "const SDL = importar(\"cgd:interface/sdl\")\n\n"
            ~ "SDL.inicializar()\n"
            ~ "tente {\n"
            ~ "    const janela: qualquer = SDL.Janela(\"" ~ name ~ "\", 800, 450)\n"
            ~ "    const renderizador: qualquer = janela.criarRenderizador()\n"
            ~ "    var executando: logico = verdadeiro\n"
            ~ "    enquanto executando {\n"
            ~ "        para cada evento: qualquer em SDL.obterEventos() {\n"
            ~ "            se evento.ehSaida() {\n"
            ~ "                executando = falso\n"
            ~ "            }\n"
            ~ "        }\n"
            ~ "        renderizador.definirCor(20, 24, 34, 255)\n"
            ~ "        renderizador.limpar()\n"
            ~ "        renderizador.definirCor(70, 200, 120, 255)\n"
            ~ "        renderizador.preencherRetangulo(120, 120, 180, 120)\n"
            ~ "        renderizador.apresentar()\n"
            ~ "        SDL.atrasar(16)\n"
            ~ "    }\n"
            ~ "} finalmente {\n"
            ~ "    SDL.finalizar()\n"
            ~ "}\n";
    }
    return "modulo principal\n\n"
        ~ "importar utilitarios.saudacao\n\n"
        ~ "const mensagem: texto = utilitarios.saudacao.cumprimentar(\"" ~ name ~ "\")\n"
        ~ "escreva(mensagem)\n";
}

void runInitCommand(string[] args)
{
    string name;
    string tipo = "aplicativo";
    for (size_t i = 0; i < args.length; i++)
    {
        if (args[i] == "--ajuda" || args[i] == "-a" || args[i] == "--help")
        {
            writeln("Uso: cgd iniciar <nome> [--tipo aplicativo|servidor|tui|gtk|sdl|biblioteca]");
            return;
        }
        if (args[i] == "--tipo")
        {
            if (i + 1 >= args.length)
                cgd_erro("Esperado valor após --tipo.");
            tipo = args[++i];
        }
        else if (args[i].startsWith("--tipo="))
            tipo = args[i][7 .. $];
        else if (args[i].startsWith("-"))
            cgd_erro("Opção desconhecida em 'cgd iniciar': " ~ args[i]);
        else if (!name.length)
            name = args[i];
        else
            cgd_erro("Argumento inesperado em 'cgd iniciar': " ~ args[i]);
    }
    if (!name.length)
        cgd_erro("Informe o nome do projeto: cgd iniciar <nome> [--tipo aplicativo]");
    if (!isValidProjectName(name))
        cgd_erro("Nome de projeto inválido: '" ~ name ~ "'. Use letras, dígitos, '-' ou '_'.");
    if (!VALID_TYPES.canFind(tipo))
        cgd_erro("Tipo de projeto inválido: '" ~ tipo ~ "'. Use: " ~ VALID_TYPES.join(", ") ~ ".");

    string projectDir = absolutePath(name).asNormalizedPath.to!string;
    if (exists(projectDir))
        cgd_erro("Diretório já existe: " ~ projectDir);

    mkdirRecurse(buildPath(projectDir, "fontes"));
    mkdirRecurse(buildPath(projectDir, "testes"));
    mkdirRecurse(buildPath(projectDir, "recursos"));
    mkdirRecurse(buildPath(projectDir, "compilacao"));

    string[] nativeLibs;
    if (tipo == "gtk")
        nativeLibs = ["gtk4"];
    else if (tipo == "sdl")
        nativeLibs = ["sdl3"];

    JSONValue manifest = JSONValue([
        "nome": JSONValue(name),
        "versao": JSONValue("0.1.0"),
        "tipo": JSONValue(tipo),
        "entrada": JSONValue("fontes/principal.delegua"),
        "saida": JSONValue("compilacao/" ~ name),
        "compilacao": JSONValue([
            "modo": JSONValue("desenvolvimento"),
            "otimizacao": JSONValue(0),
            "depuracao": JSONValue(true),
            "compiladorC": JSONValue("auto"),
            "paralelismo": JSONValue("auto")
        ]),
        "dependencias": parseJSON("{}"),
        "bibliotecasNativas": JSONValue(nativeLibs),
        "testes": JSONValue([
            "diretorio": JSONValue("testes")
        ])
    ]);
    write(buildPath(projectDir, "projeto.json"), manifest.toPrettyString() ~ "\n");
    write(buildPath(projectDir, "fontes", "principal.delegua"), templateMainSource(name, tipo));

    if (tipo == "aplicativo" || tipo == "biblioteca")
    {
        mkdirRecurse(buildPath(projectDir, "fontes", "utilitarios"));
        write(buildPath(projectDir, "fontes", "utilitarios", "saudacao.delegua"),
                "modulo utilitarios.saudacao\n\n"
                ~ "funcao cumprimentar(alvo: texto): texto {\n"
                ~ "    retorna \"Olá, \" + alvo + \"!\"\n"
                ~ "}\n");
        write(buildPath(projectDir, "testes", "principal_teste.delegua"),
                "importar utilitarios.saudacao\n\n"
                ~ "assercao(utilitarios.saudacao.cumprimentar(\"CGD\") == \"Olá, CGD!\")\n"
                ~ "escreva(\"OK\")\n");
    }
    else
    {
        write(buildPath(projectDir, "testes", "principal_teste.delegua"),
                "assercao(1 + 1 == 2)\n"
                ~ "escreva(\"OK\")\n");
    }

    write(buildPath(projectDir, "README.md"),
            format("# %s\n\nProjeto Delégua (%s) criado com CGD %s.\n\n"
                ~ "## Comandos\n\n```sh\ncgd compilar\ncgd rodar\ncgd testar\n```\n",
                name, tipo, VERSION));

    writefln("Projeto '%s' (%s) criado em %s", name, tipo, projectDir);
}

void runBuildCommand(string[] args)
{
    string fileArg;
    string mode;
    string cc;
    string outputOverride;
    bool forceOpt, hasOptFlag, debugFlag, hasDebugFlag, showPerf, forceRebuild;

    for (size_t i = 0; i < args.length; i++)
    {
        string a = args[i];
        if (a == "--ajuda" || a == "-a" || a == "--help")
        {
            writeln("Uso: cgd compilar [arquivo.delegua] [--modo desenvolvimento|producao] [--depuracao] [-o] [-s saida] [--cc compilador] [--forcar] [--tempo]");
            return;
        }
        else if (a == "--modo" && i + 1 < args.length)
            mode = args[++i];
        else if (a.startsWith("--modo="))
            mode = a[7 .. $];
        else if (a == "--cc" && i + 1 < args.length)
            cc = args[++i];
        else if (a.startsWith("--cc="))
            cc = a[5 .. $];
        else if ((a == "-s" || a == "--saida") && i + 1 < args.length)
            outputOverride = args[++i];
        else if (a.startsWith("--saida="))
            outputOverride = a[8 .. $];
        else if (a == "-o" || a == "--otimizar")
        {
            forceOpt = true;
            hasOptFlag = true;
        }
        else if (a == "--depuracao" || a == "-g")
        {
            debugFlag = true;
            hasDebugFlag = true;
        }
        else if (a == "--tempo" || a == "-t")
            showPerf = true;
        else if (a == "--forcar")
            forceRebuild = true;
        else if (a.startsWith("-"))
            cgd_erro("Opção desconhecida em 'cgd compilar': " ~ a);
        else if (!fileArg.length)
            fileArg = a;
        else
            cgd_erro("Argumento inesperado em 'cgd compilar': " ~ a);
    }

    if (fileArg.length)
    {
        CGDArguments cgdArgs;
        cgdArgs.opt = hasOptFlag ? forceOpt : (mode == "producao");
        cgdArgs.debugInfo = hasDebugFlag ? debugFlag : (mode != "producao");
        cgdArgs.cc = cc;
        cgdArgs.output = outputOverride;
        cgdArgs.showPerf = showPerf;
        compile(cgdArgs, fileArg);
        return;
    }

    string rootDir = findProjectRoot();
    if (!rootDir.length)
        cgd_erro("Nenhum projeto.json encontrado. Execute em um projeto ou informe um arquivo .delegua.");
    ProjectConfig cfg = loadProject(rootDir);
    string entry = validateProjectPath(cfg.rootDir, cfg.entrada, "entrada");
    CGDArguments cgdArgs = buildArgumentsForProject(cfg, mode, forceOpt, hasOptFlag, debugFlag,
            hasDebugFlag, cc, outputOverride, showPerf, false);
    string outBin = compileProjectIfNeeded(cfg, cgdArgs, entry, forceRebuild);
    writefln("Compilado: %s", outBin);
}

void runRunCommand(string[] args)
{
    string[] buildArgs;
    string[] programArgs;
    bool afterSep = false;
    for (size_t i = 0; i < args.length; i++)
    {
        if (!afterSep && args[i] == "--")
        {
            afterSep = true;
            continue;
        }
        if (afterSep)
            programArgs ~= args[i];
        else
            buildArgs ~= args[i];
    }

    string fileArg;
    string mode;
    string cc;
    bool forceOpt, hasOptFlag, debugFlag, hasDebugFlag, forceRebuild;
    for (size_t i = 0; i < buildArgs.length; i++)
    {
        string a = buildArgs[i];
        if (a == "--ajuda" || a == "-a" || a == "--help")
        {
            writeln("Uso: cgd rodar [arquivo.delegua] [--modo desenvolvimento|producao] [--depuracao] [-o] [-- argumentos...]");
            return;
        }
        else if (a == "--modo" && i + 1 < buildArgs.length)
            mode = buildArgs[++i];
        else if (a.startsWith("--modo="))
            mode = a[7 .. $];
        else if (a == "--cc" && i + 1 < buildArgs.length)
            cc = buildArgs[++i];
        else if (a.startsWith("--cc="))
            cc = a[5 .. $];
        else if (a == "-o" || a == "--otimizar")
        {
            forceOpt = true;
            hasOptFlag = true;
        }
        else if (a == "--depuracao" || a == "-g")
        {
            debugFlag = true;
            hasDebugFlag = true;
        }
        else if (a == "--forcar")
            forceRebuild = true;
        else if (a.startsWith("-"))
            cgd_erro("Opção desconhecida em 'cgd rodar': " ~ a);
        else if (!fileArg.length)
            fileArg = a;
        else
            programArgs ~= a;
    }

    string binary;
    if (fileArg.length)
    {
        string outDir = buildPath(tempDir(), "cgd-rodar");
        if (!exists(outDir))
            mkdirRecurse(outDir);
        binary = buildPath(outDir, stripExtension(baseName(fileArg)));
        CGDArguments cgdArgs;
        cgdArgs.opt = hasOptFlag ? forceOpt : (mode == "producao");
        cgdArgs.debugInfo = hasDebugFlag ? debugFlag : false;
        cgdArgs.cc = cc;
        cgdArgs.output = binary;
        compile(cgdArgs, fileArg);
    }
    else
    {
        string rootDir = findProjectRoot();
        if (!rootDir.length)
            cgd_erro("Nenhum projeto.json encontrado. Execute em um projeto ou informe um arquivo .delegua.");
        ProjectConfig cfg = loadProject(rootDir);
        string entry = validateProjectPath(cfg.rootDir, cfg.entrada, "entrada");
        CGDArguments cgdArgs = buildArgumentsForProject(cfg, mode, forceOpt, hasOptFlag, debugFlag,
                hasDebugFlag, cc, null, false, false);
        binary = compileProjectIfNeeded(cfg, cgdArgs, entry, forceRebuild);
    }

    Pid pid = spawnProcess([binary] ~ programArgs);
    int status = wait(pid);
    if (status != 0)
        exit(status);
}

void runTestCommand(string[] args)
{
    string filtro;
    string mode;
    string cc;
    for (size_t i = 0; i < args.length; i++)
    {
        string a = args[i];
        if (a == "--ajuda" || a == "-a" || a == "--help")
        {
            writeln("Uso: cgd testar [--filtro texto] [--modo desenvolvimento|producao] [--cc compilador]");
            return;
        }
        else if (a == "--filtro" && i + 1 < args.length)
            filtro = args[++i];
        else if (a.startsWith("--filtro="))
            filtro = a[9 .. $];
        else if (a == "--modo" && i + 1 < args.length)
            mode = args[++i];
        else if (a.startsWith("--modo="))
            mode = a[7 .. $];
        else if (a == "--cc" && i + 1 < args.length)
            cc = args[++i];
        else if (a == "--cobertura")
            writeln("Aviso: --cobertura usa execução padrão dos testes do projeto.");
        else
            cgd_erro("Opção desconhecida em 'cgd testar': " ~ a);
    }

    string rootDir = findProjectRoot();
    if (!rootDir.length)
        cgd_erro("Nenhum projeto.json encontrado para 'cgd testar'.");
    ProjectConfig cfg = loadProject(rootDir);
    string testDir = validateProjectPath(cfg.rootDir, cfg.diretorioTestes, "testes.diretorio");
    if (!exists(testDir) || !isDir(testDir))
    {
        writeln("Nenhum diretório de testes encontrado: ", testDir);
        return;
    }

    string[] testFiles;
    foreach (DirEntry entry; dirEntries(testDir, SpanMode.breadth))
        if (entry.isFile && extension(entry.name) == ".delegua")
            if (!filtro.length || entry.name.canFind(filtro))
                testFiles ~= entry.name;
    testFiles.sort();

    if (!testFiles.length)
    {
        writeln("Nenhum arquivo de teste .delegua encontrado em ", testDir);
        return;
    }

    string binDir = buildPath(cfg.rootDir, "compilacao", "testes");
    mkdirRecurse(binDir);

    size_t passed = 0;
    size_t failed = 0;
    foreach (size_t idx, string tf; testFiles)
    {
        string rel = relativePath(tf, cfg.rootDir);
        string outBin = buildPath(binDir, format("teste_%d_%s", idx, stripExtension(baseName(tf))));
        CGDArguments cgdArgs = buildArgumentsForProject(cfg, mode, false, false, false, false, cc, outBin, false, false);
        try
        {
            compile(cgdArgs, tf);
            Pid pid = spawnProcess([outBin]);
            int status = wait(pid);
            if (status == 0)
            {
                writefln("[OK]   %s", rel);
                passed++;
            }
            else
            {
                writefln("[FAIL] %s (código %d)", rel, status);
                failed++;
            }
        }
        catch (Exception e)
        {
            stderr.writefln("[ERRO] %s: %s", rel, e.msg);
            failed++;
        }
    }
    writefln("\nResumo dos testes: %d aprovado(s), %d falha(s), %d total.", passed, failed, testFiles.length);
    if (failed > 0)
        exit(1);
}

void runCleanCommand(string[] args)
{
    if (args.length && (args[0] == "--ajuda" || args[0] == "-a" || args[0] == "--help"))
    {
        writeln("Uso: cgd limpar");
        return;
    }
    string rootDir = findProjectRoot();
    if (!rootDir.length)
        cgd_erro("Nenhum projeto.json encontrado para 'cgd limpar'.");
    ProjectConfig cfg = loadProject(rootDir);
    string compDir = validateProjectPath(cfg.rootDir, "compilacao", "compilacao");
    if (exists(compDir) && isDir(compDir))
    {
        rmdirRecurse(compDir);
        writeln("Removido: ", compDir);
    }
    else
        writeln("Nada para limpar.");
}

void runCheckCommand(string[] args)
{
    string fileArg;
    for (size_t i = 0; i < args.length; i++)
    {
        if (args[i] == "--ajuda" || args[i] == "-a" || args[i] == "--help")
        {
            writeln("Uso: cgd verificar [arquivo.delegua]");
            return;
        }
        if (!fileArg.length)
            fileArg = args[i];
    }
    if (fileArg.length)
    {
        CGDArguments cgdArgs;
        cgdArgs.checkOnly = true;
        compile(cgdArgs, fileArg);
        writeln("Verificação concluída sem erros: ", fileArg);
        return;
    }
    string rootDir = findProjectRoot();
    if (!rootDir.length)
        cgd_erro("Nenhum projeto.json encontrado. Informe um arquivo .delegua.");
    ProjectConfig cfg = loadProject(rootDir);
    string entry = validateProjectPath(cfg.rootDir, cfg.entrada, "entrada");
    CGDArguments cgdArgs = buildArgumentsForProject(cfg, null, false, false, false, false, null, null, false, true);
    compile(cgdArgs, entry);
    writefln("Projeto '%s' verificado sem erros.", cfg.nome);
}

void runFormatCommand(string[] args)
{
    bool checkOnly = false;
    string[] targets;
    foreach (string a; args)
    {
        if (a == "--ajuda" || a == "-a" || a == "--help")
        {
            writeln("Uso: cgd formatar [arquivo|diretorio] [--verificar]");
            return;
        }
        if (a == "--verificar")
            checkOnly = true;
        else
            targets ~= a;
    }

    string[] files;
    if (targets.length)
    {
        foreach (string t; targets)
        {
            if (isDir(t))
            {
                foreach (DirEntry entry; dirEntries(t, SpanMode.breadth))
                    if (entry.isFile && extension(entry.name) == ".delegua")
                        files ~= entry.name;
            }
            else
                files ~= t;
        }
    }
    else
    {
        string rootDir = findProjectRoot();
        if (!rootDir.length)
            cgd_erro("Nenhum projeto.json encontrado. Informe um arquivo ou diretório.");
        ProjectConfig cfg = loadProject(rootDir);
        foreach (string sub; [cfg.diretorioFontes, cfg.diretorioTestes])
        {
            string dir = buildPath(cfg.rootDir, sub);
            if (exists(dir) && isDir(dir))
                foreach (DirEntry entry; dirEntries(dir, SpanMode.breadth))
                    if (entry.isFile && extension(entry.name) == ".delegua")
                        files ~= entry.name;
        }
    }

    files.sort();
    size_t changed = 0;
    foreach (string f; files)
    {
        string source = readText(f);
        string formatted = formatDelegua(source);
        if (source != formatted)
        {
            changed++;
            if (checkOnly)
                stderr.writefln("Fora do padrão: %s", f);
            else
                write(f, formatted);
        }
    }
    if (checkOnly)
    {
        if (changed > 0)
            exit(1);
        writefln("Formatação OK (%d arquivo(s)).", files.length);
    }
    else
        writefln("Formatado(s): %d/%d arquivo(s).", changed, files.length);
}

void runProjectCommand(string[] args)
{
    string sub = args.length ? args[0] : "informacoes";
    if (sub == "--ajuda" || sub == "-a" || sub == "--help")
    {
        writeln("Uso: cgd projeto [validar|informacoes]");
        return;
    }
    string rootDir = findProjectRoot();
    if (!rootDir.length)
        cgd_erro("Nenhum projeto.json encontrado no diretório atual ou ancestrais.");
    ProjectConfig cfg = loadProject(rootDir);
    string entry = validateProjectPath(cfg.rootDir, cfg.entrada, "entrada");

    if (sub == "validar")
    {
        if (!exists(entry) || !isFile(entry))
            cgd_erro("Arquivo de entrada não encontrado: " ~ entry);
        if (extension(entry) != ".delegua")
            cgd_erro("Arquivo de entrada deve ter extensão .delegua: " ~ entry);
        writefln("projeto.json válido (%s v%s).", cfg.nome, cfg.versao);
        return;
    }
    if (sub == "informacoes" || sub == "info")
    {
        writefln("Nome:       %s", cfg.nome);
        writefln("Versão:     %s", cfg.versao);
        writefln("Tipo:       %s", cfg.tipo);
        writefln("Raiz:       %s", cfg.rootDir);
        writefln("Entrada:    %s", cfg.entrada);
        writefln("Saída:      %s", cfg.saida);
        writefln("Modo:       %s (otimizacao=%d, depuracao=%s)", cfg.modo, cfg.otimizacao,
                cfg.depuracao ? "sim" : "nao");
        writefln("Compilador: %s", cfg.compiladorC);
        writefln("Testes:     %s", cfg.diretorioTestes);
        if (cfg.bibliotecasNativas.length)
            writefln("Nativas:    %s", cfg.bibliotecasNativas.join(", "));
        return;
    }
    cgd_erro("Subcomando desconhecido em 'cgd projeto': " ~ sub ~ ". Use 'validar' ou 'informacoes'.");
}
