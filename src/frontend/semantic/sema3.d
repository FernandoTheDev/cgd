// resolve todos os nodes
module frontend.semantic.sema3;
import catalog = diagnostics.catalog;

import std.algorithm;
import std.exception;
import std.format;
import std.array;
import std.stdio;

import backend.c.codegen;
import frontend.semantic;
import frontend.parser;
import backend.c.utils;
import ctfe.ctfe_flags;
import frontend.lexer;
import frontend;
import errors;
import utils;

class Sema3
{
private:
    Context context;
    TypeRegistry registry;
    TypeResolver resolver;
    Diagnostics err;
    size_t loopDepth, functionDepth, switchDepth, collectionDepth;
    TypeSema[] returnTypes;
    ClassDecl methodOwner;

    TypeSema anyType()
    {
        return new TypeSemaBuiltin(TypeSemaBase.Any);
    }

    void missingSymbol(Identifier node)
    {
        if (context.requiresCapture(node.value))
        {
            err.warningCode(node.pos, catalog.captureWarning, node.value);
            err.errorCode(node.pos, catalog.captureError);
        }
        else
        {
            err.errorCode(node.pos, catalog.missingSymbol, node.value);
            dstring suggestion = context.suggest(node.value);
            if (suggestion.length)
                err.hintCode(node.pos, catalog.suggestion, suggestion);
        }
        node.type_sema = anyType();
    }

    bool metadataConstant(Node node)
    {
        if (node is null)
            return true;
        switch (node.kind)
        {
            case NodeKind.StringLit:
            case NodeKind.IntLit:
            case NodeKind.DoubleLit:
            case NodeKind.BoolLit:
            case NodeKind.NullLit:
                return true;
            case NodeKind.ArrayLit:
            case NodeKind.MapLit:
            case NodeKind.UnaryExpr:
            case NodeKind.BinaryExpr:
                foreach (Node child; childNodes(node))
                    if (!metadataConstant(child))
                        return false;
                return true;
            default:
                return false;
        }
    }

    void analyzeDecorators(ref Decorator[] decorators, Position pos, bool envelopes = false)
    {
        foreach (ref Decorator d; decorators)
        {
            foreach (ref Node value; d.values)
            {
                if (!metadataConstant(value))
                    err.error(pos,
                            "Argumentos de metadados devem ser expressões constantes sem execução de funções.");
                value = analyze(value);
            }
            Symbol* sym = context.get(d.name);
            if (sym !is null && sym.isFn() && (cast(SymbolFn*) sym).node.decoratorEnvelope)
            {
                if (!envelopes)
                    err.error(pos,
                            "Envelope de decorador exige uma função livre; metadados são permitidos neste membro.");
                else
                    d.envelope = (cast(SymbolFn*) sym).node;
            }
        }
    }

    void predeclare(Node[] body)
    {
        foreach (Node child; body)
            if (FnDecl fn = cast(FnDecl) child)
            {
                if (!context.set(fn.fn, new SymbolFn(fn)))
                    err.error(fn.pos, "Função duplicada neste escopo.");
            }
    }

    void analyzeBody(ref Node[] body)
    {
        context.push();
        predeclare(body);
        foreach (ref Node child; body)
            child = analyze(child);
        context.pop();
    }

    Node analyze(Node node, bool comptimeValue = false)
    {
        if (node is null)
            return null;
        if ((node.type_sema !is null && node.kind != NodeKind.FnDecl) || node.kind == NodeKind.NaN)
            return node;

        switch (node.kind)
        {
            case NodeKind.SequenceStmt:
                SequenceStmt sequence = cast(SequenceStmt) node;
                foreach (ref Node child; sequence.body)
                    child = analyze(child);
                return node;
            case NodeKind.ConditionalExpr:
                ConditionalExpr c = cast(ConditionalExpr) node;
                c.condition = analyze(c.condition);
                c.yes = analyze(c.yes);
                c.no = analyze(c.no);
                node.type_sema = anyType();
                return node;
            case NodeKind.SpreadExpr:
                SpreadExpr s = cast(SpreadExpr) node;
                s.value = analyze(s.value);
                node.type_sema = anyType();
                return node;
            case NodeKind.SliceExpr:
                SliceExpr s = cast(SliceExpr) node;
                s.value = analyze(s.value);
                s.start = analyze(s.start);
                s.end = analyze(s.end);
                s.step = analyze(s.step);
                node.type_sema = s.value.type_sema;
                return node;
            case NodeKind.Comprehension:
                Comprehension c = cast(Comprehension) node;
                c.iterable = analyze(c.iterable);
                context.push();
                VarDecl v = new VarDecl(c.name, null, false, c.bindingType, c.pos);
                v.type_sema = c.bindingType is null ? anyType() : resolver.resolver(c.bindingType);
                context.set(c.name, new SymbolVar(v));
                c.value = analyze(c.value);
                c.condition = analyze(c.condition);
                context.pop();
                node.type_sema = new TypeSemaArray(anyType());
                return node;
            case NodeKind.LoopExpr:
                LoopExpr l = cast(LoopExpr) node;
                collectionDepth++;
                l.loop = analyze(l.loop);
                collectionDepth--;
                node.type_sema = new TypeSemaArray(anyType());
                return node;
            case NodeKind.SwitchStmt:
                SwitchStmt s = cast(SwitchStmt) node;
                s.value = analyze(s.value);
                switchDepth++;
                foreach (ref SwitchCase c; s.cases)
                {
                    foreach (ref Node v; c.values)
                        v = analyze(v);
                    analyzeBody(c.body);
                }
                analyzeBody(s.fallback);
                switchDepth--;
                return node;
            case NodeKind.ImportExpr:
                ImportExpr imported = cast(ImportExpr) node;
                if (imported.target !is null && !imported.target.analyzed)
                {
                    ModuleUnit unit = imported.target;
                    unit.analyzed = true;
                    Context ctx = new Context;
                    TypeRegistry types = new TypeRegistry;
                    new Sema1(ctx, err).analyze(unit.program);
                    new Sema2(types).analyze(unit.program);
                    new Sema3(ctx, types, new TypeResolver(types, err), err).analyze(unit.program);
                }
                node.type_sema = anyType();
                return node;
            case NodeKind.ThrowStmt:
                ThrowStmt t = cast(ThrowStmt) node;
                t.value = analyze(t.value);
                return node;
            case NodeKind.TryStmt:
                TryStmt t = cast(TryStmt) node;
                analyzeBody(t.body);
                foreach (ref CatchClause c; t.catches)
                {
                    context.push();
                    if (c.type !is null)
                        resolver.resolver(c.type);
                    if (c.name.length)
                    {
                        VarDecl v = new VarDecl(c.name, null, true, c.type, c.pos);
                        v.type_sema = anyType();
                        context.set(c.name, new SymbolVar(v, true));
                    }
                    foreach (ref Node child; c.body)
                        child = analyze(child);
                    context.pop();
                }
                analyzeBody(t.finalBody);
                return node;
            case NodeKind.ClassDecl:
                return analyzeClass(cast(ClassDecl) node);
            case NodeKind.SuperExpr:
                SuperExpr s = cast(SuperExpr) node;
                if (methodOwner is null || methodOwner.superClass is null)
                    err.error(node.pos, "Uso de super fora de uma subclasse.");
                s.owner = methodOwner;
                node.type_sema = new TypeSemaBuiltin(TypeSemaBase.Function);
                return node;
            case NodeKind.FunctionExpr:
                FunctionExpr f = cast(FunctionExpr) node;
                analyzeFnDecl(f.declaration, false);
                node.type_sema = new TypeSemaBuiltin(TypeSemaBase.Function);
                return node;
            case NodeKind.EachStmt:
                EachStmt loop = cast(EachStmt) node;
                loop.iterable = analyze(loop.iterable);
                context.push();
                VarDecl variable = new VarDecl(loop.name, null, false, loop.bindingType, loop.pos);
                variable.type_sema = loop.bindingType is null ? anyType() : resolver.resolver(loop.bindingType);
                context.set(loop.name, new SymbolVar(variable));
                foreach (size_t i, dstring name; loop.destructured)
                {
                    TypeExpr type = i < loop.destructuredTypes.length ? loop.destructuredTypes[i] : null;
                    VarDecl v = new VarDecl(name, null, false, type, loop.pos);
                    v.type_sema = type is null ? anyType() : resolver.resolver(type);
                    if (!context.set(name, new SymbolVar(v)))
                        err.error(loop.pos, "Nome duplicado na iteração.");
                }
                loopDepth++;
                analyzeBody(loop.body);
                loopDepth--;
                context.pop();
                return node;
            case NodeKind.MapLit:
                MapLit map = cast(MapLit) node;
                foreach (ref Node key; map.keys)
                    key = analyze(key);
                foreach (ref Node value; map.values)
                    value = analyze(value);
                node.type_sema = new TypeSemaBuiltin(TypeSemaBase.Map);
                return node;
            case NodeKind.NullLit:
                node.type_sema = anyType();
                return node;
            case NodeKind.BlockStmt:
                BlockStmt block = as!BlockStmt(node);
                analyzeBody(block.body);
                return node;
            case NodeKind.BreakStmt:
            case NodeKind.ContinueStmt:
                if (!loopDepth
                        && (node.kind == NodeKind.ContinueStmt || !switchDepth))
                    err.error(node.pos, "Controle de laço fora de um laço de repetição/escolha.");
                return node;
            case NodeKind.ForStmt:
                ForStmt loop = as!ForStmt(node);
                context.push();
                loop.init = analyze(loop.init);
                loop.condition = analyze(loop.condition);
                loop.step = analyze(loop.step);
                loopDepth++;
                analyzeBody(loop.body);
                loopDepth--;
                context.pop();
                return node;
            case NodeKind.DoStmt:
                DoStmt loop = as!DoStmt(node);
                loopDepth++;
                analyzeBody(loop.body);
                loopDepth--;
                loop.condition = analyze(loop.condition);
                return node;
            case NodeKind.VarDecl:
                return analyzeVarDecl(as!VarDecl(node));

            case NodeKind.BinaryExpr:
                return analyzeBinaryExpr(as!BinaryExpr(node));

            case NodeKind.FnDecl:
                return analyzeFnDecl(as!FnDecl(node));

            case NodeKind.IfStmt:
                return analyzeIfStmt(as!IfStmt(node));

            case NodeKind.CallExpr:
                return analyzeCallExpr(as!CallExpr(node));

            case NodeKind.ReturnStmt:
                return analyzeReturnStmt(as!ReturnStmt(node));

            case NodeKind.Identifier:
                return analyzeIdentifier(as!Identifier(node), comptimeValue);

            case NodeKind.TypeOfExpr:
                return analyzeTypeOfExpr(node);

            case NodeKind.AssignStmt:
                Node assign = analyzeAssignStmt(as!AssignStmt(node));
                assign.type_sema = anyType();
                return assign;

            case NodeKind.StringLit:
            case NodeKind.IntLit:
            case NodeKind.DoubleLit:
            case NodeKind.BoolLit:
                node.type_sema = resolver.resolver(node.type_expr);
                return node;

            case NodeKind.TupleLit:
                TupleLit tuple = cast(TupleLit) node;
                foreach (ref Node value; tuple.elements)
                    value = analyze(value);
                if (tuple.elements.length < 2 || tuple.elements.length > 10)
                    err.error(node.pos, "Tupla exige de 2 a 10 elementos.");
                node.type_sema = new TypeSemaBuiltin(TypeSemaBase.Tuple);
                return node;
            case NodeKind.ArrayLit:
                return analyzeArrayLit(as!ArrayLit(node));

            case NodeKind.IndexExpr:
                return analyzeIndexExpr(as!IndexExpr(node));

            case NodeKind.WhileStmt:
                return analyzeWhileStmt(as!WhileStmt(node));

            case NodeKind.UnaryExpr:
                return analyzeUnaryExpr(as!UnaryExpr(node));

            case NodeKind.MemberExpr:
                return analyzeMemberExpr(as!MemberExpr(node));

            default:
                err.error(node.pos, "Node desconhecido.");
                return node;
        }
    }

    bool[ClassDecl] classesAnalyzed, classesActive;
    Node analyzeClass(ClassDecl node)
    {
        if (node.signature.builtinName.length || node in classesAnalyzed)
            return node;
        if (node in classesActive)
        {
            err.error(node.pos, "Ciclo de herança detectado.");
            node.superClass = null;
            return node;
        }
        classesActive[node] = true;
        analyzeDecorators(node.decorators, node.pos);
        if (node.superName.length)
        {
            Symbol* sym = context.get(node.superName);
            if (sym is null || !sym.isFn() || (cast(SymbolFn*) sym).node.classFactory is null)
                err.error(node.pos, "Superclasse não encontrada.");
            else
            {
                node.superClass = (cast(SymbolFn*) sym).node.classFactory;
                analyzeClass(node.superClass);
            }
        }
        bool[dstring] names;
        foreach (ref ClassField field; node.fields)
        {
            analyzeDecorators(field.decorators, field.pos);
            resolver.resolver(field.type);
            for (ClassDecl parent = node.superClass; parent !is null; parent = parent.superClass)
            {
                foreach (ClassField inherited; parent.fields)
                    if (inherited.name == field.name)
                        err.error(field.pos, "Propriedade herdada não pode ser redeclarada.");
                foreach (FnDecl inherited; parent.methods)
                    if (inherited.fn == field.name)
                        err.error(field.pos, "Propriedade conflita com método herdado.");
            }
            if (field.name in names)
                err.error(field.pos, "Propriedade duplicada.");
            names[field.name] = true;
        }
        FnDecl constructor;
        foreach (FnDecl method; node.methods)
            if (method.fn == "construtor")
                constructor = method;
        node.signature.args = constructor !is null ? constructor.args : node.superClass !is null
            ? node.superClass.signature.args : [];
        // Identidade e assinatura prontas antes dos corpos: referências mútuas
        // entre classes não são ciclos de herança.
        classesActive.remove(node);
        classesAnalyzed[node] = true;
        foreach (FnDecl method; node.methods)
        {
            for (ClassDecl parent = node.superClass; parent !is null; parent = parent.superClass)
                foreach (ClassField field; parent.fields)
                    if (field.name == method.fn)
                        err.error(method.pos, "Método conflita com propriedade herdada.");
            if (method.fn in names)
                err.error(method.pos, "Membro duplicado.");
            names[method.fn] = true;
            if (method.fn == "construtor")
                constructor = method;
            analyzeFnDecl(method, false);
        }
        node.signature.args = constructor !is null ? constructor.args : node.superClass !is null
            ? node.superClass.signature.args : [];
        classesActive.remove(node);
        classesAnalyzed[node] = true;
        return node;
    }

    Node analyzeMemberExpr(MemberExpr node)
    {
        node.left = analyze(node.left);
        if (cast(Identifier) node.right is null)
            err.error(node.pos, "Nome de propriedade inválido.");
        node.type_sema = anyType();
        ClassDecl declaration;
        if (TypeSemaClass type = cast(TypeSemaClass) node.left.type_sema)
            declaration = type.declaration;
        if (Identifier receiver = cast(Identifier) node.left)
        {
            if (receiver.classRef !is null)
                declaration = receiver.classRef;
            else if (receiver.lexicalClass !is null)
                declaration = receiver.lexicalClass;
        }
        Identifier name = cast(Identifier) node.right;
        if (name !is null)
            for (ClassDecl current = declaration; current !is null; current = current.superClass)
            {
                foreach (FnDecl method; current.methods)
                    if (method.fn == name.value)
                    {
                        name.functionRef = method;
                        node.type_sema = new TypeSemaBuiltin(TypeSemaBase.Function);
                        return node;
                    }
                foreach (ClassField field; current.fields)
                    if (field.name == name.value)
                    {
                        node.type_expr = field.type;
                        node.type_sema = resolver.resolver(field.type);
                        return node;
                    }
            }
        return node;
    }

    Node analyzeUnaryExpr(UnaryExpr node)
    {
        node.value = analyze(node.value);
        node.type_sema = node.value.type_sema;
        if (node.type_sema is null)
        {
            node.type_sema = anyType();
            return node;
        }
        if (node.op == TokenKind.Bang)
            node.type_sema = new TypeSemaBuiltin(TypeSemaBase.Bool);
        if (node.op == TokenKind.PPlus || node.op == TokenKind.MMinus)
        {
            Identifier id = cast(Identifier) node.value;
            if (id is null && node.value.kind != NodeKind.IndexExpr)
                err.error(node.pos, "Incremento exige uma variável ou índice modificável.");
            if (id !is null)
                if (Symbol* sym = context.get(id.value))
                    if (sym.isVar() && (cast(SymbolVar*) sym).isConstant)
                        err.error(node.pos, "Não é possível incrementar uma constante.");
        }

        bool[TokenKind] opsNums = [TokenKind.PPlus: false, TokenKind.MMinus: false,];

        if (node.op in opsNums && (!node.value.type_sema.isNumeric() && !node.value.type_sema.isAny()))
            err.error(node.pos, "Não é possível usar operadores unários em valores não numéricos.");

        return node;
    }

    Node analyzeWhileStmt(WhileStmt node)
    {
        node.expr = analyze(node.expr);

        loopDepth++;
        analyzeBody(node.body);
        loopDepth--;

        return node;
    }

    Node analyzeArrayLit(ArrayLit node)
    {
        foreach (ref Node element; node.elements)
            element = analyze(element);

        node.type_sema = resolver.resolver(node.type_expr);
        return node;
    }

    Node analyzeIndexExpr(IndexExpr node)
    {
        node.value = analyze(node.value);
        node.idx = analyze(node.idx);

        Node value = node.value;
        Node idx = node.idx;

        // permitindo apenas em vetores e textos por enquanto
        if (value.type_sema is null || idx.type_sema is null)
        {
            node.type_sema = anyType();
            return node;
        }
        dstring type = value.type_sema.toStr();
        if (!value.type_sema.isArray() && type != TypeSemaBase.String && type != TypeSemaBase.Any
                && type != TypeSemaBase.Map && type != TypeSemaBase.Tuple)
        {
            err.error(node.pos,
                    format("Não é possível acessar o campo do tipo '%s'. Apenas vetores e textos são permitidos",
                        type));
            return node;
        }

        dstring type2 = idx.type_sema.toStr();
        if (type != TypeSemaBase.Map && type != TypeSemaBase.Any && type2 != TypeSemaBase.Int
                && type2 != TypeSemaBase.Any)
        {
            err.error(node.pos, format("O indíce deve ser do tipo '%s', foi recebido '%s'.",
                    TypeSemaBase.Int, type2));
            return node;
        }

        if (TypeSemaArray typeArr = cast(TypeSemaArray) value.type_sema)
            node.type_sema = typeArr.base;
        else
            node.type_sema = type == TypeSemaBase.String ? value.type_sema : anyType();

        return node;
    }

    Node analyzeAssignStmtIdx(AssignStmt node)
    {
        // val[idx] = 42
        node.left = analyze(node.left); // val[idx]
        node.value = analyze(node.value); // 42
        // Contratos de campos passam por StaticSafety: em pegue, a falha provada
        // permanece observável em execução e gera W31xx em vez de impedir o build.
        if (cast(MemberExpr) node.left is null)
            checkTypes(node.pos, node.left.type_sema, node.value.type_sema);

        return node;
    }

    Node analyzeAssignStmt(AssignStmt node)
    {
        if (node.left.kind == NodeKind.MemberExpr)
            return analyzeAssignStmtIdx(node);
        if (node.left.kind == NodeKind.IndexExpr)
            return analyzeAssignStmtIdx(node);

        if (node.left.kind != NodeKind.Identifier)
        {
            err.error(node.pos, "Atribuição inválida: o lado esquerdo da operação deve ser uma variável.");
            return node;
        }

        Identifier var = as!Identifier(node.left);
        dstring name = var.value;

        Symbol* sym = context.get(name);
        if (sym is null)
        {
            missingSymbol(var);
            return node;
        }
        if (sym.isFn())
        {
            err.error(var.pos, "Não é possível atribuir a uma função.");
            return node;
        }
        if (sym.isParam())
        {
            var.parameterRef = (cast(SymbolParam*) sym).node;
            var.type_expr = (cast(SymbolParam*) sym).node.type_expr;
            node.value = analyze(node.value);
            checkTypes(node.pos, (cast(SymbolParam*) sym).node.type_sema, node.value.type_sema);
            return node;
        }
        SymbolVar* symv = cast(SymbolVar*) sym;
        var.variableRef = symv.node;
        var.type_expr = symv.node.type_expr;

        if (symv.isConstant)
        {
            err.error(var.pos, format("A variavel '%s' não pode ser reatribuída pois é uma constante.", name));
            alreadyDeclaredHere(name, symv.node.pos, err);
            return node;
        }

        node.value = analyze(node.value);

        if (!checkTypes(node.pos, symv.node.type_sema, node.value.type_sema))
            alreadyDeclaredHere(name, symv.node.pos, err);

        return node;
    }

    Node analyzeTypeOfExpr(Node node)
    {
        TypeOfExpr toe = as!TypeOfExpr(node);
        toe.value = analyze(toe.value, true);
        toe.type_sema = new TypeSemaBuiltin(TypeSemaBase.String);
        return toe;
    }

    Node analyzeIdentifier(Identifier node, bool comptimeValue)
    {
        Symbol* sym = context.get(node.value);

        if (sym is null)
        {
            missingSymbol(node);
            return node;
        }

        if (sym.isFn())
        {
            sym.uses++;
            node.functionRef = (cast(SymbolFn*) sym).node;
            node.classRef = node.functionRef.classFactory;
            node.type_sema = new TypeSemaBuiltin(TypeSemaBase.Function);
            return node;
        }

        if (!comptimeValue)
            sym.uses++;

        if (sym.isVar())
            node.variableRef = (cast(SymbolVar*) sym).node;
        if (sym.isParam())
            node.parameterRef = (cast(SymbolParam*) sym).node;
        if (node.value == "isto")
            node.lexicalClass = methodOwner;
        node.type_sema = sym.isParam() ? (cast(SymbolParam*) sym).node.type_sema : (cast(SymbolVar*) sym)
            .node.type_sema;
        return node;
    }

    Node analyzeIfStmt(IfStmt node)
    {
        // se tiver expresão então tem um If
        if (node.expr !is null)
            node.expr = analyze(node.expr);

        analyzeBody(node.body);

        if (node._else !is null)
            node._else = as!IfStmt(analyzeIfStmt(node._else));

        return node;
    }

    Node analyzeCallExpr(CallExpr node)
    {
        if (node.intrinsic)
        {
            foreach (ref Node arg; node.args)
                arg = analyze(arg);
            node.type_sema = new TypeSemaBuiltin(TypeSemaBase.String);
            return node;
        }
        Identifier id = cast(Identifier) node.fn;
        Symbol* sym = id is null ? null : context.get(id.value);
        if (sym !is null && sym.isFn())
        {
            FnDecl fn = (cast(SymbolFn*) sym).node;
            sym.uses++;
            id.functionRef = fn;
            id.classRef = fn.classFactory;
            if (fn.classFactory !is null)
                analyzeClass(fn.classFactory);
            node.builtinCall = (cast(SymbolFn*) sym).isRuntime;
            node.type_sema = fn.classFactory is null ? resolver.resolver(
                    fn.type_expr) : new TypeSemaClass(fn.classFactory);
            bool spread = node.args.any!((Node a) => a.kind == NodeKind.SpreadExpr);
            bool rest = fn.args.length && fn.args[$ - 1].rest;
            if (id.value != "escreva" && !spread)
            {
                size_t minimum;
                foreach (FnArg arg; fn.args)
                    if (arg.value is null && !arg.rest)
                        minimum++;
                if (node.args.length < minimum || (!rest && node.args.length > fn.args.length))
                    err.error(node.pos, format("A função '%s' espera entre %s e %s argumentos; recebeu %s.",
                            id.value, minimum, fn.args.length, node.args.length));
            }
            foreach (size_t i, ref Node arg; node.args)
            {
                arg = analyze(arg);
                if (i < fn.args.length && !fn.args[i].rest && arg.kind != NodeKind.SpreadExpr)
                    checkTypes(arg.pos, resolver.resolver(fn.args[i].type_expr), arg.type_sema);
            }
            return node;
        }
        node.fn = analyze(node.fn);
        foreach (ref Node arg; node.args)
            arg = analyze(arg);
        node.type_sema = anyType();
        if (MemberExpr member = cast(MemberExpr) node.fn)
            if (Identifier name = cast(Identifier) member.right)
                if (name.functionRef !is null)
                    node.type_sema = resolver.resolver(name.functionRef.type_expr);
        if (node.fn.type_sema !is null && !node.fn.type_sema.isAny()
                && node.fn.type_sema.toStr() != TypeSemaBase.Function)
            err.error(node.pos, "O valor chamado não é uma função.");
        return node;
    }

    Node analyzeReturnStmt(ReturnStmt node)
    {
        if (collectionDepth)
        {
            node.collectionReturn = true;
            if (node.val !is null)
                node.val = analyze(node.val);
            return node;
        }
        if (!functionDepth)
            err.error(node.pos, "Retorno fora de uma função.");
        if (node.val !is null)
        {
            node.val = analyze(node.val);
            if (returnTypes.length)
                checkTypes(node.pos, returnTypes[$ - 1], node.val.type_sema);
        }
        return node;
    }

    Node analyzeFnDecl(FnDecl node, bool named = true)
    {
        if (node.analyzed)
            return node;
        node.analyzed = true;
        analyzeDecorators(node.decorators, node.pos, !node.isMethod);
        if (named && context.scopes.length > 2)
        {
            Symbol* existing = context.getLocal(node.fn);
            if (existing is null)
                context.set(node.fn, new SymbolFn(node));
            else if (!existing.isFn() || (cast(SymbolFn*) existing).node !is node)
                err.error(node.pos, "Função duplicada neste escopo.");
        }
        size_t savedLoopDepth = loopDepth, savedSwitchDepth = switchDepth, savedCollectionDepth = collectionDepth;
        loopDepth = 0;
        switchDepth = 0;
        collectionDepth = 0;
        functionDepth++;
        context.pushFunction();
        ClassDecl previousOwner = methodOwner;
        methodOwner = node.isMethod && !node.isStatic ? node.ownerClass : null;
        if (node.isMethod && !node.isStatic)
        {
            FnArg self = new FnArg("isto", new TypeExprNamed("qualquer", node.pos), null, node.pos);
            self.type_sema = anyType();
            context.set("isto", new SymbolParam(self));
        }
        node.type_sema = resolver.resolver(node.type_expr);
        returnTypes ~= node.type_sema;

        // if (node.ctfe_flags & CTFEFlags.Pure)
        //     writefln("Função pura detectada: %s", node.fn);

        for (uint i; i < node.args.length; i++)
        {
            FnArg arg = node.args[i];
            if (arg.value !is null)
                arg.value = analyze(arg.value);
            arg.type_sema = resolver.resolver(arg.type_expr);
            if (arg.rest)
                arg.type_sema = new TypeSemaArray(arg.type_sema);
            if (!context.set(arg.name, new SymbolParam(arg)))
                err.error(arg.pos, format("Parâmetro '%s' duplicado.", arg.name));
        }

        predeclare(node.body);
        for (uint i; i < node.body.length; i++)
            node.body[i] = analyze(node.body[i]);

        methodOwner = previousOwner;
        context.popFunction();
        returnTypes.length--;
        functionDepth--;
        loopDepth = savedLoopDepth;
        switchDepth = savedSwitchDepth;
        collectionDepth = savedCollectionDepth;
        return node;
    }

    Node analyzeBinaryExpr(BinaryExpr node)
    {
        node.left = analyze(node.left);
        node.right = analyze(node.right);

        TypeSema l = node.left.type_sema;
        TypeSema r = node.right.type_sema;

        if (node.op == TokenKind.And || node.op == TokenKind.Or || node.op == TokenKind.In
                || node.op == TokenKind.EEquals || node.op == TokenKind.NEquals)
        {
            node.type_sema = new TypeSemaBuiltin(TypeSemaBase.Bool);
            return node;
        }
        if (node.op == TokenKind.Coalesce)
        {
            node.type_sema = anyType();
            return node;
        }
        if (!checkTypes(node.pos, l, r))
        {
            node.type_sema = new TypeSemaBuiltin(TypeSemaBase.Any);
            return node;
        }

        TypeSema type = l.promote(r);
        node.left.type_sema = type;
        node.right.type_sema = type;

        switch (node.op)
        {
            case TokenKind.EEquals:
            case TokenKind.LEquals:
            case TokenKind.GEquals:
            case TokenKind.LThan:
            case TokenKind.GThan:
                type = new TypeSemaBuiltin(TypeSemaBase.Bool);
                break;
            default:
                break;
        }

        node.type_sema = type;
        return node;
    }

    Node analyzeVarDecl(VarDecl node)
    {
        node.value = analyze(node.value);

        dstring name = node.name;
        if (Symbol* sym = context.getLocal(name))
        {
            err.error(node.pos, format("%s '%s' já existe.", ternary(sym.isVar(), "A variavel", "O simbolo"), name));
            alreadyDeclaredHere(name, getPosFromSymbol(sym), err);
        }

        TypeSema valueType = node.value.type_sema;
        // writeln(name, ": ", valueType.toStr());
        // writeln(node.type_sema, "\n");

        if (node.type_expr !is null)
        {
            updateType(node, resolver); // atualiza o tipo semantico para fazer o checkTypes
            checkTypes(node.pos, node.type_sema, valueType); // é compativel? pode ter havido cast implicito, atualiza
        }
        else
            node.type_sema = valueType; // inferencia

        context.set(node.name, new SymbolVar(node, node.isConst));
        return node;
    }

    pragma(inline, true) bool checkTypes(Position pos, TypeSema t1, TypeSema t2)
    {
        if (t1 is null || t2 is null)
        {
            err.error(pos, "Alguma das expressões está com o tipo inválido.");
            return false;
        }
        bool comp = t1.isComp(t2);
        if (!comp)
            err.errorCode(pos, catalog.incompatibleTypes, t1.toStr(), t2.toStr());
        return comp;
    }

public:
    this(Context context, TypeRegistry registry, TypeResolver resolver, Diagnostics err)
    {
        this.context = context;
        this.registry = registry;
        this.resolver = resolver;
        this.err = err;
    }

    void analyze(Program program)
    {
        context.cursor = context.scopes.length - 1; // reseta o cursor em -1 e faz context.enter() indo pra 0
        foreach (ref Node node; program.body)
            node = analyze(node);
    }
}
