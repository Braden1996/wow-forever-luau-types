--!strict
-- LuaCATS type expressions in, Luau types out (generator/luacats/typeparse.luau and print.luau).

local Case = require("./case")
local TypeExpr = require("../../generator/typeexpr")

-- Names print as written, so a case shows only what the parser and printer did.
local function resolve(name: string, _args: { TypeExpr.Type }): string
	return name
end

-- The printed type and the unparsed rest, or "nil" when the text does not parse.
local function convert(text: string): { string }
	local t, rest = TypeExpr.parsePrefix(text)
	return { if t then TypeExpr.print(t, resolve) else "nil", rest }
end

local function case(text: string, printed: string, rest: string?): Case.Case
	return {
		name = "type " .. text,
		run = function()
			return convert(text), { printed, rest or "" }
		end,
	}
end

local cases: { Case.Case } = {
	-- Commas inside a parameter's type do not end the parameter list (stopAtComma is threaded through).
	case("fun(a: table<string, number>, b: string): boolean", "(a: { [string]: number }, b: string) -> boolean"),
	case(
		"fun(a: string|number, b?: integer):(boolean, string)",
		"(a: string | number, b: integer?) -> (boolean, string)"
	),
	case("table<string, fun(a: number): string>|nil", "{ [string]: (a: number) -> string }?"),
	-- A parenthesised return list without its `)` is not a type.
	case("fun(a: string): (boolean", "nil", "fun(a: string): (boolean"),
	-- Variadics.
	case("fun(...: string): ...number", "(...string) -> (...number)"),
	case("fun(): string, ...", "() -> (string, ...any)"),
	-- Table literals: a string key is a property, numeric keys are positions, a type key is the indexer.
	case(
		'{ ["a-b"]: string, [1]: number, [2]: boolean, name: string }',
		'{ ["a-b"]: string, name: string, [number]: number | boolean }'
	),
	case("{ [string]: boolean }", "{ [string]: boolean }"),
	case("{ 1a: string }", "nil", "{ 1a: string }"),
	-- String literals keep their escapes, and a `|` inside one is not a union bar.
	case([["a\"b" | "c|d"]], [["a\"b" | "c|d"]]),
	-- Prose after the type is left in `rest`.
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

return cases
