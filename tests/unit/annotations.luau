--!strict
-- LuaCATS annotation files read into declarations (generator/luacats/file.luau and its tags and statements).

local Case = require("./case")
local File = require("../../generator/luacats/file")
local TypeExpr = require("../../generator/typeexpr")

local function resolve(name: string, _args: { TypeExpr.Type }): string
	return name
end

local function failing(name: string, source: string, expected: { string }): Case.Case
	return {
		name = name,
		run = function()
			return File.read("t.lua", source).errors, expected
		end,
	}
end

local cases: { Case.Case } = {
	{
		name = "a function's signature",
		run = function()
			local decls = File.read(
				"t.lua",
				"---@param a string\n---@param b number?\n---@return boolean ok\n---@return ... extra\n"
					.. "function X.f(a, b, c) end\n"
			)
			local f = decls.funcs[1]
			local params = {}
			for _, p in f.signature.params do
				table.insert(params, TypeExpr.printParam(p, resolve, true))
			end
			local actual = {
				path = f.path,
				params = params,
				returns = TypeExpr.printReturns(f.signature.returns, resolve),
				returnNames = f.signature.returnNames,
				errors = decls.errors,
			}
			return actual,
				{
					path = { "X", "f" },
					params = { "a: string", "b: number?", "c: any" },
					returns = "(boolean, ...any)",
					returnNames = { "ok", "" },
					errors = {},
				}
		end,
	},
	{
		name = "alias variants, including the default and extra markers",
		run = function()
			local decls =
				File.read("t.lua", '---@alias mode\n---|>"a" # the default\n---| "b"\n---|+"c"\n\nlocal x = 1\n')
			local alias = decls.aliases[1]
			local variants = {}
			for _, v in alias.variants do
				table.insert(variants, TypeExpr.print(v, resolve))
			end
			return { name = alias.name, variants = variants, errors = decls.errors }, {
				name = "mode",
				variants = { '"a"', '"b"', '"c"' },
				errors = {},
			}
		end,
	},
	{
		name = "a one-line enum",
		run = function()
			local decls = File.read("t.lua", '---@enum Color\nColor = { Red = 1, Name = "x", Other = Enum.Y }\n')
			local enum = decls.enums[1]
			return { path = enum.path, entries = enum.entries, errors = decls.errors }, {
				path = { "Color" },
				entries = {
					{ key = "Name", value = '"x"' },
					{ key = "Other", value = "Enum.Y" },
					{ key = "Red", value = "1" },
				},
				errors = {},
			}
		end,
	},
	{
		name = "a multi-line enum ends at its closing brace",
		run = function()
			local decls = File.read("t.lua", "---@enum E\nE = {\n\tA = 1,\n\tB = 2,\n}\nfunction g() end\n")
			return { #decls.enums[1].entries, #decls.funcs, decls.errors }, { 2, 1, {} }
		end,
	},
	failing("an enum without its }", "---@enum E\nE = {\n\tA = 1,\n", { "t.lua:2: @enum E: missing }" }),
	failing(
		"an @field outside a class",
		"---@field x number\nlocal y = 1\n",
		{ "t.lua:1: @field outside a @class block: x number" }
	),
	failing(
		"an @param that is not a parameter",
		"---@param nope string\nfunction f(a) end\n",
		{ "t.lua:2: @param nope is not a parameter of f" }
	),
	failing("a ---| line outside an alias", '---| "x"\n', { "t.lua:1: `---|` line outside an @alias" }),
	failing(
		"an unparsable alias variant",
		"---@alias m\n---| (\n",
		{ "t.lua:2: cannot parse a variant of @alias m: (" }
	),
	failing("an unknown tag", "---@frobnicate x\nlocal y = 1\n", { "t.lua:1: unknown tag @frobnicate" }),
}

return cases
