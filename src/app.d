import std.stdio;
import std.getopt;
import std.file;
import std.path;
import std.process : environment;
import std.array : split;
import std.string : format;
import frontend.lexer.lexer;
import frontend.lexer.token;
import frontend.parser.parser;
import frontend.parser.ast;
import middle.semantic;
import middle.optmizer.constant_folding;
import backend.builder;
import backend.compiler;
import error;

alias fileWrite = std.file.write;

string HOME, MAIN_DIR, STDLIB_DIR;

enum string VERSAO = "v0.0.6";
enum string NOME_PROGRAMA = "cgd";
enum string NOME_COMPLETO = "Compilador Geral Delégua";

void main(string[] args)
{
	version (Posix)
	{
		HOME = environment.get("HOME");
		MAIN_DIR = HOME ~ "/.cgd/";
		STDLIB_DIR = HOME ~ "/.cgd/stdlib/";

		if (!exists(MAIN_DIR) || !exists(STDLIB_DIR))
		{
			// erro
			writefln("Erro ao buscar diretório principal '%s', reinstale o compilador.", MAIN_DIR);
			return;
		}
	}
	else version (Windows)
	{
		// sem suporte.
		return;
	}

	string arquivoSaida = "";
	bool mostrarVersao = false;
	bool emitir_ll = false;
	bool mostrarAjuda = false;
	bool verboso = false;
	bool bigO;

	try
	{
		getopt(args,
			"o|output", "Especifica o arquivo de saída", &arquivoSaida,
			"eir|emitir-ir", "Salva o código IR gerado pelo compilador", &emitir_ll,
			"v|version", "Mostra a versão do compilador", &mostrarVersao,
			"0|optimize", "Aplica otimizações ao código", &bigO,
			"h|help", "Mostra esta mensagem de ajuda", &mostrarAjuda,
			"verbose", "Modo verboso - mostra informações detalhadas", &verboso
		);

		if (mostrarVersao)
		{
			mostrarVersaoPrograma();
			return;
		}

		if (mostrarAjuda || args.length < 2)
		{
			mostrarMensagemAjuda();
			return;
		}

		if (args.length < 2)
		{
			writeln("cgd: erro: arquivo não especificado");
			writeln("Digite 'cgd --help' para mais informações.");
			return;
		}

		string arquivo = args[1];

		if (!exists(arquivo))
		{
			writefln("cgd: erro: arquivo '%s' não encontrado", arquivo);
			return;
		}

		if (!isFile(arquivo))
		{
			writefln("cgd: erro: '%s' não é um arquivo válido", arquivo);
			return;
		}

		string nomeBase = baseName(stripExtension(arquivo));
		if (arquivoSaida.length == 0)
		{
			arquivoSaida = nomeBase;
		}

		if (verboso)
		{
			writefln("Processando arquivo: %s", arquivo);
			writefln("Arquivo de saída: %s", arquivoSaida);
		}

		processarArquivo(arquivo, arquivoSaida, verboso, bigO, emitir_ll);

	}
	catch (GetOptException e)
	{
		writefln("cgd: erro: %s", e.msg);
		writeln("Digite 'cgd --help' para mais informações.");
	}
	catch (Exception e)
	{
		writefln("cgd: erro interno: %s", e.msg);
		if (verboso)
		{
			writeln("Informações de debug:");
			writeln(e.toString());
		}
	}
}

void mostrarMensagemAjuda()
{
	writeln("Uso: cgd [ARQUIVO] [OPÇÕES]");
	writeln("");
	writeln("Opções:");
	writeln("  -o, --output ARQUIVO  Especifica o arquivo de saída");
	writeln("  -v, --version         Mostra a versão do compilador");
	writeln("  -h, --help            Mostra esta mensagem de ajuda");
	writeln("  -0, --optimize        Aplica otimizações ao código");
	writeln("  --eir, --emitir-ir    Salva o código IR gerado pelo compilador");
	writeln("  --verbose             Modo verboso - mostra informações detalhadas");
	writeln("");
	writeln("Exemplos:");
	writeln("  cgd arquivo.delegua");
	writeln("  cgd arquivo.delegua --emitir-ir -o saida.ll");
	writeln("  cgd arquivo.delegua --output meuapp");
	writeln("");
	mostrarCopyright();
}

void mostrarVersaoPrograma()
{
	writefln("%s (%s) %s", NOME_COMPLETO, NOME_PROGRAMA, VERSAO);
}

void mostrarCopyright()
{
	writeln("MIT License");
	writeln("Copyright (C) 2025 Fernando");
	writeln("GitHub: https://github.com/fernandothedev");
	writeln("");
	writeln("Este é um software livre; veja o código-fonte para condições de cópia.");
	writeln("NÃO há garantia; nem mesmo para COMERCIALIZAÇÃO ou ADEQUAÇÃO A UM");
	writeln("PROPÓSITO PARTICULAR.");
}

bool checkErrors(DiagnosticError error)
{
	if (error.hasErrors() || error.hasWarnings())
	{
		error.printDiagnostics();
		return true;
	}
	return false;
}

void processarArquivo(string arquivo, string arquivoSaida, bool verboso, bool bigO, bool emitir_ll)
{
	DiagnosticError error = new DiagnosticError();
	try
	{
		if (verboso)
		{
			writeln("Iniciando análise léxica...");
		}

		string nomeArquivo = baseName(stripExtension(arquivo));
		string conteudoArquivo = readText(arquivo);

		Lexer lexer = new Lexer(arquivo, conteudoArquivo, ".", error);
		Token[] tokens = lexer.tokenize();

		if (checkErrors(error))
			return;

		if (verboso)
		{
			writefln("Análise léxica concluída. %d tokens gerados.", tokens.length);
			writeln("Iniciando análise sintática...");
		}

		Parser parser = new Parser(tokens, error);
		Program program = parser.parse();

		if (checkErrors(error))
			return;

		if (verboso)
			program.print();

		if (verboso)
		{
			writeln("Análise sintática concluída.");
			writeln("Iniciando análise semântica...");
		}

		Semantic semantic = new Semantic(error);
		Program newProgram = semantic.semantic(program);

		if (checkErrors(error))
			return;

		if (verboso)
		{
			writeln("Análise semântica concluída.");
			writeln("Iniciando otimização...");
		}

		if (bigO)
		{
			ConstantFolding cf = new ConstantFolding(error);
			newProgram = cf.prog(newProgram);
		}

		Builder builder = new Builder(newProgram, semantic);
		builder.build();

		if (checkErrors(error))
			return;

		string file = nomeArquivo ~ ".ll";

		if (emitir_ll && arquivoSaida != "")
		{
			builder.saveModule(cast(const char*) arquivoSaida);
			return;
		}

		builder.saveModule(cast(const char*) file);

		Compiler compiler = new Compiler(builder, file, arquivoSaida, STDLIB_DIR);
		compiler.compile();

		remove(file);
		writefln("Compilação concluída com sucesso. Executável gerado: %s", arquivoSaida);
	}
	catch (FileException e)
	{
		writefln("cgd: erro: não foi possível ler o arquivo '%s': %s", arquivo, e.msg);
	}
	catch (Exception e)
	{
		if (checkErrors(error))
			return;

		writefln("cgd: erro durante o processamento: %s", e.msg);
		if (verboso)
		{
			writeln("Detalhes do erro:");
			writeln(e.toString());
		}
	}
}
