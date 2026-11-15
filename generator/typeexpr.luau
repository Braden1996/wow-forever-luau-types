--!strict
-- Parses LuaCATS type expressions (the text after `---@param name`, `---@return`, `---@field name`,
-- `---@alias Name`) into a small AST, and prints that AST as a Luau type.

export type Param = {
	name: string,
	type: Type,
	optional: boolean,
}

export type Type =
	{ kind: "name", name: string, args: { Type } }
	| { kind: "string", value: string }
	| { kind: "number" }
	| { kind: "bool", value: boolean }
	| { kind: "backtick", name: string }
	| { kind: "union", types: { Type } }
	| { kind: "optional", inner: Type }
	| { kind: "array", inner: Type }
	| { kind: "fun", params: { Param }, returns: { Type }, vararg: Type? }
	| { kind: "table", fields: { { key: string, type: Type, optional: boolean } } }
	| { kind: "tuple", types: { Type } }

local TypeExpr = {}

type State = { src: string, pos: number }

local function skipSpace(s: State)
	local _, e = string.find(s.src, "^%s*", s.pos)
	s.pos = (e :: number) + 1
end

local function peek(s: State, pattern: string): string?
	return string.match(s.src, "^" .. pattern, s.pos)
end

local function take(s: State, literal: string): boolean
	if string.sub(s.src, s.pos, s.pos + #literal - 1) == literal then
		s.pos += #literal
		return true
	end
	return false
end

local parseUnion: (s: State, stopAtComma: boolean) -> Type?

-- A function type: `fun(a: T, b?: U, ...: V): R1, R2`.
local function parseFun(s: State): Type?
	if not take(s, "(") then
		return { kind = "name", name = "function", args = {} }
	end
	local params: { Param } = {}
	local index = 0
	skipSpace(s)
	while not take(s, ")") do
		index += 1
		skipSpace(s)
		local name = peek(s, "%.%.%.") or peek(s, "[%w_]+")
		local paramType: Type? = nil
		local optional = false
		if name then
			local save = s.pos
			s.pos += #name
			skipSpace(s)
			if take(s, "?") then
				optional = true
				skipSpace(s)
			end
			if take(s, ":") then
				skipSpace(s)
				paramType = parseUnion(s, true)
			elseif peek(s, "[,%)]") then
				-- LuaLS reads `fun(a, b)` as named parameters of unknown type.
				paramType = { kind = "name", name = "any", args = {} }
			else
				s.pos = save
				optional = false
				paramType = parseUnion(s, true)
				name = "arg" .. index
			end
		else
			paramType = parseUnion(s, true)
			name = "arg" .. index
		end
		if paramType == nil then
			return nil
		end
		table.insert(params, { name = name :: string, type = paramType, optional = optional })
		skipSpace(s)
		if not take(s, ",") then
			skipSpace(s)
			if not take(s, ")") then
				return nil
			end
			break
		end
		skipSpace(s)
	end
	local returns: { Type } = {}
	local save = s.pos
	skipSpace(s)
	if take(s, ":") then
		skipSpace(s)
		local parenthesised = take(s, "(")
		while true do
			skipSpace(s)
			-- Named returns: `fun(): (ok: boolean, msg: string)` or `fun(): ok: boolean`.
			local named = peek(s, "[%w_]+%s*:[^:]")
			if named then
				s.pos += #(string.match(named, "^[%w_]+%s*:") :: string)
				skipSpace(s)
			end
			local r = parseUnion(s, true)
			if r == nil then
				return nil
			end
			table.insert(returns, r)
			local before = s.pos
			skipSpace(s)
			-- A comma continues the return list only if another type follows it.
			if take(s, ",") then
				skipSpace(s)
				if not (peek(s, "[%a_\"'`{(]") or peek(s, "%.%.%.")) then
					s.pos = before
					break
				end
			else
				s.pos = before
				break
			end
		end
		if parenthesised then
			skipSpace(s)
			take(s, ")")
		end
	else
		s.pos = save
	end
	return { kind = "fun", params = params, returns = returns }
end

local function parseTableLiteral(s: State): Type?
	local fields = {}
	skipSpace(s)
	while not take(s, "}") do
		skipSpace(s)
		local key: string? = nil
		local bracket = peek(s, "%[[^%]]+%]")
		if bracket then
			key = bracket
			s.pos += #bracket
		else
			key = peek(s, "[%w_]+")
			if key == nil then
				return nil
			end
			s.pos += #key
		end
		skipSpace(s)
		local optional = take(s, "?")
		skipSpace(s)
		if not take(s, ":") then
			return nil
		end
		skipSpace(s)
		local t = parseUnion(s, true)
		if t == nil then
			return nil
		end
		table.insert(fields, { key = key :: string, type = t, optional = optional })
		skipSpace(s)
		if not take(s, ",") then
			skipSpace(s)
			if not take(s, "}") then
				return nil
			end
			break
		end
		skipSpace(s)
	end
	return { kind = "table", fields = fields }
end

local function parsePrimary(s: State): Type?
	skipSpace(s)
	local str = peek(s, '"[^"]*"') or peek(s, "'[^']*'")
	if str then
		s.pos += #str
		return { kind = "string", value = string.sub(str, 2, -2) }
	end
	local tick = peek(s, "`[^`]*`")
	if tick then
		s.pos += #tick
		return { kind = "backtick", name = string.sub(tick, 2, -2) }
	end
	local num = peek(s, "%-?0x%x+") or peek(s, "%-?%d+%.?%d*")
	if num then
		s.pos += #num
		return { kind = "number" }
	end
	if take(s, "(") then
		local inner = parseUnion(s, false)
		skipSpace(s)
		if inner == nil or not take(s, ")") then
			return nil
		end
		return inner
	end
	if take(s, "{") then
		return parseTableLiteral(s)
	end
	if peek(s, "%.%.%.") then
		s.pos += 3
		return { kind = "name", name = "any", args = {} }
	end
	local name = peek(s, "[%a_][%w_%.%-]*")
	if name == nil then
		return nil
	end
	-- A trailing '.' or '-' belongs to prose, not to the type name.
	name = string.match(name, "^(.-)[%.%-]*$") :: string
	s.pos += #name
	if name == "async" and peek(s, "%s+fun") then
		-- `async fun(...)`: Luau has no async marker; it is an ordinary function type.
		skipSpace(s)
		return parsePrimary(s)
	end
	if name == "fun" then
		return parseFun(s)
	end
	if name == "true" or name == "false" then
		return { kind = "bool", value = name == "true" }
	end
	local args: { Type } = {}
	if take(s, "<") then
		repeat
			skipSpace(s)
			local a = parseUnion(s, true)
			if a == nil then
				return nil
			end
			table.insert(args, a)
			skipSpace(s)
		until not take(s, ",")
		if not take(s, ">") then
			return nil
		end
	end
	return { kind = "name", name = name :: string, args = args }
end

local function parsePostfix(s: State): Type?
	local t = parsePrimary(s)
	if t == nil then
		return nil
	end
	while true do
		if take(s, "[]") then
			t = { kind = "array", inner = t :: Type }
		elseif take(s, "?") then
			t = { kind = "optional", inner = t :: Type }
		else
			return t
		end
	end
end

function parseUnion(s: State, _stopAtComma: boolean): Type?
	local first = parsePostfix(s)
	if first == nil then
		return nil
	end
	local types = { first }
	while true do
		local save = s.pos
		skipSpace(s)
		if take(s, "|") then
			skipSpace(s)
			local nextType = parsePostfix(s)
			if nextType == nil then
				s.pos = save
				break
			end
			table.insert(types, nextType)
		else
			s.pos = save
			break
		end
	end
	if #types == 1 then
		return first
	end
	return { kind = "union", types = types }
end

-- Parses a type at the start of `text`; returns the type and the unparsed rest (usually a description).
function TypeExpr.parsePrefix(text: string): (Type?, string)
	local s: State = { src = text, pos = 1 }
	skipSpace(s)
	local t = parseUnion(s, false)
	if t == nil then
		return nil, text
	end
	return t, string.sub(text, s.pos)
end

function TypeExpr.parse(text: string): Type?
	local t, rest = TypeExpr.parsePrefix(text)
	if t == nil or string.match(rest, "^%s*$") == nil then
		return nil
	end
	return t
end

-- Printing ---------------------------------------------------------------------------------------

export type Resolver = (name: string, args: { Type }) -> string

local RESERVED = {
	["and"] = true,
	["break"] = true,
	["do"] = true,
	["else"] = true,
	["elseif"] = true,
	["end"] = true,
	["false"] = true,
	["for"] = true,
	["function"] = true,
	["if"] = true,
	["in"] = true,
	["local"] = true,
	["nil"] = true,
	["not"] = true,
	["or"] = true,
	["repeat"] = true,
	["return"] = true,
	["then"] = true,
	["true"] = true,
	["until"] = true,
	["while"] = true,
}
TypeExpr.RESERVED = RESERVED

function TypeExpr.paramName(name: string): string
	if name == "..." then
		return name
	end
	name = string.gsub(name, "[^%w_]", "_")
	if RESERVED[name] or string.match(name, "^%d") then
		return name .. "_"
	end
	return name
end

local function quote(value: string): string
	return '"' .. string.gsub(value, '[\\"]', "\\%0") .. '"'
end

local print_: (t: Type, resolve: Resolver) -> string

local function isFunctionType(text: string): boolean
	-- A printed function type starts with '(' or '<' and contains a top-level '->'.
	return string.find(text, "->", 1, true) ~= nil and (string.sub(text, 1, 1) == "(" or string.sub(text, 1, 1) == "<")
end

local function wrap(text: string): string
	if isFunctionType(text) or string.find(text, " | ", 1, true) or string.find(text, " & ", 1, true) then
		return "(" .. text .. ")"
	end
	return text
end
TypeExpr.wrap = wrap

-- Splits a printed type on its top-level ` | ` separators (not those inside parentheses or braces).
function TypeExpr.splitUnion(text: string): { string }
	local out = {}
	local depth = 0
	local start = 1
	local i = 1
	while i <= #text do
		local c = string.sub(text, i, i)
		if c == "(" or c == "{" or c == "<" then
			depth += 1
		elseif c == ")" or c == "}" or (c == ">" and string.sub(text, i - 1, i - 1) ~= "-") then
			depth -= 1
		elseif c == '"' then
			local close = string.find(text, '[^\\]"', i)
			i = if close then close + 1 else #text
		elseif depth == 0 and string.sub(text, i, i + 2) == " | " then
			table.insert(out, string.sub(text, start, i - 1))
			start = i + 3
			i += 2
		end
		i += 1
	end
	table.insert(out, string.sub(text, start))
	return out
end

local function unionOf(parts: { string }): string
	local seen: { [string]: boolean } = {}
	local out: { string } = {}
	local optional = false
	local hasAny = false
	for _, p in parts do
		if p == "nil" then
			optional = true
		elseif p == "any" then
			hasAny = true
		elseif not seen[p] then
			seen[p] = true
			table.insert(out, p)
		end
	end
	if hasAny then
		return "any"
	end
	-- Literal string members are absorbed by a plain `string`, `true`/`false` by `boolean`.
	if seen["string"] then
		local kept = {}
		for _, p in out do
			if string.sub(p, 1, 1) ~= '"' then
				table.insert(kept, p)
			end
		end
		out = kept
	end
	if seen["boolean"] then
		local kept = {}
		for _, p in out do
			if p ~= "true" and p ~= "false" then
				table.insert(kept, p)
			end
		end
		out = kept
	end
	if #out == 0 then
		return "nil"
	end
	local text
	if #out == 1 then
		text = out[1]
	else
		local wrapped = {}
		for _, p in out do
			table.insert(wrapped, if isFunctionType(p) then "(" .. p .. ")" else p)
		end
		text = table.concat(wrapped, " | ")
	end
	if optional then
		if string.sub(text, -1) == "?" then
			return text
		end
		return wrap(text) .. "?"
	end
	return text
end
TypeExpr.unionOf = unionOf

local function flattenUnion(t: Type, resolve: Resolver, out: { string })
	if t.kind == "union" then
		for _, member in t.types do
			flattenUnion(member, resolve, out)
		end
	elseif t.kind == "optional" then
		flattenUnion(t.inner, resolve, out)
		table.insert(out, "nil")
	else
		table.insert(out, print_(t, resolve))
	end
end

function TypeExpr.printReturns(returns: { Type }, resolve: Resolver): string
	if #returns == 0 then
		return "()"
	end
	local parts = {}
	for _, r in returns do
		local text = print_(r, resolve)
		table.insert(parts, text)
		if string.match(text, "^%.%.%.") then
			break -- a variadic return must be last; it covers everything after it
		end
	end
	if #parts == 1 and not string.match(parts[1], "^%.%.%.") then
		return wrap(parts[1])
	end
	return "(" .. table.concat(parts, ", ") .. ")"
end

-- `declaration` selects `declare function` parameter syntax (`...: T`) over function-type syntax (`...T`).
function TypeExpr.printParam(p: Param, resolve: Resolver, labelled: boolean, declaration: boolean?): string
	local t = print_(p.type, resolve)
	if p.name == "..." then
		if string.sub(t, -1) == "?" then
			t = string.sub(t, 1, -2) -- a vararg element is already optional
			if string.sub(t, 1, 1) == "(" and string.sub(t, -1) == ")" and not isFunctionType(string.sub(t, 2, -2)) then
				t = string.sub(t, 2, -2)
			end
		end
		if declaration then
			return "...: " .. t
		end
		return "..." .. wrap(t)
	end
	if p.optional and t ~= "any" and string.sub(t, -1) ~= "?" then
		t = wrap(t) .. "?"
	end
	if labelled then
		return TypeExpr.paramName(p.name) .. ": " .. t
	end
	return t
end

function print_(t: Type, resolve: Resolver): string
	if t.kind == "name" then
		return resolve(t.name, t.args)
	elseif t.kind == "string" then
		return quote(t.value)
	elseif t.kind == "number" then
		return "number"
	elseif t.kind == "bool" then
		return if t.value then "true" else "false"
	elseif t.kind == "backtick" then
		return "string"
	elseif t.kind == "union" or t.kind == "optional" then
		local parts = {}
		flattenUnion(t, resolve, parts)
		return unionOf(parts)
	elseif t.kind == "array" then
		local inner = print_(t.inner, resolve)
		return "{ " .. inner .. " }"
	elseif t.kind == "fun" then
		local params = {}
		for _, p in t.params do
			table.insert(params, TypeExpr.printParam(p, resolve, true))
		end
		return "(" .. table.concat(params, ", ") .. ") -> " .. TypeExpr.printReturns(t.returns, resolve)
	elseif t.kind == "table" then
		if #t.fields == 0 then
			return "{ [any]: any }"
		end
		local fields = {}
		local hasIndexer = false
		for _, f in t.fields do
			if string.sub(f.key, 1, 1) == "[" then
				-- Luau allows one indexer per table type; keep the first.
				if hasIndexer then
					continue
				end
				hasIndexer = true
			end
			local ft = print_(f.type, resolve)
			if f.optional and string.sub(ft, -1) ~= "?" and ft ~= "any" then
				ft = wrap(ft) .. "?"
			end
			local key = f.key
			if string.sub(key, 1, 1) == "[" then
				local inner = string.sub(key, 2, -2)
				local keyType = TypeExpr.parse(inner)
				key = "[" .. (if keyType then print_(keyType, resolve) else "any") .. "]"
			elseif RESERVED[key] then
				key = "[" .. quote(key) .. "]"
			end
			table.insert(fields, key .. ": " .. ft)
		end
		return "{ " .. table.concat(fields, ", ") .. " }"
	elseif t.kind == "tuple" then
		local parts = {}
		for _, member in t.types do
			table.insert(parts, print_(member, resolve))
		end
		return "(" .. table.concat(parts, ", ") .. ")"
	end
	error("unreachable")
end

TypeExpr.print = print_

return TypeExpr
