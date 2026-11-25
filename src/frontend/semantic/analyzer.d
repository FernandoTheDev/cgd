// Resolve expressões, escopos e contratos após a declaração dos símbolos.
module frontend.semantic.analyzer;
import catalog = diagnostics.catalog;

import std.algorithm;
import std.exception;
import std.format;
import std.array;
import std.conv : to;

import frontend.semantic;
import frontend.semantic.members;
import frontend.semantic.contracts;
import frontend.semantic.defaults;
import frontend.semantic.foreign;
import frontend.semantic.assignments;
import frontend.semantic.native_methods;
import frontend.semantic.operators;
import frontend.parser;
import frontend.lexer;
import frontend;
import errors;
import utils;

class SemanticAnalyzer
{
private:
    Context context;
    TypeRegistry registry;
    TypeResolver resolver;
    Diagnostics err;
    size_t loopDepth, functionDepth, switchDepth, collectionDepth;
    TypeSema[] returnTypes;
    bool asyncBody;
    ClassDecl methodOwner, lexicalOwner;

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
            if (VarDecl enumeration = cast(VarDecl) child)
            {
                if (enumeration.isEnum && !registry.declareEnum(enumeration.name))
                    err.error(enumeration.pos, "Nome de enum conflita com tipo existente neste escopo.");
            }
            else if (FnDecl fn = cast(FnDecl) child)
            {
                if (!context.set(fn.fn, new SymbolFn(fn)))
                    err.error(fn.pos, "Função duplicada neste escopo.");
            }
    }

    void analyzeBody(ref Node[] body)
    {
        context.push();
        registry.pushEnumScope();
        predeclare(body);
        foreach (ref Node child; body)
            child = analyze(child);
        registry.popEnumScope();
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
            case NodeKind.AwaitExpr:
                AwaitExpr awaited = cast(AwaitExpr) node;
                if (!asyncBody)
                    err.errorCode(node.pos, asyncContext);
                awaited.value = analyze(awaited.value);
                if (TypeSemaPromise promise = cast(TypeSemaPromise) awaited.value.type_sema)
                    node.type_sema = promise.result;
                else if (TypeSemaTask task = cast(TypeSemaTask) awaited.value.type_sema)
                    node.type_sema = task.result;
                else
                {
                    node.type_sema = anyType();
                    if (!awaited.value.type_sema.isAny())
                        err.errorCode(node.pos, awaitOperand, awaited.value.type_sema.toStr());
                }
                return node;
            case NodeKind.RoutineExpr:
                return analyzeRoutineExpr(cast(RoutineExpr) node);
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
                if (c.yes.type_sema !is null && c.no.type_sema !is null && !c.yes.type_sema.isAny()
                        && !c.no.type_sema.isAny() && c.yes.type_sema.toStr() == c.no.type_sema.toStr())
                    node.type_sema = c.yes.type_sema;
                else
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
                registry.pushEnumScope();
                VarDecl v = new VarDecl(c.name, null, false, c.bindingType, c.pos);
                v.type_sema = c.bindingType is null ? anyType() : resolver.resolver(c.bindingType);
                context.set(c.name, new SymbolVar(v));
                c.value = analyze(c.value);
                c.condition = analyze(c.condition);
                registry.popEnumScope();
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
                    new DeclarationAnalysis(ctx, types, err).analyze(unit.program);

                    new SemanticAnalyzer(ctx, types, new TypeResolver(types, err), err).analyze(unit.program);
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
                    registry.pushEnumScope();
                    if (c.type !is null)
                        resolver.resolver(c.type);
                    if (c.name.length)
                    {
                        VarDecl v = new VarDecl(c.name, null, true, c.type, c.pos);
                        v.type_sema = anyType();
                        context.set(c.name, new SymbolVar(v, true));
                    }
                    predeclare(c.body);
                    foreach (ref Node child; c.body)
                        child = analyze(child);
                    registry.popEnumScope();
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
                registry.pushEnumScope();
                VarDecl variable = new VarDecl(loop.name, null, false, loop.bindingType, loop.pos);
                if (loop.bindingType !is null)
                    variable.type_sema = resolver.resolver(loop.bindingType);
                else if (TypeSemaArray arrType = cast(TypeSemaArray) loop.iterable.type_sema)
                    variable.type_sema = arrType.base;
                else if (TypeSemaNativeContainer nc = cast(TypeSemaNativeContainer) loop.iterable.type_sema)
                    variable.type_sema = (nc.containerKind == NativeContainerKind.VetorNativo
                            || nc.containerKind == NativeContainerKind.FatiaNativa)
                        && nc.typeArgs.length >= 1 ? nc.typeArgs[0] : anyType();
                else if (TypeSemaBuiltin strType = cast(TypeSemaBuiltin) loop.iterable.type_sema)
                    variable.type_sema = strType.base == TypeSemaBase.String ? strType : anyType();
                else
                    variable.type_sema = anyType();
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
                registry.popEnumScope();
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
                registry.pushEnumScope();
                loop.init = analyze(loop.init);
                loop.condition = analyze(loop.condition);
                loop.step = analyze(loop.step);
                loopDepth++;
                analyzeBody(loop.body);
                loopDepth--;
                registry.popEnumScope();
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
        bool previousAsync = asyncBody;
        asyncBody = false;
        scope (exit)
            asyncBody = previousAsync;
        if (node.signature.builtinName.length || node.analyzed || node in classesAnalyzed)
            return node;
        if (node in classesActive)
        {
            err.error(node.pos, "Ciclo de herança detectado.");
            node.superClass = null;
            return node;
        }
        classesActive[node] = true;
        foreach (dstring name; node.mixinNames)
        {
            Symbol* symbol = context.get(name);
            if (symbol is null || !symbol.isFn() || (cast(SymbolFn*) symbol).node.classFactory is null)
                err.error(node.pos, "Classe de mescla não encontrada: " ~ name.to!string);
            else
            {
                ClassDecl mixinClass = (cast(SymbolFn*) symbol).node.classFactory;
                if (mixinClass.isInterface || mixinClass.isForeign)
                    err.error(node.pos, "Composição mescla exige classe gerenciada: " ~ name.to!string);
                else
                {
                    analyzeClass(mixinClass);
                    node.mixins ~= mixinClass;
                }
            }
        }
        foreach (dstring name; node.interfaceNames)
        {
            Symbol* symbol = context.get(name);
            if (symbol is null || !symbol.isFn() || (cast(SymbolFn*) symbol)
                    .node.classFactory is null || !(cast(SymbolFn*) symbol).node.classFactory.isInterface)
                err.error(node.pos, "Interface não encontrada: " ~ name.to!string);
            else
            {
                ClassDecl contract = (cast(SymbolFn*) symbol).node.classFactory;
                analyzeClass(contract);
                node.interfaces ~= contract;
            }
        }
        bool[dstring][] previousEnums = registry.enterClassScope(node);
        scope (exit)
            registry.leaveClassScope(previousEnums);
        foreach (ClassField field; node.fields)
            if (field.isEnum && !registry.declareEnum(field.name))
                err.error(field.pos, "Nome de enum conflita com tipo existente neste escopo.");
        analyzeDecorators(node.decorators, node.pos);
        if (node.isForeign)
        {
            foreach (FnDecl method; node.methods)
            {
                resolver.resolver(method.type_expr);
                foreach (FnArg argument; method.args)
                    resolver.resolver(argument.type_expr);
            }
            resolveForeignClass(node, err);
            node.isAbstract = true;
        }
        if (node.superName.length)
        {
            if (node.superQualifier.length > 0)
            {
                ModuleUnit mod = registry.resolveModule(node.superQualifier);
                ClassDecl foundSuper;
                if (mod !is null && mod.program !is null)
                {
                    foreach (Node exported; mod.program.body)
                        if (ClassDecl cls = cast(ClassDecl) exported)
                            if (cls.name == node.superName)
                            {
                                foundSuper = cls;
                                break;
                            }
                }
                if (foundSuper is null)
                    err.error(node.pos, "Superclasse não encontrada.");
                else
                {
                    node.superClass = foundSuper;
                    analyzeClass(node.superClass);
                }
            }
            else
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
        }
        bool[dstring] names;
        foreach (ref ClassField field; node.fields)
        {
            analyzeDecorators(field.decorators, field.pos);
            TypeSema fieldType = resolver.resolver(field.type);
            field.type_sema = fieldType;
            if (field.isEnum)
                field.value = analyze(field.value);
            else if (field.isStatic)
            {
                Node initial = field.value is null ? defaultValue(fieldType, field.pos) : field.value;
                if (initial is null)
                    initial = new NullLit(field.pos);
                field.value = analyze(initial);
                checkTypes(field.pos, fieldType, field.value.type_sema);
            }
            else if (!node.isInterface && !node.isForeign)
            {
                Node initial = field.value is null ? defaultValue(fieldType, field.pos) : field.value;
                if (initial !is null)
                {
                    FnDecl initializer = new FnDecl("#init_"d ~ field.name, [], field.type,
                            [cast(Node) new ReturnStmt(initial, field.pos)], 0, field.pos);
                    initializer.isMethod = true;
                    initializer.accessor = true;
                    initializer.ownerClass = node;
                    field.initializer = initializer;
                    node.methods ~= initializer;
                }
            }
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
        if (constructor !is null)
            node.signature.args = constructor.args;
        else if (node.isValueType)
        {
            FnArg[] autoArgs;
            foreach (ClassField field; node.fields)
                if (!field.isEnum && !field.isStatic)
                {
                    Node defVal = field.value !is null ? field.value : defaultValue(field.type_sema, field.pos);
                    FnArg fa = new FnArg(field.name, field.type, defVal, field.pos);
                    fa.type_sema = field.type_sema;
                    autoArgs ~= fa;
                }
            node.signature.args = autoArgs;
        }
        else
            node.signature.args = node.superClass !is null ? node.superClass.signature.args : [];
        // Identidade e assinatura prontas antes dos corpos: referências mútuas
        // entre classes não são ciclos de herança.
        classesActive.remove(node);
        classesAnalyzed[node] = true;
        node.analyzed = true;
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
        if (constructor !is null)
            node.signature.args = constructor.args;
        else if (!node.isValueType)
            node.signature.args = node.superClass !is null ? node.superClass.signature.args : [];
        if (!node.isInterface)
            validateClassContracts(node, err);
        validateClassOperators(node, err);
        classesActive.remove(node);
        classesAnalyzed[node] = true;
        node.analyzed = true;
        return node;
    }

    bool isStaticEnumReceiver(Node target)
    {
        if (Identifier id = cast(Identifier) target)
        {
            if (id.classRef !is null || id.moduleRef !is null)
                return true;
            if (id.variableRef !is null && cast(ImportExpr) id.variableRef.value !is null)
                return true;
            return false;
        }
        if (MemberExpr member = cast(MemberExpr) target)
        {
            if (member.resolvedModule !is null)
                return true;
            if (Identifier right = cast(Identifier) member.right)
                if (right.classRef !is null)
                    return isStaticEnumReceiver(member.left);
            return false;
        }
        return false;
    }

    Node analyzeMemberExpr(MemberExpr node)
    {
        MapLit members;
        if (Identifier receiver = cast(Identifier) node.left)
            if (VarDecl enumeration = context.enumDeclaration(receiver.value))
            {
                receiver.variableRef = enumeration;
                receiver.type_sema = new TypeSemaBuiltin(TypeSemaBase.Map);
                members = cast(MapLit) enumeration.value;
            }
        if (members is null)
            node.left = analyze(node.left);
        if (MemberExpr receiver = cast(MemberExpr) node.left)
            if (receiver.enumMembers !is null && isStaticEnumReceiver(receiver.left))
                members = receiver.enumMembers;
        if (members !is null)
            if (Identifier name = cast(Identifier) node.right)
                if (name.value != "#incompleto")
                {
                    foreach (size_t index, Node key; members.keys)
                        if ((cast(StringLit) key).value == name.value)
                        {
                            node.enumValue = new IntLit((cast(IntLit) members.values[index]).value, node.pos);
                            node.enumValue.type_sema = new TypeSemaBuiltin(TypeSemaBase.Int);
                            node.type_sema = node.enumValue.type_sema;
                            node.readonly = true;
                            return node;
                        }
                    err.error(name.pos, "Membro de enum não encontrado.");
                    node.type_sema = anyType();
                    return node;
                }
        if (cast(Identifier) node.right is null)
            err.error(node.pos, "Nome de propriedade inválido.");
        node.type_sema = anyType();
        ClassDecl declaration;
        bool isClassReceiver = false;
        if (TypeSemaClass type = cast(TypeSemaClass) node.left.type_sema)
            declaration = type.declaration;
        if (Identifier receiver = cast(Identifier) node.left)
        {
            if (receiver.classRef !is null)
            {
                declaration = receiver.classRef;
                isClassReceiver = true;
            }
            else if (receiver.lexicalClass !is null)
                declaration = receiver.lexicalClass;
            else if (receiver.variableRef !is null && receiver.variableRef.isConst)
            {
                if (MemberExpr initMember = cast(MemberExpr) receiver.variableRef.value)
                    if (Identifier initRight = cast(Identifier) initMember.right)
                        if (initRight.classRef !is null)
                        {
                            declaration = initRight.classRef;
                            isClassReceiver = true;
                        }
            }
        }
        else if (MemberExpr leftMember = cast(MemberExpr) node.left)
            if (Identifier leftRight = cast(Identifier) leftMember.right)
                if (leftRight.classRef !is null)
                {
                    declaration = leftRight.classRef;
                    isClassReceiver = true;
                }
        Identifier name = cast(Identifier) node.right;
        if (name is null || name.value == "#incompleto")
            return node;
        dstring[] leftNamespace;
        if (Identifier leftNsId = cast(Identifier) node.left)
            leftNamespace = leftNsId.namespacePath;
        else if (MemberExpr leftNsMember = cast(MemberExpr) node.left)
            leftNamespace = leftNsMember.namespacePath;
        if (leftNamespace.length > 0)
        {
            dstring[] candidatePath = leftNamespace ~ name.value;
            if (ModuleUnit resolvedMod = registry.resolveModule(candidatePath))
            {
                node.resolvedModule = resolvedMod;
                node.namespacePath = candidatePath;
                return node;
            }
            if (registry.hasNamespacePrefix(candidatePath))
            {
                node.namespacePath = candidatePath;
                return node;
            }
        }
        ModuleUnit importedModule;
        if (ImportExpr directImport = cast(ImportExpr) node.left)
            importedModule = directImport.target;
        else if (MemberExpr leftModMember = cast(MemberExpr) node.left)
            importedModule = leftModMember.resolvedModule;
        else if (Identifier leftId = cast(Identifier) node.left)
        {
            if (leftId.moduleRef !is null)
                importedModule = leftId.moduleRef;
            else if (leftId.variableRef !is null)
                if (ImportExpr varImport = cast(ImportExpr) leftId.variableRef.value)
                    importedModule = varImport.target;
        }
        if (importedModule !is null && importedModule.program !is null)
        {
            foreach (Node exported; importedModule.program.body)
            {
                if (ClassDecl cls = cast(ClassDecl) exported)
                    if (cls.name == name.value)
                    {
                        name.classRef = cls;
                        node.type_sema = new TypeSemaBuiltin(TypeSemaBase.Function);
                        return node;
                    }
                if (FnDecl fn = cast(FnDecl) exported)
                    if (fn.fn == name.value)
                    {
                        name.functionRef = fn;
                        node.type_sema = new TypeSemaBuiltin(TypeSemaBase.Function);
                        return node;
                    }
                if (VarDecl varDecl = cast(VarDecl) exported)
                    if (varDecl.name == name.value)
                    {
                        name.variableRef = varDecl;
                        if (varDecl.isEnum)
                        {
                            node.readonly = true;
                            node.enumMembers = cast(MapLit) varDecl.value;
                        }
                        node.type_sema = varDecl.type_sema is null ? anyType() : varDecl.type_sema;
                        return node;
                    }
            }
        }
        else if (leftNamespace.length > 0)
        {
            err.error(name.pos, format("Módulo ou símbolo '%s' não encontrado no namespace '%s'.",
                    name.value, leftNamespace.join("."d)));
            return node;
        }
        if (declaration !is null)
        {
            ClassMember member = resolveClassMember(declaration, name.value);
            if (member.owner !is null)
            {
                if (!member.visibleFrom(lexicalOwner))
                    err.errorCode(name.pos, inaccessibleMember, name.value);
                if (isClassReceiver && (member.method is null ? (!member.field.isEnum
                        && !member.field.isStatic) : !member.method.isStatic))
                    err.errorCode(name.pos, instanceMember, name.value);
                if (member.method !is null)
                {
                    name.functionRef = member.method;
                    node.type_sema = new TypeSemaBuiltin(TypeSemaBase.Function);
                }
                else
                {
                    node.readonly = member.field.isEnum;
                    node.enumMembers = member.field.isEnum ? cast(MapLit) member.field.value : null;
                    node.type_expr = member.field.type;
                    node.type_sema = member.field.type_sema !is null ? member.field.type_sema
                        : resolver.resolver(member.field.type);
                }
                return node;
            }
        }
        TypeSemaBuiltin receiverType = cast(TypeSemaBuiltin) node.left.type_sema;
        if (declaration is null && (receiverType is null || receiverType.base != TypeSemaBase.Map))
            if (FnDecl builtin = builtinMethod(node.left.type_sema, name.value.to!string))
            {
                name.functionRef = builtin;
                node.type_sema = new TypeSemaBuiltin(TypeSemaBase.Function);
            }
        if (cast(TypeSemaNativeContainer) node.left.type_sema !is null)
            node.type_sema = new TypeSemaBuiltin(TypeSemaBase.Function);
        return node;
    }

    private TypeSema resolveNativeContainerMethodReturn(TypeSemaNativeContainer nc, dstring methodName, bool isStaticCall)
    {
        TypeSema elem0 = nc.typeArgs.length >= 1 ? nc.typeArgs[0] : anyType();
        TypeSema elem1 = nc.typeArgs.length >= 2 ? nc.typeArgs[1] : anyType();
        TypeSema csizeType = new TypeSemaNative(NativeScalarKind.CSize, "csize"d);
        TypeSema cboolType = new TypeSemaNative(NativeScalarKind.CBool, "cbool"d);
        TypeSema voidType = new TypeSemaBuiltin(TypeSemaBase.Void);
        TypeSema strType = new TypeSemaBuiltin(TypeSemaBase.String);

        if (isStaticCall)
        {
            if (nc.containerKind == NativeContainerKind.StringNativa
                    && (methodName == "criar"d || methodName == "vazia"d))
                return nc;
            if (nc.containerKind == NativeContainerKind.VisaoTexto && methodName == "deTexto"d)
                return nc;
            if (nc.containerKind == NativeContainerKind.OpcionalNativo
                    && (methodName == "algum"d || methodName == "nenhum"d))
                return nc;
            if (nc.containerKind == NativeContainerKind.ResultadoNativo
                    && (methodName == "ok"d || methodName == "erro"d))
                return nc;
            return nc;
        }

        final switch (nc.containerKind)
        {
            case NativeContainerKind.VetorNativo:
                switch (methodName)
                {
                    case "tamanho":
                    case "capacidade":
                        return csizeType;
                    case "obter":
                    case "removerUltimo":
                        return elem0;
                    case "adicionar":
                    case "definir":
                    case "limpar":
                    case "reservar":
                    case "liberar":
                        return voidType;
                    case "vazio":
                        return cboolType;
                    case "fatia":
                        return new TypeSemaNativeContainer(NativeContainerKind.FatiaNativa, [elem0]);
                    case "clonar":
                        return nc;
                    case "paraVetor":
                        return new TypeSemaArray(elem0);
                    default:
                        return anyType();
                }
            case NativeContainerKind.MapaNativo:
                switch (methodName)
                {
                    case "tamanho":
                    case "capacidade":
                        return csizeType;
                    case "obter":
                        return elem1;
                    case "definir":
                    case "limpar":
                    case "liberar":
                        return voidType;
                    case "contem":
                    case "contém":
                    case "remover":
                    case "vazio":
                        return cboolType;
                    case "clonar":
                        return nc;
                    case "paraDicionario":
                        return new TypeSemaBuiltin(TypeSemaBase.Map);
                    default:
                        return anyType();
                }
            case NativeContainerKind.FatiaNativa:
                switch (methodName)
                {
                    case "tamanho":
                        return csizeType;
                    case "obter":
                        return elem0;
                    case "vazio":
                        return cboolType;
                    case "fatia":
                        return nc;
                    default:
                        return anyType();
                }
            case NativeContainerKind.StringNativa:
                switch (methodName)
                {
                    case "tamanho":
                    case "capacidade":
                        return csizeType;
                    case "anexar":
                    case "limpar":
                    case "liberar":
                        return voidType;
                    case "visao":
                    case "visão":
                        return new TypeSemaNativeContainer(NativeContainerKind.VisaoTexto);
                    case "igual":
                    case "comecaCom":
                    case "vazia":
                        return cboolType;
                    case "clonar":
                        return nc;
                    case "paraTexto":
                        return strType;
                    default:
                        return anyType();
                }
            case NativeContainerKind.VisaoTexto:
                switch (methodName)
                {
                    case "tamanho":
                        return csizeType;
                    case "igual":
                    case "comecaCom":
                    case "vazia":
                        return cboolType;
                    case "paraTexto":
                        return strType;
                    default:
                        return anyType();
                }
            case NativeContainerKind.ResultadoNativo:
                switch (methodName)
                {
                    case "ehOk":
                    case "ehErro":
                        return cboolType;
                    case "valor":
                        return elem0;
                    case "erro":
                        return elem1;
                    case "valorOu":
                        return elem0;
                    default:
                        return anyType();
                }
            case NativeContainerKind.OpcionalNativo:
                switch (methodName)
                {
                    case "temValor":
                    case "ehNenhum":
                        return cboolType;
                    case "valor":
                    case "valorOu":
                        return elem0;
                    default:
                        return anyType();
                }
            case NativeContainerKind.MatrizNativa:
                switch (methodName)
                {
                    case "linhas":
                    case "colunas":
                    case "tamanho":
                        return csizeType;
                    case "obter":
                        return elem0;
                    case "definir":
                    case "liberar":
                        return voidType;
                    case "multiplicar":
                    case "transpor":
                    case "clonar":
                        return nc;
                    default:
                        return anyType();
                }
        }
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
        if (cast(TypeSemaClass) node.value.type_sema !is null)
        {
            dstring sym = tokenToUnaryOperatorSymbol(node.op);
            if (sym.length)
            {
                FnDecl opMethod = resolveUnaryOperator(sym, node.value.type_sema, lexicalOwner, node.pos, err);
                if (opMethod !is null)
                {
                    node.resolvedOperator = opMethod;
                    node.type_sema = callResult(opMethod);
                    return node;
                }
            }
        }
        if (node.op == TokenKind.Bang)
            node.type_sema = new TypeSemaBuiltin(TypeSemaBase.Bool);
        if (node.op == TokenKind.PPlus || node.op == TokenKind.MMinus)
        {
            validateAssignmentTarget(node.value, err);
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

        if (value.type_sema is null || idx.type_sema is null)
        {
            node.type_sema = anyType();
            return node;
        }
        if (TypeSemaNativeContainer nc = cast(TypeSemaNativeContainer) value.type_sema)
        {
            if ((nc.containerKind == NativeContainerKind.VetorNativo
                    || nc.containerKind == NativeContainerKind.FatiaNativa) && nc.typeArgs.length >= 1)
            {
                node.type_sema = nc.typeArgs[0];
                return node;
            }
            if (nc.containerKind == NativeContainerKind.MapaNativo && nc.typeArgs.length >= 2)
            {
                node.type_sema = nc.typeArgs[1];
                return node;
            }
        }
        if (cast(TypeSemaClass) value.type_sema !is null)
        {
            FnDecl opMethod = resolveIndexOperator("[]"d, value.type_sema, idx.type_sema, null,
                    lexicalOwner, node.pos, err);
            if (opMethod !is null)
            {
                node.resolvedOperator = opMethod;
                node.type_sema = callResult(opMethod);
                return node;
            }
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
        bool idxIsInt = type2 == TypeSemaBase.Int || type2 == TypeSemaBase.Any
            || (cast(TypeSemaNative) idx.type_sema !is null && (cast(TypeSemaNative) idx.type_sema).isInteger());
        if (type != TypeSemaBase.Map && type != TypeSemaBase.Any && !idxIsInt)
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

    Node analyzeAssignStmt(AssignStmt node)
    {
        if (IndexExpr idxLeft = cast(IndexExpr) node.left)
        {
            idxLeft.value = analyze(idxLeft.value);
            idxLeft.idx = analyze(idxLeft.idx);
            node.value = analyze(node.value);
            if (idxLeft.value !is null && cast(TypeSemaClass) idxLeft.value.type_sema !is null)
            {
                FnDecl setOp = resolveIndexOperator("[]="d, idxLeft.value.type_sema, idxLeft.idx.type_sema,
                        node.value.type_sema, lexicalOwner, node.pos, err);
                if (setOp !is null)
                {
                    node.resolvedIndexSetOperator = setOp;
                    idxLeft.type_sema = node.value.type_sema;
                    node.type_sema = callResult(setOp);
                    return node;
                }
            }
            if (idxLeft.value !is null && cast(TypeSemaNativeContainer) idxLeft.value.type_sema !is null)
            {
                TypeSemaNativeContainer nc = cast(TypeSemaNativeContainer) idxLeft.value.type_sema;
                TypeSema elemType = nc.containerKind == NativeContainerKind.MapaNativo && nc.typeArgs.length >= 2
                    ? nc.typeArgs[1] : (nc.typeArgs.length >= 1 ? nc.typeArgs[0] : anyType());
                idxLeft.type_sema = elemType;
                node.type_sema = elemType;
                checkTypes(node.pos, elemType, node.value.type_sema);
                return node;
            }
        }
        node.left = analyze(node.left);
        node.value = analyze(node.value);
        node.type_sema = node.left.type_sema;
        if (!validateAssignmentTarget(node.left, err))
            return node;
        // Campos passam pela segurança estática: falhas tratadas em pegue são W31xx.
        if (cast(MemberExpr) node.left is null)
            checkTypes(node.pos, node.left.type_sema, node.value.type_sema);
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

        if (sym.isModule())
        {
            sym.uses++;
            SymbolModule modSym = cast(SymbolModule)*sym;
            node.moduleRef = modSym.target;
            node.namespacePath = [node.value];
            node.type_sema = anyType();
            return node;
        }

        if (sym.isFn())
        {
            sym.uses++;
            node.functionRef = (cast(SymbolFn*) sym).node;
            node.classRef = node.functionRef.classFactory;
            if (cast(TypeExprGeneric) node.type_expr !is null)
            {
                node.type_sema = resolver.resolver(node.type_expr);
                return node;
            }
            if (node.value == "StringNativa"d)
            {
                node.type_sema = new TypeSemaNativeContainer(NativeContainerKind.StringNativa);
                return node;
            }
            if (node.value == "VisaoTexto"d)
            {
                node.type_sema = new TypeSemaNativeContainer(NativeContainerKind.VisaoTexto);
                return node;
            }
            node.type_sema = new TypeSemaBuiltin(TypeSemaBase.Function);
            return node;
        }

        if (!comptimeValue)
            sym.uses++;

        if (sym.isVar())
        {
            node.variableRef = (cast(SymbolVar*) sym).node;
            node.type_expr = node.variableRef.type_expr;
            if (node.variableRef.isConst)
                if (MemberExpr initMember = cast(MemberExpr) node.variableRef.value)
                    if (Identifier initRight = cast(Identifier) initMember.right)
                        if (initRight.classRef !is null)
                            node.classRef = initRight.classRef;
        }
        if (sym.isParam())
        {
            node.parameterRef = (cast(SymbolParam*) sym).node;
            node.type_expr = node.parameterRef.rest ? new TypeExprArray(node.parameterRef.type_expr,
                    node.pos) : node.parameterRef.type_expr;
        }
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

    TypeSema callResult(FnDecl declaration)
    {
        TypeSema result = declaration.type_sema !is null ? declaration.type_sema
            : resolver.resolver(declaration.type_expr);
        return declaration.isAsync ? new TypeSemaPromise(result) : result;
    }

    FnDecl knownCallable(Node expression, size_t depth = 0)
    {
        if (expression is null || depth > 32)
            return null;
        if (FunctionExpr functionValue = cast(FunctionExpr) expression)
            return functionValue.declaration;
        if (MemberExpr member = cast(MemberExpr) expression)
            if (Identifier name = cast(Identifier) member.right)
                return name.functionRef;
        if (Identifier name = cast(Identifier) expression)
        {
            if (name.functionRef !is null)
                return name.functionRef;
            if (name.variableRef !is null && name.variableRef.isConst)
                return knownCallable(name.variableRef.value, depth + 1);
        }
        return null;
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
        if (id !is null && cast(TypeExprGeneric) id.type_expr !is null)
        {
            TypeSema resolvedGen = resolver.resolver(id.type_expr);
            id.type_sema = resolvedGen;
            foreach (ref Node arg; node.args)
                arg = analyze(arg);
            node.type_sema = resolvedGen;
            return node;
        }
        Symbol* sym = id is null ? null : context.get(id.value);
        if (sym !is null && sym.isFn())
        {
            FnDecl fn = (cast(SymbolFn*) sym).node;
            sym.uses++;
            id.functionRef = fn;
            id.classRef = fn.classFactory;
            if (fn.classFactory !is null)
            {
                analyzeClass(fn.classFactory);
                if (fn.classFactory.isAbstract)
                    err.error(node.pos, "Classe abstrata/interface não pode ser instanciada.");
            }
            node.builtinCall = (cast(SymbolFn*) sym).isRuntime;
            node.type_sema = fn.classFactory is null ? callResult(fn) : new TypeSemaClass(fn.classFactory);
            foreach (ref Node arg; node.args)
                arg = analyze(arg);
            if (id.value != "escreva")
                validateArguments(fn, node);
            return node;
        }
        node.fn = analyze(node.fn);
        foreach (ref Node arg; node.args)
            arg = analyze(arg);
        node.type_sema = anyType();
        bool isClassFactoryCall = false;
        if (MemberExpr member = cast(MemberExpr) node.fn)
            if (Identifier name = cast(Identifier) member.right)
            {
                if (TypeSemaNativeContainer nc = cast(TypeSemaNativeContainer) member.left.type_sema)
                {
                    bool isStaticFactory = (cast(Identifier) member.left) !is null
                        && ((cast(Identifier) member.left).value == "StringNativa"d
                            || (cast(Identifier) member.left).value == "VisaoTexto"d
                            || cast(TypeExprGeneric)(cast(Identifier) member.left).type_expr !is null);
                    node.type_sema = resolveNativeContainerMethodReturn(nc, name.value, isStaticFactory);
                    return node;
                }
                if (name.functionRef !is null)
                {
                    FnDecl target = name.functionRef;
                    node.type_sema = callResult(target);
                    validateArguments(target, node);
                }
                else if (name.classRef !is null)
                {
                    isClassFactoryCall = true;
                    ClassDecl cls = name.classRef;
                    if (cls.isAbstract)
                        err.error(node.pos, "Classe abstrata/interface não pode ser instanciada.");
                    node.type_sema = new TypeSemaClass(cls);
                    if (cls.signature !is null)
                        validateArguments(cls.signature, node);
                }
            }
        if (!isClassFactoryCall)
            if (Identifier fnId = cast(Identifier) node.fn)
                if (fnId.variableRef !is null && fnId.variableRef.isConst)
                    if (MemberExpr initMember = cast(MemberExpr) fnId.variableRef.value)
                        if (Identifier initRight = cast(Identifier) initMember.right)
                            if (initRight.classRef !is null)
                            {
                                isClassFactoryCall = true;
                                ClassDecl cls = initRight.classRef;
                                if (cls.isAbstract)
                                    err.error(node.pos, "Classe abstrata/interface não pode ser instanciada.");
                                node.type_sema = new TypeSemaClass(cls);
                                if (cls.signature !is null)
                                    validateArguments(cls.signature, node);
                            }
        FnDecl known = knownCallable(node.fn);
        if (known !is null && (known.isAsync || cast(TypeExprPromise) known.type_expr) && !cast(MemberExpr) node.fn)
        {
            node.type_sema = callResult(known);
            validateArguments(known, node);
        }
        if (!isClassFactoryCall && node.fn.type_sema !is null && !node.fn.type_sema.isAny()
                && node.fn.type_sema.toStr() != TypeSemaBase.Function)
            err.errorCode(node.pos, notCallable, node.fn.type_sema.toStr());
        return node;
    }

    private bool isTransferableType(TypeSema type)
    {
        if (type is null)
            return true;
        if (TypeSemaBuiltin builtin = cast(TypeSemaBuiltin) type)
            return builtin.base == TypeSemaBase.Int || builtin.base == TypeSemaBase.Double
                || builtin.base == TypeSemaBase.Bool || builtin.base == TypeSemaBase.String
                || builtin.base == TypeSemaBase.Void || builtin.base == TypeSemaBase.Any;
        return false;
    }

    Node analyzeRoutineExpr(RoutineExpr node)
    {
        node.call = cast(CallExpr) analyzeCallExpr(node.call);
        FnDecl target = knownCallable(node.call.fn);
        if (target is null || node.call.builtinCall || target.classFactory !is null || (target.isMethod
                && !target.isStatic) || target.accessor || target.isAbstract
                || target.foreignSymbol.length || !target.linkName.length
                || node.call.args.any!((Node a) => a.kind == NodeKind.SpreadExpr))
        {
            err.errorCode(node.pos, catalog.routineTarget);
            node.type_sema = new TypeSemaTask(anyType());
            return node;
        }
        if (target.isAsync)
        {
            err.errorCode(node.pos, catalog.routineAsync);
            node.type_sema = new TypeSemaTask(anyType());
            return node;
        }
        foreach (size_t i, Node arg; node.call.args)
        {
            if (!isTransferableType(arg.type_sema))
                err.errorCode(arg.pos, catalog.routineTransfer, arg.type_sema.toStr());
            else if (i < target.args.length)
            {
                TypeSema paramType = target.args[i].type_sema !is null ? target.args[i].type_sema
                    : resolver.resolver(target.args[i].type_expr);
                if (!isTransferableType(paramType))
                    err.errorCode(arg.pos, catalog.routineTransfer, paramType.toStr());
            }
        }
        TypeSema retType = target.type_sema !is null ? target.type_sema : resolver.resolver(target.type_expr);
        if (!isTransferableType(retType))
            err.errorCode(node.pos, catalog.routineTransfer, retType.toStr());
        node.target = target;
        node.resultType = target.type_expr;
        node.type_sema = new TypeSemaTask(retType);
        return node;
    }

    void validateArguments(FnDecl target, CallExpr call)
    {
        if (call.args.any!((Node argument) => argument.kind == NodeKind.SpreadExpr))
            return;
        size_t minimum;
        bool rest = target.args.length && target.args[$ - 1].rest;
        foreach (FnArg argument; target.args)
            if (argument.value is null && !argument.rest)
                minimum++;
        if (call.args.length < minimum || (!rest && call.args.length > target.args.length))
            err.errorCode(call.pos, invalidArity, target.fn, minimum, target.args.length, call.args.length);
        foreach (size_t i, Node argument; call.args)
            if (i < target.args.length && !target.args[i].rest)
            {
                TypeSema expected = target.args[i].type_sema !is null ? target.args[i].type_sema
                    : resolver.resolver(target.args[i].type_expr);
                checkTypes(argument.pos, expected, argument.type_sema);
            }
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
        bool previousAsync = asyncBody;
        asyncBody = false;
        scope (exit)
            asyncBody = previousAsync;
        if (node.isAsync && (node.accessor || node.foreignSymbol.length || node.fn == "construtor"
                || node.fn == "destrutor"))
            err.errorCode(node.pos, asyncContext);
        if (node.isAsync && node.ctfe_flags)
            err.errorCode(node.pos, asyncPure);
        bool allowEnvelopes = !node.isMethod || (!node.accessor && !node.isAbstract
                && !node.foreignSymbol.length && node.fn != "construtor" && node.fn != "destrutor");
        analyzeDecorators(node.decorators, node.pos, allowEnvelopes);
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
        registry.pushEnumScope();
        ClassDecl previousOwner = methodOwner;
        ClassDecl previousLexicalOwner = lexicalOwner;
        lexicalOwner = node.ownerClass;
        methodOwner = node.isMethod && !node.isStatic ? node.ownerClass : null;
        if (node.isMethod && !node.isStatic)
        {
            TypeExpr selfExpr = node.ownerClass !is null && node.ownerClass.isValueType
                ? new TypeExprNamed(node.ownerClass.name, node.pos) : new TypeExprNamed("qualquer", node.pos);
            FnArg self = new FnArg("isto", selfExpr, null, node.pos);
            self.type_sema = node.ownerClass !is null && node.ownerClass.isValueType
                ? cast(TypeSema) new TypeSemaClass(node.ownerClass) : anyType();
            context.set("isto", new SymbolParam(self));
        }
        node.type_sema = resolver.resolver(node.type_expr);
        returnTypes ~= node.type_sema;

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

        asyncBody = node.isAsync;
        predeclare(node.body);
        for (uint i; i < node.body.length; i++)
            node.body[i] = analyze(node.body[i]);

        methodOwner = previousOwner;
        lexicalOwner = previousLexicalOwner;
        registry.popEnumScope();
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

        // Resolução de operadores personalizados (@operador) quando ao menos um operando é classe.
        // Operadores primitivos têm prioridade absoluta.
        if (cast(TypeSemaClass) l !is null || cast(TypeSemaClass) r !is null)
        {
            dstring opSym = tokenToBinaryOperatorSymbol(node.op);
            if (opSym.length)
            {
                bool swapped;
                FnDecl opMethod = resolveBinaryOperator(opSym, l, r, lexicalOwner, node.pos, err, swapped);
                if (opMethod !is null)
                {
                    node.resolvedOperator = opMethod;
                    node.operatorSwapped = swapped;
                    node.type_sema = callResult(opMethod);
                    return node;
                }
            }
        }

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
        if (cast(TypeSemaNative) l is null && cast(TypeSemaNative) r is null)
        {
            node.left.type_sema = type;
            node.right.type_sema = type;
        }

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
        if (node.uninitialized)
            node.lackedExplicitInit = true;
        if (node.uninitialized && node.type_expr !is null)
        {
            Node initial = defaultValue(resolver.resolver(node.type_expr), node.pos);
            if (initial !is null)
            {
                node.value = initial;
                node.uninitialized = false;
            }
        }
        node.value = analyze(node.value);

        dstring name = node.name;
        if (Symbol* sym = context.getLocal(name))
        {
            err.error(node.pos, format("%s '%s' já existe.", ternary(sym.isVar(), "A variavel", "O simbolo"), name));
            alreadyDeclaredHere(name, getPosFromSymbol(sym), err);
        }

        TypeSema valueType = node.value.type_sema;

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
