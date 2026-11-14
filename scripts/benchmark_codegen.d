/// Microbenchmark reproduzível dos codificadores C; não é teste de tempo limite.
module benchmark_codegen;

import backend.c.utils : cName, cString, formatD;
import std.conv : to;
import std.datetime.stopwatch : StopWatch, AutoStart;
import std.stdio : writefln;

private dstring oldName(dstring name)
{
    dstring result = "cgd_user";
    foreach (ch; name)
        result ~= formatD("_%x", cast(uint) ch);
    return result;
}

private dstring oldString(dstring value)
{
    dstring result = "\"";
    foreach (ubyte ch; cast(const(ubyte)[]) value.to!string)
        result ~= formatD("\\%03o", ch);
    return result ~ "\"";
}

void main()
{
    enum iterations = 10_000;
    auto names = ["identificadorComAcentuação"d, "x"d, "#fn_1234"d, "valorDoParametro"d];
    auto texts = ["Olá, Delégua!"d, "texto com aspas \" e barra \\"d, "linha\ncom\ttab"d];
    size_t sink;
    foreach (i; 0 .. 2)
    {
        auto timer = StopWatch(AutoStart.yes);
        foreach (_; 0 .. iterations)
        {
            foreach (name; names)
                sink += i == 0 ? oldName(name).length : cName(name).length;
            foreach (text; texts)
                sink += i == 0 ? oldString(text).length : cString(text).length;
        }
        writefln("%s: %s ms", i == 0 ? "formatD por caractere" : "emissão direta com reserva",
                timer.peek.total!"msecs");
    }
    writefln("checksum: %s", sink);
}
