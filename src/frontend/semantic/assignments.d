module frontend.semantic.assignments;

import frontend.parser;
import errors;

/// Mesma regra para atribuições simples, compostas e incremento/decremento.
bool validateAssignmentTarget(Node node, Diagnostics diagnostics)
{
    if (MemberExpr member = cast(MemberExpr) node)
        if (member.readonly)
        {
            diagnostics.errorCode(node.pos, invalidAssignment, "Não é possível substituir um enum.");
            return false;
        }
    if (cast(MemberExpr) node || cast(IndexExpr) node)
        return true;
    if (Identifier identifier = cast(Identifier) node)
    {
        if (identifier.functionRef !is null)
            diagnostics.errorCode(node.pos, invalidAssignment, "Não é possível atribuir a uma função.");
        else if (identifier.value == "isto")
            diagnostics.errorCode(node.pos, invalidAssignment, "O receptor isto não pode ser reatribuído.");
        else if (identifier.variableRef !is null && identifier.variableRef.isConst)
            diagnostics.errorCode(node.pos, invalidAssignment, "Não é possível modificar uma constante.");
        else
            return identifier.variableRef !is null || identifier.parameterRef !is null;
        return false;
    }
    diagnostics.errorCode(node.pos, invalidAssignment,
            "Atribuição exige uma variável, propriedade ou índice modificável.");
    return false;
}
