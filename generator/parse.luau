--!strict
-- Reads one LuaCATS annotation file (as shipped in Ketho/vscode-wow-api) into declarations.
-- The format is line-oriented: a block of `---` doc lines, then one Lua statement it describes.

local TypeExpr = require("./typeexpr")

type Type = TypeExpr.Type
type Param = TypeExpr.Param

export type Field = {
	name: string, -- "[string]" for an index signature
	type: Type,
	optional: boolean,
	visibility: string?,
}

export type Signature = {
	params: { Param },
	returns: { Type },
	generics: { string },
	deprecated: boolean,
	doc: string?,
}

export type Func = {
	path: { string }, -- e.g. {"C_Container", "GetBagName"}
	method: boolean, -- defined with ':'
	signature: Signature,
	overloads: { Signature },
	file: string,
}

export type Class = {
	name: string,
	parents: { string },
	fields: { Field },
	doc: string?,
	file: string,
}

export type Alias = {
	name: string,
	base: Type?,
	variants: { Type },
	file: string,
}

export type EnumDecl = {
	path: { string },
	entries: { { key: string, value: string } }, -- value is the Lua literal text
	file: string,
}

export type Global = {
	path: { string },
	class: string?, -- the ---@class annotating the assignment, if any
	value: string, -- the right-hand side text
	file: string,
}

export type FileDecls = {
	file: string,
	classes: { Class },
	aliases: { Alias },
	funcs: { Func },
	enums: { EnumDecl },
	globals: { Global },
	locals: { [string]: string }, -- local variable name -> class name it holds
	errors: { string },
}

local Parse = {}

local function splitPath(text: string): { string }
	local out = {}
	for part in string.gmatch(text, "[^%.:]+") do
		table.insert(out, part)
	end
	return out
end

local function trim(s: string): string
	return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

type Pending = {
	params: { Param },
	returns: { Type },
	generics: { string },
	overloads: { Type },
	deprecated: boolean,
	doc: string?,
	class: Class?,
	enum: string?,
}

local function newPending(): Pending
	return {
		params = {},
		returns = {},
		generics = {},
		overloads = {},
		deprecated = false,
		doc = nil,
		class = nil,
		enum = nil,
	}
end

local function signatureFromFun(t: Type, doc: string?): Signature?
	if t.kind ~= "fun" then
		return nil
	end
	local returns = table.clone(t.returns)
	return { params = t.params, returns = returns, generics = {}, deprecated = false, doc = doc }
end

function Parse.file(file: string, source: string): FileDecls
	local out: FileDecls = {
		file = file,
		classes = {},
		aliases = {},
		funcs = {},
		enums = {},
		globals = {},
		locals = {},
		errors = {},
	}
	local pending = newPending()
	local currentAlias: Alias? = nil
	local lines = string.split((string.gsub(source, "\r", "")), "\n")
	local i = 0

	local function fail(lineNo: number, message: string)
		table.insert(out.errors, file .. ":" .. lineNo .. ": " .. message)
	end

	local function typeOrAny(text: string, lineNo: number): (Type, string)
		local t, rest = TypeExpr.parsePrefix(text)
		if t == nil then
			fail(lineNo, "cannot parse type: " .. text)
			return { kind = "name", name = "any", args = {} }, ""
		end
		return t, rest
	end

	while i < #lines do
		i += 1
		local line = lines[i]
		local tag, rawRest = string.match(line, "^%-%-%-@(%w+)%s*(.*)$")
		if tag then
			local rest: string = trim(rawRest :: string)
			if tag ~= "alias" then
				currentAlias = nil
			end
			if tag == "param" then
				local name, opt, after = string.match(rest, "^([%w_%.]+)(%??)%s+(.*)$")
				if name then
					local t = typeOrAny(after :: string, i)
					table.insert(pending.params, { name = name, type = t, optional = opt == "?" })
				else
					fail(i, "bad @param: " .. rest)
				end
			elseif tag == "return" then
				local t, after = typeOrAny(rest, i)
				local returnName = string.match(after, "^%s*([%w_%.]+)")
				if returnName == "..." then
					-- `---@return string ...` is a variadic tail of strings.
					table.insert(pending.returns, { kind = "name", name = "...", args = { t } })
				else
					table.insert(pending.returns, t)
				end
			elseif tag == "field" then
				local visibility, body = string.match(rest, "^(%l+)%s+(.*)$")
				if
					visibility ~= "public"
					and visibility ~= "private"
					and visibility ~= "protected"
					and visibility ~= "package"
				then
					visibility = nil
					body = rest
				end
				local name, opt, after = string.match(body :: string, "^(%b[])(%??)%s+(.*)$")
				if not name then
					name, opt, after = string.match(body :: string, "^([%w_]+)(%??)%s+(.*)$")
				end
				if name and pending.class then
					local t = typeOrAny(after :: string, i)
					table.insert(
						(pending.class :: Class).fields,
						{ name = name, type = t, optional = opt == "?", visibility = visibility }
					)
				elseif name == nil then
					fail(i, "bad @field: " .. rest)
				end
			elseif tag == "class" then
				local name, parents = string.match(rest, "^([%w_%.%-]+)%s*:%s*([^#]*)")
				if not name then
					name = string.match(rest, "^([%w_%.%-]+)")
					parents = ""
				end
				if name then
					local class: Class = { name = name, parents = {}, fields = {}, doc = pending.doc, file = file }
					for parent in string.gmatch(parents :: string, "[^,%s]+") do
						-- `---@class Foo : Bar, { x: number }` style parents are not supported; skip them.
						if string.match(parent, "^[%w_%.%-]+$") then
							table.insert(class.parents, parent)
						end
					end
					table.insert(out.classes, class)
					pending.class = class
				else
					fail(i, "bad @class: " .. rest)
				end
			elseif tag == "alias" then
				local name, after = string.match(rest, "^([%w_%.%-]+)%s*(.*)$")
				if name then
					local base: Type? = nil
					local afterText = trim(after :: string)
					if afterText ~= "" and string.sub(afterText, 1, 1) ~= "#" then
						base = (typeOrAny(afterText, i))
					end
					local alias: Alias = { name = name, base = base, variants = {}, file = file }
					table.insert(out.aliases, alias)
					currentAlias = alias
				else
					fail(i, "bad @alias: " .. rest)
				end
			elseif tag == "enum" then
				pending.enum = string.match(rest, "^([%w_%.]+)")
			elseif tag == "overload" then
				local t = typeOrAny(rest, i)
				table.insert(pending.overloads, t)
			elseif tag == "generic" then
				for g in string.gmatch((string.gsub(rest, ":%s*[%w_%.]+", "")), "[%w_]+") do
					table.insert(pending.generics, g)
				end
			elseif tag == "deprecated" then
				pending.deprecated = true
			end
			-- meta, nodiscard, see, diagnostic, type, name, paramsig, protected: not needed for types.
		elseif string.match(line, "^%-%-%-%s*|") then
			-- `---| "VALUE" # comment` continues an alias.
			local body = string.match(line, "^%-%-%-%s*|%s*(.*)$") :: string
			if currentAlias then
				local t = TypeExpr.parsePrefix(body)
				if t then
					table.insert(currentAlias.variants, t)
				end
			end
		elseif string.match(line, "^%-%-%-") then
			local text = string.match(line, "^%-%-%-%s?(.*)$") :: string
			local url = string.match(text, "%[[^%]]*%]%((https?://[^%)]+)%)")
			if url and pending.doc == nil then
				pending.doc = url
			end
		elseif string.match(line, "^%s*$") or string.match(line, "^%-%-") then
			-- Blank lines and ordinary comments end an alias continuation but keep the doc block.
			currentAlias = nil
			if string.match(line, "^%s*$") and pending.class == nil and #pending.params == 0 then
				pending.doc = nil
			end
		else
			currentAlias = nil
			-- A Lua statement: the declaration the pending block describes.
			local fname, args = string.match(line, "^function%s+([%w_%.:]+)%s*%(([^%)]*)%)")
			if not fname then
				fname, args = string.match(line, "^local%s+function%s+([%w_]+)%s*%(([^%)]*)%)")
				if fname then
					fname = nil -- local helper functions are not API.
				end
			end
			if fname then
				local path = splitPath(fname)
				local method = string.find(fname, ":", 1, true) ~= nil
				-- Parameters named in the Lua signature but not annotated are `any`.
				local annotated: { [string]: Param } = {}
				for _, p in pending.params do
					annotated[p.name] = p
				end
				local params: { Param } = {}
				for argName in string.gmatch(args :: string, "[^,%s]+") do
					local p = annotated[argName]
					if p then
						table.insert(params, p)
					else
						table.insert(
							params,
							{ name = argName, type = { kind = "name", name = "any", args = {} }, optional = true }
						)
					end
				end
				local signature: Signature = {
					params = params,
					returns = pending.returns,
					generics = pending.generics,
					deprecated = pending.deprecated,
					doc = pending.doc,
				}
				local overloads = {}
				for _, o in pending.overloads do
					local sig = signatureFromFun(o, pending.doc)
					if sig and method and sig.params[1] and sig.params[1].name == "self" then
						-- `---@overload fun(self, ...)` on a method: `self` is implicit.
						sig.params = table.move(sig.params, 2, #sig.params, 1, {})
					end
					if sig then
						sig.generics = pending.generics
						table.insert(overloads, sig)
					end
				end
				table.insert(out.funcs, {
					path = path,
					method = method,
					signature = signature,
					overloads = overloads,
					file = file,
				})
			else
				local localStmt = string.match(line, "^local%s+(.*)$")
				local lhs, rhs = string.match(localStmt or line, "^([%w_%.]+)%s*=%s*(.-)%s*$")
				if lhs then
					if localStmt then
						if pending.class then
							out.locals[lhs] = (pending.class :: Class).name
						end
					elseif pending.enum and string.sub(rhs :: string, 1, 1) == "{" then
						local entries = {}
						while i < #lines do
							i += 1
							local entryLine = lines[i]
							if string.match(entryLine, "^%s*}") then
								break
							end
							local key, value = string.match(entryLine, '^%s*%[?"?([%w_]+)"?%]?%s*=%s*([^,]+),?')
							if key then
								table.insert(entries, { key = key, value = trim(value :: string) })
							end
						end
						table.insert(out.enums, { path = splitPath(lhs), entries = entries, file = file })
					else
						table.insert(out.globals, {
							path = splitPath(lhs),
							class = if pending.class then (pending.class :: Class).name else nil,
							value = rhs :: string,
							file = file,
						})
					end
				end
			end
			pending = newPending()
		end
	end
	return out
end

return Parse
