module driver.args;

struct CGDArguments
{
    bool help, showVersion, showDebug, showHelp, opt, showPerf;
    bool checkOnly, emitC, debugInfo, memReport;
    string explain;
    string output, diagnostics = "texto", cc, target, sysroot, runtimeRoot, runtimeObject, pkgConfig;
    string debugMapPath, gcBackend, memOpts, memReportPath;
    string[] cFlags, linkFlags, moduleRoots, nativePackages, extraObjects, features;
}
