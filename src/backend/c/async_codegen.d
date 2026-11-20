module backend.c.async_codegen;

import backend.c.codegen;
import backend.c.descriptors;
import backend.c.utils;
import frontend.lexer.token;
import frontend.parser;
import frontend.type_expr;
import middle.async_ir;

/// Emite wrapper, frame de suspensão e função step C99 para uma função assíncrona.
void emitAsyncFunction(BackendC backend, FnDecl node, dstring prototype)
{
    AsyncIR ir = new AsyncLowering().lower(node);
    ClassDecl previousClass = backend.currentClass;
    dstring previousSelf = backend.asyncSelf;
    backend.currentClass = node.ownerClass;
    backend.asyncSelf = ir.self == size_t.max ? ""d : cName(ir.slots[ir.self].name);
    scope (exit)
    {
        backend.currentClass = previousClass;
        backend.asyncSelf = previousSelf;
    }
    dstring name = cName(node.linkName), frameName = name ~ "_frame", stepName = name ~ "_step";
    dstring fields;
    foreach (size_t i, AsyncSlot slot; ir.slots)
        if (i in ir.persistent)
            fields ~= formatD("delegua_value v%s;\n", i);
    backend.emitProto(formatD("typedef struct { unsigned pc; %s } %s;\nstatic void %s(rt_task*,sz,delegua_value*);",
            fields, frameName, stepName));
    backend.emit(formatD(
            "%s { rt_task *task=rt_task_create(sizeof(%s),%s,%s); return rt_task_start(task,argc,argv); }",
            prototype, frameName, stepName, typeDescriptor(node.type_expr)));
    backend.emit(formatD("static void %s(rt_task *task,sz argc,delegua_value *argv) {\n(void)argc;(void)argv;\n%s *frame=(%s*)rt_task_frame(task);",
            stepName, frameName, frameName));
    foreach (size_t i, AsyncSlot slot; ir.slots)
    {
        dstring variable = cName(slot.name);
        backend.emit(formatD("volatile delegua_value %s=%s; %s", variable, i in ir.persistent
                ? formatD("frame->v%s", i) : "create_nulo()"d, backend.acknowledgeBinding(variable)));
        if (i in ir.persistent)
            backend.emit(formatD("frame->v%s=create_nulo();", i));
    }
    backend.emit("if(frame->pc==0) {");
    if (ir.self != size_t.max)
        backend.emit(formatD("%s=argv[0];", backend.asyncSelf));
    if (ir.self != size_t.max)
        backend.emit(formatD("delegua_value %s=%s;%s", cName("isto"), backend.asyncSelf,
                backend.acknowledgeBinding(cName("isto"))));
    foreach (size_t i, FnArg argument; node.args)
    {
        dstring variable = cName(argument.name);
        size_t index = i + (ir.self == size_t.max ? 0 : 1);
        backend.emit(formatD("delegua_value %s;", variable));
        if (argument.rest)
            backend.emit(formatD("%s=delegua_rest(argc,argv,%s);", variable, index));
        else if (argument.value is null)
            backend.emit(formatD("%s=argv[%s];", variable, index));
        else
        {
            dstring value;
            dstring setup = backend.captureExpr(argument.value, value);
            backend.emit(formatD("if(argc>%s) %s=argv[%s]; else { %s %s=%s; }", index, variable,
                    index, setup, variable, value));
        }
        backend.emit(backend.acknowledgeBinding(variable));
    }
    foreach (size_t i, FnArg argument; node.args)
        backend.emit(formatD("%s=%s;", cName(ir.slots[ir.parameters[i]].name),
                backend.checked(cName(argument.name), argument.rest
                ? new TypeExprArray(argument.type_expr, argument.pos) : argument.type_expr)));
    backend.emit("}\ndelegua_try_frame *const cgd_async_boundary=delegua_tentar();");
    backend.emit("if(setjmp(cgd_async_boundary->env)!=0){");
    backend.emit(formatD("%s=cgd_async_boundary->error;switch(frame->pc){", cName(ir.slots[ir.error].name)));
    foreach (size_t index, AsyncInstruction instruction; ir.instructions)
        if (instruction.exceptional != size_t.max)
            backend.emit(formatD("case %s:frame->pc=%s;break;", index, instruction.exceptional));
    backend.emit(formatD("default:delegua_sair_tente(cgd_async_boundary);delegua_falhar(%s);return;}}",
            cName(ir.slots[ir.error].name)));
    backend.emit("for(;;) {switch(frame->pc) {");
    foreach (size_t i, AsyncInstruction instruction; ir.instructions)
    {
        backend.emit(formatD("case %s: {rt_task_mask_cancel(task,%s);", i, instruction.cleanup ? "true" : "false"));
        dstring value, setup;
        if (instruction.value !is null && instruction.op != AsyncOp.Resume)
            setup = backend.captureExpr(instruction.value, value);
        backend.emit(setup);
        final switch (instruction.op)
        {
            case AsyncOp.CaptureReturn:
                backend.emit(formatD("%s=%s;",
                        cName(ir.slots[instruction.target].name), value));
                break;
            case AsyncOp.Evaluate:
                backend.emit(formatD("%s=%s;",
                        cName(ir.slots[instruction.target].name), backend.checked(value,
                        ir.slots[instruction.target].type, instruction.value.pos)));
                break;
            case AsyncOp.Jump:
                break;
            case AsyncOp.Branch:
                backend.emit(formatD("frame->pc=(%s)?%s:%s;continue;",
                        instruction.condition == TokenKind.Coalesce
                        ? value ~ ".type==DELEGUA_T_NULO" : formatD("delegua_is_truthy(%s)", value),
                        instruction.next, instruction.alternative));
                break;
            case AsyncOp.Await:
                foreach (size_t index, AsyncSlot slot; ir.slots)
                    if (index in ir.persistent)
                        backend.emit(formatD("frame->v%s=%s;", index, index in ir.liveOut[i]
                                ? cName(slot.name) : "create_nulo()"d));
                backend.emit(formatD(
                        "frame->pc=%s;%s;rt_task_await(task,%s);delegua_sair_tente(cgd_async_boundary);return;",
                        instruction.next, backend.location(instruction.value), value));
                break;
            case AsyncOp.Resume:
                backend.emit(formatD("%s;%s=rt_task_input(task);",
                        backend.location(instruction.value), cName(ir.slots[instruction.target].name)));
                break;
            case AsyncOp.Return:
                backend.emit(formatD("rt_task_finish(task,%s);delegua_sair_tente(cgd_async_boundary);return;",
                        backend.checked(value, node.type_expr, instruction.value.pos)));
                break;
            case AsyncOp.Throw:
                backend.emit(formatD("%s;delegua_falhar(%s);return;",
                        backend.location(instruction.value), value));
                break;
        }
        if (instruction.op == AsyncOp.Evaluate || instruction.op == AsyncOp.CaptureReturn
                || instruction.op == AsyncOp.Resume || instruction.op == AsyncOp.Jump)
            backend.emit(formatD("frame->pc=%s;continue;", instruction.next));
        backend.emit("}");
    }
    backend.emit(
            "default: delegua_sair_tente(cgd_async_boundary);delegua_panic(\"Estado assíncrono inválido.\");return;}}}");
}
