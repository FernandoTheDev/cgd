module dap.server;

import core.sync.condition : Condition;
import core.sync.mutex : Mutex;
import core.thread : Thread;
import std.algorithm : canFind, endsWith, startsWith;
import std.array : Appender, appender, join, replace, split;
import std.conv : to;
import std.file : exists, isFile, mkdirRecurse, readText, tempDir;
import std.format : format;
import std.json;
import std.path : absolutePath, asNormalizedPath, baseName, buildPath, dirName, extension, stripExtension;
import std.process : Pid, ProcessPipes, Redirect, kill, pipeProcess, spawnProcess, wait;
import std.stdio : File, stderr, stdin, stdout, writefln, writeln;
import std.string : indexOf, strip;

import backend.c.utils : cName;
import driver.args;
import driver.compile;
import driver.project;
import driver.toolchain : executableAvailable;
import env : VERSION;
import utils : cgd_erro;

/// Decodifica um identificador C emitido por `cName` (`cgd_user_78_79`) para o nome Delégua original.
string decodeCgdUserName(string raw)
{
    if (raw == "cgd_self")
        return "isto";
    if (raw.endsWith("_ptr") && raw.startsWith("cgd_user_"))
        raw = raw[0 .. $ - 4];
    if (!raw.startsWith("cgd_user_"))
        return raw;
    string rest = raw[9 .. $];
    string[] hexParts = rest.split("_");
    dstring decoded;
    foreach (string part; hexParts)
    {
        if (!part.length)
            return raw;
        uint cp = 0;
        foreach (char ch; part)
        {
            uint d;
            if (ch >= '0' && ch <= '9')
                d = cast(uint)(ch - '0');
            else if (ch >= 'a' && ch <= 'f')
                d = cast(uint)(10 + ch - 'a');
            else if (ch >= 'A' && ch <= 'F')
                d = cast(uint)(10 + ch - 'A');
            else
                return raw;
            cp = (cp << 4) | d;
        }
        decoded ~= cast(dchar) cp;
    }
    return decoded.to!string;
}

private bool isInternalCVariable(string rawName, string decoded)
{
    if (!rawName.length)
        return true;
    if (rawName.startsWith("cgd_tmp_") || rawName.startsWith("cgd_ic")
            || rawName.startsWith("cgd_cond_") || rawName.startsWith("cgd_map_")
            || rawName.startsWith("cgd_loop_") || rawName.startsWith("cgd_comp_")
            || rawName.startsWith("cgd_args_") || rawName.startsWith("cgd_ffi_")
            || rawName.startsWith("cgd_nt_") || rawName.startsWith("cgd_mv_")
            || rawName.startsWith("cgd_ret_") || rawName.startsWith("cgd_op_")
            || rawName.startsWith("cgd_uop_") || rawName.startsWith("cgd_iop_")
            || rawName.startsWith("cgd_addr_") || rawName.startsWith("cgd_mk_")
            || rawName.startsWith("cgd_ta_") || rawName.startsWith("cgd_ca_")
            || rawName == "cgd_self_val" || rawName == "cgd_v" || rawName == "cgd_res"
            || rawName == "argc" || rawName == "argv")
        return true;
    if (rawName.length >= 2 && rawName[0] == 't' && rawName[1] >= '0' && rawName[1] <= '9')
        return true;
    if (decoded.startsWith("#"))
        return true;
    return false;
}

private string unescapeMiString(string s)
{
    Appender!string buf = appender!string();
    for (size_t i = 0; i < s.length; i++)
    {
        if (s[i] == '\\' && i + 1 < s.length)
        {
            char n = s[++i];
            if (n == 'n')
                buf.put('\n');
            else if (n == 'r')
                buf.put('\r');
            else if (n == 't')
                buf.put('\t');
            else if (n == '"')
                buf.put('"');
            else if (n == '\\')
                buf.put('\\');
            else
                buf.put(n);
        }
        else
            buf.put(s[i]);
    }
    return buf.data;
}

private string extractMiField(string record, string key)
{
    string needle = key ~ "=\"";
    ptrdiff_t idx = record.indexOf(needle);
    if (idx < 0)
        return "";
    size_t pos = cast(size_t) idx + needle.length;
    Appender!string buf = appender!string();
    while (pos < record.length)
    {
        char ch = record[pos++];
        if (ch == '\\' && pos < record.length)
        {
            buf.put(ch);
            buf.put(record[pos++]);
            continue;
        }
        if (ch == '"')
            break;
        buf.put(ch);
    }
    return unescapeMiString(buf.data);
}

private string[] extractMiObjects(string record, string prefix)
{
    string[] items;
    size_t cursor = 0;
    while (cursor < record.length)
    {
        ptrdiff_t rel = record[cursor .. $].indexOf(prefix);
        if (rel < 0)
            break;
        size_t start = cursor + cast(size_t) rel + prefix.length;
        int depth = 1;
        bool inStr = false;
        size_t i = start;
        while (i < record.length && depth > 0)
        {
            char ch = record[i++];
            if (inStr)
            {
                if (ch == '\\' && i < record.length)
                    i++;
                else if (ch == '"')
                    inStr = false;
            }
            else
            {
                if (ch == '"')
                    inStr = true;
                else if (ch == '{')
                    depth++;
                else if (ch == '}')
                    depth--;
            }
        }
        if (depth == 0)
        {
            items ~= record[start .. i - 1];
            cursor = i;
        }
        else
            break;
    }
    return items;
}

private struct ScopeRef
{
    int frameId;
    string expr; // vazio = locals do frame; não-vazio = expressão vetor/objeto expansível
    int kind;    // 0 = locals, 1 = vetor/tupla
    int length;
}

class DapServer
{
    private Mutex sendMutex;
    private Mutex miMutex;
    private Condition miCond;

    private int nextSeq = 1;
    private int nextToken = 100;
    private string[int] miResponses;
    private bool gdbRunning = false;
    private bool inferiorRunning = false;
    private bool stopOnEntry = false;
    private bool terminatedSent = false;
    private bool shuttingDown = false;

    private ProcessPipes gdb;
    private Thread readerThread;

    private string binaryPath;
    private string entrySource;
    private string[string] fnDisplayMap;
    private string[string] fnReverseMap;
    private int[][string] breakpointsByFile;
    private int[] functionBpNumbers;
    private int[] exceptionBpNumbers;

    private ScopeRef[int] varRefs;
    private int nextVarRef = 1;

    this()
    {
        sendMutex = new Mutex();
        miMutex = new Mutex();
        miCond = new Condition(miMutex);
    }

    private void sendMessage(JSONValue msg)
    {
        synchronized (sendMutex)
        {
            msg["seq"] = JSONValue(nextSeq++);
            string payload = msg.toString();
            stdout.write("Content-Length: ", payload.length, "\r\n\r\n", payload);
            stdout.flush();
        }
    }

    private void sendResponse(int reqSeq, string command, bool success, JSONValue body = JSONValue.init,
            string message = "")
    {
        JSONValue[string] resp;
        resp["type"] = JSONValue("response");
        resp["request_seq"] = JSONValue(reqSeq);
        resp["success"] = JSONValue(success);
        resp["command"] = JSONValue(command);
        if (!success && message.length)
            resp["message"] = JSONValue(message);
        if (body.type != JSONType.null_)
            resp["body"] = body;
        sendMessage(JSONValue(resp));
    }

    private void sendEvent(string eventName, JSONValue body = JSONValue.init)
    {
        JSONValue[string] ev;
        ev["type"] = JSONValue("event");
        ev["event"] = JSONValue(eventName);
        if (body.type != JSONType.null_)
            ev["body"] = body;
        sendMessage(JSONValue(ev));
    }

    private void sendOutput(string text, string category = "stdout")
    {
        if (!text.length)
            return;
        sendEvent("output", JSONValue([
            "category": JSONValue(category),
            "output": JSONValue(text)
        ]));
    }

    private string gdbCommand(string cmd)
    {
        if (!gdbRunning)
            return "^error,msg=\"GDB não está ativo.\"";
        int tok;
        synchronized (miMutex)
        {
            tok = nextToken++;
            gdb.stdin.writefln("%d%s", tok, cmd);
            gdb.stdin.flush();
            while ((tok in miResponses) is null && gdbRunning)
                miCond.wait();
            if (string* resp = tok in miResponses)
            {
                string val = *resp;
                miResponses.remove(tok);
                return val;
            }
        }
        return "^error,msg=\"GDB encerrado.\"";
    }

    private void gdbReaderLoop()
    {
        try
        {
            while (gdbRunning)
            {
                string line = gdb.stdout.readln();
                if (line is null)
                    break;
                string trimmed = line.strip();
                if (!trimmed.length || trimmed == "(gdb)")
                    continue;

                // Result record com token numérico: e.g. 101^done,...
                size_t digitEnd = 0;
                while (digitEnd < trimmed.length && trimmed[digitEnd] >= '0' && trimmed[digitEnd] <= '9')
                    digitEnd++;
                if (digitEnd > 0 && digitEnd < trimmed.length && trimmed[digitEnd] == '^')
                {
                    int tok = trimmed[0 .. digitEnd].to!int;
                    string payload = trimmed[digitEnd .. $];
                    synchronized (miMutex)
                    {
                        miResponses[tok] = payload;
                        miCond.notifyAll();
                    }
                    continue;
                }

                if (trimmed.startsWith("*stopped"))
                {
                    inferiorRunning = false;
                    string reason = extractMiField(trimmed, "reason");
                    string tidStr = extractMiField(trimmed, "thread-id");
                    int tid = tidStr.length ? tidStr.to!int : 1;

                    if (reason == "exited-normally" || reason == "exited" || reason == "exited-signalled")
                    {
                        string exitCodeStr = extractMiField(trimmed, "exit-code");
                        int exitCode = 0;
                        if (exitCodeStr.length)
                        {
                            try
                                exitCode = exitCodeStr.to!int;
                            catch (Exception)
                                exitCode = 0;
                        }
                        if (!terminatedSent)
                        {
                            terminatedSent = true;
                            sendEvent("exited", JSONValue(["exitCode": JSONValue(exitCode)]));
                            sendEvent("terminated", JSONValue.emptyObject);
                        }
                    }
                    else
                    {
                        string dapReason = "pause";
                        if (reason == "breakpoint-hit")
                            dapReason = "breakpoint";
                        else if (reason == "end-stepping-range" || reason == "function-finished")
                            dapReason = "step";
                        else if (reason == "signal-received")
                            dapReason = "exception";
                        sendEvent("stopped", JSONValue([
                            "reason": JSONValue(dapReason),
                            "threadId": JSONValue(tid),
                            "allThreadsStopped": JSONValue(true)
                        ]));
                    }
                    continue;
                }

                if (trimmed.startsWith("*running"))
                {
                    inferiorRunning = true;
                    continue;
                }

                if (trimmed.startsWith("@\""))
                {
                    string content = unescapeMiString(trimmed[2 .. $ - 1]);
                    sendOutput(content, "stdout");
                    continue;
                }

                if (trimmed.startsWith("~\"") || trimmed.startsWith("&\"") || trimmed.startsWith("=")
                        || trimmed.startsWith("^"))
                    continue;

                // Saída direta stdout do processo alvo misturada no pipe
                sendOutput(line, "stdout");
            }
        }
        catch (Exception)
        {
        }
        synchronized (miMutex)
        {
            gdbRunning = false;
            miCond.notifyAll();
        }
        if (!terminatedSent && !shuttingDown)
        {
            terminatedSent = true;
            sendEvent("terminated", JSONValue.emptyObject);
        }
    }

    private void loadDebugMetadata(string metaPath)
    {
        fnDisplayMap = null;
        fnReverseMap = null;
        fnDisplayMap["delegua_main"] = "<principal>";
        if (!exists(metaPath) || !isFile(metaPath))
            return;
        try
        {
            JSONValue meta = parseJSON(readText(metaPath));
            if (const(JSONValue)* pFns = "funcoes" in meta)
            {
                if (pFns.type == JSONType.object)
                {
                    foreach (string k, JSONValue v; pFns.object)
                    {
                        if (v.type == JSONType.string)
                        {
                            fnDisplayMap[k] = v.str;
                            fnReverseMap[v.str] = k;
                        }
                    }
                }
            }
        }
        catch (Exception)
        {
        }
    }

    private string compileTargetForDebug(string programPath, string cwd, string mode)
    {
        string targetBin;
        string metaPath;
        if (programPath.length && exists(programPath) && isFile(programPath) && extension(programPath) == ".delegua")
        {
            entrySource = absolutePath(programPath).asNormalizedPath.to!string;
            string outDir = buildPath(tempDir(), "cgd-dap");
            mkdirRecurse(outDir);
            string base = stripExtension(baseName(entrySource));
            targetBin = buildPath(outDir, base ~ "_dbg");
            metaPath = targetBin ~ ".cgd.dbg.json";

            CGDArguments cgdArgs;
            cgdArgs.opt = (mode == "producao");
            cgdArgs.debugInfo = true;
            cgdArgs.output = targetBin;
            cgdArgs.debugMapPath = metaPath;

            string projRoot = findProjectRoot(dirName(entrySource));
            if (projRoot.length)
            {
                ProjectConfig cfg = loadProject(projRoot);
                cgdArgs.moduleRoots = [buildPath(cfg.rootDir, cfg.diretorioFontes), cfg.rootDir];
                foreach (string lib; cfg.bibliotecasNativas)
                    if (lib == "gtk4" || lib == "sdl3" || lib == "ncursesw")
                        cgdArgs.nativePackages ~= lib;
            }
            compile(cgdArgs, entrySource);
        }
        else
        {
            string startDir = cwd.length ? cwd : ".";
            string projRoot = findProjectRoot(startDir);
            if (!projRoot.length)
                throw new Exception("Nenhum arquivo .delegua ou projeto.json encontrado para depuração.");
            ProjectConfig cfg = loadProject(projRoot);
            entrySource = validateProjectPath(cfg.rootDir, cfg.entrada, "entrada");
            targetBin = validateProjectPath(cfg.rootDir, cfg.saida, "saida") ~ "_dbg";
            metaPath = targetBin ~ ".cgd.dbg.json";

            CGDArguments cgdArgs;
            cgdArgs.opt = (mode == "producao");
            cgdArgs.debugInfo = true;
            cgdArgs.output = targetBin;
            cgdArgs.debugMapPath = metaPath;
            cgdArgs.moduleRoots = [buildPath(cfg.rootDir, cfg.diretorioFontes), cfg.rootDir];
            foreach (string lib; cfg.bibliotecasNativas)
                if (lib == "gtk4" || lib == "sdl3" || lib == "ncursesw")
                    cgdArgs.nativePackages ~= lib;
            compile(cgdArgs, entrySource);
        }
        loadDebugMetadata(metaPath);
        return targetBin;
    }

    private string evalExpr(int frameId, string expr)
    {
        string escaped = expr.replace("\\", "\\\\").replace("\"", "\\\"");
        string resp = gdbCommand(format("-data-evaluate-expression --thread 1 --frame %d \"%s\"", frameId, escaped));
        if (!resp.startsWith("^done"))
            return "";
        return extractMiField(resp, "value");
    }

    private string decodeStructDisplay(string rawVal)
    {
        if (!rawVal.startsWith("{") || !rawVal.endsWith("}"))
            return rawVal;
        string inner = rawVal[1 .. $ - 1].strip();
        string[] parts = inner.split(",");
        string[] formatted;
        foreach (string part; parts)
        {
            string p = part.strip();
            ptrdiff_t eq = p.indexOf("=");
            if (eq > 0)
            {
                string fname = decodeCgdUserName(p[0 .. cast(size_t) eq].strip());
                string fval = p[cast(size_t) eq + 1 .. $].strip();
                formatted ~= fname ~ " = " ~ fval;
            }
            else if (p.length)
                formatted ~= p;
        }
        return "{" ~ formatted.join(", ") ~ "}";
    }

    private void formatNativeCExpr(int frameId, string expr, string rawVal, out string outValue,
            out string outType, out int outVarRef)
    {
        outVarRef = 0;
        if (rawVal.canFind("<optimized out>"))
        {
            outValue = "<otimizado pelo compilador>";
            outType = "otimizado";
            return;
        }
        // Verifica se é VetorNativo (`data`, `len`, `cap`)
        if (rawVal.canFind("data =") && rawVal.canFind("len =") && rawVal.canFind("cap ="))
        {
            string lenStr = evalExpr(frameId, "(int)(" ~ expr ~ ").len");
            int len = 0;
            try
                len = lenStr.split(" ")[0].to!int;
            catch (Exception)
                len = 0;
            outType = "VetorNativo";
            outValue = format("VetorNativo[%d]", len);
            if (len > 0)
            {
                outVarRef = nextVarRef++;
                varRefs[outVarRef] = ScopeRef(frameId, expr, 2, len);
            }
            return;
        }
        // Verifica se é StringNativa / VisaoTexto (`ptr`, `len`)
        if (rawVal.canFind("ptr =") && rawVal.canFind("len ="))
        {
            string ptrStr = evalExpr(frameId, "(" ~ expr ~ ").ptr");
            outType = rawVal.canFind("cap =") ? "StringNativa" : "VisaoTexto";
            outValue = ptrStr.length ? ptrStr : rawVal;
            return;
        }
        // Struct de valor @pilha (`{cgd_user_... = ...}`)
        if (rawVal.startsWith("{") && rawVal.endsWith("}"))
        {
            outType = "@pilha struct";
            outValue = decodeStructDisplay(rawVal);
            outVarRef = nextVarRef++;
            varRefs[outVarRef] = ScopeRef(frameId, expr, 3, 0);
            return;
        }
        // Escalares C nativos (int8..uint64, float, double, bool)
        if (rawVal == "true" || rawVal == "false")
        {
            outType = "cbool";
            outValue = rawVal == "true" ? "verdadeiro" : "falso";
            return;
        }
        outValue = rawVal;
        outType = rawVal.canFind(".") ? "cf64" : "ci64";
    }

    private void formatDeleguaExpr(int frameId, string expr, out string outValue, out string outType,
            out int outVarRef)
    {
        outVarRef = 0;
        string tStr = evalExpr(frameId, "(int)(" ~ expr ~ ").type");
        if (!tStr.length)
        {
            string rawVal = evalExpr(frameId, expr);
            formatNativeCExpr(frameId, expr, rawVal, outValue, outType, outVarRef);
            return;
        }
        if (tStr.canFind("<optimized out>"))
        {
            outValue = "<otimizado pelo compilador>";
            outType = "otimizado";
            return;
        }
        int t = 0;
        try
            t = tStr.split(" ")[0].to!int;
        catch (Exception)
        {
            outValue = tStr;
            outType = "desconhecido";
            return;
        }

        switch (t)
        {
            case 0: // DELEGUA_T_NULO
                outValue = "nulo";
                outType = "nulo";
                return;
            case 2: // DELEGUA_T_BOOL
                string bVal = evalExpr(frameId, "(int)(" ~ expr ~ ").value.b1");
                outValue = (bVal == "0" || bVal == "false") ? "falso" : "verdadeiro";
                outType = "logico";
                return;
            case 3: // DELEGUA_T_NUM
                outValue = evalExpr(frameId, "(" ~ expr ~ ").value.num");
                outType = "inteiro";
                return;
            case 4: // DELEGUA_T_REAL
                outValue = evalExpr(frameId, "(" ~ expr ~ ").value.real");
                outType = "real";
                return;
            case 5: // DELEGUA_T_TEXT
                string rawText = evalExpr(frameId, "(" ~ expr ~ ").value.text.ptr");
                ptrdiff_t qIdx = rawText.indexOf('"');
                outValue = qIdx >= 0 ? rawText[qIdx .. $] : rawText;
                outType = "texto";
                return;
            case 6: // DELEGUA_T_VETOR
            case 7: // DELEGUA_T_TUPLA
                string szStr = evalExpr(frameId, "(" ~ expr ~ ").value.vetor->size");
                int len = 0;
                try
                    len = szStr.to!int;
                catch (Exception)
                    len = 0;
                outType = t == 6 ? "vetor" : "tupla";
                outValue = format("%s[%d]", outType, len);
                if (len > 0)
                {
                    int refId = nextVarRef++;
                    varRefs[refId] = ScopeRef(frameId, expr, 1, len);
                    outVarRef = refId;
                }
                return;
            case 8: // DELEGUA_T_MAP
                outType = "dicionario";
                outValue = "{...}";
                return;
            case 9: // DELEGUA_T_CLASSE
                outType = "classe";
                outValue = "<classe>";
                return;
            case 10: // DELEGUA_T_OBJETO
                outType = "objeto";
                outValue = "<objeto>";
                return;
            case 11: // DELEGUA_T_FUNCAO
                outType = "funcao";
                outValue = "<funcao>";
                return;
            case 13: // DELEGUA_T_MODULO
                outType = "modulo";
                outValue = "<modulo>";
                return;
            case 16:
                outType = "Promessa";
                outValue = "<Promessa>";
                return;
            case 17:
                outType = "Tarefa";
                outValue = "<Tarefa>";
                return;
            case 19:
                outType = "Bytes";
                outValue = "<Bytes>";
                return;
            default:
                outType = "qualquer";
                outValue = "<valor>";
                return;
        }
    }

    private void handleRequest(JSONValue req)
    {
        int reqSeq = cast(int) req["seq"].integer;
        string cmd = req["command"].str;
        JSONValue args = ("arguments" in req) ? req["arguments"] : JSONValue.emptyObject;

        if (cmd == "initialize")
        {
            JSONValue caps = JSONValue([
                "supportsConfigurationDoneRequest": JSONValue(true),
                "supportsConditionalBreakpoints": JSONValue(true),
                "supportsFunctionBreakpoints": JSONValue(true),
                "supportsEvaluateForHovers": JSONValue(true),
                "supportsTerminateRequest": JSONValue(true),
                "exceptionBreakpointFilters": JSONValue([
                    JSONValue([
                        "filter": JSONValue("all"),
                        "label": JSONValue("Todas as exceções Delégua"),
                        "default": JSONValue(false)
                    ])
                ])
            ]);
            sendResponse(reqSeq, cmd, true, caps);
            return;
        }

        if (cmd == "launch")
        {
            if (!executableAvailable("gdb"))
            {
                sendResponse(reqSeq, cmd, false, JSONValue.init,
                        "GDB não encontrado no PATH. Instale 'gdb' para depurar programas CGD.");
                return;
            }
            string prog = ("program" in args && args["program"].type == JSONType.string) ? args["program"].str : "";
            string cwd = ("cwd" in args && args["cwd"].type == JSONType.string) ? args["cwd"].str : "";
            string mode = ("modo" in args && args["modo"].type == JSONType.string) ? args["modo"].str : "desenvolvimento";
            stopOnEntry = ("stopOnEntry" in args && args["stopOnEntry"].type == JSONType.true_);

            try
            {
                binaryPath = compileTargetForDebug(prog, cwd, mode);
            }
            catch (Exception e)
            {
                sendResponse(reqSeq, cmd, false, JSONValue.init, "Falha na compilação para depuração: " ~ e.msg);
                return;
            }

            string[] gdbCmd = ["gdb", "--interpreter=mi2", "--quiet", "--nx", binaryPath];
            gdb = pipeProcess(gdbCmd, Redirect.stdin | Redirect.stdout | Redirect.stderrToStdout);
            gdbRunning = true;
            terminatedSent = false;
            readerThread = new Thread(&gdbReaderLoop);
            readerThread.isDaemon = true;
            readerThread.start();

            if (cwd.length && exists(cwd))
                gdbCommand(format("-environment-cd \"%s\"", cwd.replace("\"", "\\\"")));
            if ("args" in args && args["args"].type == JSONType.array && args["args"].array.length > 0)
            {
                string[] progArgs;
                foreach (JSONValue a; args["args"].array)
                    if (a.type == JSONType.string)
                        progArgs ~= "\"" ~ a.str.replace("\"", "\\\"") ~ "\"";
                if (progArgs.length)
                    gdbCommand("-exec-arguments " ~ progArgs.join(" "));
            }
            // Desabilita buffering de stdout/stderr no GDB e evita parar em sinais internos do Boehm GC
            gdbCommand("-gdb-set pagination off");
            gdbCommand("-gdb-set confirm off");
            gdbCommand("handle SIGPWR nostop noprint pass");
            gdbCommand("handle SIGXCPU nostop noprint pass");

            sendResponse(reqSeq, cmd, true);
            sendEvent("initialized", JSONValue.emptyObject);
            return;
        }

        if (cmd == "setBreakpoints")
        {
            string filePath;
            if ("source" in args && args["source"].type == JSONType.object)
                if ("path" in args["source"] && args["source"]["path"].type == JSONType.string)
                    filePath = absolutePath(args["source"]["path"].str).asNormalizedPath.to!string;

            if (int[]* prev = filePath in breakpointsByFile)
            {
                foreach (int bpNum; *prev)
                    gdbCommand(format("-break-delete %d", bpNum));
                breakpointsByFile.remove(filePath);
            }

            JSONValue[] results;
            int[] newNums;
            if ("breakpoints" in args && args["breakpoints"].type == JSONType.array)
            {
                foreach (JSONValue bp; args["breakpoints"].array)
                {
                    int line = cast(int) bp["line"].integer;
                    string cond = ("condition" in bp && bp["condition"].type == JSONType.string)
                        ? bp["condition"].str.strip() : "";
                    string insertCmd = format("-break-insert -f \"%s:%d\"", filePath.replace("\"", "\\\""), line);
                    if (cond.length)
                        insertCmd = format("-break-insert -f -c \"%s\" \"%s:%d\"",
                                cond.replace("\"", "\\\""), filePath.replace("\"", "\\\""), line);
                    string resp = gdbCommand(insertCmd);
                    bool ok = resp.startsWith("^done");
                    int bpLine = line;
                    int bpId = 0;
                    if (ok)
                    {
                        string numStr = extractMiField(resp, "number");
                        string lineStr = extractMiField(resp, "line");
                        if (numStr.length)
                        {
                            try
                                bpId = numStr.split(".")[0].to!int;
                            catch (Exception)
                                bpId = 0;
                        }
                        if (bpId > 0)
                            newNums ~= bpId;
                        if (lineStr.length)
                        {
                            try
                                bpLine = lineStr.to!int;
                            catch (Exception)
                                bpLine = line;
                        }
                    }
                    results ~= JSONValue([
                        "id": JSONValue(bpId),
                        "verified": JSONValue(ok),
                        "line": JSONValue(bpLine)
                    ]);
                }
            }
            if (newNums.length)
                breakpointsByFile[filePath] = newNums;
            sendResponse(reqSeq, cmd, true, JSONValue(["breakpoints": JSONValue(results)]));
            return;
        }

        if (cmd == "setFunctionBreakpoints")
        {
            foreach (int bpNum; functionBpNumbers)
                gdbCommand(format("-break-delete %d", bpNum));
            functionBpNumbers = null;
            JSONValue[] results;
            if ("breakpoints" in args && args["breakpoints"].type == JSONType.array)
            {
                foreach (JSONValue bp; args["breakpoints"].array)
                {
                    string name = bp["name"].str;
                    string cSym = (name in fnReverseMap) ? fnReverseMap[name] : name;
                    string resp = gdbCommand(format("-break-insert -f %s", cSym));
                    bool ok = resp.startsWith("^done");
                    int bpId = 0;
                    if (ok)
                    {
                        string numStr = extractMiField(resp, "number");
                        if (numStr.length)
                        {
                            try
                                bpId = numStr.split(".")[0].to!int;
                            catch (Exception)
                                bpId = 0;
                        }
                        if (bpId > 0)
                            functionBpNumbers ~= bpId;
                    }
                    results ~= JSONValue(["id": JSONValue(bpId), "verified": JSONValue(ok)]);
                }
            }
            sendResponse(reqSeq, cmd, true, JSONValue(["breakpoints": JSONValue(results)]));
            return;
        }

        if (cmd == "setExceptionBreakpoints")
        {
            foreach (int bpNum; exceptionBpNumbers)
                gdbCommand(format("-break-delete %d", bpNum));
            exceptionBpNumbers = null;
            if ("filters" in args && args["filters"].type == JSONType.array && args["filters"].array.length > 0)
            {
                foreach (string sym; ["delegua_falhar", "delegua_erro"])
                {
                    string resp = gdbCommand("-break-insert -f " ~ sym);
                    if (resp.startsWith("^done"))
                    {
                        string numStr = extractMiField(resp, "number");
                        if (numStr.length)
                        {
                            try
                                exceptionBpNumbers ~= numStr.split(".")[0].to!int;
                            catch (Exception)
                            {
                            }
                        }
                    }
                }
            }
            sendResponse(reqSeq, cmd, true);
            return;
        }

        if (cmd == "configurationDone")
        {
            sendResponse(reqSeq, cmd, true);
            if (stopOnEntry)
                gdbCommand("-break-insert -t delegua_main");
            gdbCommand("-exec-run");
            return;
        }

        if (cmd == "threads")
        {
            string resp = gdbCommand("-thread-info");
            JSONValue[] list;
            string[] objs = extractMiObjects(resp, "{");
            foreach (string obj; objs)
            {
                string idStr = extractMiField(obj, "id");
                if (!idStr.length)
                    continue;
                int id = 1;
                try
                    id = idStr.to!int;
                catch (Exception)
                    continue;
                list ~= JSONValue([
                    "id": JSONValue(id),
                    "name": JSONValue(id == 1 ? "Thread principal Delégua" : format("Rotina #%d", id))
                ]);
            }
            if (!list.length)
                list ~= JSONValue(["id": JSONValue(1), "name": JSONValue("Thread principal Delégua")]);
            sendResponse(reqSeq, cmd, true, JSONValue(["threads": JSONValue(list)]));
            return;
        }

        if (cmd == "stackTrace")
        {
            string resp = gdbCommand("-stack-list-frames");
            string[] framesRaw = extractMiObjects(resp, "frame={");
            JSONValue[] frames;
            foreach (string fr; framesRaw)
            {
                string levelStr = extractMiField(fr, "level");
                string func = extractMiField(fr, "func");
                string fullname = extractMiField(fr, "fullname");
                string file = extractMiField(fr, "file");
                string lineStr = extractMiField(fr, "line");
                int level = levelStr.length ? levelStr.to!int : 0;
                int line = lineStr.length ? lineStr.to!int : 0;
                string srcPath = fullname.length ? fullname : file;

                // Oculta frames puramente de libc/startup abaixo de delegua_main
                if (func == "__libc_start_main" || func == "__libc_start_call_main" || func == "_start")
                    continue;

                string displayFunc = func;
                if (string* mapped = func in fnDisplayMap)
                    displayFunc = *mapped;
                else if (func.startsWith("cgd_user_"))
                    displayFunc = decodeCgdUserName(func);

                JSONValue[string] fObj;
                fObj["id"] = JSONValue(level);
                fObj["name"] = JSONValue(displayFunc);
                fObj["line"] = JSONValue(line);
                fObj["column"] = JSONValue(1);
                if (srcPath.length)
                {
                    fObj["source"] = JSONValue([
                        "name": JSONValue(baseName(srcPath)),
                        "path": JSONValue(srcPath)
                    ]);
                }
                frames ~= JSONValue(fObj);
            }
            sendResponse(reqSeq, cmd, true, JSONValue([
                "stackFrames": JSONValue(frames),
                "totalFrames": JSONValue(frames.length)
            ]));
            return;
        }

        if (cmd == "scopes")
        {
            int frameId = ("frameId" in args) ? cast(int) args["frameId"].integer : 0;
            int refId = nextVarRef++;
            varRefs[refId] = ScopeRef(frameId, "", 0, 0);
            JSONValue[] scopes = [
                JSONValue([
                    "name": JSONValue("Locais"),
                    "variablesReference": JSONValue(refId),
                    "expensive": JSONValue(false)
                ])
            ];
            sendResponse(reqSeq, cmd, true, JSONValue(["scopes": JSONValue(scopes)]));
            return;
        }

        if (cmd == "variables")
        {
            int refId = ("variablesReference" in args) ? cast(int) args["variablesReference"].integer : 0;
            JSONValue[] vars;
            if (ScopeRef* sref = refId in varRefs)
            {
                if (sref.kind == 0)
                {
                    string resp = gdbCommand(format("-stack-list-variables --thread 1 --frame %d --simple-values",
                            sref.frameId));
                    string[] items = extractMiObjects(resp, "{");
                    foreach (string item; items)
                    {
                        string rawName = extractMiField(item, "name");
                        string decoded = decodeCgdUserName(rawName);
                        if (isInternalCVariable(rawName, decoded))
                            continue;
                        string val, typ;
                        int childRef;
                        formatDeleguaExpr(sref.frameId, rawName, val, typ, childRef);
                        vars ~= JSONValue([
                            "name": JSONValue(decoded),
                            "value": JSONValue(val),
                            "type": JSONValue(typ),
                            "variablesReference": JSONValue(childRef)
                        ]);
                    }
                }
                else if (sref.kind == 1)
                {
                    int limit = sref.length > 64 ? 64 : sref.length;
                    for (int i = 0; i < limit; i++)
                    {
                        string elemExpr = format("(%s).value.vetor->values[%d]", sref.expr, i);
                        string val, typ;
                        int childRef;
                        formatDeleguaExpr(sref.frameId, elemExpr, val, typ, childRef);
                        vars ~= JSONValue([
                            "name": JSONValue(format("[%d]", i)),
                            "value": JSONValue(val),
                            "type": JSONValue(typ),
                            "variablesReference": JSONValue(childRef)
                        ]);
                    }
                }
                else if (sref.kind == 2)
                {
                    // Elementos de VetorNativo<T> sem boxing
                    int limit = sref.length > 64 ? 64 : sref.length;
                    for (int i = 0; i < limit; i++)
                    {
                        string elemExpr = format("(%s).data[%d]", sref.expr, i);
                        string val, typ;
                        int childRef;
                        formatDeleguaExpr(sref.frameId, elemExpr, val, typ, childRef);
                        vars ~= JSONValue([
                            "name": JSONValue(format("[%d]", i)),
                            "value": JSONValue(val),
                            "type": JSONValue(typ),
                            "variablesReference": JSONValue(childRef)
                        ]);
                    }
                }
                else if (sref.kind == 3)
                {
                    // Campos de struct de valor @pilha
                    string rawVal = evalExpr(sref.frameId, sref.expr);
                    if (rawVal.startsWith("{") && rawVal.endsWith("}"))
                    {
                        foreach (string part; rawVal[1 .. $ - 1].split(","))
                        {
                            string p = part.strip();
                            ptrdiff_t eq = p.indexOf("=");
                            if (eq > 0)
                            {
                                string rawField = p[0 .. cast(size_t) eq].strip();
                                string decField = decodeCgdUserName(rawField);
                                string fExpr = format("(%s).%s", sref.expr, rawField);
                                string val, typ;
                                int childRef;
                                formatDeleguaExpr(sref.frameId, fExpr, val, typ, childRef);
                                vars ~= JSONValue([
                                    "name": JSONValue(decField),
                                    "value": JSONValue(val),
                                    "type": JSONValue(typ),
                                    "variablesReference": JSONValue(childRef)
                                ]);
                            }
                        }
                    }
                }
            }
            sendResponse(reqSeq, cmd, true, JSONValue(["variables": JSONValue(vars)]));
            return;
        }

        if (cmd == "evaluate")
        {
            string expr = ("expression" in args && args["expression"].type == JSONType.string)
                ? args["expression"].str.strip() : "";
            int frameId = ("frameId" in args) ? cast(int) args["frameId"].integer : 0;
            if (!expr.length)
            {
                sendResponse(reqSeq, cmd, false, JSONValue.init, "Expressão vazia.");
                return;
            }
            string cExpr = cName(expr.to!dstring).to!string;
            string val, typ;
            int childRef;
            formatDeleguaExpr(frameId, cExpr, val, typ, childRef);
            if (typ == "desconhecido" && !val.length)
            {
                // Fallback para expressão C/GDB direta se o usuário inspecionar algo avançado
                val = evalExpr(frameId, expr);
            }
            sendResponse(reqSeq, cmd, true, JSONValue([
                "result": JSONValue(val.length ? val : "<indisponível>"),
                "type": JSONValue(typ),
                "variablesReference": JSONValue(childRef)
            ]));
            return;
        }

        if (cmd == "continue")
        {
            sendResponse(reqSeq, cmd, true, JSONValue(["allThreadsContinued": JSONValue(true)]));
            sendEvent("continued", JSONValue(["threadId": JSONValue(1), "allThreadsContinued": JSONValue(true)]));
            gdbCommand("-exec-continue");
            return;
        }

        if (cmd == "next")
        {
            sendResponse(reqSeq, cmd, true);
            gdbCommand("-exec-next");
            return;
        }

        if (cmd == "stepIn")
        {
            sendResponse(reqSeq, cmd, true);
            gdbCommand("-exec-step");
            return;
        }

        if (cmd == "stepOut")
        {
            sendResponse(reqSeq, cmd, true);
            gdbCommand("-exec-finish");
            return;
        }

        if (cmd == "pause")
        {
            sendResponse(reqSeq, cmd, true);
            gdbCommand("-exec-interrupt");
            return;
        }

        if (cmd == "terminate" || cmd == "disconnect")
        {
            shuttingDown = true;
            if (gdbRunning)
            {
                try
                {
                    gdb.stdin.writeln("-gdb-exit");
                    gdb.stdin.flush();
                }
                catch (Exception)
                {
                }
                try
                    kill(gdb.pid);
                catch (Exception)
                {
                }
                gdbRunning = false;
            }
            sendResponse(reqSeq, cmd, true);
            return;
        }

        sendResponse(reqSeq, cmd, false, JSONValue.init, "Comando DAP não suportado: " ~ cmd);
    }

    void run()
    {
        while (!shuttingDown)
        {
            size_t contentLength = 0;
            bool gotHeader = false;
            while (true)
            {
                string line = stdin.readln();
                if (line is null)
                    return;
                string trimmed = line.strip();
                if (!trimmed.length)
                    break;
                if (trimmed.startsWith("Content-Length:"))
                {
                    contentLength = trimmed[15 .. $].strip().to!size_t;
                    gotHeader = true;
                }
            }
            if (!gotHeader || contentLength == 0)
                continue;

            char[] buf = new char[contentLength];
            size_t readTotal = 0;
            while (readTotal < contentLength)
            {
                char[] chunk = stdin.rawRead(buf[readTotal .. $]);
                if (!chunk.length)
                    return;
                readTotal += chunk.length;
            }
            JSONValue req;
            try
                req = parseJSON(cast(string) buf);
            catch (Exception)
                continue;
            if ("type" in req && req["type"].str == "request")
                handleRequest(req);
        }
    }
}

void runDapServer(string[] args)
{
    foreach (string a; args)
    {
        if (a == "--ajuda" || a == "-a" || a == "--help")
        {
            writeln("Uso: cgd dap --stdio");
            return;
        }
    }
    DapServer server = new DapServer();
    server.run();
}

void runDebugCliCommand(string[] args)
{
    string fileArg;
    foreach (string a; args)
    {
        if (a == "--ajuda" || a == "-a" || a == "--help")
        {
            writeln("Uso: cgd depurar [arquivo.delegua]");
            return;
        }
        if (!fileArg.length)
            fileArg = a;
    }
    if (!executableAvailable("gdb"))
        cgd_erro("GDB não encontrado no PATH. Instale 'gdb' para usar 'cgd depurar'.");

    DapServer helper = new DapServer();
    string bin = helper.compileTargetForDebug(fileArg, ".", "desenvolvimento");
    writefln("Iniciando depuração GDB em %s (símbolos Delégua ativos)...", bin);
    Pid pid = spawnProcess([
        "gdb", "-q", "-ex", "handle SIGPWR nostop noprint pass",
        "-ex", "handle SIGXCPU nostop noprint pass",
        "-ex", "break delegua_main", bin
    ]);
    wait(pid);
}
