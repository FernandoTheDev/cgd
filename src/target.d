module target;

import std.system : os, OS;
import std.process : environment;
import std.string : toLower;
import std.algorithm : canFind;

struct TargetInfo
{
    string triple;
    string[] initFunctions;
}

TargetInfo getTarget()
{
    version (Windows)
    {
        return getWindowsTarget();
    }
    else version (linux)
    {
        return getLinuxTarget();
    }
    else version (OSX)
    {
        return getMacOSTarget();
    }
    else version (FreeBSD)
    {
        return getFreeBSDTarget();
    }
    else
    {
        // Fallback genérico
        return TargetInfo("x86_64-unknown-unknown", ["X86"]);
    }
}

private TargetInfo getWindowsTarget()
{
    version (X86_64)
    {
        return TargetInfo("x86_64-pc-windows-msvc", ["X86"]);
    }
    else version (X86)
    {
        return TargetInfo("i686-pc-windows-msvc", ["X86"]);
    }
    else version (AArch64)
    {
        return TargetInfo("aarch64-pc-windows-msvc", ["AArch64"]);
    }
    else
    {
        return TargetInfo("x86_64-pc-windows-msvc", ["X86"]);
    }
}

private TargetInfo getLinuxTarget()
{
    version (X86_64)
    {
        return TargetInfo("x86_64-unknown-linux-gnu", ["X86"]);
    }
    else version (X86)
    {
        return TargetInfo("i686-unknown-linux-gnu", ["X86"]);
    }
    else version (AArch64)
    {
        return TargetInfo("aarch64-unknown-linux-gnu", ["AArch64"]);
    }
    else version (ARM)
    {
        return TargetInfo("arm-unknown-linux-gnueabi", ["ARM"]);
    }
    else
    {
        return TargetInfo("x86_64-unknown-linux-gnu", ["X86"]);
    }
}

private TargetInfo getMacOSTarget()
{
    version (X86_64)
    {
        return TargetInfo("x86_64-apple-darwin", ["X86"]);
    }
    else version (AArch64)
    {
        return TargetInfo("arm64-apple-darwin", ["AArch64"]);
    }
    else
    {
        return TargetInfo("x86_64-apple-darwin", ["X86"]);
    }
}

private TargetInfo getFreeBSDTarget()
{
    version (X86_64)
    {
        return TargetInfo("x86_64-unknown-freebsd", ["X86"]);
    }
    else version (X86)
    {
        return TargetInfo("i686-unknown-freebsd", ["X86"]);
    }
    else
    {
        return TargetInfo("x86_64-unknown-freebsd", ["X86"]);
    }
}

TargetInfo createCustomTarget(string triple)
{
    string[] initFuncs;

    // Detecta a arquitetura baseada no triple
    if (triple.canFind("x86_64") || triple.canFind("i686") || triple.canFind("i386"))
    {
        initFuncs = ["X86"];
    }
    else if (triple.canFind("aarch64") || triple.canFind("arm64"))
    {
        initFuncs = ["AArch64"];
    }
    else if (triple.canFind("arm"))
    {
        initFuncs = ["ARM"];
    }
    else
    {
        // Fallback para X86
        initFuncs = ["X86"];
    }

    return TargetInfo(triple, initFuncs);
}
