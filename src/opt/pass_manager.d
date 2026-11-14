module opt.pass_manager;

import frontend;
import ctfe;
import opt.constant_folding;
import opt.dead_code;

struct OptimizationStats
{
    size_t iterations;
    size_t folded;
    size_t removed;
}

/// Cada execução tem caches locais; o limite é defesa, não a condição usual de parada.
OptimizationStats optimize(Program program, Context context, CTFEContext ctfe)
{
    OptimizationStats stats;
    foreach (_; 0 .. 8)
    {
        auto folding = new CgdConstantFolding(program, context, ctfe);
        folding.opt();
        auto dead = new CgdDeadCode(program, context);
        dead.remove();
        stats.iterations++;
        stats.folded += folding.changes;
        stats.removed += dead.changes;
        if (folding.changes + dead.changes == 0)
            break;
    }
    return stats;
}
