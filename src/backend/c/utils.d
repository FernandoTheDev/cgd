module backend.c.utils;

import std.format;
import std.array;
import std.conv;

dstring formatD(Args...)(string fmt, Args args)
{
    Appender!dstring app = appender!dstring();
    formattedWrite(app, fmt, args);
    return app.data;
}

private dstring[dstring] cNameCache;
private dstring[dstring] cStringCache;

/// Codificação injetiva: nomes do usuário não colidem com símbolos internos C.
/// Emite dígitos diretamente, sem parsear um formato por ponto de código.
dstring cName(dstring name)
{
    if (dstring* cached = name in cNameCache)
        return *cached;
    enum dstring digits = "0123456789abcdef"d;
    Appender!dstring result = appender!dstring();
    result.reserve(8 + name.length * 7);
    result.put("cgd_user"d);
    foreach (dchar c; name)
    {
        dchar[8] buffer;
        size_t start = buffer.length;
        uint value = cast(uint) c;
        do
        {
            buffer[--start] = digits[value & 15];
            value >>= 4;
        }
        while (value);
        result.put('_');
        result.put(buffer[start .. $]);
    }
    dstring built = result.data;
    cNameCache[name] = built;
    return built;
}

/// Cada byte UTF-8 vira escape octal de três dígitos. Isso impede que o próximo
/// caractere se una ao escape e evita injetar aspas, barras ou diretivas C.
dstring cString(dstring value)
{
    if (dstring* cached = value in cStringCache)
        return *cached;
    string bytes = value.to!string;
    Appender!dstring result = appender!dstring();
    result.reserve(2 + bytes.length * 4);
    result.put('"');
    foreach (ubyte c; cast(const(ubyte)[]) bytes)
    {
        result.put('\\');
        result.put(cast(dchar)('0' + ((c >> 6) & 7)));
        result.put(cast(dchar)('0' + ((c >> 3) & 7)));
        result.put(cast(dchar)('0' + (c & 7)));
    }
    result.put('"');
    dstring built = result.data;
    cStringCache[value] = built;
    return built;
}
