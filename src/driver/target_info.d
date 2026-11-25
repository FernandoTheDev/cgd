module driver.target_info;

import driver.args;
import std.algorithm : canFind;
import std.path : baseName;
import std.string : toLower;

/// Metadados determinísticos do alvo de compilação (nunca confundindo host com target).
struct TargetInfo
{
    string os;
    string arch;
    int pointerBits = 64;
    string abi;
    string cCompiler;
    string mode;
    bool[string] features;

    static TargetInfo fromArgs(const ref CGDArguments args)
    {
        TargetInfo info;
        info.mode = args.opt ? "producao" : "desenvolvimento";
        info.cCompiler = detectCompilerName(args.cc);

        foreach (string feat; args.features)
            if (feat.length)
                info.features[feat] = true;

        if (args.target.length)
            parseTriple(args.target, info);
        else
            fillDefaultHostTarget(info);

        return info;
    }

    static TargetInfo hostDefault()
    {
        TargetInfo info;
        info.mode = "desenvolvimento";
        info.cCompiler = "clang";
        fillDefaultHostTarget(info);
        return info;
    }

    bool hasFeature(string name) const
    {
        return (name in features) !is null;
    }

    private static string detectCompilerName(string cc)
    {
        if (!cc.length)
            return "clang";
        string base = baseName(cc).toLower;
        if (base.canFind("clang"))
            return "clang";
        if (base.canFind("gcc"))
            return "gcc";
        if (base.canFind("tcc"))
            return "tcc";
        if (base.canFind("msvc") || base == "cl" || base == "cl.exe")
            return "msvc";
        return base;
    }

    private static void fillDefaultHostTarget(ref TargetInfo info)
    {
        version (linux)
            info.os = "linux";
        else version (Windows)
            info.os = "windows";
        else version (OSX)
            info.os = "macos";
        else version (FreeBSD)
            info.os = "freebsd";
        else
            info.os = "desconhecido";

        version (X86_64)
        {
            info.arch = "x86_64";
            info.pointerBits = 64;
        }
        else version (AArch64)
        {
            info.arch = "aarch64";
            info.pointerBits = 64;
        }
        else version (X86)
        {
            info.arch = "x86";
            info.pointerBits = 32;
        }
        else version (ARM)
        {
            info.arch = "arm";
            info.pointerBits = 32;
        }
        else version (RISCV64)
        {
            info.arch = "riscv64";
            info.pointerBits = 64;
        }
        else
        {
            info.arch = "desconhecido";
            info.pointerBits = cast(int)(size_t.sizeof * 8);
        }

        version (Windows)
            info.abi = "msvc";
        else version (ARM)
            info.abi = "eabi";
        else
            info.abi = "sysv";
    }

    private static void parseTriple(string triple, ref TargetInfo info)
    {
        string lower = triple.toLower;
        if (lower.canFind("x86_64") || lower.canFind("amd64"))
        {
            info.arch = "x86_64";
            info.pointerBits = 64;
        }
        else if (lower.canFind("aarch64") || lower.canFind("arm64"))
        {
            info.arch = "aarch64";
            info.pointerBits = 64;
        }
        else if (lower.canFind("riscv64"))
        {
            info.arch = "riscv64";
            info.pointerBits = 64;
        }
        else if (lower.canFind("riscv32"))
        {
            info.arch = "riscv32";
            info.pointerBits = 32;
        }
        else if (lower.canFind("i386") || lower.canFind("i686") || lower.canFind("x86"))
        {
            info.arch = "x86";
            info.pointerBits = 32;
        }
        else if (lower.canFind("wasm32"))
        {
            info.arch = "wasm32";
            info.pointerBits = 32;
        }
        else if (lower.canFind("wasm64"))
        {
            info.arch = "wasm64";
            info.pointerBits = 64;
        }
        else if (lower.canFind("arm"))
        {
            info.arch = "arm";
            info.pointerBits = 32;
        }
        else
        {
            info.arch = "x86_64";
            info.pointerBits = 64;
        }

        if (lower.canFind("windows") || lower.canFind("mingw") || lower.canFind("win32") || lower.canFind("msvc"))
            info.os = "windows";
        else if (lower.canFind("darwin") || lower.canFind("macos") || lower.canFind("apple"))
            info.os = "macos";
        else if (lower.canFind("freebsd"))
            info.os = "freebsd";
        else if (lower.canFind("android"))
            info.os = "android";
        else if (lower.canFind("linux"))
            info.os = "linux";
        else if (lower.canFind("wasi"))
            info.os = "wasi";
        else
            info.os = "desconhecido";

        if (lower.canFind("msvc"))
            info.abi = "msvc";
        else if (lower.canFind("musl"))
            info.abi = "musl";
        else if (lower.canFind("gnueabi") || lower.canFind("eabi"))
            info.abi = "eabi";
        else if (lower.canFind("gnu"))
            info.abi = "gnu";
        else if (info.os == "windows")
            info.abi = "msvc";
        else
            info.abi = "sysv";
    }
}
