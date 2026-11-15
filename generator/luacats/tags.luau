--!strict
-- The `---@tag` lines of a LuaCATS doc block, one handler per tag. Each adds to the pending block
-- (parameters, results, overloads, generics) or to the file (classes, aliases).

local Ast = require("./ast")
local Decls = require("./decls")

type Reader = Decls.Reader
type Type = Ast.Type

local Tags = {}

local function trim(s: string): string
	return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

local VISIBILITY: { [string]: boolean } = { public = true, private = true, protected = true, package = true }

-- Tags that carry nothing a Luau declaration can use.
local IGNORED: { [string]: boolean } = {
	meta = true,
	nodiscard = true,
	see = true,
	diagnostic = true,
	type = true,
	name = true,
	paramsig = true,
	protected = true,
	deprecated = true,
	async = true,
	cast = true,
	operator = true,
	module = true,
	vararg = true,
	version = true,
	source = true,
	private = true,
	package = true,
	public = true,
	return_cast = true,
}

local handlers: { [string]: (r: Reader, rest: string, lineNo: number) -> () } = {}

-- `---@param name[?] Type description`
function handlers.param(r: Reader, rest: string, lineNo: number)
	local name, opt, after = string.match(rest, "^([%w_%.]+)(%??)%s+(.*)$")
	if name == nil then
		r.fail(lineNo, "bad @param: " .. rest)
		return
	end
	local t = r.typeOrAny(after :: string, lineNo)
	table.insert(r.pending.params, { name = name, type = t, optional = opt == "?" })
end

-- `---@return Type [name] [description]`; `---@return T ...` is a variadic tail of T, and a bare
-- `---@return ...` a variadic of anything.
handlers["return"] = function(r: Reader, rest: string, lineNo: number)
	if string.match(rest, "^%.%.%.%s") or rest == "..." then
		local variadic: Type = { kind = "variadic", inner = { kind = "name", name = "any", args = {} } }
		table.insert(r.pending.returns, variadic)
		return
	end
	local t, after = r.typeOrAny(rest, lineNo)
	local returnName = string.match(after, "^%s*([%w_%.]+)")
	if returnName == "..." then
		local variadic: Type = { kind = "variadic", inner = t }
		table.insert(r.pending.returns, variadic)
	else
		table.insert(r.pending.returns, t)
	end
end

-- `---@field [visibility] name[?] Type description` or `---@field [KeyType] Type description`.
function handlers.field(r: Reader, rest: string, lineNo: number)
	local visibility, body = string.match(rest, "^(%l+)%s+(.*)$")
	if visibility == nil or not VISIBILITY[visibility] then
		visibility = nil
		body = rest
	end
	local class = r.pending.class
	if class == nil then
		r.fail(lineNo, "@field outside a @class block: " .. rest)
		return
	end
	local bracket, opt, after = string.match(body :: string, "^(%b[])(%??)%s+(.*)$")
	if bracket then
		local keyType = r.typeOrAny(string.sub(bracket, 2, -2), lineNo)
		local t = r.typeOrAny(after :: string, lineNo)
		table.insert(class.fields, { name = bracket, keyType = keyType, type = t, optional = opt == "?" })
		return
	end
	local name, optional, typeText = string.match(body :: string, "^([%a_][%w_]*)(%??)%s+(.*)$")
	if name == nil then
		r.fail(lineNo, "bad @field: " .. rest)
		return
	end
	local t = r.typeOrAny(typeText :: string, lineNo)
	table.insert(class.fields, { name = name, type = t, optional = optional == "?", visibility = visibility })
end

-- `---@class Name [: Parent, Parent]`
function handlers.class(r: Reader, rest: string, lineNo: number)
	local name, parents = string.match(rest, "^([%w_%.%-]+)%s*:%s*([^#]*)")
	if not name then
		name = string.match(rest, "^([%w_%.%-]+)")
		parents = ""
	end
	if name == nil then
		r.fail(lineNo, "bad @class: " .. rest)
		return
	end
	local class: Decls.Class = { name = name, parents = {}, fields = {}, file = r.file }
	for parent in string.gmatch(parents :: string, "[^,%s]+") do
		-- `---@class Foo : Bar, { x: number }` style parents are not supported; skip them.
		if string.match(parent, "^[%w_%.%-]+$") then
			table.insert(class.parents, parent)
		end
	end
	table.insert(r.out.classes, class)
	r.pending.class = class
end

-- `---@alias Name [Type]`, continued by `---| Variant` lines (luacats/file.luau).
function handlers.alias(r: Reader, rest: string, lineNo: number)
	local name, after = string.match(rest, "^([%w_%.%-]+)%s*(.*)$")
	if name == nil then
		r.fail(lineNo, "bad @alias: " .. rest)
		return
	end
	local base: Type? = nil
	local afterText = trim(after :: string)
	if afterText ~= "" and string.sub(afterText, 1, 1) ~= "#" then
		base = (r.typeOrAny(afterText, lineNo))
	end
	local alias: Decls.Alias = { name = name, base = base, variants = {}, file = r.file }
	table.insert(r.out.aliases, alias)
	r.currentAlias = alias
end

-- `---@enum Name`: the next statement assigns the enum's table.
function handlers.enum(r: Reader, rest: string, lineNo: number)
	local name = string.match(rest, "^([%w_%.]+)")
	if name == nil then
		r.fail(lineNo, "bad @enum: " .. rest)
		return
	end
	r.pending.enum = name
end

-- `---@overload fun(...)`
function handlers.overload(r: Reader, rest: string, lineNo: number)
	local t = r.typeOrAny(rest, lineNo)
	table.insert(r.pending.overloads, t)
end

-- `---@generic T, U : Constraint` (constraints are dropped: Luau generics have none).
function handlers.generic(r: Reader, rest: string, _lineNo: number)
	for g in string.gmatch((string.gsub(rest, ":%s*[%w_%.]+", "")), "[%w_]+") do
		table.insert(r.pending.generics, g)
	end
end

-- Reads one `---@tag rest` line. An unknown tag is reported; an ignored one is skipped.
function Tags.read(r: Reader, tag: string, rest: string, lineNo: number)
	local handler = handlers[tag]
	if handler then
		handler(r, trim(rest), lineNo)
	elseif not IGNORED[tag] then
		r.fail(lineNo, "unknown tag @" .. tag)
	end
end

return Tags
