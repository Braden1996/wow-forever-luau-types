--!strict
-- Parses Lua table literals as data (never executes them): Blizzard_APIDocumentationGenerated tables and the
-- `---@enum` tables of the annotations. Values are strings, numbers, booleans, nested tables, and references:
-- a dotted name such as `Enum.SecretAspect.ObjectSecurity`, `nil`, or an arithmetic expression
-- (`Constants.X.A + 1`), each kept as { kind = "ref", ref = <its text> }.

export type Ref = { kind: "ref", ref: string }
export type Table = { kind: "table", array: { Value }, map: { [string]: Value } }
export type Value = string | number | boolean | Ref | Table

local LuaTable = {}

type State = { src: string, pos: number }

local function fail(s: State, message: string): never
	local line = select(2, string.gsub(string.sub(s.src, 1, s.pos), "\n", "")) + 1
	error(string.format("line %d: %s", line, message), 0)
end

-- Skips whitespace and comments, line (`--`) and long (`--[[ ]]`, `--[==[ ]==]`).
local function skip(s: State)
	while true do
		local _, e = string.find(s.src, "^%s+", s.pos)
		if e then
			s.pos = e + 1
		end
		if string.sub(s.src, s.pos, s.pos + 1) ~= "--" then
			return
		end
		local level = string.match(s.src, "^%-%-%[(=*)%[", s.pos)
		if level then
			local close = string.find(s.src, "]" .. level .. "]", s.pos, true)
			if close == nil then
				fail(s, "unterminated long comment")
			end
			s.pos = (close :: number) + #level + 2
		else
			local nl = string.find(s.src, "\n", s.pos, true)
			s.pos = if nl then nl + 1 else #s.src + 1
		end
	end
end

local ESCAPES: { [string]: string } = { n = "\n", t = "\t", r = "\r", ['"'] = '"', ["'"] = "'", ["\\"] = "\\" }

local function parseString(s: State): string
	local quote = string.sub(s.src, s.pos, s.pos)
	s.pos += 1
	local parts = {}
	while true do
		local c = string.sub(s.src, s.pos, s.pos)
		if c == "" then
			fail(s, "unterminated string")
		elseif c == quote then
			s.pos += 1
			return table.concat(parts)
		elseif c == "\\" then
			local e = string.sub(s.src, s.pos + 1, s.pos + 1)
			table.insert(parts, ESCAPES[e] or e)
			s.pos += 2
		else
			table.insert(parts, c)
			s.pos += 1
		end
	end
end

-- A number: hex, or a decimal mantissa with an optional exponent (`1-2` is three tokens, not one).
local function readNumber(s: State): number?
	local hex = string.match(s.src, "^%-?0[xX]%x+", s.pos)
	if hex then
		s.pos += #hex
		return tonumber(hex)
	end
	local mantissa = string.match(s.src, "^%-?%d+%.?%d*", s.pos) or string.match(s.src, "^%-?%.%d+", s.pos)
	if mantissa == nil then
		return nil
	end
	local text = mantissa
	local exponent = string.match(s.src, "^[eE][%-+]?%d+", s.pos + #mantissa)
	if exponent then
		text ..= exponent
	end
	s.pos += #text
	return tonumber(text) or fail(s, "bad number " .. text)
end

local parseValue: (s: State) -> Value

local function keyOf(s: State, k: Value): string
	if type(k) == "string" or type(k) == "number" or type(k) == "boolean" then
		return tostring(k)
	elseif type(k) == "table" and k.kind == "ref" then
		return k.ref
	end
	return fail(s, "a table cannot be a table key")
end

local function parseTable(s: State): Table
	s.pos += 1 -- {
	local t: Table = { kind = "table", array = {}, map = {} }
	while true do
		skip(s)
		local c = string.sub(s.src, s.pos, s.pos)
		if c == "}" then
			s.pos += 1
			return t
		elseif c == "" then
			fail(s, "expected }")
		end
		local key = string.match(s.src, "^([%a_][%w_]*)%s*=[^=]", s.pos)
		if key then
			s.pos = (string.find(s.src, "=", s.pos, true) :: number) + 1
			t.map[key] = parseValue(s)
		elseif c == "[" then
			s.pos += 1
			local k = parseValue(s)
			skip(s)
			if string.sub(s.src, s.pos, s.pos) ~= "]" then
				fail(s, "expected ]")
			end
			s.pos += 1
			skip(s)
			if string.sub(s.src, s.pos, s.pos) ~= "=" then
				fail(s, "expected =")
			end
			s.pos += 1
			t.map[keyOf(s, k)] = parseValue(s)
		else
			table.insert(t.array, parseValue(s))
		end
		skip(s)
		local sep = string.sub(s.src, s.pos, s.pos)
		if sep == "," or sep == ";" then
			s.pos += 1
		elseif sep ~= "}" then
			fail(s, "expected , or }")
		end
	end
end

local function parsePrimary(s: State): Value
	skip(s)
	local c = string.sub(s.src, s.pos, s.pos)
	if c == "{" then
		return parseTable(s)
	elseif c == '"' or c == "'" then
		return parseString(s)
	end
	local num = readNumber(s)
	if num then
		return num
	end
	local word = string.match(s.src, "^[%a_][%w_%.]*", s.pos)
	if word then
		s.pos += #word
		if word == "true" then
			return true
		elseif word == "false" then
			return false
		end
		return { kind = "ref", ref = word } -- a dotted name, or `nil`
	end
	return fail(s, "unexpected " .. string.sub(s.src, s.pos, s.pos + 10))
end

-- A value, or an arithmetic expression of values, which is kept as an opaque reference to its text.
function parseValue(s: State): Value
	skip(s)
	local start = s.pos
	local first = parsePrimary(s)
	local isExpression = false
	while true do
		local save = s.pos
		skip(s)
		if string.match(s.src, "^[%+%-%*/]", s.pos) then
			s.pos += 1
			parsePrimary(s)
			isExpression = true
		else
			s.pos = save
			break
		end
	end
	if isExpression then
		return { kind = "ref", ref = string.sub(s.src, start, s.pos - 1) }
	end
	return first
end

-- Every `local Name = { ... }` table in a documentation file.
function LuaTable.parseFile(source: string): { Table }
	local out = {}
	local s: State = { src = source, pos = 1 }
	while true do
		local start = (if s.pos == 1 then string.find(s.src, "^local [%w_]+%s*=%s*{") else nil)
			or string.find(s.src, "\nlocal [%w_]+%s*=%s*{", s.pos)
		if start == nil then
			return out
		end
		s.pos = string.find(s.src, "{", start, true) :: number
		table.insert(out, parseTable(s))
	end
end

-- One table literal: `text` must start with `{` and hold nothing but the table (and comments after it).
function LuaTable.parseTableText(text: string): Table
	local s: State = { src = text, pos = 1 }
	skip(s)
	if string.sub(s.src, s.pos, s.pos) ~= "{" then
		fail(s, "expected {")
	end
	local t = parseTable(s)
	skip(s)
	if s.pos <= #s.src then
		fail(s, "unexpected text after the table")
	end
	return t
end

function LuaTable.str(v: Value?): string?
	return if type(v) == "string" then v else nil
end

function LuaTable.bool(v: Value?): boolean
	return v == true
end

function LuaTable.tbl(v: Value?): Table?
	if type(v) == "table" and v.kind == "table" then
		return v
	end
	return nil
end

return LuaTable
