module middle.async_ir;

import frontend;
import std.conv : to;
import std.algorithm : canFind, any;

final class AsyncLimitException : Exception
{
    Position position;
    this(Position position)
    {
        super(asyncBudget.message);
        this.position = position;
    }
}

enum AsyncOp
{
    Evaluate,
    CaptureReturn,
    Jump,
    Branch,
    Await,
    Resume,
    Return,
    Throw
}

class AsyncLabel
{
    size_t index = size_t.max;
}

struct AsyncInstruction
{
    AsyncOp op;
    Node value;
    size_t target = size_t.max;
    size_t next = size_t.max;
    size_t alternative = size_t.max;
    TokenKind condition = TokenKind.If;
    size_t[] uses, definitions;
    size_t exceptional = size_t.max;
    AsyncLabel handler;
    bool cleanup;
}

struct AsyncSlot
{
    dstring name;
    dstring sourceName;
    TypeExpr type;
    TypeSema semanticType;
}

/// CFG de instruções atômicas: nenhuma expressão contém uma suspensão oculta.
class AsyncIR
{
    Position position;
    size_t factBudget = 2_000_000;
    size_t workBudget = 50_000_000;
    AsyncInstruction[] instructions;
    AsyncSlot[] slots;
    size_t[] parameters;
    size_t self = size_t.max;
    size_t error = size_t.max;
    bool[size_t][] liveIn, liveOut;
    bool[size_t] persistent;

    void analyzeLiveness()
    {
        liveIn = null;
        liveOut = null;
        persistent = null;
        liveIn.length = liveOut.length = instructions.length;
        size_t facts, work;
        bool changed = true;
        while (changed)
        {
            changed = false;
            foreach_reverse (size_t i, AsyncInstruction instruction; instructions)
            {
                bool[size_t] outgoing;
                if (instruction.next != size_t.max)
                    foreach (size_t slot, bool present; liveIn[instruction.next])
                        outgoing[slot] = present;
                if (instruction.alternative != size_t.max)
                    foreach (size_t slot, bool present; liveIn[instruction.alternative])
                        outgoing[slot] = present;
                bool[size_t] incoming = outgoing.dup;
                foreach (size_t slot; instruction.definitions)
                    incoming.remove(slot);
                if (instruction.exceptional != size_t.max)
                    foreach (size_t slot, bool present; liveIn[instruction.exceptional])
                        if (slot != error)
                        {
                            incoming[slot] = present;
                            outgoing[slot] = present;
                        }
                foreach (size_t slot; instruction.uses)
                    incoming[slot] = true;
                facts += incoming.length + outgoing.length - liveIn[i].length - liveOut[i].length;
                work += 1 + incoming.length + outgoing.length;
                if (facts > factBudget || work > workBudget)
                    throw new AsyncLimitException(position);
                if (incoming.length != liveIn[i].length || outgoing.length != liveOut[i].length)
                    changed = true;
                liveIn[i] = incoming;
                liveOut[i] = outgoing;
            }
        }
        foreach (size_t i, AsyncInstruction instruction; instructions)
            if (instruction.op == AsyncOp.Await)
                foreach (size_t slot, bool present; liveOut[i])
                    persistent[slot] = present;
    }

    private bool atomic(Node node)
    {
        if (node is null || cast(FunctionExpr) node || cast(ImportExpr) node)
            return true;
        if (cast(AwaitExpr) node)
            return false;
        foreach (Node child; childNodes(node))
            if (!atomic(child))
                return false;
        return true;
    }

    bool verify()
    {
        if (!instructions.length)
            return false;
        foreach (AsyncInstruction instruction; instructions)
        {
            if (instruction.next != size_t.max && instruction.next >= instructions.length)
                return false;
            if (instruction.alternative != size_t.max && instruction.alternative >= instructions.length)
                return false;
            if (instruction.exceptional != size_t.max && instruction.exceptional >= instructions.length)
                return false;
            if (instruction.target != size_t.max && instruction.target >= slots.length)
                return false;
            foreach (size_t slot; instruction.uses)
                if (slot >= slots.length)
                    return false;
            foreach (size_t slot; instruction.definitions)
                if (slot >= slots.length)
                    return false;
            if (instruction.op != AsyncOp.Resume && !atomic(instruction.value))
                return false;
            if ((instruction.op == AsyncOp.Branch) && instruction.alternative == size_t.max)
                return false;
            if (instruction.op != AsyncOp.Return && instruction.op != AsyncOp.Throw && instruction.next == size_t.max)
                return false;
        }
        foreach (AsyncInstruction instruction; instructions)
        {
            if (instruction.op == AsyncOp.Await && instructions[instruction.next].op != AsyncOp.Resume)
                return false;
            if (instruction.next != size_t.max
                    && instructions[instruction.next].op == AsyncOp.Resume && instruction.op != AsyncOp.Await)
                return false;
            if (instruction.alternative != size_t.max && instructions[instruction.alternative].op == AsyncOp.Resume)
                return false;
        }
        return true;
    }
}

public import middle.async_lower;
