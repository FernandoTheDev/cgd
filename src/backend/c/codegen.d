module backend.c.codegen;

import std.algorithm;
import std.format;
import std.array;
import std.stdio;
import std.conv;

import frontend.lexer.token;
import frontend.type_sema;
import frontend.type_expr;
import backend.c.lvalue;
import frontend.parser;
import backend.c.utils;

enum string VALUE = "delegua_value";
enum string ENTRY = "delegua_main";

class BackendC
{
private:
    size_t tmp;
    dstring[] sourceSites;
    size_t[string] sourceSiteIds;
    ClassDecl currentClass;
    TypeExpr functionReturn;
    dstring descriptor(TypeExpr type)
    {
        if (TypeExprNamed named = cast(TypeExprNamed) type)
            return named.classLinkName.length ? formatD("delegua_descr_classe(%s)",
                    cName(named.classLinkName)) : formatD("delegua_descr_nome(%s)", cString(named.name));
        if (TypeExprArray array = cast(TypeExprArray) type)
            return formatD("delegua_descr_array(%s)", descriptor(array.base));
        if (TypeExprTuple tuple = cast(TypeExprTuple) type)
        {
            dstring[] children;
            foreach (TypeExpr t; tuple.types)
                children ~= descriptor(t);
            return formatD("delegua_descr_tupla(%s,(delegua_tipo*[]){%s})", children.length, children.join(","));
        }
        return "delegua_descr_nome(\"qualquer\")";
    }

    dstring checked(dstring value, TypeExpr type, Position pos = null)
    {
        if (type is null || type.toStr() == "qualquer")
            return value;
        dstring site = location(pos is null ? type.pos : pos);
        dstring expression = formatD("delegua_assegurar_descr(%s,%s)", value, descriptor(type));
        return site.length ? "(" ~ site ~ ", " ~ expression ~ ")" : expression;
    }

    dstring lexicalClass()
    {
        return currentClass is null ? "create_nulo()"d : cName(currentClass.signature.linkName);
    }

    dstring[] continueLabels, breakLabels;
    size_t[] breakTryDepth;
    struct Collector
    {
        dstring output, label;
        size_t depth;
    }

    Collector[] collectors;
    dstring pendingCollector;
    void enterLoop(dstring label)
    {
        continueLabels ~= label;
        loopTryDepth ~= cleanups.length;
        breakLabels ~= label ~ "_break";
        breakTryDepth ~= cleanups.length;
        if (pendingCollector.length)
        {
            collectors ~= Collector(pendingCollector, label, cleanups.length);
            pendingCollector = "";
        }
    }

    void leaveLoop(dstring label)
    {
        continueLabels.length--;
        loopTryDepth.length--;
        breakLabels.length--;
        breakTryDepth.length--;
        if (collectors.length && collectors[$ - 1].label == label)
            collectors.length--;
    }

    dstring compileAssignment(AssignStmt assign)
    {
        LValue lv = resolveLValue(assign.left);
        dstring value;
        if (assign.op == TokenKind.Equals)
            value = materialize(assign.value);
        else
        {
            dstring old = formatD("cgd_tmp_%s", tmp++);
            emitLocal(formatD("delegua_value %s=%s;", old, atSite(lv.read(), assign.pos)));
            dstring op;
            switch (assign.op)
            {
                case TokenKind.PlusAssign:
                    op = "add";
                    break;
                case TokenKind.MinusAssign:
                    op = "sub";
                    break;
                case TokenKind.MulAssign:
                    op = "mul";
                    break;
                case TokenKind.DivAssign:
                    op = "div";
                    break;
                case TokenKind.ModAssign:
                    op = "mod";
                    break;
                default:
                    throw new Exception("Atribuição inválida no backend.");
            }
            dstring rhs = materialize(assign.value);
            value = atSite(formatD("delegua_op_%s(%s,%s)", op, old, rhs), assign.pos);
        }
        dstring result = formatD("cgd_tmp_%s", tmp++);
        emitLocal(formatD("delegua_value %s=%s;", result, checked(value, assign.left.type_expr, assign.pos)));
        emitLocal(atSite(lv.write(result), assign.pos) ~ ";");
        return result;
    }

    dstring compileSwitch(SwitchStmt node)
    {
        dstring value = materialize(node.value), label = formatD("cgd_switch_%s", tmp++),
            done = formatD("cgd_done_%s", tmp++);
        breakLabels ~= label;
        breakTryDepth ~= cleanups.length;
        dstring[] result = [formatD("{bool %s=false;", done)];
        foreach (SwitchCase c; node.cases)
        {
            dstring matched = formatD("cgd_match_%s", tmp++);
            result ~= formatD("if(!%s){bool %s=false;", done, matched);
            foreach (Node v; c.values)
            {
                dstring expression;
                dstring setup = captureExpr(v, expression);
                result ~= formatD("if(!%s){%s\n%s=delegua_op_eq(%s,%s).value.b1;}", matched, setup,
                        matched, value, expression);
            }
            result ~= formatD("if(%s){%s=true;", matched, done);
            foreach (Node child; c.body)
                result ~= compileStmtOrdered(child);
            result ~= "}}";
        }
        result ~= formatD("if(!%s){", done);
        foreach (Node child; node.fallback)
            result ~= compileStmtOrdered(child);
        result ~= "}";
        result ~= label ~ ":; }";
        breakLabels.length--;
        breakTryDepth.length--;
        return result.join("\n");
    }

    size_t[] loopTryDepth;
    struct Cleanup
    {
        dstring frame;
        Node[] finalBody;
    }

    Cleanup[] cleanups;
    dstring classValue(ClassDecl c)
    {
        return c.signature.builtinName.length ? formatD("delegua_builtin(%s)",
                cString(c.signature.builtinName)) : cName(c.signature.linkName);
    }

    dstring cleanupCode(size_t limit)
    {
        Cleanup[] original = cleanups.dup;
        dstring[] result;
        while (cleanups.length > limit)
        {
            Cleanup current = cleanups[$ - 1];
            cleanups.length--;
            result ~= formatD("delegua_sair_tente(%s);", current.frame);
            foreach (Node child; current.finalBody)
                result ~= compileStmtOrdered(child);
        }
        cleanups = original;
        return result.join("\n");
    }

    dstring compileTry(TryStmt node)
    {
        dstring outer = formatD("cgd_try_%s", tmp++), inner = formatD("cgd_try_%s", tmp++);
        dstring[] result = [
            "{", formatD("delegua_try_frame *const %s=delegua_tentar();", outer),
            formatD("if(setjmp(%s->env)==0) {", outer)
        ];
        cleanups ~= Cleanup(outer, node.finalBody);
        result ~= formatD("delegua_try_frame *const %s=delegua_tentar();", inner);
        result ~= formatD("if(setjmp(%s->env)==0) {", inner);
        cleanups ~= Cleanup(inner, []);
        foreach (Node child; node.body)
            result ~= compileStmtOrdered(child);
        result ~= formatD("delegua_sair_tente(%s); } else {", inner);
        cleanups.length--;
        result ~= formatD("delegua_sair_tente(%s);", inner);
        foreach (size_t i, CatchClause c; node.catches)
        {
            dstring condition = c.type is null ? "true"d : formatD("delegua_tipo_compativel(%s->error,%s)",
                    inner, cString(c.type.toStr()));
            result ~= formatD("%sif(%s) {", i ? "else "d : ""d, condition);
            if (c.name.length)
                result ~= formatD("volatile delegua_value %s=%s->error;", cName(c.name), inner);
            foreach (Node child; c.body)
                result ~= compileStmtOrdered(child);
            result ~= "}";
        }
        result ~= (node.catches.length ? "else "d : ""d) ~ formatD("{delegua_falhar(%s->error);}", inner);
        result ~= "}";
        result ~= formatD("delegua_sair_tente(%s);", outer);
        cleanups.length--;
        foreach (Node child; node.finalBody)
            result ~= compileStmtOrdered(child);
        result ~= formatD("} else { delegua_sair_tente(%s);", outer);
        foreach (Node child; node.finalBody)
            result ~= compileStmtOrdered(child);
        result ~= formatD("delegua_falhar(%s->error); } }", outer);
        return location(node) ~ ";\n" ~ result.join("\n");
    }

    public dstring materialize(Node node)
    {
        dstring expr = compileExpr(node);
        dstring name = formatD("cgd_tmp_%d", tmp++);
        emitLocal(formatD("%s %s = %s;", VALUE, name, expr));
        return name;
    }

    dstring captureExpr(Node node, out dstring expression)
    {
        pushFrame();
        expression = compileExpr(node);
        return popFrame().join("\n");
    }

    dstring loopCode(Node condition, Node[] body, Node step = null, bool post = false)
    {
        dstring label = formatD("cgd_continue_%d", tmp++);
        enterLoop(label);
        dstring test;
        dstring setup = condition is null ? ""d : captureExpr(condition, test);
        dstring check = condition is null ? ""d : setup ~ formatD("\nif (!delegua_is_truthy(%s)) break;", test);
        dstring[] result = ["while (1) {"d];
        if (!post)
            result ~= check;
        foreach (Node child; body)
            result ~= compileStmtOrdered(child);
        result ~= label ~ ":;";
        if (step !is null)
            result ~= compileStmtOrdered(step);
        if (post)
            result ~= check;
        result ~= "}";
        result ~= label ~ "_break:;";
        leaveLoop(label);
        return result.join("\n");
    }

    dstring[] includes = [`#include "vendor/delegua-runtime/src/delegua_rt.h"`];

    dstring[] prototypes = ["\n/* protótipos */",];

    dstring[] code = ["\n\n/* código */"];

    dstring[][] pendingStack;

    pragma(inline, true) void pushFrame()
    {
        pendingStack ~= (dstring[]).init;
    }

    pragma(inline, true) dstring[] popFrame()
    {
        dstring[] top = pendingStack[$ - 1];
        pendingStack.length -= 1;
        return top;
    }

    const BuiltinFn[dstring] builtinFn = ["escreva": &compileEscreva];

    pragma(inline, true) dstring genIndent(uint indent = 0)
    {
        dstring buffer;
        while (indent-- > 0)
            buffer ~= " ";
        return buffer;
    }

    pragma(inline, true) void emit(dstring line, uint indent = 0)
    {
        code ~= genIndent(indent) ~ line;
    }

    // emitLocal(): vai para o frame local do topo da pilha, se
    // houver um aberto; caso contrário cai no buffer global (isso
    // preserva o comportamento antigo fora de qualquer frame, ex.
    // no nível de compile()/compileFnDecl(), que já emitem direto).
    pragma(inline, true) void emitLocal(dstring line, uint indent = 0)
    {
        if (pendingStack.length > 0)
            pendingStack[$ - 1] ~= genIndent(indent) ~ line;
        else
            emit(line, indent);
    }

    pragma(inline, true) void emitProto(dstring line, uint indent = 0)
    {
        prototypes ~= genIndent(indent) ~ line;
    }

    void compileDecl(Node node)
    {
        if (node is null || node.kind == NodeKind.NaN)
            return;
        switch (node.kind)
        {
            case NodeKind.FnDecl:
                return compileFnDecl(cast(FnDecl) node);

            default:
                writeln("...");
                return;
        }
    }

    public dstring compileStmt(Node node)
    {
        if (node is null)
            return "/* Nó nulo recebido no codegen */";
        if (node.kind == NodeKind.NaN)
            return "/* NaN */";
        switch (node.kind)
        {
            case NodeKind.SequenceStmt:
                dstring[] statements;
                foreach (Node child; (cast(SequenceStmt) node).body)
                    statements ~= compileStmtOrdered(child);
                return statements.join("\n");
            case NodeKind.EachStmt:
                EachStmt loop = cast(EachStmt) node;
                dstring iterable = materialize(loop.iterable);
                dstring idx = formatD("cgd_idx_%d", tmp++);
                dstring label = formatD("cgd_continue_%d", tmp++);
                enterLoop(label);
                dstring[] body;
                if (loop.bindingType !is null && loop.bindingType.toStr() != "qualquer")
                    body ~= atSite(formatD("%s=%s", cName(loop.name), checked(cName(loop.name),
                            loop.bindingType)), loop.pos) ~ ";";
                foreach (size_t i, dstring name; loop.destructured)
                {
                    dstring element = formatD("delegua_obter(%s,create_num(%s))", cName(loop.name), i);
                    TypeExpr type = i < loop.destructuredTypes.length ? loop.destructuredTypes[i] : null;
                    body ~= formatD("volatile delegua_value %s=%s;", cName(name),
                            atSite(checked(element, type), loop.pos));
                }
                foreach (Node child; loop.body)
                    body ~= compileStmtOrdered(child);
                leaveLoop(label);
                return formatD("for (sz %s = 0; %s < delegua_tamanho(%s); ++%s) {\n%s %s = delegua_iterar(%s, %s);\n%s\n%s:;\n}\n%s_break:;",
                        idx, idx, iterable, idx, "volatile "d ~ VALUE, cName(loop.name), iterable,
                        idx, body.join("\n"), label, label);
            case NodeKind.TryStmt:
                return compileTry(cast(TryStmt) node);
            case NodeKind.ThrowStmt:
                dstring thrown = materialize((cast(ThrowStmt) node).value);
                return location(node) ~ ";" ~ formatD("delegua_falhar(%s);", thrown);
            case NodeKind.ForStmt:
                ForStmt loop = cast(ForStmt) node;
                dstring init = loop.init is null ? ""d : compileStmtOrdered(loop.init);
                return "{\n" ~ init ~ "\n" ~ loopCode(loop.condition, loop.body, loop.step) ~ "\n}";
            case NodeKind.DoStmt:
                DoStmt loop = cast(DoStmt) node;
                return loopCode(loop.condition, loop.body, null, true);
            case NodeKind.BreakStmt:
                return cleanupCode(breakTryDepth[$ - 1]) ~ "\ngoto " ~ breakLabels[$ - 1] ~ ";";
            case NodeKind.ContinueStmt:
                return cleanupCode(loopTryDepth[$ - 1]) ~ "\ngoto " ~ continueLabels[$ - 1] ~ ";";
            case NodeKind.VarDecl:
                VarDecl var = cast(VarDecl) node;
                dstring initial = var.type_expr !is null && !var.uninitialized
                    && var.type_expr.toStr() != "qualquer" ? materialize(var.value) : compileExpr(var.value);
                return formatD("volatile %s %s = %s;", VALUE, cName(var.name), checked(initial,
                        var.uninitialized ? null : var.type_expr, var.pos));

            case NodeKind.ReturnStmt:
                ReturnStmt ret = cast(ReturnStmt) node;
                dstring value = ret.val is null ? "create_nulo()"d : materialize(ret.val);
                if (ret.collectionReturn)
                {
                    Collector collector = collectors[$ - 1];
                    return cleanupCode(collector.depth) ~ formatD("\ndelegua_vetor_adicionar(&%s,%s); goto %s;",
                            collector.output, value, collector.label);
                }
                return cleanupCode(0) ~ formatD("\nreturn %s;", checked(value, functionReturn, ret.pos));

            case NodeKind.CallExpr:
            case NodeKind.UnaryExpr:
                return "(void)(" ~ compileExpr(node) ~ ");";

            case NodeKind.IfStmt:
                return compileIfStmt(to!IfStmt(node));

            case NodeKind.AssignStmt:
                return "(void)(" ~ compileExpr(node) ~ ");";
            case NodeKind.SwitchStmt:
                return compileSwitch(cast(SwitchStmt) node);
            case NodeKind.NaN:
                return ";";
            case NodeKind.BlockStmt:
                BlockStmt block = cast(BlockStmt) node;
                dstring[] body;

                foreach (Node child; block.body)
                    body ~= compileStmtOrdered(child);

                return "{\n" ~ body.join("\n") ~ "\n}";

            case NodeKind.WhileStmt:
                WhileStmt wstmt = cast(WhileStmt) node;
                return loopCode(wstmt.expr, wstmt.body);

            case NodeKind.ClassDecl:
            case NodeKind.FnDecl:
                return ";";
            case NodeKind.MemberExpr:
                return "(void)(" ~ compileExpr(node) ~ ");";

            default:
                return "/* statement desconhecido. */";
        }
    }

    // -------------------------------------------------------------
    // compileStmtOrdered: abre um frame local, roda compileStmt(),
    // e devolve TODOS os efeitos colaterais gerados durante essa
    // chamada seguidos da linha final do statement, na ordem
    // correta. É isso que garante que side effects de UM statement
    // nunca vazem para antes de statements anteriores do mesmo
    // bloco (o bug do `i++` saindo antes de `a_bits`/`b_bits`).
    // -------------------------------------------------------------
    dstring compileStmtOrdered(Node node)
    {
        pushFrame();
        dstring result = compileStmt(node);
        dstring[] sideEffects = popFrame();

        if (sideEffects.length == 0)
            return result;

        return (sideEffects ~ result).join("\n");
    }

    dstring location(Position pos)
    {
        if (pos is null)
            return "";
        string key = format("%s:%s:%s", pos.filename, pos.start.line, pos.start.offset);
        size_t index;
        if (size_t* cached = key in sourceSiteIds)
            index = *cached;
        else
        {
            index = sourceSites.length;
            sourceSiteIds[key] = index;
            sourceSites ~= formatD("{%s,%s,%s}", cString(pos.filename.to!dstring), pos.start.line, pos.start.offset);
        }
        return formatD("delegua_local_atual=&cgd_source_sites[%s]", index);
    }

    dstring location(Node node)
    {
        return node is null ? ""d : location(node.pos);
    }

    dstring atSite(dstring expression, Position pos)
    {
        dstring site = location(pos);
        return site.length ? "(" ~ site ~ ", " ~ expression ~ ")" : expression;
    }

    bool canFail(Node node)
    {
        if (node is null)
            return false;
        switch (node.kind)
        {
            case NodeKind.CallExpr:
            case NodeKind.IndexExpr:
            case NodeKind.MemberExpr:
            case NodeKind.UnaryExpr:
            case NodeKind.SliceExpr:
            case NodeKind.ImportExpr:
                return true;
            default:
                return false;
        }
    }

    public dstring compileExpr(Node node)
    {
        if (node !is null && (cast(ArrayLit) node || cast(MapLit) node || cast(Comprehension) node))
        {
            dstring site = location(node);
            if (site.length)
                emitLocal(site ~ ";");
        }
        dstring expression = compileExprIntern(node);
        dstring site = canFail(node) ? location(node) : ""d;
        return site.length ? "(" ~ site ~ ", " ~ expression ~ ")" : expression;
    }

    private dstring compileExprIntern(Node node)
    {
        if (node is null)
            return "/* Nó nulo recebido no codegen */";
        if (node.kind == NodeKind.NaN)
            return "/* NaN */";

        switch (node.kind)
        {
            case NodeKind.AssignStmt:
                return compileAssignment(cast(AssignStmt) node);
            case NodeKind.SpreadExpr:
                throw new Exception("Espalhamento fora de chamada/coleção.");
            case NodeKind.ConditionalExpr:
                ConditionalExpr c = cast(ConditionalExpr) node;
                dstring test = materialize(c.condition);
                dstring resultName = formatD("cgd_cond_%s", tmp++);
                emitLocal(formatD("delegua_value %s;", resultName));
                dstring yes, no;
                dstring yesSetup = captureExpr(c.yes, yes), noSetup = captureExpr(c.no, no);
                emitLocal(formatD("if(delegua_is_truthy(%s)){%s\n%s=%s;}else{%s\n%s=%s;}", test,
                        yesSetup, resultName, yes, noSetup, resultName, no));
                return resultName;
            case NodeKind.SliceExpr:
                SliceExpr s = cast(SliceExpr) node;
                dstring value = materialize(s.value);
                dstring start = s.start is null ? "create_nulo()"d : materialize(s.start);
                dstring end = s.end is null ? "create_nulo()"d : materialize(s.end);
                dstring step = s.step is null ? "create_nulo()"d : materialize(s.step);
                return formatD("delegua_intervalo(%s,%s,%s,%s)", value, start, end, step);
            case NodeKind.LoopExpr:
                LoopExpr l = cast(LoopExpr) node;
                dstring resultName = formatD("cgd_loop_%s", tmp++);
                emitLocal(formatD("delegua_value %s=create_vetor();", resultName));
                dstring oldPending = pendingCollector;
                pendingCollector = resultName;
                emitLocal(compileStmtOrdered(l.loop));
                pendingCollector = oldPending;
                return resultName;
            case NodeKind.Comprehension:
                Comprehension c = cast(Comprehension) node;
                dstring source = materialize(c.iterable);
                dstring resultName = formatD("cgd_comp_%s", tmp++), idx = formatD("cgd_comp_i_%s", tmp++);
                emitLocal(formatD("delegua_value %s=create_vetor();", resultName));
                dstring value, condition;
                dstring valueSetup = captureExpr(c.value, value);
                dstring condSetup = c.condition is null ? ""d : captureExpr(c.condition, condition);
                dstring body = formatD("%s\ndelegua_vetor_adicionar(&%s,%s);", valueSetup, resultName, value);
                if (c.condition !is null)
                    body = formatD("%s\nif(delegua_is_truthy(%s)){%s}", condSetup, condition, body);
                emitLocal(formatD("for(sz %s=0;%s<delegua_tamanho(%s);++%s){volatile delegua_value %s=%s;%s}", idx,
                        idx, source, idx, cName(c.name), checked(formatD("delegua_iterar(%s,%s)",
                        source, idx), c.bindingType, c.pos), body));
                return resultName;
            case NodeKind.Identifier:
                Identifier id = cast(Identifier) node;
                if (id.classRef !is null)
                    return classValue(id.classRef);
                return id.functionRef is null ? cName(id.value) : functionValue(id.functionRef);

            case NodeKind.UnaryExpr:
                UnaryExpr unary = cast(UnaryExpr) node;
                LValue lv = resolveLValue(unary.value);
                dstring previous = formatD("cgd_tmp_%d", tmp++);
                dstring updated = formatD("cgd_tmp_%d", tmp++);
                dstring site = location(node);
                if (site.length)
                    emitLocal(site ~ ";");
                emitLocal(formatD("%s %s = %s;", VALUE, previous, lv.read()));
                emitLocal(formatD("%s %s = %s;", VALUE, updated, atSite(formatD("delegua_op_%s(%s,create_num(1))",
                        unary.op == TokenKind.PPlus ? "add" : "sub", previous), node.pos)));
                emitLocal(atSite(lv.write(updated), node.pos) ~ ";");
                return unary.post ? previous : updated;
            case NodeKind.MapLit:
                MapLit map = cast(MapLit) node;
                dstring name = formatD("cgd_map_%d", tmp++);
                emitLocal(formatD("%s %s = create_map();", VALUE, name));
                foreach (size_t i, Node key; map.keys)
                {
                    if (key is null)
                    {
                        SpreadExpr spread = cast(SpreadExpr) map.values[i];
                        emitLocal(formatD("delegua_map_expandir(%s,%s);", name, materialize(spread.value)));
                        continue;
                    }
                    dstring k = materialize(key);
                    dstring v = materialize(map.values[i]);
                    emitLocal(formatD("delegua_map_setar(%s, %s, %s);", name, k, v));
                }
                return name;
            case NodeKind.NullLit:
                return "create_nulo()";
            case NodeKind.BinaryExpr:
                BinaryExpr binary = cast(BinaryExpr) node;
                dstring left = materialize(binary.left);
                dstring result = formatD("cgd_tmp_%d", tmp++);
                emitLocal(formatD("%s %s = %s;", VALUE, result, left));
                dstring condition = binary.op == TokenKind.And ? formatD("delegua_is_truthy(%s)",
                        left) : binary.op == TokenKind.Or
                    ? formatD("!delegua_is_truthy(%s)", left) : formatD("%s.type == DELEGUA_T_NULO", left);
                dstring right;
                dstring setup = captureExpr(binary.right, right);
                emitLocal(formatD("if (%s) {\n%s\n%s = %s;\n}", condition, setup, result, right));
                return result;
            case NodeKind.ImportExpr:
                ImportExpr imported = cast(ImportExpr) node;
                dstring name = cName(imported.target.linkName);
                return formatD("(%s_init(), %s)", name, name);
            case NodeKind.SuperExpr:
                SuperExpr superExpr = cast(SuperExpr) node;
                return formatD("delegua_super_metodo(%s, %s, %s)", lexicalClass(), cName("isto"),
                        cString(superExpr.name));
            case NodeKind.FunctionExpr:
                return functionValue((cast(FunctionExpr) node).declaration);
            case NodeKind.MemberExpr:
                MemberExpr member = cast(MemberExpr) node;
                dstring receiver = materialize(member.left);
                return formatD("delegua_propriedade_em(%s, %s, %s)", receiver,
                        cString((cast(Identifier) member.right).value), lexicalClass());
            case NodeKind.StringLit:
                dstring text = (cast(StringLit) node).value;
                return formatD("create_text_len(%s, %s)", cString(text), text.to!string.length);

            case NodeKind.IntLit:
                return formatD("create_num(%d)", (cast(IntLit) node).value);

            case NodeKind.DoubleLit:
                return formatD("create_real(%.17g)", (cast(DoubleLit) node).value);

            case NodeKind.BoolLit:
                return formatD("create_bool(%d)", (cast(BoolLit) node).value);

            case NodeKind.CallExpr:
                CallExpr call = cast(CallExpr) node;
                if (call.runtimeCall)
                    return formatD("%s(%s)", (cast(Identifier) call.fn).value, nodesToStr(call.args));
                dstring callee = materialize(call.fn);
                if (call.args.any!((Node a) => a.kind == NodeKind.SpreadExpr))
                {
                    dstring vector = formatD("cgd_args_%s", tmp++);
                    emitLocal(formatD("delegua_value %s=create_vetor();", vector));
                    foreach (Node arg; call.args)
                    {
                        if (SpreadExpr spread = cast(SpreadExpr) arg)
                            emitLocal(formatD("delegua_expandir(&%s,%s);", vector, materialize(spread.value)));
                        else
                            emitLocal(formatD("delegua_vetor_adicionar(&%s,%s);", vector, materialize(arg)));
                    }
                    return formatD("delegua_chamar_vetor(%s,%s)", callee, vector);
                }
                dstring args = nodesToStr(call.args);
                return formatD("delegua_chamar(%s, %s, %s)", callee, call.args.length,
                        call.args.length ? "(delegua_value[]){" ~ args ~ "}" : "NULL");

            case NodeKind.TupleLit:
            case NodeKind.ArrayLit:
                ArrayLit arr = cast(ArrayLit) node;

                dstring temp = formatD("t%d", tmp++);
                // cria uma variavel temporaria
                emitLocal(formatD("%s %s = create_vetor();", VALUE, temp));

                foreach (Node element; arr.elements)
                    if (SpreadExpr spread = cast(SpreadExpr) element)
                        emitLocal(formatD("delegua_expandir(&%s,%s);", temp, materialize(spread.value)));
                    else
                        emitLocal(formatD("delegua_vetor_adicionar(&%s, %s);", temp, compileExpr(element)));

                return node.kind == NodeKind.TupleLit ? formatD("delegua_para_tupla(%s)", temp) : temp;

            case NodeKind.IndexExpr:
                return compileIndexExpr(cast(IndexExpr) node);

            case NodeKind.BlockStmt:
                BlockStmt block = cast(BlockStmt) node;
                dstring[] body;

                foreach (Node child; block.body)
                    body ~= compileStmtOrdered(child);

                for (size_t i; i + 1 < block.body.length; i++)
                    emitLocal(body[i]);

                return compileExpr(block.body[$ - 1]);

            default:
                node.print();
                return "/* expressão desconhecida. */";
        }
    }

    LValue resolveLValue(Node node)
    {
        switch (node.kind)
        {
            case NodeKind.MemberExpr:
                MemberExpr member = cast(MemberExpr) node;
                return LValue(LValueKind.Member, null, materialize(member.left),
                        cString((cast(Identifier) member.right).value), lexicalClass());
            case NodeKind.Identifier:
                return LValue(LValueKind.Var, cName((cast(Identifier) node).value));

            case NodeKind.IndexExpr:
                IndexExpr idx = cast(IndexExpr) node;
                return LValue(LValueKind.Index, null, materialize(idx.value), // container reference, evaluated once
                        materialize(idx.idx) // index evaluated once

                        );

            default:
                node.print();
                assert(0, "nó não é um lvalue válido");
        }
    }

    dstring compileIndexExpr(IndexExpr idxexpr)
    {
        // o vetor é passado por referencia
        dstring value = materialize(idxexpr.value); // vetor
        dstring idx = materialize(idxexpr.idx); // indice

        return formatD("delegua_obter(%s, %s)", value, idx);
    }

    dstring functionValue(FnDecl node)
    {
        if (node.builtinName.length)
            return formatD("delegua_builtin(%s)", cString(node.builtinName));
        size_t minimum;
        foreach (FnArg arg; node.args)
            if (arg.value is null && !arg.rest)
                minimum++;
        dstring maximum = node.args.length && node.args[$ - 1].rest ? "SIZE_MAX"d : node.args.length.to!dstring;
        if (node.anonymous)
            return formatD("create_funcao_intervalo(&%s,%s,%s)", cName(node.linkName), minimum, maximum);
        return formatD("delegua_funcao_cache(&%s_slot,&%s,%s,%s)", cName(node.linkName),
                cName(node.linkName), minimum, maximum);
    }

    void compileFnDecl(FnDecl node)
    {
        dstring proto = formatD("delegua_value %s(sz argc, delegua_value *argv)", cName(node.linkName));
        emitProto(proto ~ ";");
        emitProto(formatD("static delegua_value %s_slot;", cName(node.linkName)));
        ClassDecl previousClass = currentClass;
        currentClass = node.ownerClass;
        TypeExpr previousReturn = functionReturn;
        functionReturn = node.type_expr;
        emit(proto ~ " {\n(void)argc; (void)argv;");
        if (node.isMethod && !node.isStatic)
            emit(formatD("volatile delegua_value %s=argv[0];", cName("isto")));
        foreach (size_t i, FnArg arg; node.args)
        {
            dstring binding = formatD("volatile delegua_value %s;", cName(arg.name));
            emit(binding);
            if (arg.rest)
                emit(formatD("%s=delegua_rest(argc,argv,%s);", cName(arg.name), i + (node.isMethod
                        && !node.isStatic ? 1 : 0)));
            else if (arg.value is null)
                emit(formatD("%s = argv[%s];", cName(arg.name), i + (node.isMethod && !node.isStatic ? 1 : 0)));
            else
            {
                dstring value;
                dstring setup = captureExpr(arg.value, value);
                emit(formatD("if (argc > %s) %s = argv[%s]; else {\n%s\n%s = %s;\n}",
                        i + (node.isMethod && !node.isStatic ? 1 : 0), cName(arg.name),
                        i + (node.isMethod && !node.isStatic ? 1 : 0), setup, cName(arg.name), value));
            }
        }
        foreach (FnArg arg; node.args)
            if (arg.type_expr !is null)
                emit(formatD("%s=%s;", cName(arg.name), checked(cName(arg.name), arg.rest
                        ? new TypeExprArray(arg.type_expr, arg.pos) : arg.type_expr)));
        foreach (Node n; node.body)
            emit(compileStmtOrdered(n), 4);
        emit("return " ~ checked("create_nulo()", functionReturn) ~ ";\n}");
        currentClass = previousClass;
        functionReturn = previousReturn;
    }

    FnDecl[] functions;
    bool[FnDecl] functionsInitialized, functionsInitializing;
    dstring metadata(Decorator[] decorators)
    {
        dstring list = formatD("cgd_attrs_%s", tmp++);
        emitLocal(formatD("delegua_value %s=create_vetor();", list));
        foreach (Decorator d; decorators)
        {
            dstring attr = formatD("cgd_attr_%s", tmp++), args = formatD("cgd_attr_args_%s", tmp++);
            emitLocal(formatD("delegua_value %s=create_map(),%s=create_map();", attr, args));
            foreach (size_t i, Node value; d.values)
                emitLocal(formatD("delegua_map_setar(%s,create_text(%s),%s);", args,
                        cString(d.keys[i]), materialize(value)));
            emitLocal(formatD("delegua_map_setar(%s,create_text(\"nome\"),create_text(%s));", attr, cString(d.name)));
            emitLocal(formatD("delegua_map_setar(%s,create_text(\"argumentos\"),%s);delegua_vetor_adicionar(&%s,%s);",
                    attr, args, list, attr));
        }
        return list;
    }

    void initializeFunction(FnDecl fn)
    {
        if (fn in functionsInitialized)
            return;
        if (fn in functionsInitializing)
            throw new Exception("Ciclo entre envelopes de decoradores.");
        functionsInitializing[fn] = true;
        foreach (Decorator d; fn.decorators)
            if (d.envelope !is null)
                initializeFunction(d.envelope);
        if (fn.decorators.length)
        {
            dstring original = functionValue(fn);
            dstring name = cName(fn.linkName) ~ "_slot";
            emit(formatD("%s=%s;", name, original));
            foreach_reverse (Decorator d; fn.decorators)
                if (d.envelope !is null)
                    emit(formatD("%s=delegua_assegurar_tipo(delegua_chamar(%s,1,&%s),\"funcao\");",
                            name, functionValue(d.envelope), name));
            dstring attrs = metadata(fn.decorators);
            emit(formatD("delegua_definir_decoradores(%s,%s);", name, attrs));
        }
        functionsInitializing.remove(fn);
        functionsInitialized[fn] = true;
    }

    ModuleUnit[] modules;
    bool[Node] collected;
    ClassDecl[] classes;
    bool[ClassDecl] initializedClasses;
    bool[ClassDecl] classShells;
    void createClassShell(ClassDecl c)
    {
        if (c.signature.builtinName.length || c in classShells)
            return;
        classShells[c] = true;
        if (c.superClass !is null)
            createClassShell(c.superClass);
        dstring name = cName(c.signature.linkName);
        emit(formatD("%s=create_classe(%s,%s);", name, cString(c.name), c.superClass is null
                ? "delegua_classe_objeto()"d : classValue(c.superClass)));
        emit(formatD("delegua_classe_fechada(%s);", name));
    }

    void initializeClass(ClassDecl c)
    {
        if (c.signature.builtinName.length || c in initializedClasses)
            return;
        initializedClasses[c] = true;
        if (c.superClass !is null)
            initializeClass(c.superClass);
        dstring name = cName(c.signature.linkName);
        if (c.decorators.length)
            emit(formatD("delegua_definir_decoradores(%s,%s);", name, metadata(c.decorators)));
        foreach (ClassField field; c.fields)
            if (field.decorators.length)
                emit(formatD("delegua_classe_decoradores_campo(%s,%s,%s);", name,
                        cString(field.name), metadata(field.decorators)));
        foreach (ClassField field; c.fields)
            emit(formatD("delegua_classe_campo_tipo(%s,%s,%s,%s);", name, cString(field.name),
                    descriptor(field.type), field.access));
        foreach (ClassField field; c.fields)
            if (field.customAccess)
                emit(formatD("delegua_classe_acessor(%s,%s,%s,%s,%s,%s);", name, cString(field.name),
                        field.getter is null ? "create_nulo()"d : functionValue(field.getter),
                        field.setter is null ? "create_nulo()"d : functionValue(field.setter),
                        field.readable ? 1 : 0, field.writable ? 1 : 0));
        foreach (FnDecl method; c.methods)
            if (!method.accessor)
                emit(formatD(method.isStatic
                        ? "delegua_classe_metodo_estatico(%s,%s,%s,%s);" : "delegua_classe_metodo_acesso(%s,%s,%s,%s);",
                        name, cString(method.fn), functionValue(method), method.access));
    }

    void compileModule(ModuleUnit m)
    {
        dstring name = cName(m.linkName), frame = name ~ "_frame";
        emit(formatD("static void %s_init(void) { if(%s_state==2) return; if(%s_state==1) delegua_panic(\"Ciclo de inicialização de módulos.\"); %s_state=1;",
                name, name, name, name));
        emit(formatD("delegua_try_frame *const %s=delegua_tentar(); if(setjmp(%s->env)!=0) { delegua_sair_tente(%s); %s_state=0; delegua_falhar(%s->error); }",
                frame, frame, frame, name, frame));
        foreach (Node node; m.program.body)
            if (!isDecl(node.kind))
                emit(compileStmtOrdered(node));
        emit(formatD("delegua_value %s_exports=create_map();", name));
        Node[] exports;
        foreach (Node node; m.program.body)
        {
            if (SequenceStmt sequence = cast(SequenceStmt) node)
                exports ~= sequence.body;
            else
                exports ~= node;
        }
        foreach (Node node; exports)
        {
            dstring key, value;
            if (VarDecl v = cast(VarDecl) node)
            {
                key = v.name;
                value = cName(v.name);
            }
            if (FnDecl fn = cast(FnDecl) node)
            {
                key = fn.fn;
                value = functionValue(fn);
            }
            if (ClassDecl c = cast(ClassDecl) node)
            {
                key = c.name;
                value = classValue(c);
            }
            if (key.length && key[0] != '#')
                emit(formatD("delegua_map_setar(%s_exports,%s,%s);", name, cString(key).length
                        ? formatD("create_text(%s)", cString(key)) : "create_nulo()"d, value));
        }
        emit(formatD("%s=create_modulo(%s_exports); %s_state=2; delegua_sair_tente(%s); }", name, name, name, frame));
    }

    void collectFunctions(Node node)
    {
        if (node is null || node in collected)
            return;
        collected[node] = true;
        if (ModuleUnit m = cast(ModuleUnit) node)
        {
            modules ~= m;
            emitProto(formatD("static delegua_value %s; static int %s_state; static void %s_init(void);",
                    cName(m.linkName), cName(m.linkName), cName(m.linkName)));
        }
        if (ClassDecl c = cast(ClassDecl) node)
        {
            classes ~= c;
            emitProto(formatD("static delegua_value %s;", cName(c.signature.linkName)));
        }
        foreach (Node child; childNodes(node))
            collectFunctions(child);
        if (FnDecl fn = cast(FnDecl) node)
        {
            functions ~= fn;
            compileFnDecl(fn);
        }
    }

    dstring compileIfStmt(IfStmt node, bool fromIf = false)
    {
        dstring[] body;
        foreach (Node child; node.body)
            body ~= compileStmtOrdered(child);
        if (node.expr is null)
            return "{\n" ~ body.join("\n") ~ "\n}";
        dstring condition;
        dstring setup = captureExpr(node.expr, condition);
        dstring result = setup ~ formatD("\nif (delegua_is_truthy(%s)) {\n%s\n}", condition, body.join("\n"));
        if (node._else !is null)
            result ~= " else {\n" ~ compileIfStmt(node._else) ~ "\n}";
        return result;
    }

    pragma(inline, true) bool isDecl(NodeKind kind) => kind == NodeKind.FnDecl || kind == NodeKind.ClassDecl;

    pragma(inline, true) public dstring nodesToStr(Node[] nodes) => (nodes.map!((Node n) => materialize(n)).array).join(
            ", ");

public:
    dstring compile(Program prog)
    {
        collectFunctions(prog);
        foreach (ModuleUnit m; modules)
            compileModule(m);

        emit(formatD("void %s(void) {", ENTRY));
        foreach (ClassDecl c; classes)
            createClassShell(c);
        foreach (ClassDecl c; classes)
            initializeClass(c);
        foreach (FnDecl fn; functions)
            initializeFunction(fn);

        foreach (Node node; prog.body)
            if (!isDecl(node.kind))
                emit(compileStmtOrdered(node), 4);

        emit("}");

        dstring source = includes.join("\n");
        if (sourceSites.length)
            source ~= "\nstatic const delegua_local cgd_source_sites[]={" ~ sourceSites.join(",") ~ "};\n";
        source ~= prototypes.join("\n");
        source ~= code.join("\n");
        return source;
    }
}
