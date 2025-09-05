module middle.optmizer.constant_folding;

import std.stdio;
import std.conv;
import std.format;
import std.variant;
import frontend.parser.ast;
import frontend.lexer.token;
import frontend.parser.ftype_info;
import frontend.values;

import error;

class ConstantFolding
{
private:
    DiagnosticError error;

    bool isLiteral(Stmt node)
    {
        // TODO: suportar mais tipos de literais
        return node.kind == NodeType.IntLiteral ||
            node.kind == NodeType.FloatLiteral ||
            node.kind == NodeType.BoolLiteral ||
            node.kind == NodeType.StringLiteral;
    }

    // Cria um literal baseado no resultado da operação
    Stmt makeLiteral(Variant result, TypesNative type, Loc loc)
    {
        switch (type)
        {
        case TypesNative.I32:
            return new IntLiteral(result.get!long(), createTypeInfo(type), loc);
        case TypesNative.F32:
            return new FloatLiteral(result.get!double(), createTypeInfo(type), loc);
        case TypesNative.I1:
            return new BoolLiteral(result.get!bool(), loc);
        case TypesNative.I8P:
            return new StringLiteral(result.get!string(), loc);
        default:
            throw new Exception(format("Tipo não suportado para literal: %s", type));
        }
    }

    // Realiza operações aritméticas entre dois literais
    Variant performArithmeticOp(Stmt left, Stmt right, string op)
    {
        // Ambos são inteiros
        if (left.kind == NodeType.IntLiteral && right.kind == NodeType.IntLiteral)
        {
            long leftVal = left.value.get!long();
            long rightVal = right.value.get!long();

            switch (op)
            {
            case "+":
                return Variant(leftVal + rightVal);
            case "-":
                return Variant(leftVal - rightVal);
            case "*":
                return Variant(leftVal * rightVal);
            case "**":
                return Variant(leftVal ^^ rightVal);
            case "<<":
                return Variant(leftVal << rightVal);
            case "/":
                if (rightVal == 0)
                    throw new Exception("Divisão por zero detectada durante constant folding");
                return Variant(leftVal / rightVal);
            case "%":
                if (rightVal == 0)
                    throw new Exception("Módulo por zero detectado durante constant folding");
                return Variant(leftVal % rightVal);
            default:
                throw new Exception(format("Operador aritmético não suportado: %s", op));
            }
        }

        // Ambos são floats
        else if (left.kind == NodeType.FloatLiteral && right.kind == NodeType.FloatLiteral)
        {
            float leftVal = left.value.get!float();
            float rightVal = right.value.get!float();

            switch (op)
            {
            case "+":
                return Variant(leftVal + rightVal);
            case "-":
                return Variant(leftVal - rightVal);
            case "*":
                return Variant(leftVal * rightVal);
            case "**":
                return Variant(leftVal ^^ rightVal);
            case "<<":
                return Variant(to!long(leftVal) << to!long(rightVal));
            case "/":
                if (rightVal == 0.0f)
                    throw new Exception("Divisão por zero detectada durante constant folding");
                return Variant(leftVal / rightVal);
            default:
                throw new Exception(format("Operador aritmético não suportado para float: %s", op));
            }
        }

        // Operações mistas (int e float)
        else if ((left.kind == NodeType.IntLiteral && right.kind == NodeType.FloatLiteral) ||
            (left.kind == NodeType.FloatLiteral && right.kind == NodeType.IntLiteral))
        {
            float leftVal = left.kind == NodeType.IntLiteral ?
                cast(float) left.value.get!long() : left.value.get!float();
            float rightVal = right.kind == NodeType.IntLiteral ?
                cast(float) right.value.get!long() : right.value.get!float();

            switch (op)
            {
            case "+":
                return Variant(leftVal + rightVal);
            case "-":
                return Variant(leftVal - rightVal);
            case "*":
                return Variant(leftVal * rightVal);
            case "**":
                return Variant(leftVal ^^ rightVal);
            case "<<":
                return Variant(to!long(leftVal) << to!long(rightVal));
            case "/":
                if (rightVal == 0.0f)
                    throw new Exception("Divisão por zero detectada durante constant folding");
                return Variant(leftVal / rightVal);
            default:
                throw new Exception(format("Operador aritmético não suportado para tipos mistos: %s", op));
            }
        }

        throw new Exception("Tipos incompatíveis para operação aritmética");
    }

    // Realiza operações de comparação entre dois literais
    Variant performComparisonOp(Stmt left, Stmt right, string op)
    {
        // Comparações entre inteiros
        if (left.kind == NodeType.IntLiteral && right.kind == NodeType.IntLiteral)
        {
            long leftVal = left.value.get!long();
            long rightVal = right.value.get!long();

            switch (op)
            {
            case "==":
                return Variant(leftVal == rightVal);
            case "!=":
                return Variant(leftVal != rightVal);
            case "<":
                return Variant(leftVal < rightVal);
            case "<=":
                return Variant(leftVal <= rightVal);
            case ">":
                return Variant(leftVal > rightVal);
            case ">=":
                return Variant(leftVal >= rightVal);
            default:
                throw new Exception(format("Operador de comparação não suportado: %s", op));
            }
        }

        throw new Exception("Tipos não suportados para operação de comparação");
    }

    Variant performLogicalOp(Stmt left, Stmt right, string op)
    {
        if (left.kind == NodeType.BoolLiteral && right.kind == NodeType.BoolLiteral)
        {
            bool leftVal = left.value.get!bool();
            bool rightVal = right.value.get!bool();

            switch (op)
            {
            case "&&":
                return Variant(leftVal && rightVal);
            case "||":
                return Variant(leftVal || rightVal);
            default:
                throw new Exception(format("Operador lógico não suportado: %s", op));
            }
        }

        throw new Exception("Operadores lógicos requerem valores booleanos");
    }

    TypesNative getResultType(Stmt left, Stmt right, string op)
    {
        if (op == "==" || op == "!=" || op == "<" || op == "<=" || op == ">" || op == ">=")
            return TypesNative.I1;

        if (op == "&&" || op == "||")
            return TypesNative.I1;

        if (left.kind == NodeType.FloatLiteral || right.kind == NodeType.FloatLiteral)
            return TypesNative.F32;

        return TypesNative.I32;
    }

    Stmt binaryExpr(BinaryExpr binary)
    {
        if (binary.left.kind == NodeType.BinaryExpr)
            binary.left = binaryExpr(cast(BinaryExpr) binary.left);
        if (binary.right.kind == NodeType.BinaryExpr)
            binary.right = binaryExpr(cast(BinaryExpr) binary.right);

        if (!isLiteral(binary.left) || !isLiteral(binary.right))
        {
            binary.left = processStatement(binary.left);
            binary.right = processStatement(binary.right);
            return binary;
        }

        try
        {
            Variant result;

            if (binary.op == "+" || binary.op == "-" || binary.op == "*" || binary.op == "**" ||
                binary.op == "/" || binary.op == "%" || binary.op == "<<")
            {
                result = performArithmeticOp(binary.left, binary.right, binary.op);
            }
            else if (binary.op == "==" || binary.op == "!=" || binary.op == "<" ||
                binary.op == "<=" || binary.op == ">" || binary.op == ">=")
            {
                result = performComparisonOp(binary.left, binary.right, binary.op);
            }
            else if (binary.op == "&&" || binary.op == "||")
            {
                result = performLogicalOp(binary.left, binary.right, binary.op);
            }
            else
            {
                return binary;
            }

            TypesNative resultType = getResultType(binary.left, binary.right, binary.op);
            return makeLiteral(result, resultType, binary.loc);
        }
        catch (Exception e)
        {
            // Em caso de erro (como divisão por zero), retornar a expressão original
            // e possivelmente registrar o erro
            if (error !is null)
            {
                error.addError(Diagnostic(e.msg, binary.loc));
            }
            return binary;
        }
    }

    Stmt unaryExpr(UnaryExpr unary)
    {
        if (unary.operand.kind == NodeType.BinaryExpr)
            unary.operand = binaryExpr(cast(BinaryExpr) unary.operand);
        else if (unary.operand.kind == NodeType.UnaryExpr)
            unary.operand = unaryExpr(cast(UnaryExpr) unary.operand);

        if (!isLiteral(unary.operand))
            return unary;

        try
        {
            switch (unary.op)
            {
            case "-":
                if (unary.operand.kind == NodeType.IntLiteral)
                {
                    long val = unary.operand.value.get!long();
                    return new IntLiteral(-val, unary.operand.type, unary.loc);
                }
                else if (unary.operand.kind == NodeType.FloatLiteral)
                {
                    float val = unary.operand.value.get!float();
                    return new FloatLiteral(-val, unary.operand.type, unary.loc);
                }
                break;
            case "!":
                if (unary.operand.kind == NodeType.BoolLiteral)
                {
                    bool val = unary.operand.value.get!bool();
                    return new BoolLiteral(!val, unary.loc);
                }
                break;
            default:
                // Operador não suportado para constant folding
                return unary;
            }
        }
        catch (Exception e)
        {
            if (error !is null)
            {
                error.addError(Diagnostic(e.msg, unary.loc));
            }
        }

        return unary;
    }

public:
    this(DiagnosticError e)
    {
        this.error = e;
    }

    Program prog(Program program)
    {
        Program newProg = new Program([]);

        foreach (Stmt node; program.body)
        {
            Stmt processedNode = processStatement(node);
            newProg.body ~= processedNode;
        }

        return newProg;
    }

    Stmt processStatement(Stmt stmt)
    {
        switch (stmt.kind)
        {
        case NodeType.BinaryExpr:
            return binaryExpr(cast(BinaryExpr) stmt);
        case NodeType.UnaryExpr:
            return unaryExpr(cast(UnaryExpr) stmt);
        case NodeType.VariableDeclaration:
            auto varDecl = cast(VariableDeclaration) stmt;
            if (varDecl.value.hasValue())
                varDecl.value = processStatement(varDecl.value.get!Stmt());
            return varDecl;
        case NodeType.AssignmentDeclaration:
            auto assignDecl = cast(AssignmentDeclaration) stmt;
            if (assignDecl.value.hasValue())
                assignDecl.value = processStatement(assignDecl.value.get!Stmt());
            return assignDecl;
        case NodeType.ReturnStatement:
            auto retStmt = cast(ReturnStatement) stmt;
            if (retStmt.expr !is null)
                retStmt.expr = processStatement(retStmt.expr);
            return retStmt;
        case NodeType.CallExpr:
            auto callStmt = cast(CallExpr) stmt;
            for (long i; i < callStmt.args.length; i++)
                callStmt.args[i] = processStatement(callStmt.args[i]);
            return callStmt;
        case NodeType.IndexExpr:
            IndexExpr indexExpr = cast(IndexExpr) stmt;
            indexExpr.left = processStatement(indexExpr.left);
            indexExpr.index = processStatement(indexExpr.index);
            return indexExpr;
        case NodeType.IndexExprAssignment:
            IndexExprAssignment indexExprA = cast(IndexExprAssignment) stmt;
            indexExprA.left = processStatement(indexExprA.left);
            indexExprA.index = processStatement(indexExprA.index);
            indexExprA.value = processStatement(indexExprA.value);
            return indexExprA;
        default:
            return stmt;
        }
    }
}
