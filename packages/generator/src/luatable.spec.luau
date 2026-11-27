--!strict
-- Lua table literals read as data (luatable.luau).

local LuaTable = require("./luatable")
local SpecCase = require("./spec-case")

local function parse(text: string): unknown
	local ok, result = pcall(LuaTable.parseTableText, text)
	return if ok then result else { error = tostring(result) }
end

local function case(name: string, text: string, expected: unknown): SpecCase.Case
	return {
		name = name,
		run = function()
			return parse(text), expected
		end,
	}
end

local function tbl(array: { unknown }, map: { [string]: unknown }): unknown
	return { kind = "table", array = array, map = map }
end

local function ref(text: string): unknown
	return { kind = "ref", ref = text }
end

local cases: { SpecCase.Case } = {
	case("one-line table", '{ A = 1, B = "x", C = true }', tbl({}, { A = 1, B = "x", C = true })),
	case("positional values", "{ 1, 2; 3, }", tbl({ 1, 2, 3 }, {})),
	case(
		"bracket keys",
		'{ ["a b"] = 1, [2] = "two", [true] = 3 }',
		tbl({}, { ["a b"] = 1, ["2"] = "two", ["true"] = 3 })
	),
	case("a table key is an error", "{ [{}] = 1 }", { error = "line 1: a table cannot be a table key" }),
	case(
		"references and expressions",
		"{ A = Enum.X.Y, B = nil, C = Constants.Z + 1 }",
		tbl({}, { A = ref("Enum.X.Y"), B = ref("nil"), C = ref("Constants.Z + 1") })
	),
	case("numbers", "{ 0x1F, -2, 1.5e3, .5, 1-2 }", tbl({ 31, -2, 1500, 0.5, ref("1-2") }, {})),
	case("string escapes", [[{ "a\"b", 'c\\d', "e\nf" }]], tbl({ 'a"b', "c\\d", "e\nf" }, {})),
	case("comments", "{ --[[ long ]] A = 1, -- line\n --[==[ x ]] ]==] B = 2 }", tbl({}, { A = 1, B = 2 })),
	case("nested tables", "{ A = { 1, { B = 2 } } }", tbl({}, { A = tbl({ 1, tbl({}, { B = 2 }) }, {}) })),
	case("missing }", "{ A = 1", { error = "line 1: expected , or }" }),
	case("text after the table", "{ } x", { error = "line 1: unexpected text after the table" }),
	case("unterminated long comment", "{ --[[ A = 1 }", { error = "line 1: unterminated long comment" }),
	{
		name = "parseFile reads every local table",
		run = function()
			local tables = LuaTable.parseFile('local A =\n{\n\tName = "A",\n}\n\nlocal B = { Name = "B" }\n')
			local names = {}
			for _, t in tables do
				table.insert(names, LuaTable.str(t.map.Name))
			end
			return names, { "A", "B" }
		end,
	},
}

return SpecCase.specs(cases)
