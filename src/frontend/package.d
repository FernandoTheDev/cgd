module frontend;

public import std.stdio, std.variant, std.array, std.conv, std.format, std.algorithm;
public import frontend.lexer.lexer, frontend.lexer.token, frontend.types.type, frontend.parser.ast,
frontend.parser.parse_decl, frontend.parser.parse_expr, frontend.parser.parse_stmt,
frontend.parser.parser, frontend.types.type_expr, frontend.parser.parse_type,
frontend.types.builtins, frontend.semantic.context,
frontend.semantic.semantic1, frontend.types.registry, frontend.semantic.type_resolution, frontend
    .semantic.semantic2, frontend.semantic.semantic3, frontend.semantic.type_checker, frontend
    .semantic.context, frontend.semantic.function_analyzer;
