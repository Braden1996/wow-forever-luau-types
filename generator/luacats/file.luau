--!strict
-- Reads one LuaCATS annotation file (as shipped in Ketho/vscode-wow-api) into declarations. The format is
-- line-oriented: a block of `---` doc lines (luacats/tags.luau), then the Lua statement it describes
-- (luacats/statements.luau). Malformed input is reported in `errors`, never dropped silently.

local Ast = require("./ast")
local Decls = require("./decls")
local Statements = require("./statements")
local Tags = require("./tags")
local TypeParse = require("./typeparse")

type Type = Ast.Type

local File = {}

function File.read(file: string, source: string): Decls.FileDecls
	local text: string = (string.gsub(source, "\r", ""))
	local lines = string.split(text, "\n")
	local lineStarts: { number } = {}
	local offset = 1
	for i, line in lines do
		lineStarts[i] = offset
		offset += #line + 1
	end
	local out: Decls.FileDecls = {
		file = file,
		classes = {},
		aliases = {},
		funcs = {},
		enums = {},
		globals = {},
		locals = {},
		errors = {},
	}
	local r: Decls.Reader
	r = {
		file = file,
		source = text,
		lines = lines,
		lineStarts = lineStarts,
		out = out,
		pending = Decls.newPending(),
		currentAlias = nil :: Decls.Alias?,
		fail = function(lineNo: number, message: string)
			table.insert(out.errors, file .. ":" .. lineNo .. ": " .. message)
		end,
		typeOrAny = function(typeText: string, lineNo: number): (Type, string)
			local t, rest = TypeParse.parsePrefix(typeText)
			if t == nil then
				r.fail(lineNo, "cannot parse type: " .. typeText)
				return { kind = "name", name = "any", args = {} }, ""
			end
			return t, rest
		end,
	}

	local i = 0
	while i < #lines do
		i += 1
		local line = lines[i]
		local tag, rest = string.match(line, "^%-%-%-@([%w_]+)%s*(.*)$")
		if tag then
			if tag ~= "alias" then
				r.currentAlias = nil
			end
			Tags.read(r, tag, rest :: string, i)
		elseif string.match(line, "^%-%-%-%s*|") then
			-- `---| "VALUE" # comment` continues an alias; LuaCATS marks a default `---|>` and an extra `---|+`.
			local body = string.match(line, "^%-%-%-%s*|%s*[>+]?%s*(.*)$") :: string
			local alias = r.currentAlias
			if alias then
				local t = TypeParse.parsePrefix(body)
				if t then
					table.insert(alias.variants, t)
				else
					r.fail(i, "cannot parse a variant of @alias " .. alias.name .. ": " .. body)
				end
			else
				r.fail(i, "`---|` line outside an @alias")
			end
		elseif string.match(line, "^%-%-") or string.match(line, "^%s*$") then
			-- Doc text, ordinary comments and blank lines end an alias continuation but keep the doc block.
			if not string.match(line, "^%-%-%-") then
				r.currentAlias = nil
			end
		else
			r.currentAlias = nil
			i = Statements.read(r, i)
			r.pending = Decls.newPending()
		end
	end
	return out
end

return File
