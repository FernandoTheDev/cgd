module frontend.semantic.value_types;

import diagnostics.catalog;
import errors;
import frontend.parser.ast;
import frontend.type_sema;
import std.conv : to;

/// Verifica se um tipo tem layout nativo estático válido para campos de `@pilha` e funções `@nativo`.
bool isStaticNativeLayoutType(TypeSema type, bool allowVoid = false)
{
    if (type is null)
        return false;
    if (cast(TypeSemaNative) type !is null)
        return true;
    if (TypeSemaBuiltin b = cast(TypeSemaBuiltin) type)
    {
        return b.base == TypeSemaBase.Int || b.base == TypeSemaBase.Double
            || b.base == TypeSemaBase.Bool || (allowVoid && b.base == TypeSemaBase.Void);
    }
    if (TypeSemaClass cls = cast(TypeSemaClass) type)
        return cls.declaration !is null && cls.declaration.isValueType;
    if (TypeSemaNativeContainer nc = cast(TypeSemaNativeContainer) type)
    {
        foreach (TypeSema ta; nc.typeArgs)
            if (!isStaticNativeLayoutType(ta, false))
                return false;
        return true;
    }
    return false;
}

/// Retorna `true` se o tipo possui semântica de cópia trivial (bit a bit segura, sem ownership exclusivo).
bool isTriviallyCopyable(TypeSema type)
{
    if (type is null)
        return false;
    if (cast(TypeSemaNative) type !is null)
        return true;
    if (TypeSemaBuiltin b = cast(TypeSemaBuiltin) type)
        return b.base == TypeSemaBase.Int || b.base == TypeSemaBase.Double
            || b.base == TypeSemaBase.Bool || b.base == TypeSemaBase.Void;
    if (TypeSemaClass cls = cast(TypeSemaClass) type)
        return cls.declaration !is null && cls.declaration.isValueType && cls.declaration.isTrivialCopy;
    if (TypeSemaNativeContainer nc = cast(TypeSemaNativeContainer) type)
    {
        if (nc.isOwnedResource())
            return false;
        if (nc.isBorrowedView())
            return true;
        foreach (TypeSema ta; nc.typeArgs)
            if (!isTriviallyCopyable(ta))
                return false;
        return true;
    }
    return false;
}

/// Retorna `true` se o tipo exige destruição determinística (ownership exclusivo).
bool hasOwnershipResource(TypeSema type)
{
    if (type is null)
        return false;
    if (TypeSemaNativeContainer nc = cast(TypeSemaNativeContainer) type)
    {
        if (nc.isOwnedResource())
            return true;
        if (nc.containerKind == NativeContainerKind.ResultadoNativo
                || nc.containerKind == NativeContainerKind.OpcionalNativo)
        {
            foreach (TypeSema ta; nc.typeArgs)
                if (hasOwnershipResource(ta))
                    return true;
        }
        return false;
    }
    if (TypeSemaClass cls = cast(TypeSemaClass) type)
        return cls.declaration !is null && cls.declaration.isValueType && cls.declaration.hasNonTrivialDrop;
    return false;
}

/// Retorna `true` se o tipo é uma visão emprestada que não pode escapar do escopo do dono.
bool isBorrowedViewType(TypeSema type)
{
    if (TypeSemaNativeContainer nc = cast(TypeSemaNativeContainer) type)
        return nc.isBorrowedView();
    return false;
}

final class ValueTypeValidator
{
private:
    Diagnostics diag;
    bool[Node] visited;
    bool[ClassDecl] validated;
    bool[ClassDecl] activeLayout;

    void validateClass(ClassDecl cls)
    {
        if (cls is null || cls in validated)
            return;
        if (cls in activeLayout)
        {
            diag.errorCode(cls.pos, valueClassRecursive, cls.name);
            return;
        }
        if (!cls.isValueType)
            return;

        activeLayout[cls] = true;
        scope (exit)
        {
            activeLayout.remove(cls);
            validated[cls] = true;
        }

        if (cls.superName.length || cls.superClass !is null)
            diag.errorCode(cls.pos, valueClassInvalidStructure, cls.name, "herança dinâmica (herda)");
        if (cls.isAbstract)
            diag.errorCode(cls.pos, valueClassInvalidStructure, cls.name, "classe abstrata");
        if (cls.isInterface)
            diag.errorCode(cls.pos, valueClassInvalidStructure, cls.name, "interface");
        if (cls.isForeign)
            diag.errorCode(cls.pos, valueClassInvalidStructure, cls.name, "classe estrangeira");
        if (cls.mixinNames.length || cls.mixins.length)
            diag.errorCode(cls.pos, valueClassInvalidStructure, cls.name, "composição mescla");
        if (cls.interfaceNames.length || cls.interfaces.length)
            diag.errorCode(cls.pos, valueClassInvalidStructure, cls.name, "implementação de interfaces dinâmicas");

        bool trivial = true;
        bool hasDrop = false;

        foreach (ClassField field; cls.fields)
        {
            if (field.isEnum)
                continue;
            if (field.isStatic)
            {
                diag.errorCode(field.pos, valueClassInvalidFeature, cls.name, "campo estático");
                continue;
            }
            if (field.customAccess)
            {
                diag.errorCode(field.pos, valueClassInvalidFeature, cls.name, "acessor dinâmico obter/definir");
                continue;
            }
            if (field.type_sema is null || !isStaticNativeLayoutType(field.type_sema, false))
            {
                dstring got = field.type_sema is null ? "qualquer"d : field.type_sema.toStr();
                diag.errorCode(field.pos, valueClassInvalidField, field.name, cls.name, got);
                continue;
            }
            if (TypeSemaClass nested = cast(TypeSemaClass) field.type_sema)
            {
                if (nested.declaration is cls || nested.declaration in activeLayout)
                {
                    diag.errorCode(field.pos, valueClassRecursive, cls.name);
                    continue;
                }
                validateClass(nested.declaration);
                if (!nested.declaration.isTrivialCopy)
                    trivial = false;
                if (nested.declaration.hasNonTrivialDrop)
                    hasDrop = true;
            }
            else
            {
                if (!isTriviallyCopyable(field.type_sema))
                    trivial = false;
                if (hasOwnershipResource(field.type_sema))
                    hasDrop = true;
            }
        }

        foreach (FnDecl method; cls.methods)
        {
            if (method.accessor)
                continue;
            if (method.isAbstract)
                diag.errorCode(method.pos, valueClassInvalidFeature, cls.name, "método abstrato");
            if (method.isAsync)
                diag.errorCode(method.pos, valueClassInvalidFeature, cls.name, "método assíncrono");
            if (method.fn == "destrutor"d)
            {
                trivial = false;
                hasDrop = true;
            }
        }

        cls.isTrivialCopy = trivial;
        cls.hasNonTrivialDrop = hasDrop;
    }

    void visit(Node node)
    {
        if (node is null || node in visited)
            return;
        visited[node] = true;
        if (ClassDecl cls = cast(ClassDecl) node)
            validateClass(cls);
        foreach (Node child; childNodes(node))
            visit(child);
    }

public:
    this(Diagnostics diag)
    {
        this.diag = diag;
    }

    void analyze(Program program)
    {
        visit(program);
    }
}

void validateValueTypes(Program program, Diagnostics diag)
{
    new ValueTypeValidator(diag).analyze(program);
}
