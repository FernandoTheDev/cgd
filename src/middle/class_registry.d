module middle.class_registry;

import std.stdio;
import std.format;
import frontend.lexer.token;
import frontend.parser.ftype_info;
import frontend.parser.ast;

struct ClassProperty
{
    string name;
    FTypeInfo type;
    Stmt defaultValue; // nullable
    bool isPublic = true;
    Loc location;
}

struct ClassMethod
{
    string name;
    FTypeInfo returnType;
    FunctionArg[] parameters;
    Stmt[] body;
    bool isPublic = true;
    bool isStatic = false;
    Loc location;
}

struct ClassConstructor
{
    FunctionArg[] parameters;
    Stmt[] body;
    Loc location;
}

struct ClassInfo
{
    string name;
    ClassProperty[string] properties; // nome -> propriedade
    ClassMethod[string] methods; // nome -> método
    ClassConstructor constructor; // pode ser null
    bool hasDestructor = false;
    Loc location;

    // Métodos utilitários
    bool hasProperty(string propName) const
    {
        return (propName in properties) !is null;
    }

    bool hasMethod(string methodName) const
    {
        return (methodName in methods) !is null;
    }

    ClassProperty* getProperty(string propName)
    {
        return propName in properties;
    }

    ClassMethod* getMethod(string methodName)
    {
        return methodName in methods;
    }
}

// Sistema de registro de classes
class ClassRegistry
{
private:
    ClassInfo[string] classes;

public:
    // Registrar uma nova classe
    void registerClass(string className, ClassDeclaration classDecl)
    {
        if (className in classes)
        {
            throw new Exception(format("Classe '%s' já foi declarada", className));
        }

        ClassInfo info;
        info.name = className;
        info.location = classDecl.loc;

        // Registrar propriedades
        foreach (prop; classDecl.properties)
        {
            string propName = prop.name.value.get!string;
            info.properties[propName] = ClassProperty(
                propName,
                prop.type,
                prop.defaultValue,
                true, // assumindo público por padrão
                prop.name.loc
            );
        }

        // Registrar métodos
        foreach (method; classDecl.methods)
        {
            string methodName = method.id.value.get!string;
            info.methods[methodName] = ClassMethod(
                methodName,
                method.type,
                method.args,
                method.body,
                true, // assumindo público por padrão
                false, // não estático por padrão
                method.id.loc
            );
        }

        // Registrar construtor se existir
        if (classDecl.construct !is null)
        {
            info.constructor = ClassConstructor(
                classDecl.construct.args,
                classDecl.construct.body,
                classDecl.construct.loc
            );
        }

        classes[className] = info;
    }

    // Verificar se uma classe existe
    bool classExists(string className) const
    {
        return (className in classes) !is null;
    }

    // Obter informações de uma classe
    ClassInfo* getClass(string className)
    {
        return className in classes;
    }

    // Validar acesso a membro
    FTypeInfo validateMemberAccess(string className, string memberName, bool isMethodCall = false)
    {
        ClassInfo* classInfo = getClass(className);
        if (classInfo is null)
        {
            throw new Exception(format("Classe '%s' não encontrada", className));
        }

        if (isMethodCall)
        {
            if (!classInfo.hasMethod(memberName))
            {
                throw new Exception(format("Método '%s' não encontrado na classe '%s'",
                        memberName, className));
            }
            return classInfo.getMethod(memberName).returnType;
        }
        else
        {
            if (!classInfo.hasProperty(memberName))
            {
                throw new Exception(format("Propriedade '%s' não encontrada na classe '%s'",
                        memberName, className));
            }
            return classInfo.getProperty(memberName).type;
        }
    }

    // Validar chamada de método com argumentos
    FTypeInfo validateMethodCall(string className, string methodName, FTypeInfo[] argTypes)
    {
        ClassMethod* method = getClass(className).getMethod(methodName);
        if (method is null)
        {
            throw new Exception(format("Método '%s' não encontrado na classe '%s'",
                    methodName, className));
        }

        if (argTypes.length != method.parameters.length)
        {
            throw new Exception(format("Método '%s' espera %d argumentos, mas recebeu %d",
                    methodName, method.parameters.length, argTypes.length));
        }

        // Validar tipos dos argumentos
        for (size_t i = 0; i < argTypes.length; i++)
        {
            // if (!typeChecker.areTypesCompatible(argTypes[i], method.parameters[i].type))
            // {
            //     throw new Exception(format("Argumento %d tem tipo incompatível", i + 1));
            // }
        }

        return method.returnType;
    }

    string[] getAllClassNames() const
    {
        return classes.keys;
    }

    void printClassInfo(string className) const
    {
        const ClassInfo* info = className in classes;
        if (info is null)
        {
            writeln("Classe não encontrada: ", className);
            return;
        }

        writeln("Classe: ", className);
        writeln("Propriedades:");
        foreach (prop; info.properties)
        {
            writeln("  - ", prop.name, ": ", cast(string) prop.type.baseType);
        }
        writeln("Métodos:");
        foreach (method; info.methods)
        {
            writeln("  - ", method.name, "(): ", cast(string) method.returnType.baseType);
        }
    }
}
