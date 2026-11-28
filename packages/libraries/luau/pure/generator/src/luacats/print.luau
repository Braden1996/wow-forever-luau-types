--!strict
-- Prints the AST of a LuaCATS type expression as a Luau type, with helpers for parameters, results and
-- unions.

local Ast = require("./ast")

type Type = Ast.Type
type Param = Ast.Param

local Printer = {}

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
Printer.RESERVED = RESERVED

function Printer.paramName(name: string): string
	if name == "..." then
		return name
	end
	name = string.gsub(name, "[^%w_]", "_")
	if RESERVED[name] or string.match(name, "^%d") then
		return name .. "_"
	end
	return name
end

-- A Luau string literal for an unescaped value.
function Printer.quote(value: string): string
	local escaped = string.gsub(value, '[\\"\n\r\t]', function(c: string): string
		if c == "\n" then
			return "\\n"
		elseif c == "\r" then
			return "\\r"
		elseif c == "\t" then
			return "\\t"
		end
		return "\\" .. c
	end)
	return '"' .. escaped .. '"'
end
local quote = Printer.quote

-- Walks a printed type at bracket depth 0, skipping string literals (with their escapes). Calls
-- `visit(i)` for every top-level character position; stops early when it returns true.
local function scanTopLevel(text: string, visit: (i: number) -> boolean): boolean
	local depth = 0
	local i = 1
	while i <= #text do
		local c = string.sub(text, i, i)
		if c == '"' then
			i += 1
			while i <= #text and string.sub(text, i, i) ~= '"' do
				i += if string.sub(text, i, i) == "\\" then 2 else 1
			end
		elseif c == "(" or c == "{" or c == "<" then
			depth += 1
		elseif c == ")" or c == "}" or (c == ">" and string.sub(text, i - 1, i - 1) ~= "-") then
			depth -= 1
		elseif depth == 0 and visit(i) then
			return true
		end
		i += 1
	end
	return false
end

-- A printed function type: it has an arrow outside every bracket (`(a) -> b`, `<T>(a: T) -> T`),
-- not merely one nested inside (`{ f: (a) -> b }`).
local function isFunctionType(text: string): boolean
	return scanTopLevel(text, function(i: number): boolean
		return string.sub(text, i, i + 1) == "->"
	end)
end

local function wrap(text: string): string
	if isFunctionType(text) or #Printer.splitUnion(text) > 1 or string.find(text, " & ", 1, true) then
		return "(" .. text .. ")"
	end
	return text
end
Printer.wrap = wrap

-- Splits a printed type on its top-level ` | ` separators (not inside brackets or string literals).
function Printer.splitUnion(text: string): { string }
	local out = {}
	local start = 1
	local skipTo = 0
	scanTopLevel(text, function(i: number): boolean
		if i > skipTo and string.sub(text, i, i + 2) == " | " then
			table.insert(out, string.sub(text, start, i - 1))
			start = i + 3
			skipTo = i + 2
		end
		return false
	end)
	table.insert(out, string.sub(text, start))
	return out
end

local function unionOf(parts: { string }): string
	local seen: { [string]: boolean } = {}
	local out: { string } = {}
	local optional = false
	local hasAny = false
	local hasUnknown = false
	for _, p in parts do
		if p == "nil" then
			optional = true
		elseif p == "any" then
			hasAny = true
		elseif p == "unknown" then
			hasUnknown = true
		elseif not seen[p] then
			seen[p] = true
			table.insert(out, p)
		end
	end
	if hasAny then
		return "any"
	end
	if hasUnknown then
		return "unknown" -- unknown already includes nil and every other member
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
Printer.unionOf = unionOf

local print_: (t: Type, resolve: Resolver) -> string

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

-- A function's results: `()`, `T`, or `(A, B, ...C)`. A variadic result ends the list.
function Printer.printReturns(returns: { Type }, resolve: Resolver): string
	if #returns == 0 then
		return "()"
	end
	local parts = {}
	local variadic = false
	for _, r in returns do
		table.insert(parts, print_(r, resolve))
		if r.kind == "variadic" then
			variadic = true
			break -- a variadic result covers everything after it
		end
	end
	if #parts == 1 and not variadic then
		return wrap(parts[1])
	end
	return "(" .. table.concat(parts, ", ") .. ")"
end

-- `declaration` selects `declare function` parameter syntax (`...: T`) over function-type syntax (`...T`).
function Printer.printParam(p: Param, resolve: Resolver, labelled: boolean, declaration: boolean?): string
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
	if p.optional and t ~= "any" and t ~= "unknown" and string.sub(t, -1) ~= "?" then
		t = wrap(t) .. "?"
	end
	if labelled then
		return Printer.paramName(p.name) .. ": " .. t
	end
	return t
end

-- A table type literal. Named keys are properties; the first key-type key is the one indexer Luau
-- allows; array positions (`[1]`) become a `[number]` indexer over the union of their types.
local function printTable(t: Type, resolve: Resolver): string
	assert(t.kind == "table", "printTable needs a table type")
	if #t.fields == 0 then
		return "{ [any]: any }"
	end
	local fields = {}
	local indexer: string? = nil
	local positional: { string } = {}
	for _, f in t.fields do
		local ft = print_(f.type, resolve)
		if f.optional and string.sub(ft, -1) ~= "?" and ft ~= "any" and ft ~= "unknown" then
			ft = wrap(ft) .. "?"
		end
		local key = f.key
		if key.kind == "prop" then
			local name = key.name
			local valid = string.match(name, "^[%a_][%w_]*$") ~= nil and not RESERVED[name]
			table.insert(fields, (if valid then name else "[" .. quote(name) .. "]") .. ": " .. ft)
		elseif key.kind == "index" then
			if indexer == nil then
				indexer = "[" .. print_(key.type, resolve) .. "]: " .. ft
			end
		else
			table.insert(positional, ft)
		end
	end
	if #positional > 0 then
		if #fields == 0 and indexer == nil then
			return "{ " .. unionOf(positional) .. " }"
		elseif indexer == nil then
			indexer = "[number]: " .. unionOf(positional)
		end
	end
	if indexer then
		table.insert(fields, indexer)
	end
	return "{ " .. table.concat(fields, ", ") .. " }"
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
		return "{ " .. print_(t.inner, resolve) .. " }"
	elseif t.kind == "map" then
		return "{ [" .. print_(t.key, resolve) .. "]: " .. print_(t.value, resolve) .. " }"
	elseif t.kind == "variadic" then
		return "..." .. wrap(print_(t.inner, resolve))
	elseif t.kind == "fun" then
		local params = {}
		for _, p in t.params do
			table.insert(params, Printer.printParam(p, resolve, true))
		end
		return "(" .. table.concat(params, ", ") .. ") -> " .. Printer.printReturns(t.returns, resolve)
	elseif t.kind == "table" then
		return printTable(t, resolve)
	end
	error("unreachable")
end

Printer.print = print_

return Printer
