module frontend.semantic.type_checker;

import frontend;
import common.reporter;

class TypeChecker
{
    Context ctx;
    DiagnosticError error;
    FunctionAnalyzer funcAnalyzer;

    this(Context ctx, DiagnosticError error)
    {
        this.ctx = ctx;
        this.error = error;
    }

    Type checkExpression(Node expr)
    {
        if (expr is null)
            return VoidType.instance();

        if (expr.resolvedType !is null)
            return expr.resolvedType;

        Type type = checkExpressionInternal(expr);
        expr.resolvedType = type;
        return type;
    }

private:

    Type checkExpressionInternal(Node expr)
    {
        // Literais
        if (auto lit = cast(IntLit) expr)
            return new PrimitiveType(BaseType.Int);
        if (auto lit = cast(LongLit) expr)
            return new PrimitiveType(BaseType.Long);
        if (auto lit = cast(FloatLit) expr)
            return new PrimitiveType(BaseType.Float);
        if (auto lit = cast(DoubleLit) expr)
            return new PrimitiveType(BaseType.Double);
        if (auto lit = cast(StringLit) expr)
            return new PrimitiveType(BaseType.String);
        if (auto lit = cast(BoolLit) expr)
            return new PrimitiveType(BaseType.Bool);
        if (auto lit = cast(NullLit) expr)
            return new PrimitiveType(BaseType.Any); // ou NullType

        // Identificadores
        if (auto ident = cast(Identifier) expr)
            return checkIdentifier(ident);

        // Operações
        if (auto binary = cast(BinaryExpr) expr)
            return checkBinaryExpr(binary);
        if (auto unary = cast(UnaryExpr) expr)
            return checkUnaryExpr(unary);
        if (auto assign = cast(AssignDecl) expr)
            return checkAssignDecl(assign);

        // Chamadas e acessos
        if (auto call = cast(CallExpr) expr)
            return checkCallExpr(call);
        if (auto index = cast(IndexExpr) expr)
            return checkIndexExpr(index);
        // if (auto member = cast(MemberExpr) expr)
        //     return checkMemberExpr(member);

        // Arrays
        if (auto arr = cast(ArrayLit) expr)
            return checkArrayLiteral(arr);

        // Agrupamento
        if (auto grouped = cast(GroupedExpr) expr)
            return checkExpression(grouped.expr);

        if (auto ternary = cast(TernaryExpr) expr)
            return checkTernary(ternary);

        if (auto fn = cast(FuncExpr) expr)
            return checkFuncExpr(fn);

        error.addError(Diagnostic(
                "Expressão desconhecida na checagem de tipos",
                expr.loc
        ));
        return new PrimitiveType(BaseType.Any);
    }

    Type checkFuncExpr(FuncExpr fn)
    {
        this.funcAnalyzer.analyzeLambda(fn);
        return fn.resolvedType;
    }

    Type checkTernary(TernaryExpr ternary)
    {
        Type condition = checkExpression(ternary.condition);
        Type left = ternary.trueExpr is null ? null : checkExpression(ternary.trueExpr);
        Type right = checkExpression(ternary.falseExpr);

        if (!condition.isCompatibleWith(new PrimitiveType(BaseType.Bool)))
        {
            error.addError(Diagnostic(
                    "A condição do ternario deve ser do tipo 'lógico'.",
                    ternary.loc
            ));
            return new PrimitiveType(BaseType.Any);
        }

        if (left is null)
            return right;

        if (!left.isCompatibleWith(right, false) || !right.isCompatibleWith(left, false))
        {
            error.addError(Diagnostic(
                    "Ambos os valores devem ser compativeis entre si.",
                    ternary.loc
            ));
            return new PrimitiveType(BaseType.Any);
        }

        if (right.toStr() == left.toStr())
            return left;

        return new UnionType([left, right]);
    }

    Type checkIdentifier(Identifier ident)
    {
        string id = ident.value.get!string;
        Symbol sym = ctx.lookup(id);

        if (sym is null)
        {
            error.addError(Diagnostic(
                    format("'%s' não foi declarado", id),
                    ident.loc,
                    [
                        Suggestion("Verifique se a variável foi declarada antes do uso")
                    ]
            ));
            return new PrimitiveType(BaseType.Any);
        }

        // pode ser uma função
        if (sym.type is null)
        {
            if (ctx.lookupFunction(id) !is null)
            {
                FunctionSymbol fnSym = ctx.lookupFunction(id);
                sym.type = fnSym.returnType;
            }
        }

        if (sym.type is null)
        {
            error.addError(Diagnostic(
                    format("'%s' não tem tipo definido", id),
                    ident.loc
            ));
            return new PrimitiveType(BaseType.Any);
        }

        ident.resolvedType = sym.type;
        return sym.type;
    }

    Type checkBinaryExpr(BinaryExpr expr)
    {
        Type leftType = checkExpression(expr.left);
        expr.left.resolvedType = leftType;
        Type rightType = checkExpression(expr.right);
        expr.right.resolvedType = rightType;

        string op = expr.op;

        // Operadores aritméticos: +, -, *, /, %
        if (op == "+" || op == "-" || op == "*" || op == "/" || op == "%")
        {
            if (!leftType.isNumeric() || !rightType.isNumeric())
            {
                error.addError(Diagnostic(
                        format("Operador '%s' requer operandos numéricos", op),
                        expr.loc
                ));
                return new PrimitiveType(BaseType.Any);
            }

            // Type promotion
            Type t = leftType.getPromotedType(rightType);
            expr.resolvedType = t;
            return t;
        }

        // Operadores de comparação: ==, !=, <, >, <=, >=
        if (op == "==" || op == "!=" || op == "<" || op == ">" ||
            op == "<=" || op == ">=")
        {
            if (!leftType.isCompatibleWith(rightType, false))
            {
                error.addError(Diagnostic(
                        format("Não é possível comparar '%s' com '%s'",
                        leftType.toStr(), rightType.toStr()),
                        expr.loc
                ));
            }
            Type t = new PrimitiveType(BaseType.Bool);
            expr.resolvedType = t;
            return t;
        }

        // Operadores lógicos: &&, ||
        if (op == "&&" || op == "||")
        {
            auto boolType = new PrimitiveType(BaseType.Bool);
            if (!leftType.isCompatibleWith(boolType) ||
                !rightType.isCompatibleWith(boolType))
            {
                error.addError(Diagnostic(
                        format("Operador '%s' requer operandos lógicos", op),
                        expr.loc
                ));
            }
            expr.resolvedType = boolType;
            return boolType;
        }

        // Operadores bitwise: &, |, ^, <<, >>, >>>
        if (op == "&" || op == "|" || op == "^" ||
            op == "<<" || op == ">>" || op == ">>>")
        {
            if (!leftType.isNumeric() || !rightType.isNumeric())
            {
                error.addError(Diagnostic(
                        format("Operador bitwise '%s' requer operandos inteiros", op),
                        expr.loc
                ));
            }
            expr.resolvedType = leftType;
            return leftType;
        }

        error.addError(Diagnostic(
                format("Operador binário desconhecido: '%s'", op),
                expr.loc
        ));
        return new PrimitiveType(BaseType.Any);
    }

    Type checkUnaryExpr(UnaryExpr expr)
    {
        Type operandType = checkExpression(expr.operand);
        string op = expr.op;
        expr.resolvedType = operandType;

        // Negação: -x
        if (op == "-")
        {
            if (!operandType.isNumeric())
            {
                error.addError(Diagnostic(
                        "Operador '-' requer operando numérico",
                        expr.loc
                ));
            }
            return operandType;
        }

        // NOT lógico: !x
        if (op == "!")
        {
            auto boolType = new PrimitiveType(BaseType.Bool);
            if (!operandType.isCompatibleWith(boolType))
            {
                error.addError(Diagnostic(
                        "Operador '!' requer operando lógico",
                        expr.loc
                ));
            }
            expr.resolvedType = boolType;
            return boolType;
        }

        // NOT bitwise: ~x
        if (op == "~")
        {
            if (!operandType.isNumeric())
            {
                error.addError(Diagnostic(
                        "Operador '~' requer operando inteiro",
                        expr.loc
                ));
            }
            return operandType;
        }

        // ++, --
        if (op == "++" || op == "--" ||
            op == "++_prefix" || op == "--_prefix" ||
            op == "++_postfix" || op == "--_postfix")
        {
            if (!operandType.isNumeric())
            {
                error.addError(Diagnostic(
                        format("Operador '%s' requer operando numérico",
                        op[0 .. 2]),
                        expr.loc
                ));
            }
            return operandType;
        }

        if (op == "&")
        {
            expr.resolvedType = new PointerType(operandType);
            return expr.resolvedType;
        }

        if (op == "*")
        {
            if (!operandType.isPointer())
            {
                error.addError(Diagnostic(
                        "Operador '*' requer um ponteiro.",
                        expr.loc
                ));
                return operandType;
            }
            expr.resolvedType = (cast(PointerType) operandType).pointeeType;
            return (cast(PointerType) operandType).pointeeType;
        }

        return operandType;
    }

    Type checkAssignDecl(AssignDecl expr)
    {
        Type targetType = checkExpression(expr.left);
        Type valueType = checkExpression(expr.right);

        // Verifica se pode atribuir
        if (auto ident = cast(Identifier) expr.left)
        {
            string id = ident.value.get!string;
            if (!ctx.canAssign(id))
            {
                error.addError(Diagnostic(
                        format("'%s' é constante e não pode ser modificada",
                        id),
                        expr.loc
                ));
            }
        }

        // Atribuição simples: =
        if (expr.op == "=")
        {
            if (!valueType.isCompatibleWith(targetType))
            {
                error.addError(Diagnostic(
                        format("Tipo incompatível: não pode atribuir '%s' a '%s'",
                        valueType.toStr(), targetType.toStr()),
                        expr.loc
                ));
            }
            return targetType;
        }

        // Atribuições compostas: +=, -=, *=, etc
        // Checa como operação binária
        string binOp = expr.op[0 .. $ - 1]; // remove '='
        auto binaryType = checkBinaryExpr(
            new BinaryExpr(expr.left, expr.right, binOp, expr.loc)
        );

        if (!binaryType.isCompatibleWith(targetType))
        {
            error.addError(Diagnostic(
                    format("Tipo incompatível na atribuição composta '%s'", expr.op),
                    expr.loc
            ));
        }

        return targetType;
    }

    Type checkCallExpr(CallExpr expr)
    {
        FunctionSymbol funcSym = null;
        if (auto ident = expr.id)
            funcSym = ctx.lookupFunction(ident);

        if (funcSym is null)
        {
            error.addError(Diagnostic(
                    "Tentativa de chamar algo que não é função",
                    expr.loc
            ));
            return new PrimitiveType(BaseType.Any);
        }

        // Verifica número de argumentos
        if (expr.args.length != funcSym.paramTypes.length)
        {
            error.addError(Diagnostic(
                    format("Função espera %d argumentos, obteve %d",
                    funcSym.paramTypes.length, expr.args.length),
                    expr.loc
            ));
            return funcSym.returnType;
        }

        // Verifica tipo de cada argumento
        foreach (i, arg; expr.args)
        {
            Type argType = checkExpression(arg);
            Type paramType = funcSym.paramTypes[i];

            if (!paramType.isCompatibleWith(argType))
            {
                error.addError(Diagnostic(
                        format("Argumento %d: esperado '%s', obteve '%s'",
                        i + 1, paramType.toStr(), argType.toStr()),
                        arg.loc
                ));
            }
        }

        expr.resolvedType = funcSym.returnType;
        return funcSym.returnType;
    }

    Type checkIndexExpr(IndexExpr expr)
    {
        Type targetType = checkExpression(expr.target);
        Type indexType = checkExpression(expr.index);

        // Índice deve ser inteiro
        if (!indexType.isCompatibleWith(new PrimitiveType(BaseType.Int)))
        {
            error.addError(Diagnostic(
                    format("Índice deve ser inteiro, obteve '%s'",
                    indexType.toStr()),
                    expr.index.loc
            ));
        }

        // Target deve ser array
        if (auto arrType = cast(ArrayType) targetType)
        {
            expr.resolvedType = arrType.elementType;
            return arrType.elementType;
        }

        error.addError(Diagnostic(
                format("'%s' não é indexável", targetType.toStr()),
                expr.target.loc
        ));
        return new PrimitiveType(BaseType.Any);
    }

    // private Type checkMemberExpr(MemberExpr expr)
    // {
    //     Type targetType = checkExpression(expr.target);

    //     // Acesso a membro de classe
    //     if (auto classType = cast(ClassType) targetType)
    //     {
    //         Symbol member = classType.symbol.findMember(expr.member);
    //         if (member is null)
    //         {
    //             error.addError(Diagnostic(
    //                     format("Classe '%s' não tem membro '%s'",
    //                     classType.toStr(), expr.member),
    //                     expr.loc
    //             ));
    //             return new PrimitiveType(BaseType.Any);
    //         }
    //         return member.type;
    //     }

    //     // Acesso a campo de struct
    //     if (auto structType = cast(StructType) targetType)
    //     {
    //         Symbol field = structType.symbol.fields.get(expr.member, null);
    //         if (field is null)
    //         {
    //             error.addError(Diagnostic(
    //                     format("Struct '%s' não tem campo '%s'",
    //                     structType.toStr(), expr.member),
    //                     expr.loc
    //             ));
    //             return new PrimitiveType(BaseType.Any);
    //         }
    //         return field.type;
    //     }

    //     error.addError(Diagnostic(
    //             format("'%s' não tem membros", targetType.toStr()),
    //             expr.target.loc
    //     ));
    //     return new PrimitiveType(BaseType.Any);
    // }

    Type checkArrayLiteral(ArrayLit expr)
    {
        if (expr.elements.length == 0)
        {
            // Array vazio - tipo genérico
            return new ArrayType(new PrimitiveType(BaseType.Any));
        }

        // Infere tipo do primeiro elemento
        Type elemType = checkExpression(expr.elements[0]);

        // Verifica que todos elementos são compatíveis
        foreach (i, elem; expr.elements[1 .. $])
        {
            Type thisType = checkExpression(elem);
            if (!thisType.isCompatibleWith(elemType))
            {
                error.addError(Diagnostic(
                        format(
                        "Elemento %d do array tem tipo incompatível: " ~
                        "esperado '%s', obteve '%s'",
                        i + 2, elemType.toStr(), thisType.toStr()),
                        elem.loc
                ));
            }
        }

        Type t = new ArrayType(elemType);
        expr.resolvedType = t;
        return t;
    }
}
