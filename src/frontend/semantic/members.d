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
        bool inherits(ClassDecl current)
        {
            if (current is null || current in seen)
                return false;
            seen[current] = true;
            if (current is owner)
                return true;
            foreach (ClassDecl mixinClass; current.mixins)
                if (inherits(mixinClass))
                    return true;
            return inherits(current.superClass);
        }

        return inherits(caller);
    }
}

/// A primeira declaração esconde as herdadas, inclusive quando não é acessível.
ClassMember resolveClassMember(ClassDecl declaration, dstring name)
{
    bool[ClassDecl] seen;
    ClassMember search(ClassDecl current)
    {
        if (current is null || current in seen)
            return ClassMember.init;
        seen[current] = true;
        foreach (FnDecl method; current.methods)
            if (method.fn == name)
                return ClassMember(current, method, null);
        foreach (ref ClassField field; current.fields)
            if (field.name == name)
                return ClassMember(current, null, &field);
        foreach_reverse (ClassDecl mixinClass; current.mixins)
        {
            ClassMember fromMixin = search(mixinClass);
            if (fromMixin.owner !is null)
                return fromMixin;
        }
        return search(current.superClass);
    }

    return search(declaration);
}
