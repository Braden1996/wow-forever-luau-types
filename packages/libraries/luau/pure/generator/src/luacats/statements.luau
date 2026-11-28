--!strict
-- The Lua statement after a doc block: a function definition, a `local` holding a class, an `---@enum`
-- table, or a global assignment. Each turns the pending block into a declaration.

local LuaTable = require("../luatable")
local Ast = require("./ast")
local Decls = require("./decls")
local Printer = require("./print")

type Reader = Decls.Reader
type Type = Ast.Type
type Param = Ast.Param
type Signature = Decls.Signature

local Statements = {}

local ANY: Type = { kind = "name", name = "any", args = {} }

local function splitPath(text: string): { string }
	local out = {}
	for part in string.gmatch(text, "[^%.:]+") do
		table.insert(out, part)
	end
	return out
end

-- `function Path.name(args)` / `function Path:name(args)`: the pending block's signature.
local function readFunction(r: Reader, fname: string, args: string, lineNo: number)
	local pending = r.pending
	local path = splitPath(fname)
	local method = string.find(fname, ":", 1, true) ~= nil
	local argNames: { string } = {}
	for argName in string.gmatch(args, "[^,%s]+") do
		table.insert(argNames, argName)
	end
	local annotated: { [string]: Param } = {}
	for _, p in pending.params do
		annotated[p.name] = p
		if not table.find(argNames, p.name) then
			r.fail(lineNo, "@param " .. p.name .. " is not a parameter of " .. fname)
		end
	end
	-- Parameters named in the Lua signature but not annotated are `any`, and marked implicit.
	local params: { Param } = {}
	for _, argName in argNames do
		table.insert(params, annotated[argName] or { name = argName, type = ANY, optional = true, implicit = true })
	end
	local untagged = #pending.params == 0 and #pending.returns == 0 and #pending.overloads == 0
	local signature: Signature = {
		params = params,
		returns = pending.returns,
		returnNames = pending.returnNames,
		generics = pending.generics,
		untagged = if untagged then true else nil,
	}
	local overloads: { Signature } = {}
	for _, o in pending.overloads do
		if o.kind == "fun" then
			local oparams = o.params
			if method and oparams[1] and oparams[1].name == "self" then
				-- `---@overload fun(self, ...)` on a method: `self` is implicit.
				oparams = table.move(oparams, 2, #oparams, 1, {})
			end
			table.insert(overloads, { params = oparams, returns = o.returns, generics = pending.generics })
		else
			r.fail(lineNo, "@overload is not a function type")
		end
	end
	table.insert(
		r.out.funcs,
		{ path = path, method = method, signature = signature, overloads = overloads, file = r.file }
	)
end

-- The Lua text of an enum entry's value.
local function literal(v: LuaTable.Value): string
	if type(v) == "string" then
		return Printer.quote(v)
	elseif type(v) == "number" or type(v) == "boolean" then
		return tostring(v)
	elseif v.kind == "ref" then
		return v.ref
	end
	return "{...}"
end

-- `Name = { Key = value, ... }` after `---@enum`: the balanced table text from the source, which may span
-- lines or sit on one. Returns the index of the statement's last line.
local function readEnum(r: Reader, lhs: string, lineNo: number): number
	local start = r.lineStarts[lineNo] + (string.find(r.lines[lineNo], "{", 1, true) :: number) - 1
	local text = string.match(r.source, "^%b{}", start)
	if text == nil then
		r.fail(lineNo, "@enum " .. lhs .. ": missing }")
		return lineNo
	end
	local lastLine = lineNo + select(2, string.gsub(text, "\n", ""))
	local ok, parsed = pcall(LuaTable.parseTableText, text)
	if not ok then
		r.fail(lineNo, "@enum " .. lhs .. ": " .. tostring(parsed))
		return lastLine
	end
	local map = (parsed :: LuaTable.Table).map
	local keys = {}
	for key in map do
		table.insert(keys, key)
	end
	table.sort(keys)
	local entries = {}
	for _, key in keys do
		table.insert(entries, { key = key, value = literal(map[key]) })
	end
	table.insert(r.out.enums, { path = splitPath(lhs), entries = entries, file = r.file })
	return lastLine
end

-- Reads the statement on line `lineNo`; returns the index of its last line (an enum table may span many).
function Statements.read(r: Reader, lineNo: number): number
	local line = r.lines[lineNo]
	local pending = r.pending
	local fname, args = string.match(line, "^function%s+([%w_%.:]+)%s*%(([^%)]*)%)")
	if fname then
		readFunction(r, fname, args :: string, lineNo)
		return lineNo
	end
	if string.match(line, "^local%s+function%s") then
		return lineNo -- a local helper function is not API
	end
	local localStmt = string.match(line, "^local%s+(.*)$")
	local lhs, rhs = string.match(localStmt or line, "^([%w_%.]+)%s*=%s*(.-)%s*$")
	if lhs == nil then
		return lineNo
	end
	if localStmt then
		if pending.class then
			r.out.locals[lhs] = pending.class.name
		end
	elseif pending.enum and string.sub(rhs :: string, 1, 1) == "{" then
		return readEnum(r, lhs, lineNo)
	else
		table.insert(r.out.globals, {
			path = splitPath(lhs),
			class = if pending.class then pending.class.name else nil,
			value = rhs :: string,
			file = r.file,
		})
	end
	return lineNo
end

return Statements
