module backend.c.lvalue;

import backend.c.utils;

enum LValueKind
{
    Var,      // variável simples: t = valor
    Index,    // vetor[idx] = valor
}

struct LValue
{
    LValueKind kind;

    // Var
    dstring name;

    // Index
    dstring container;
    dstring index;

    dstring read()
    {
        final switch (kind)
        {
            case LValueKind.Var:
                return name;

            case LValueKind.Index:
                return formatD("delegua_vetor_obter(&%s, %s)", container, index);
        }
    }

    dstring write(dstring value)
    {
        final switch (kind)
        {
            case LValueKind.Var:
                return formatD("%s = %s", name, value);

            case LValueKind.Index:
                return formatD("delegua_vetor_setar(&%s, %s, %s)", container, index, value);
        }
    }
}
