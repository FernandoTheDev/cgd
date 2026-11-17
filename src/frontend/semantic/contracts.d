module frontend.semantic.contracts;

import frontend;
import std.conv : to;
import frontend.semantic.members;

void validateClassContracts(ClassDecl declaration, Diagnostics diagnostics)
{
    void requireMember(ClassDecl contract, dstring name, FnDecl expected, ClassField* expectedField)
    {
        ClassMember found = resolveClassMember(declaration, name);
        if (found.owner is null || (found.access != 0 && (expected is null || expected.access != 2
                || found.access != 2)) || (expected !is null && (found.method is null
                || found.method.isAbstract || found.method.isStatic)))
        {
            if (!declaration.isAbstract)
                diagnostics.error(declaration.pos,
                        "Classe concreta não implementa membro público exigido: " ~ name.to!string);
            return;
        }
        if (expectedField !is null)
        {
            if (found.field is null || found.field.isEnum || found.field.type.toStr() != expectedField.type.toStr())
                diagnostics.error(declaration.pos, "Campo incompatível com interface: " ~ name.to!string);
            return;
        }
        if (found.method.args.length != expected.args.length
                || found.method.type_expr.toStr() != expected.type_expr.toStr())
            diagnostics.error(found.method.pos, "Assinatura incompatível com contrato: " ~ name.to!string);
        else
            foreach (size_t index, FnArg argument; expected.args)
                if (argument.type_expr.toStr() != found.method.args[index].type_expr.toStr()
                        || argument.rest != found.method.args[index].rest
                        || (argument.value !is null && found.method.args[index].value is null))
                    diagnostics.error(found.method.pos, "Parâmetro incompatível com contrato: " ~ name.to!string);
    }

    ClassDecl[] contracts = declaration.interfaces.dup;
    for (ClassDecl parent = declaration.superClass; parent !is null; parent = parent.superClass)
        contracts ~= parent.interfaces;
    foreach (ClassDecl contract; contracts)
    {
        foreach (ref ClassField field; contract.fields)
            if (!field.isEnum)
                requireMember(contract, field.name, null, &field);
        foreach (FnDecl method; contract.methods)
            requireMember(contract, method.fn, method, null);
    }
    for (ClassDecl parent = declaration.superClass; parent !is null; parent = parent.superClass)
        foreach (FnDecl method; parent.methods)
            if (method.isAbstract && !declaration.isAbstract)
                requireMember(parent, method.fn, method, null);
}
