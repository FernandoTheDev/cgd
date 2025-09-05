module backend.compiler;

import std.stdio;
import std.format;
import std.file;
import std.path;
import std.process;
import std.array : split;
import std.string;
import std.array;
import backend.codegen.core;
import backend.builder;
import middle.semantic;
import middle.stdlib.primitives;
import middle.stdlib.std_lib_module_builder;

class Compiler
{
private:
    Builder builder;
    Semantic semantic;
    string filename;
    string arquivoSaida;
    string stdlibPath;

public:
    this(Builder builder, string filename, string arquivoSaida, string stdlibpath)
    {
        this.builder = builder;
        this.semantic = builder.semantic;
        this.filename = filename;
        this.arquivoSaida = arquivoSaida;
        this.stdlibPath = stdlibpath;
    }

    void compile()
    {
        compileWithClang();
    }

private:
    void compileWithClang()
    {
        string[] clangCommand = buildClangCommand();

        auto result = execute(clangCommand);

        if (!(result.status == 0))
        {
            writeln("❌ Erro na compilação:");
            writeln(result.output);
        }

    }

    string[] buildClangCommand()
    {
        string[] command;

        command ~= "clang";
        command ~= filename;
        command ~= "-o";
        command ~= arquivoSaida;
        command ~= "-Woverride-module";

        writeln("Comando: ", command);
        return command;
    }
}
