module driver.args;

struct CGDArguments
{
    bool help, showVersion, showDebug, showHelp, opt, showPerf;
    bool checkOnly, emitC;
    string explain;
    string output, diagnostics = "texto", cc, target, sysroot, runtimeRoot, runtimeObject, pkgConfig;
    string[] cFlags, linkFlags;
}
