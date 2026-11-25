module frontend.semantic.routine_validation;

import catalog = diagnostics.catalog;
import frontend;
import frontend.semantic.members;
import frontend.semantic.native_methods : builtinMethods;
import std.algorithm : canFind;
import std.conv : to;

/// Auditoria transitiva de efeitos para chamadas iniciadas com `rotina`.
void validateRoutines(Program program, Diagnostics diagnostics)
{
    bool[VarDecl] mutableGlobals;
    bool[Node] collectedModules;
    bool[Node] importVisited;

    void collectGlobals(Program unit)
    {
        if (unit is null || unit in collectedModules)
            return;
        collectedModules[unit] = true;
        foreach (Node stmt; unit.body)
        {
            if (VarDecl decl = cast(VarDecl) stmt)
            {
                if (!decl.isConst && !decl.isEnum)
                    mutableGlobals[decl] = true;
            }
            else if (SequenceStmt seq = cast(SequenceStmt) stmt)
            {
                foreach (Node inner; seq.body)
                    if (VarDecl innerDecl = cast(VarDecl) inner)
                        if (!innerDecl.isConst && !innerDecl.isEnum)
                            mutableGlobals[innerDecl] = true;
            }
        }
        void findImports(Node node)
        {
            if (node is null || node in importVisited || cast(ModuleUnit) node)
                return;
            importVisited[node] = true;
            if (ImportExpr imported = cast(ImportExpr) node)
                if (imported.target !is null)
                    collectGlobals(imported.target.program);
            foreach (Node child; childNodes(node))
                findImports(child);
        }

        findImports(unit);
    }

    collectGlobals(program);

    bool isSafeBuiltin(dstring name)
    {
        static immutable dstring[] allowed = [
            "tamanho", "inteiro", "numero", "número", "real", "texto", "logico", "lógico",
            "tupla", "clonar", "assercao", "asserção"
        ];
        return allowed.canFind(name);
    }

    bool[FnDecl] audited;
    bool[FnDecl] failed;
    string[FnDecl] failReason;

    FnDecl resolveCallee(Node expr, size_t depth = 0)
    {
        if (expr is null || depth > 32)
            return null;
        if (FunctionExpr fnExpr = cast(FunctionExpr) expr)
            return fnExpr.declaration;
        if (MemberExpr member = cast(MemberExpr) expr)
            if (Identifier right = cast(Identifier) member.right)
                return right.functionRef;
        if (Identifier id = cast(Identifier) expr)
        {
            if (id.functionRef !is null)
                return id.functionRef;
            if (id.variableRef !is null && id.variableRef.isConst)
                return resolveCallee(id.variableRef.value, depth + 1);
        }
        return null;
    }

    string auditFunction(FnDecl fn)
    {
        if (fn is null)
            return "alvo desconhecido";
        if (fn in failed)
            return failReason[fn];
        if (fn in audited)
            return null;
        audited[fn] = true;

        if (fn.isAsync)
        {
            failed[fn] = true;
            failReason[fn] = "chama função assíncrona";
            return failReason[fn];
        }
        if (fn.foreignSymbol.length && !fn.foreignParallelSafe)
        {
            failed[fn] = true;
            failReason[fn] = "chama função estrangeira/FFI";
            return failReason[fn];
        }

        bool[Node] seen;
        string inspect(Node node)
        {
            if (node is null || node in seen)
                return null;
            seen[node] = true;

            string auditModuleUnit(ModuleUnit target)
            {
                if (target is null || target.program is null)
                    return "importa módulo desconhecido dentro da rotina";
                foreach (Node stmt; target.program.body)
                {
                    if (cast(ClassDecl) stmt || cast(FnDecl) stmt)
                        continue;
                    if (ImportExpr subImp = cast(ImportExpr) stmt)
                    {
                        string subErr = auditModuleUnit(subImp.target);
                        if (subErr.length)
                            return subErr;
                        continue;
                    }
                    if (VarDecl vd = cast(VarDecl) stmt)
                    {
                        if (!vd.isConst && !vd.isEnum)
                            return "importa módulo com variável global mutável dentro da rotina";
                        string initErr = inspect(vd.value);
                        if (initErr.length)
                            return initErr;
                        continue;
                    }
                    return "importa módulo com código executável de topo dentro da rotina";
                }
                return null;
            }

            if (Identifier id = cast(Identifier) node)
            {
                if (id.variableRef !is null && (id.variableRef in mutableGlobals) !is null)
                    return "acessa variável global mutável '" ~ id.value.to!string ~ "'";
                if (id.classRef !is null && id.classRef.isForeign)
                    return "referencia classe estrangeira '" ~ id.classRef.name.to!string ~ "'";
                if (id.moduleRef !is null)
                    return auditModuleUnit(id.moduleRef);
                return null;
            }
            if (MemberExpr member = cast(MemberExpr) node)
            {
                if (member.resolvedModule !is null)
                    return auditModuleUnit(member.resolvedModule);
            }
            if (ImportExpr imported = cast(ImportExpr) node)
            {
                return auditModuleUnit(imported.target);
            }
            if (cast(AwaitExpr) node)
                return "usa aguardar dentro da rotina";
            if (cast(RoutineExpr) node)
                return "inicia rotina aninhada dentro de worker";
            if (cast(ClassDecl) node)
                return "declara classe dentro da rotina";
            if (MemberExpr member = cast(MemberExpr) node)
            {
                string leftErr = inspect(member.left);
                if (leftErr.length)
                    return leftErr;
                ClassDecl decl;
                if (TypeSemaClass clsType = cast(TypeSemaClass) member.left.type_sema)
                    decl = clsType.declaration;
                if (Identifier leftId = cast(Identifier) member.left)
                    if (leftId.classRef !is null)
                        decl = leftId.classRef;
                if (decl !is null)
                    if (Identifier rightId = cast(Identifier) member.right)
                    {
                        ClassMember found = resolveClassMember(decl, rightId.value);
                        if (found.field !is null && found.field.isStatic && !found.field.isEnum)
                            return "acessa campo estático mutável '" ~ rightId.value.to!string ~ "'";
                    }
                return null;
            }
            if (CallExpr call = cast(CallExpr) node)
            {
                foreach (Node arg; call.args)
                {
                    string argErr = inspect(arg);
                    if (argErr.length)
                        return argErr;
                }
                if (call.intrinsic)
                    return null;
                if (call.builtinCall)
                {
                    Identifier id = cast(Identifier) call.fn;
                    if (id is null || !isSafeBuiltin(id.value))
                        return "executa operação nativa com I/O ou estado global ('" ~ (id is null
                                ? "desconhecida" : id.value.to!string) ~ "')";
                    return null;
                }
                if (MemberExpr member = cast(MemberExpr) call.fn)
                {
                    if (Identifier right = cast(Identifier) member.right)
                    {
                        if (right.classRef !is null)
                        {
                            string recvErr = inspect(member.left);
                            if (recvErr.length)
                                return recvErr;
                            if (right.classRef.isForeign)
                                return "instancia classe estrangeira";
                            foreach (ClassField field; right.classRef.fields)
                                if (field.initializer !is null)
                                {
                                    string initErr = auditFunction(field.initializer);
                                    if (initErr.length)
                                        return initErr;
                                }
                            foreach (FnDecl method; right.classRef.methods)
                                if (method.fn == "construtor")
                                {
                                    string ctorErr = auditFunction(method);
                                    if (ctorErr.length)
                                        return ctorErr;
                                }
                            return null;
                        }
                        if (right.functionRef !is null)
                        {
                            if (!right.functionRef.foreignParallelSafe)
                            {
                                string recvErr = inspect(member.left);
                                if (recvErr.length)
                                    return recvErr;
                            }
                            string calleeErr = auditFunction(right.functionRef);
                            if (calleeErr.length)
                                return calleeErr;
                            return null;
                        }
                        string recvErr = inspect(member.left);
                        if (recvErr.length)
                            return recvErr;
                        if (member.left.type_sema !is null && !member.left.type_sema.isAny()
                                && builtinMethods(member.left.type_sema).canFind(right.value.to!string))
                            return null;
                    }
                    else
                    {
                        string recvErr = inspect(member.left);
                        if (recvErr.length)
                            return recvErr;
                    }
                    return "chamada de método sem contrato paralelo";
                }
                FnDecl callee = resolveCallee(call.fn);
                if (callee is null)
                    return "chamada indireta sem contrato paralelo";
                if (callee.classFactory !is null)
                {
                    if (callee.classFactory.isForeign)
                        return "instancia classe estrangeira";
                    foreach (FnDecl method; callee.classFactory.methods)
                        if (method.fn == "construtor")
                        {
                            string ctorErr = auditFunction(method);
                            if (ctorErr.length)
                                return ctorErr;
                        }
                    return null;
                }
                string calleeErr = auditFunction(callee);
                if (calleeErr.length)
                    return calleeErr;
                return null;
            }
            foreach (Node child; childNodes(node))
            {
                string childErr = inspect(child);
                if (childErr.length)
                    return childErr;
            }
            return null;
        }

        foreach (FnArg arg; fn.args)
        {
            string err = inspect(arg.value);
            if (err.length)
            {
                failed[fn] = true;
                failReason[fn] = err;
                return err;
            }
        }
        foreach (Node stmt; fn.body)
        {
            string err = inspect(stmt);
            if (err.length)
            {
                failed[fn] = true;
                failReason[fn] = err;
                return err;
            }
        }
        return null;
    }

    bool[Node] walked;
    void scan(Node node)
    {
        if (node is null || node in walked)
            return;
        walked[node] = true;
        if (RoutineExpr routine = cast(RoutineExpr) node)
        {
            if (routine.target !is null)
            {
                string reason = auditFunction(routine.target);
                if (reason.length)
                    diagnostics.errorCode(routine.pos, catalog.routineEffect, routine.target.fn, reason);
            }
        }
        foreach (Node child; childNodes(node))
            scan(child);
    }

    scan(program);
}
