module testes.runtime;

import std.stdio;
import std.variant;
import std.conv;
import std.format;
import std.array;

// Enum para identificar tipos em runtime
enum ValueType
{
    Null,
    Integer,
    Float,
    String,
    Boolean,
    Array,
    Object,
    Function
}

// Union para armazenar diferentes tipos de dados
union ValueData
{
    long intVal;
    double floatVal;
    bool boolVal;
    string strPtr;
    Array arrayPtr;
    Object objPtr;
    Function funcPtr;
}

// Tipo base - todos os valores da sua linguagem são desse tipo
struct Value
{
    ValueType type;
    ValueData data;

    // Construtor para inteiros
    static Value integer(long val)
    {
        Value v;
        v.type = ValueType.Integer;
        v.data.intVal = val;
        return v;
    }

    // Construtor para floats
    static Value float_(double val)
    {
        Value v;
        v.type = ValueType.Float;
        v.data.floatVal = val;
        return v;
    }

    // Construtor para strings
    static Value string_(string val)
    {
        Value v;
        v.type = ValueType.String;
        v.data.strPtr = val;
        return v;
    }

    // Construtor para booleanos
    static Value boolean(bool val)
    {
        Value v;
        v.type = ValueType.Boolean;
        v.data.boolVal = val;
        return v;
    }

    // Construtor para arrays
    static Value array(Value[] values...)
    {
        Value v;
        v.type = ValueType.Array;
        v.data.arrayPtr = Array(values);
        return v;
    }

    // Construtor para null
    static Value null_()
    {
        Value v;
        v.type = ValueType.Null;
        return v;
    }

    // Conversão para string (para print, etc)
    string toString() const
    {
        final switch (type)
        {
        case ValueType.Null:
            return "null";
        case ValueType.Integer:
            return to!string(data.intVal);
        case ValueType.Float:
            return to!string(data.floatVal);
        case ValueType.String:
            return data.strPtr;
        case ValueType.Boolean:
            return data.boolVal ? "true" : "false";
        case ValueType.Array:
            return data.arrayPtr.toString();
        case ValueType.Object:
            return data.objPtr.toString();
        case ValueType.Function:
            return "<function>";
        }
    }

    // Operadores aritméticos
    Value opBinary(string op)(Value rhs)
    {
        static if (op == "+")
        {
            // Adição de inteiros
            if (type == ValueType.Integer && rhs.type == ValueType.Integer)
            {
                return Value.integer(data.intVal + rhs.data.intVal);
            }
            // Adição de floats
        else if (type == ValueType.Float && rhs.type == ValueType.Float)
            {
                return Value.float_(data.floatVal + rhs.data.floatVal);
            }
            // Concatenação de strings
        else if (type == ValueType.String && rhs.type == ValueType.String)
            {
                return Value.string_(data.strPtr ~ rhs.data.strPtr);
            }
            // Conversões implícitas
        else if (type == ValueType.Integer && rhs.type == ValueType.Float)
            {
                return Value.float_(data.intVal + rhs.data.floatVal);
            }
            else if (type == ValueType.Float && rhs.type == ValueType.Integer)
            {
                return Value.float_(data.floatVal + rhs.data.intVal);
            }
            else
            {
                throw new Exception("Operação + inválida entre " ~ to!string(
                        type) ~ " e " ~ to!string(rhs.type));
            }
        }
        // Implementar outros operadores similarmente
        else static if (op == "-" || op == "*" || op == "/")
        {
            if (type == ValueType.Integer && rhs.type == ValueType.Integer)
            {
                static if (op == "-")
                    return Value.integer(data.intVal - rhs.data.intVal);
                else static if (op == "*")
                    return Value.integer(data.intVal * rhs.data.intVal);
                else static if (op == "/")
                    return Value.integer(data.intVal / rhs.data.intVal);
            }
            else if (type == ValueType.Float && rhs.type == ValueType.Float)
            {
                static if (op == "-")
                    return Value.float_(data.floatVal - rhs.data.floatVal);
                else static if (op == "*")
                    return Value.float_(data.floatVal * rhs.data.floatVal);
                else static if (op == "/")
                    return Value.float_(data.floatVal / rhs.data.floatVal);
            }
            else
            {
                throw new Exception("Operação aritmética inválida");
            }
        }
        assert(0);
    }

    // Comparações
    bool opEquals()(auto ref const Value rhs) const
    {
        if (type != rhs.type)
            return false;

        final switch (type)
        {
        case ValueType.Null:
            return true;
        case ValueType.Integer:
            return data.intVal == rhs.data.intVal;
        case ValueType.Float:
            return data.floatVal == rhs.data.floatVal;
        case ValueType.String:
            return *data.strPtr == *rhs.data.strPtr;
        case ValueType.Boolean:
            return data.boolVal == rhs.data.boolVal;
        case ValueType.Array:
            return data.arrayPtr == rhs.data.arrayPtr;
        case ValueType.Object:
            return data.objPtr == rhs.data.objPtr;
        case ValueType.Function:
            return data.funcPtr == rhs.data.funcPtr;
        }
    }
}

// Tipo Array com métodos
struct Array
{
    Value[] elements;

    this(Value[] vals)
    {
        elements = vals.dup;
    }

    // Método push
    void push(Value val)
    {
        elements ~= val;
    }

    // Método pop
    Value pop()
    {
        if (elements.length == 0)
        {
            throw new Exception("Pop de array vazio");
        }
        Value val = elements[$ - 1];
        elements = elements[0 .. $ - 1];
        return val;
    }

    // Método length
    Value length()
    {
        return Value.integer(cast(long) elements.length);
    }

    // Acesso por índice
    Value get(long index)
    {
        if (index < 0 || index >= elements.length)
        {
            throw new Exception("Índice fora dos limites");
        }
        return elements[cast(size_t) index];
    }

    // Atribuição por índice
    void set(long index, Value val)
    {
        if (index < 0 || index >= elements.length)
        {
            throw new Exception("Índice fora dos limites");
        }
        elements[cast(size_t) index] = val;
    }

    string toString() const
    {
        string result = "[";
        foreach (i, elem; elements)
        {
            if (i > 0)
                result ~= ", ";
            result ~= elem.toString();
        }
        result ~= "]";
        return result;
    }
}

// Tipo Object (hash map / dicionário)
struct Object
{
    Value[string] fields;

    // Obter propriedade
    Value get(string key)
    {
        if (key !in fields)
        {
            return Value.null_();
        }
        return fields[key];
    }

    // Definir propriedade
    void set(string key, Value val)
    {
        fields[key] = val;
    }

    // Verificar se tem propriedade
    bool has(string key)
    {
        return (key in fields) !is null;
    }

    string toString() const
    {
        string result = "{";
        bool first = true;
        foreach (key, val; fields)
        {
            if (!first)
                result ~= ", ";
            first = false;
            result ~= key ~ ": " ~ val.toString();
        }
        result ~= "}";
        return result;
    }
}

// Tipo Function
struct Function
{
    Value delegate(Value[]) func;

    this(Value delegate(Value[]) f)
    {
        func = f;
    }

    Value call(Value[] args)
    {
        return func(args);
    }
}

// Funções de runtime auxiliares
void print(Value val)
{
    writeln(val.toString());
}

void print(Value[] vals...)
{
    foreach (i, val; vals)
    {
        if (i > 0)
            write(" ");
        write(val.toString());
    }
    writeln();
}

// Exemplo de uso / testes
void main()
{
    writeln("=== Testando Sistema de Tipos ===\n");

    // Operações básicas
    auto a = Value.integer(10);
    auto b = Value.integer(20);
    auto c = a + b;
    writeln("10 + 20 = ", c.toString());

    // Strings
    auto s1 = Value.string_("Hello, ");
    auto s2 = Value.string_("World!");
    auto s3 = s1 + s2;
    writeln("String concat: ", s3.toString());

    // Arrays
    auto arr = Value.array(
        Value.integer(1),
        Value.integer(2),
        Value.integer(3)
    );
    writeln("Array inicial: ", arr.toString());

    arr.data.arrayPtr.push(Value.integer(4));
    writeln("Após push(4): ", arr.toString());

    auto popped = arr.data.arrayPtr.pop();
    writeln("Pop retornou: ", popped.toString());
    writeln("Array após pop: ", arr.toString());

    // Acesso por índice
    auto elem = arr.data.arrayPtr.get(1);
    writeln("Elemento no índice 1: ", elem.toString());

    // Objects
    auto obj = Value.null_();
    obj.type = ValueType.Object;
    obj.data.objPtr = Object();
    obj.data.objPtr.set("name", Value.string_("João"));
    obj.data.objPtr.set("age", Value.integer(25));
    writeln("Object: ", obj.toString());

    auto name = obj.data.objPtr.get("name");
    writeln("Nome: ", name.toString());
}
