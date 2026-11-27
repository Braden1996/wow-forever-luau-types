--!strict
-- LuaCATS type expressions in, Luau types out (luacats/typeparse.luau and print.luau).

local SpecCase = require("./spec-case")
local TypeExpr = require("./typeexpr")

local function resolve(name: string, _args: { TypeExpr.Type }): string
	return name
end

local function convert(text: string): { string }
	local t, rest = TypeExpr.parsePrefix(text)
	return { if t then TypeExpr.print(t, resolve) else "nil", rest }
end

local function case(text: string, printed: string, rest: string?): SpecCase.Case
	return {
		name = "type " .. text,
		run = function()
			return convert(text), { printed, rest or "" }
		end,
	}
end

local cases: { SpecCase.Case } = {
	case("fun(a: table<string, number>, b: string): boolean", "(a: { [string]: number }, b: string) -> boolean"),
	case(
		"fun(a: string|number, b?: integer):(boolean, string)",
		"(a: string | number, b: integer?) -> (boolean, string)"
	),
	case("table<string, fun(a: number): string>|nil", "{ [string]: (a: number) -> string }?"),
	case("fun(a: string): (boolean", "nil", "fun(a: string): (boolean"),
	case("fun(...: string): ...number", "(...string) -> (...number)"),
	case("fun(): string, ...", "() -> (string, ...any)"),
	case(
		'{ ["a-b"]: string, [1]: number, [2]: boolean, name: string }',
		'{ ["a-b"]: string, name: string, [number]: number | boolean }'
	),
	case("{ [string]: boolean }", "{ [string]: boolean }"),
	case("{ 1a: string }", "nil", "{ 1a: string }"),
	case([["a\"b" | "c|d"]], [["a\"b" | "c|d"]]),
	case("string[] # the names", "{ string }", " # the names"),
	case("(fun(): string)?", "(() -> string)?"),
	case("`Enum.Foo`", "string"),
	{
		name = "splitUnion skips strings and parentheses",
		run = function()
			return TypeExpr.splitUnion('"a|b" | number | (x | y)'), { '"a|b"', "number", "(x | y)" }
		end,
	},
	{
		name = "wrap parenthesises function types and unions, not types that contain them",
		run = function()
			return {
				TypeExpr.wrap("(a: number) -> ()"),
				TypeExpr.wrap("string | number"),
				TypeExpr.wrap("{ (a: number) -> () }"),
				TypeExpr.wrap("string"),
			}, { "((a: number) -> ())", "(string | number)", "{ (a: number) -> () }", "string" }
		end,
	},
	{
		name = "quote escapes backslash, quote and control characters",
		run = function()
			return TypeExpr.quote('a"b\\c\n\t'), [["a\"b\\c\n\t"]]
		end,
	},
}

return SpecCase.specs(cases)
