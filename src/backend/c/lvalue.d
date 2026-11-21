module backend.c.lvalue;

import backend.c.utils;

enum LValueKind
{
    Var, // variável simples: t = valor
    Member,
    Index, // vetor[idx] = valor
}

struct LValue
{
    LValueKind kind;

    // Var
    dstring name;

    // Index
    dstring container;
    dstring index;
    dstring caller;
    dstring icSlot;

    dstring read()
    {
        final switch (kind)
        {
            case LValueKind.Var:
                return name;

            case LValueKind.Member:
                return icSlot.length
                    ? formatD("delegua_prop_ic(%s, %s, %s, %s)", container, index, caller, icSlot)
                    : formatD("delegua_propriedade_em(%s, %s, %s)", container, index, caller);
            case LValueKind.Index:
                return formatD("delegua_obter(%s, %s)", container, index);
        }
    }

    dstring write(dstring value)
    {
        final switch (kind)
        {
            case LValueKind.Var:
                return formatD("%s = %s", name, value);

            case LValueKind.Member:
                return icSlot.length
                    ? formatD("delegua_def_ic(%s, %s, %s, %s, %s)", container, index, value, caller, icSlot)
                    : formatD("delegua_definir_em(%s, %s, %s, %s)", container, index, value, caller);
            case LValueKind.Index:
                return formatD("delegua_setar(%s, %s, %s)", container, index, value);
        }
    }
}
