module driver.time;

import core.time;
import std.stdio;

struct Timer 
{
    bool showTime;
    string label;
    MonoTime time;

    void start(string label)
    {
        this.label = label;
        time = MonoTime.currTime;
    }

    void show() 
    {
        if (!showTime) return;
        auto us = (MonoTime.currTime - time).total!"usecs";
        writeln("[", label, "] ", us, " us");
    }
}
