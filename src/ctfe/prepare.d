module ctfe.prepare;

import frontend.parser : FnDecl;
import ctfe.context;
import ctfe.compile;

/// Prepara bytecode apenas de funções previamente aprovadas pela semântica.
void prepareCTFE(CTFEContext context, FnDecl[] functions)
{
    CTFECompile compiler = new CTFECompile;
    foreach (FnDecl functionNode; functions)
    {
        context.bytecode[functionNode.linkName] = compiler.compile(functionNode);
        context.declarations[functionNode.linkName] = functionNode;
    }
}
