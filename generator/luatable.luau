--!strict
-- Parses the Lua table literals in Blizzard_APIDocumentationGenerated as data (never executes them).
-- Values: strings, numbers, booleans, nil, nested tables and dotted references such as
-- `Enum.SecretAspect.ObjectSecurity`, which are kept as { ref = "Enum.SecretAspect.ObjectSecurity" }.

export type Value = string | number | boolean | Ref | Table
export type Ref = { ref: string }
export type Table = { array: { Value }, map: { [string]: Value } }

local LuaTable = {}

type State = { src: string, pos: number }

local function fail(s: State, message: string): never
	local line = select(2, string.gsub(string.sub(s.src, 1, s.pos), "\n", "")) + 1
	error(string.format("line %d: %s", line, message), 0)
end

local function skip(s: State)
	while true do
		local _, e = string.find(s.src, "^%s+", s.pos)
		if e then
			s.pos = e + 1
		end
		if string.sub(s.src, s.pos, s.pos + 1) == "--" then
			local nl = string.find(s.src, "\n", s.pos, true)
			s.pos = if nl then nl + 1 else #s.src + 1
		else
			return
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

local parseValue: (s: State) -> Value

local function parseTable(s: State): Table
	s.pos += 1 -- {
	local t: Table = { array = {}, map = {} }
	while true do
		skip(s)
		local c = string.sub(s.src, s.pos, s.pos)
		if c == "}" then
			s.pos += 1
			return t
		end
		local key = string.match(s.src, "^([%a_][%w_]*)%s*=[^=]", s.pos)
		if key then
			s.pos = (string.find(s.src, "=", s.pos, true) :: number) + 1
			skip(s)
			t.map[key] = parseValue(s)
		elseif c == "[" then
			s.pos += 1
			skip(s)
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
			skip(s)
			t.map[tostring(k)] = parseValue(s)
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
	local num = string.match(s.src, "^%-?0[xX]%x+", s.pos) or string.match(s.src, "^%-?%d+%.?%d*[eE]?[%-+]?%d*", s.pos)
	if num then
		s.pos += #num
		return tonumber(num) or fail(s, "bad number " .. num)
	end
	local word = string.match(s.src, "^[%a_][%w_%.]*", s.pos)
	if word then
		s.pos += #word
		if word == "true" then
			return true
		elseif word == "false" then
			return false
		elseif word == "nil" then
			return { ref = "nil" }
		end
		local r: Ref = { ref = word :: string }
		return r
	end
	return fail(s, "unexpected " .. string.sub(s.src, s.pos, s.pos + 10))
end

-- A value, or an arithmetic expression of values (`Constants.X.A + Constants.X.B + 1`), which is kept
-- as the opaque reference { ref = "<expression>" }: only its presence matters to the generator.
function parseValue(s: State): Value
	local first = parsePrimary(s)
	local start = s.pos
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
		return { ref = "expression:" .. string.sub(s.src, start, s.pos - 1) }
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

function LuaTable.str(v: Value?): string?
	return if type(v) == "string" then v else nil
end

function LuaTable.bool(v: Value?): boolean
	return v == true
end

function LuaTable.tbl(v: Value?): Table?
	if type(v) == "table" and (v :: any).array ~= nil then
		return v :: Table
	end
	return nil
end

return LuaTable
