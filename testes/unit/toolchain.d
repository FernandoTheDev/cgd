module tests.toolchain;

import driver.toolchain;
import std.algorithm : canFind;

unittest
{
    assert(splitToolFlags(`-I'/um prefixo/include' -L/um\ prefixo/lib -lgc`) == [
        "-I/um prefixo/include", "-L/um prefixo/lib", "-lgc"
    ]);
    assert(splitToolFlags(`-DVAL="a b" '$(literal)'`) == ["-DVAL=a b", "$(literal)"]);
    bool failed;
    try
        splitToolFlags("'incompleto");
    catch (Exception)
        failed = true;
    assert(failed);
}

unittest
{
    CToolchain toolchain;
    toolchain.compiler = "clang";
    toolchain.runtimeRoot = "/prefixo com espaços";
    toolchain.runtimeObject = "/alvo/runtime.o";
    toolchain.target = "x86_64-w64-windows-gnu";
    toolchain.sysroot = "/sdk";
    string[] args = toolchain.command("arquivo $(literal).c", "programa.exe", true, ["-lgc"]);
    assert(args.canFind("--target=x86_64-w64-windows-gnu"));
    assert(args.canFind("--sysroot=/sdk"));
    assert(args.canFind("arquivo $(literal).c"));
    assert(!args.canFind("-ldl") && !args.canFind("-rdynamic"));
    toolchain.target = "aarch64-linux-gnu";
    assert(toolchain.command("a.c", "a", false, []).canFind("-ldl"));
}
