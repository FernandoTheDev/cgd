import std.stdio;
import std.getopt;
import std.file;
import std.path;
import std.process : environment;
import std.array : split;
import std.string : format, strip, toLower;
import std.algorithm : canFind;
import std.conv : to;
import frontend.lexer.lexer;
import frontend.lexer.token;
import frontend.parser.parser;
import frontend.parser.ast;
import middle.semantic;
import middle.optmizer.constant_folding;
import backend.builder;
import backend.compiler;
import error;
import target;

alias fileWrite = std.file.write;

immutable string VERSAO = "v0.0.7";
immutable string NOME_PROGRAMA = "cgd";
immutable string NOME_COMPLETO = "Compilador Geral Delégua";
immutable string[] EXTENSOES_VALIDAS = [".delegua", ".del"];

string HOME, MAIN_DIR, STDLIB_DIR;

struct CompilerOptions
{
	string arquivoSaida;
	string targetTriple;
	string arquivoEntrada;
	bool mostrarVersao;
	bool emitirIR;
	bool mostrarAjuda;
	bool verboso;
	bool otimizar;
	bool mostrarTokens;
	bool mostrarAST;
}

enum ExitCode : int
{
	Success = 0,
	InvalidArguments = 1,
	FileNotFound = 2,
	CompileError = 3,
	InternalError = 4,
	DirectoryNotFound = 5
}

void main(string[] args)
{
	try
	{
		if (!inicializarDiretorios())
		{
			exit(ExitCode.DirectoryNotFound);
		}

		CompilerOptions opcoes = processarArgumentos(args);

		if (opcoes.mostrarVersao)
		{
			mostrarVersaoPrograma();
			exit(ExitCode.Success);
		}

		if (opcoes.mostrarAjuda)
		{
			mostrarMensagemAjuda();
			exit(ExitCode.Success);
		}

		if (opcoes.arquivoEntrada.length == 0)
		{
			writeln("cgd: erro: arquivo não especificado");
			writeln("Digite 'cgd --help' para mais informações.");
			exit(ExitCode.InvalidArguments);
		}

		if (!validarArquivoEntrada(opcoes.arquivoEntrada))
		{
			exit(ExitCode.FileNotFound);
		}

		TargetInfo target = obterTarget(opcoes.targetTriple, opcoes.verboso);

		string arquivoSaida = determinarArquivoSaida(opcoes.arquivoEntrada, opcoes.arquivoSaida);

		if (opcoes.verboso)
		{
			mostrarInformacoesCompilacao(opcoes.arquivoEntrada, arquivoSaida, target);
		}

		bool sucesso = processarArquivo(opcoes.arquivoEntrada, arquivoSaida, opcoes, target);

		exit(sucesso ? ExitCode.Success : ExitCode.CompileError);
	}
	catch (GetOptException e)
	{
		writefln("cgd: erro nos argumentos: %s", e.msg);
		writeln("Digite 'cgd --help' para mais informações.");
		exit(ExitCode.InvalidArguments);
	}
	catch (Exception e)
	{
		writefln("cgd: erro interno: %s", e.msg);
		stderr.writeln("Um erro inesperado ocorreu. Por favor, reporte este bug.");
		exit(ExitCode.InternalError);
	}
}

bool inicializarDiretorios()
{
	version (Posix)
	{
		HOME = environment.get("HOME");
		if (HOME.length == 0)
		{
			writeln("cgd: erro: variável HOME não definida");
			return false;
		}

		MAIN_DIR = buildPath(HOME, ".cgd");
		STDLIB_DIR = buildPath(MAIN_DIR, "stdlib");

		if (!exists(MAIN_DIR))
		{
			writefln("cgd: erro: diretório principal '%s' não encontrado", MAIN_DIR);
			writeln("Execute 'cgd --install' ou reinstale o compilador.");
			return false;
		}

		if (!exists(STDLIB_DIR))
		{
			writefln("cgd: erro: biblioteca padrão '%s' não encontrada", STDLIB_DIR);
			writeln("Execute 'cgd --install' ou reinstale o compilador.");
			return false;
		}

		return true;
	}
	else version (Windows)
	{
		writeln("cgd: erro: plataforma Windows não suportada atualmente");
		writeln("Contribuições para suporte ao Windows são bem-vindas!");
		return false;
	}
	else
	{
		writeln("cgd: erro: plataforma não suportada");
		return false;
	}
}

CompilerOptions processarArgumentos(string[] args)
{
	CompilerOptions opcoes;

	auto result = getopt(args,
		"o|output", "Especifica o arquivo de saída", &opcoes.arquivoSaida,
		"target", "Especifica o alvo de saída (x86_64-gnu-linux, i386-gnu-linux)", &opcoes.targetTriple,
		"eir|emitir-ir", "Salva o código IR LLVM gerado pelo compilador", &opcoes.emitirIR,
		"v|version", "Mostra a versão do compilador", &opcoes.mostrarVersao,
		"0|optimize", "Aplica otimizações ao código", &opcoes.otimizar,
		"h|help", "Mostra esta mensagem de ajuda", &opcoes.mostrarAjuda,
		"verbose", "Modo verboso - mostra informações detalhadas", &opcoes.verboso,
		"tokens", "Mostra os tokens gerados (debug)", &opcoes.mostrarTokens,
		"ast", "Mostra a árvore sintática abstrata (debug)", &opcoes.mostrarAST
	);

	if (args.length > 1)
	{
		opcoes.arquivoEntrada = args[1];
	}

	if (args.length < 2 && !opcoes.mostrarVersao && !opcoes.mostrarAjuda)
	{
		opcoes.mostrarAjuda = true;
	}

	return opcoes;
}

bool validarArquivoEntrada(string arquivo)
{
	if (!exists(arquivo))
	{
		writefln("cgd: erro: arquivo '%s' não encontrado", arquivo);
		return false;
	}

	if (!isFile(arquivo))
	{
		writefln("cgd: erro: '%s' não é um arquivo válido", arquivo);
		return false;
	}

	string extensao = extension(arquivo).toLower();
	if (!EXTENSOES_VALIDAS.canFind(extensao))
	{
		writefln("cgd: aviso: arquivo '%s' não possui extensão reconhecida", arquivo);
		writefln("Extensões suportadas: %s", EXTENSOES_VALIDAS);
	}

	return true;
}

TargetInfo obterTarget(string targetTriple, bool verboso)
{
	TargetInfo target;

	try
	{
		if (targetTriple.length > 0)
		{
			target = createCustomTarget(targetTriple);
			if (verboso)
				writefln("Usando target personalizado: %s", target.triple);
		}
		else
		{
			target = getTarget();
			if (verboso)
				writefln("Usando target padrão: %s", target.triple);
		}
	}
	catch (Exception e)
	{
		writefln("cgd: erro: target inválido '%s': %s", targetTriple, e.msg);
		writeln("Targets suportados: x86_64-gnu-linux, i386-gnu-linux");
		throw e;
	}

	return target;
}

string determinarArquivoSaida(string arquivoEntrada, string arquivoSaidaEspecificado)
{
	if (arquivoSaidaEspecificado.length > 0)
		return arquivoSaidaEspecificado;

	return baseName(stripExtension(arquivoEntrada));
}

void mostrarInformacoesCompilacao(string entrada, string saida, TargetInfo target)
{
	writeln("=== Informações da Compilação ===");
	writefln("Arquivo de entrada: %s", entrada);
	writefln("Arquivo de saída: %s", saida);
	writefln("Target: %s", target.triple);
	writefln("Diretório stdlib: %s", STDLIB_DIR);
	writeln("================================");
}

void safeRemove(string path)
{
	try
	{
		remove(path);
	}
	catch (Exception)
	{
		// ignora
	}
}

bool processarArquivo(string arquivo, string arquivoSaida, CompilerOptions opcoes, TargetInfo target)
{
	DiagnosticError error = new DiagnosticError();
	string arquivoTemporarioLL;

	try
	{
		scope (exit)
			if (arquivoTemporarioLL.length > 0 && exists(arquivoTemporarioLL))
				safeRemove(arquivoTemporarioLL);

		if (opcoes.verboso)
			writeln("[1/6] Iniciando análise léxica...");

		string conteudoArquivo = readText(arquivo);
		Lexer lexer = new Lexer(arquivo, conteudoArquivo, ".", error);
		Token[] tokens = lexer.tokenize();

		if (verificarErros(error))
			return false;

		if (opcoes.verboso)
			writefln("✓ Análise léxica concluída. %d tokens gerados.", tokens.length);

		if (opcoes.mostrarTokens)
			mostrarTokens(tokens);

		if (opcoes.verboso)
			writeln("[2/6] Iniciando análise sintática...");

		Parser parser = new Parser(tokens, error);
		Program program = parser.parse();

		if (verificarErros(error))
			return false;

		if (opcoes.verboso)
			writeln("✓ Análise sintática concluída.");

		if (opcoes.mostrarAST)
			program.print();

		if (opcoes.verboso)
			writeln("[3/6] Iniciando análise semântica...");

		Semantic semantic = new Semantic(error);
		Program programaSemantico = semantic.semantic(program);

		if (verificarErros(error))
			return false;

		if (opcoes.verboso)
			writeln("✓ Análise semântica concluída.");

		if (opcoes.verboso)
			writeln("[4/6] Iniciando otimização...");

		if (opcoes.otimizar)
		{
			ConstantFolding cf = new ConstantFolding(error);
			programaSemantico = cf.prog(programaSemantico);

			if (verificarErros(error))
				return false;

			if (opcoes.verboso)
				writeln("✓ Otimizações aplicadas.");
		}
		else if (opcoes.verboso)
		{
			writeln("- Otimizações desabilitadas.");
		}

		if (opcoes.verboso)
			writeln("[5/6] Gerando código IR...");

		Builder builder = new Builder(programaSemantico, semantic, target);
		builder.build();

		if (verificarErros(error))
			return false;

		string nomeBase = baseName(stripExtension(arquivo));
		arquivoTemporarioLL = nomeBase ~ ".ll";

		if (opcoes.emitirIR)
		{
			string arquivoIR = opcoes.arquivoSaida.length > 0 ? opcoes.arquivoSaida
				: arquivoTemporarioLL;
			builder.saveModule(arquivoIR);
			writefln("✓ Código IR salvo em: %s", arquivoIR);
			return true;
		}

		builder.saveModule(arquivoTemporarioLL);

		if (opcoes.verboso)
			writeln("✓ Código IR gerado.");

		if (opcoes.verboso)
			writeln("[6/6] Compilando para executável...");

		Compiler compiler = new Compiler(builder, arquivoTemporarioLL, arquivoSaida, STDLIB_DIR);
		compiler.compile();

		writefln("✓ Compilação concluída com sucesso!");
		writefln("Executável gerado: %s", arquivoSaida);

		return true;
	}
	catch (FileException e)
	{
		writefln("cgd: erro: não foi possível acessar o arquivo '%s': %s", arquivo, e.msg);
		return false;
	}
	catch (Exception e)
	{
		if (verificarErros(error))
			return false;

		writefln("cgd: erro durante o processamento: %s", e.msg);

		if (opcoes.verboso)
		{
			writeln("\n=== Informações de Debug ===");
			writeln(e.toString());
			writeln("===========================");
		}

		return false;
	}
}

bool verificarErros(DiagnosticError error)
{
	if (error.hasErrors() || error.hasWarnings())
	{
		error.printDiagnostics();
		return error.hasErrors(); // Continuar se só há warnings
	}
	return false;
}

void mostrarTokens(Token[] tokens)
{
	writeln("\n=== Tokens Gerados ===");
	foreach (i, token; tokens)
	{
		writefln("%3d: %s", i + 1, to!string(token.value));
	}
	writeln("=====================");
}

void mostrarMensagemAjuda()
{
	writefln("Uso: %s [ARQUIVO] [OPÇÕES]", NOME_PROGRAMA);
	writeln();
	writeln("ARQUIVO deve ser um arquivo fonte Delégua (.delegua ou .del)");
	writeln();
	writeln("Opções principais:");
	writeln("  -o, --output ARQUIVO     Especifica o arquivo de saída");
	writeln("  -v, --version            Mostra a versão do compilador");
	writeln("  -h, --help               Mostra esta mensagem de ajuda");
	writeln();
	writeln("Opções de compilação:");
	writeln("  -0, --optimize           Aplica otimizações ao código");
	writeln("  --eir, --emitir-ir       Salva o código IR LLVM gerado");
	writeln("  --target TARGET          Especifica o alvo de saída");
	writeln("  --verbose                Modo verboso - mostra informações detalhadas");
	writeln();
	writeln("Opções de debug:");
	writeln("  --tokens                 Mostra os tokens gerados (debug)");
	writeln("  --ast                    Mostra a árvore sintática abstrata (debug)");
	writeln();
	writeln("Targets suportados:");
	writeln("  x86_64-gnu-linux         64-bit x86, Linux (padrão)");
	writeln("  i386-gnu-linux           32-bit x86, Linux");
	writeln();
	writeln("Exemplos:");
	writeln("  cgd programa.delegua                    # Compila para executável");
	writeln("  cgd programa.delegua -o meuapp          # Especifica nome do executável");
	writeln("  cgd programa.delegua -O --verbose       # Compila com otimizações e modo verboso");
	writeln("  cgd programa.delegua --emitir-ir        # Gera apenas código IR LLVM");
	writeln("  cgd programa.delegua --target i386-gnu-linux  # Compila para 32-bit");
	writeln();
	mostrarCopyright();
}

void mostrarVersaoPrograma()
{
	writefln("%s (%s) %s", NOME_COMPLETO, NOME_PROGRAMA, VERSAO);
	writeln();
	mostrarCopyright();
}

void mostrarCopyright()
{
	writeln("MIT License");
	writeln("Copyright (C) 2025 Fernando");
	writeln("GitHub: https://github.com/fernandothedev");
	writeln();
	writeln("Este é um software livre; veja o código-fonte para condições de cópia.");
	writeln("NÃO há garantia; nem mesmo para COMERCIALIZAÇÃO ou ADEQUAÇÃO A UM");
	writeln("PROPÓSITO PARTICULAR.");
}

void exit(ExitCode code)
{
	import core.stdc.stdlib : exit;

	exit(cast(int) code);
}
