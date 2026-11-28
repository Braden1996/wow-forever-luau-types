--!strict
-- LuaCATS type expressions: parses them into a small AST (luacats/typeparse.luau) and prints that AST as a
-- Luau type (luacats/print.luau). This module re-exports both under one name.

local Ast = require("./luacats/ast")
local Printer = require("./luacats/print")
local TypeParse = require("./luacats/typeparse")

export type Type = Ast.Type
export type Param = Ast.Param
export type TableKey = Ast.TableKey
export type Resolver = Printer.Resolver

return {
	parse = TypeParse.parse,
	parsePrefix = TypeParse.parsePrefix,
	print = Printer.print,
	printParam = Printer.printParam,
	printReturns = Printer.printReturns,
	paramName = Printer.paramName,
	quote = Printer.quote,
	unionOf = Printer.unionOf,
	splitUnion = Printer.splitUnion,
	wrap = Printer.wrap,
	RESERVED = Printer.RESERVED,
}
