module frontend.semantic.members;

import frontend.parser.ast;

struct ClassMember
{
    ClassDecl owner;
    FnDecl method;
    ClassField* field;

    int access()
    {
        return method !is null ? method.access : field !is null ? field.access : 0;
    }

    bool visibleFrom(ClassDecl caller)
    {
        if (access == 0 || owner is caller)
            return true;
        if (access == 1)
            return false;
        bool[ClassDecl] seen;
        for (ClassDecl current = caller; current !is null && current !in seen; current = current.superClass)
        {
            if (current is owner)
                return true;
            seen[current] = true;
        }
        return false;
    }
}

/// A primeira declaração esconde as herdadas, inclusive quando não é acessível.
ClassMember resolveClassMember(ClassDecl declaration, dstring name)
{
    bool[ClassDecl] seen;
    for (ClassDecl current = declaration; current !is null && current !in seen; current = current.superClass)
    {
        seen[current] = true;
        foreach (FnDecl method; current.methods)
            if (method.fn == name)
                return ClassMember(current, method, null);
        foreach (ref ClassField field; current.fields)
            if (field.name == name)
                return ClassMember(current, null, &field);
    }
    return ClassMember.init;
}
