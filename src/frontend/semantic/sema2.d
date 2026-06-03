// resolve os tipos
module frontend.semantic.sema2;

import utils;
import std.exception;
import frontend;
import frontend.parser;
import frontend.semantic;

class Sema2
{
private:
    TypeRegistry registry;

    void analyze(Node node)
    {
        switch (node.kind)
        {
        default:
            return;
        }
    }

public:
    this(TypeRegistry registry)
    {
        this.registry = registry;
    }

    void analyze(Program program)
    {
        foreach (Node node; program.body)
            analyze(node);
    }
}
