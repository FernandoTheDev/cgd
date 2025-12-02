module frontend.parser.parse_stmt;
import frontend;

mixin template ParseStmt()
{
    Node parseStatement()
    {
        switch (this.peek().kind)
        {
        default:
            return null;
        }
    }
}
