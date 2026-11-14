module tests.codegen;

import backend.c.utils;
import std.format : format;
import std.conv : to;

unittest
{
    foreach (name; [""d, "main"d, "ação"d, "#fn_0"d, "int"d, "x_12"d])
    {
        dstring expected = "cgd_user"d;
        foreach (ch; name)
            expected ~= format("_%x", cast(uint) ch).to!dstring;
        assert(cName(name) == expected);
    }
    assert(cName("a_b") != cName("a5fb"));
}

unittest
{
    foreach (text; [""d, "a\\b\"c\n"d, "ação💚"d, "\0"d])
    {
        dstring expected = "\""d;
        foreach (ubyte byteValue; cast(const(ubyte)[]) text.to!string)
            expected ~= format("\\%03o", byteValue).to!dstring;
        expected ~= '"';
        assert(cString(text) == expected);
    }
}
