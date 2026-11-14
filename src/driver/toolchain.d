module driver.toolchain;

import driver.args;
import std.algorithm : canFind;
import std.array : split;
import std.file : exists, isFile, thisExePath;
import std.path : buildPath, dirName, pathSeparator, absolutePath;
import std.process : environment, execute;
import std.string : endsWith, toLower;
import std.exception : enforce;

bool executableAvailable(string command)
{
    if (command.canFind('/') || command.canFind('\\'))
        return exists(command) && isFile(command);
    foreach (dir; environment.get("PATH").split(pathSeparator))
    {
        auto path = buildPath(dir.length ? dir : ".", command);
        if (exists(path) && isFile(path))
            return true;
        version (Windows)
            foreach (suffix; environment.get("PATHEXT", ".EXE;.CMD;.BAT").split(";"))
                if (exists(path ~ suffix) && isFile(path ~ suffix))
                    return true;
    }
    return false;
}

/// O resultado é argv, nunca texto para um shell. Respeita aspas de pkg-config
/// inclusive em prefixos com espaços; não expande $, globbing ou comandos.
string[] splitToolFlags(string text)
{
    string[] result;
    string word;
    char quote = 0;
    bool escaped, started;
    foreach (ch; text)
    {
        if (escaped)
        {
            word ~= ch;
            escaped = false;
            started = true;
            continue;
        }
        if (ch == '\\' && quote != '\'')
        {
            escaped = true;
            started = true;
            continue;
        }
        if (quote)
        {
            if (ch == quote)
                quote = 0;
            else
                word ~= ch;
            started = true;
            continue;
        }
        if (ch == '\'' || ch == '"')
        {
            quote = ch;
            started = true;
            continue;
        }
        if (ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n')
        {
            if (started)
            {
                result ~= word;
                word = "";
                started = false;
            }
        }
        else
        {
            word ~= ch;
            started = true;
        }
    }
    enforce(!escaped && !quote, "Saída inválida de pkg-config: aspas/escape incompletos.");
    if (started)
        result ~= word;
    return result;
}

struct CToolchain
{
    string compiler;
    string runtimeRoot;
    string runtimeObject;
    string pkgConfig;
    string target;
    string sysroot;
    string[] cFlags;
    string[] linkFlags;

    static CToolchain discover(CGDArguments args)
    {
        CToolchain toolchain;
        toolchain.compiler = args.cc.length ? args.cc : environment.get("CC");
        if (!toolchain.compiler.length)
            foreach (candidate; ["clang", "gcc", "tcc"])
                if (executableAvailable(candidate))
                {
                    toolchain.compiler = candidate;
                    break;
                }
        enforce(toolchain.compiler.length && executableAvailable(toolchain.compiler),
                "Não foi possível encontrar um compilador C. Use --cc ou CC (somente executável).");
        toolchain.runtimeRoot = args.runtimeRoot.length ? absolutePath(args.runtimeRoot) : dirName(thisExePath());
        toolchain.runtimeObject = args.runtimeObject.length
            ? absolutePath(args.runtimeObject) : buildPath(toolchain.runtimeRoot, "lib", "libdelegua_rt.o");
        enforce(exists(toolchain.runtimeObject),
                "Runtime ausente. Execute ./build-runtime ou informe --runtime-object do alvo.");
        toolchain.pkgConfig = args.pkgConfig.length ? args.pkgConfig : environment.get("PKG_CONFIG", "pkg-config");
        enforce(executableAvailable(toolchain.pkgConfig), "pkg-config ausente. Use --pkg-config ou PKG_CONFIG.");
        toolchain.target = args.target;
        toolchain.sysroot = args.sysroot;
        toolchain.cFlags = args.cFlags;
        toolchain.linkFlags = args.linkFlags;
        return toolchain;
    }

    string[] command(string source, string output, bool optimized, string[] libraries)
    {
        auto result = [
            compiler, "-std=c99", "-Werror=implicit-function-declaration", "-Werror=return-type",
            "-Werror=incompatible-pointer-types"
        ];
        if (target.length)
            result ~= "--target=" ~ target;
        if (sysroot.length)
            result ~= "--sysroot=" ~ sysroot;
        result ~= ["-I", runtimeRoot, source, "-o", output, optimized ? "-O2" : "-O0"];
        result ~= cFlags;
        result ~= runtimeObject;
        result ~= libraries;
        // Bibliotecas do hospedeiro não são injetadas em um alvo explícito.
        if (target.length)
        {
            auto lower = target.toLower;
            if (lower.canFind("linux"))
                result ~= ["-rdynamic", "-ldl", "-lm"];
            else if (lower.canFind("darwin") || lower.canFind("apple"))
                result ~= "-lm";
        }
        else
        {
            version (linux)
                result ~= ["-rdynamic", "-ldl", "-lm"];
            else version (OSX)
                result ~= "-lm";
        }
        result ~= linkFlags;
        return result;
    }

    string[] gcFlags()
    {
        auto pkg = execute([pkgConfig, "--cflags", "--libs", "bdw-gc"]);
        enforce(pkg.status == 0, "Não foi possível localizar bdw-gc: " ~ pkg.output);
        return splitToolFlags(pkg.output);
    }
}
