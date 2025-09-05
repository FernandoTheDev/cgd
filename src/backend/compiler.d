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
        // CodeGenerator codegen = this.builder;
        // codegen.saveToFile(filename);
        compileWithLDC();
    }

private:
    void removeTempFiles()
    {
        if (exists(this.filename))
            remove(this.filename);

        string oFile = this.filename.split(".")[0] ~ ".o";
        if (exists(oFile))
            remove(oFile);
    }

    void compileWithLDC()
    {
        string[] stdlibFiles = collectStdlibFiles();
        string[] stdTypeFiles = collectStdTypeFiles();
        string[] ldcCommand = buildLDCCommand(stdlibFiles, stdTypeFiles);

        auto result = execute(ldcCommand);

        if (result.status == 0)
        {
            writeln("✅ Compilação concluída com sucesso!");
            if (result.output.length > 0)
            {
                writeln("📝 Saída do compilador:");
                writeln(result.output);
            }
        }
        else
        {
            writeln("❌ Erro na compilação:");
            writeln(result.output);
        }

        this.removeTempFiles();
    }

    string[] collectStdlibFiles()
    {
        string[] files;

        if (!exists(stdlibPath) || !isDir(stdlibPath))
        {
            writefln("⚠️  Diretório '%s' não encontrado", stdlibPath);
            return files;
        }

        foreach (string moduleName, bool imported; this.semantic.importedModules)
        {
            if (imported)
            {
                string stdlibFile = buildPath(stdlibPath, moduleName ~ ".d");

                if (exists(stdlibFile) && isFile(stdlibFile))
                {
                    files ~= stdlibFile;
                }
                else
                {
                    writefln("⚠️  Biblioteca '%s.d' não encontrada em '%s'", moduleName, stdlibPath);
                }
            }
        }

        return files;
    }

    // TODO: Evitar essa cópia de código refatorando com o collectStdlibFiles
    string[] collectStdTypeFiles()
    {
        string[] files;
        string stdTypesPath = stdlibPath ~ "types/";

        if (!exists(stdTypesPath))
        {
            writefln("⚠️  Diretório '%s' não encontrado", stdTypesPath);
            return files;
        }

        foreach (string typeName, Primitive primitive; this.semantic.primitive.get())
        {
            string stdTypeFile = buildPath(stdlibPath ~ "types/", typeName ~ ".d");

            if (exists(stdTypeFile) && isFile(stdTypeFile))
            {
                files ~= stdTypeFile;
            }
            else
            {
                writefln("⚠️  Biblioteca '%s.d' não encontrada em '%s'", typeName, stdTypesPath);
            }
        }

        return files;
    }

    string[] buildLDCCommand(string[] stdlibFiles, string[] stdTypeFiles)
    {
        string[] command;

        // Comando base do LDC
        command ~= "ldc2";

        // Arquivo principal
        command ~= filename;

        // Arquivos da stdlib
        command ~= stdlibFiles;
        command ~= stdTypeFiles;

        command ~= "--release";

        command ~= "--Oz";

        command ~= "--ffast-math";

        command ~= "--linkonce-templates";

        command ~= "--flto=full";

        command ~= "-of=" ~ this.arquivoSaida;

        writeln("Comando: ", command);

        return command;
    }

    void compileWithVerboseOutput()
    {
        writeln("🔧 Compilando com LDC (modo verbose)...");

        string[] stdlibFiles = collectStdlibFiles();
        string[] stdTypeFiles = collectStdTypeFiles();
        string[] command = buildLDCCommand(stdlibFiles, stdTypeFiles);

        // Adicionar flags de debug/verbose
        command ~= "-v"; // Verbose
        command ~= "-g"; // Debug info

        writefln("🚀 Comando completo: %s", command.join(" "));

        auto pipes = pipeProcess(command, Redirect.all);
        scope (exit)
            wait(pipes.pid);

        // Mostrar saída em tempo real
        foreach (line; pipes.stdout.byLine)
        {
            writefln("   %s", line);
        }

        foreach (line; pipes.stderr.byLine)
        {
            writefln("⚠️  %s", line);
        }

        int exitCode = wait(pipes.pid);

        if (exitCode == 0)
        {
            writeln("✅ Compilação concluída com sucesso!");
        }
        else
        {
            writefln("❌ Compilação falhou com código: %d", exitCode);
        }

        this.removeTempFiles();
    }

    void precompileStdlib()
    {
        writeln("🔨 Pré-compilando bibliotecas padrão...");

        string[] stdlibFiles = collectStdlibFiles();

        foreach (file; stdlibFiles)
        {
            string objFile = file.stripExtension() ~ ".o";
            string[] command = ["ldc2", "-c", file, "-of=" ~ objFile];

            writefln("🔧 Compilando: %s → %s", file, objFile);

            auto result = execute(command);
            if (result.status == 0)
            {
                writefln("   ✅ %s compilado", file.baseName);
            }
            else
            {
                writefln("   ❌ Erro compilando %s:", file.baseName);
                writeln(result.output);
            }
        }
    }
}
