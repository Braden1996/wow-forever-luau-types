--!strict
-- Parses LuaCATS type expressions (the text after `---@param name`, `---@return`, `---@field name`,
-- `---@alias Name`) into the AST in luacats/ast.luau.

local Ast = require("./ast")

type Type = Ast.Type
type Param = Ast.Param
type TableKey = Ast.TableKey

local TypeParse = {}

type State = { src: string, pos: number }

local ANY: Type = { kind = "name", name = "any", args = {} }

local function skipSpace(s: State)
	local _, e = string.find(s.src, "^%s*", s.pos)
	s.pos = (e :: number) + 1
end

local function peek(s: State, pattern: string): string?
	return (string.match(s.src, "^" .. pattern, s.pos))
end

local function take(s: State, literal: string): boolean
	if string.sub(s.src, s.pos, s.pos + #literal - 1) == literal then
		s.pos += #literal
		return true
	end
	return false
end

local ESCAPES: { [string]: string } = { n = "\n", t = "\t", r = "\r", ["\\"] = "\\", ['"'] = '"', ["'"] = "'" }

-- A quoted string at the cursor, scanned character by character; returns its unescaped value.
local function readString(s: State): string?
	local quote = string.sub(s.src, s.pos, s.pos)
	if quote ~= '"' and quote ~= "'" then
		return nil
	end
	local i = s.pos + 1
	local parts = {}
	while i <= #s.src do
		local c = string.sub(s.src, i, i)
		if c == quote then
			s.pos = i + 1
			return table.concat(parts)
		elseif c == "\\" then
			local e = string.sub(s.src, i + 1, i + 1)
			table.insert(parts, ESCAPES[e] or e)
			i += 2
		else
			table.insert(parts, c)
			i += 1
		end
	end
	return nil -- unterminated
end

-- A number literal: hex, or a decimal mantissa with an optional exponent (`1-2` is not one token).
local function readNumber(s: State): string?
	local hex = peek(s, "%-?0[xX]%x+")
	if hex then
		s.pos += #hex
		return hex
	end
	local mantissa = peek(s, "%-?%d+%.?%d*")
	if mantissa == nil then
		return nil
	end
	s.pos += #mantissa
	local exponent = peek(s, "[eE][%-+]?%d+")
	if exponent then
		s.pos += #exponent
		return mantissa .. exponent
	end
	return mantissa
end

-- `stopAtComma`: the type sits in a comma-separated list (function parameters, table fields, `<...>`
-- arguments), so an unparenthesised `fun(): A, B` return list ends at its first top-level comma.
local parseUnion: (s: State, stopAtComma: boolean) -> Type?

-- A function type: `fun(a: T, b?: U, ...: V): R1, R2`.
local function parseFun(s: State, stopAtComma: boolean): Type?
	if not take(s, "(") then
		return { kind = "name", name = "function", args = {} }
	end
	local params: { Param } = {}
	local index = 0
	skipSpace(s)
	while not take(s, ")") do
		index += 1
		skipSpace(s)
		local name = peek(s, "%.%.%.") or peek(s, "[%a_][%w_]*")
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
				paramType = ANY -- LuaLS reads `fun(a, b)` as named parameters of unknown type
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
	if not take(s, ":") then
		s.pos = save
		return { kind = "fun", params = params, returns = returns }
	end
	skipSpace(s)
	local parenthesised = take(s, "(")
	while true do
		skipSpace(s)
		-- Named returns: `fun(): (ok: boolean, msg: string)` or `fun(): ok: boolean`.
		local named = peek(s, "[%a_][%w_]*%s*:[^:]")
		if named then
			s.pos += #(string.match(named, "^[%a_][%w_]*%s*:") :: string)
			skipSpace(s)
		end
		local r: Type?
		if take(s, "...") then
			-- `fun(): ...T` (the last return): a variadic; a bare `...` is a variadic of anything.
			local mark = s.pos
			local inner = parseUnion(s, true)
			if inner == nil then
				s.pos = mark
			end
			r = { kind = "variadic", inner = inner or ANY } :: Type
		else
			r = parseUnion(s, true)
		end
		if r == nil then
			return nil
		end
		table.insert(returns, r)
		local before = s.pos
		skipSpace(s)
		-- A comma continues the return list only inside parentheses, or at the top level of an
		-- expression that is not itself in a comma-separated list, and only if a type follows.
		local continues = (parenthesised or not stopAtComma) and take(s, ",")
		if continues then
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
		if not take(s, ")") then
			return nil -- `fun(): (A, B` without its closing parenthesis
		end
	end
	return { kind = "fun", params = params, returns = returns }
end

-- A table key: `name`, `["name"]`, `[1]` or `[KeyType]`. Identifiers cannot start with a digit.
local function parseTableKey(s: State): TableKey?
	if take(s, "[") then
		skipSpace(s)
		local key: TableKey? = nil
		local str = readString(s)
		if str then
			key = { kind = "prop", name = str }
		else
			local num = peek(s, "%d+%s*%]")
			if num then
				local digits = string.match(num, "^%d+") :: string
				s.pos += #digits
				key = { kind = "position", index = tonumber(digits) :: number }
			else
				local keyType = parseUnion(s, false)
				if keyType == nil then
					return nil
				end
				key = { kind = "index", type = keyType }
			end
		end
		skipSpace(s)
		if not take(s, "]") then
			return nil
		end
		return key
	end
	if peek(s, "%d") then
		return nil -- `{ 1abc: T }`: not an identifier
	end
	local name = peek(s, "[%a_][%w_]*")
	if name == nil then
		return nil
	end
	s.pos += #name
	return { kind = "prop", name = name }
end

local function parseTableLiteral(s: State): Type?
	local fields = {}
	skipSpace(s)
	while not take(s, "}") do
		skipSpace(s)
		local key = parseTableKey(s)
		if key == nil then
			return nil
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
		table.insert(fields, { key = key, type = t, optional = optional })
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

local function parsePrimary(s: State, stopAtComma: boolean): Type?
	skipSpace(s)
	local str = readString(s)
	if str then
		return { kind = "string", value = str }
	end
	local tick = peek(s, "`[^`]*`")
	if tick then
		s.pos += #tick
		return { kind = "backtick", name = string.sub(tick, 2, -2) }
	end
	if readNumber(s) then
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
	if take(s, "...") then
		return ANY -- `...` as a type: anything
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
		return parsePrimary(s, stopAtComma)
	end
	if name == "fun" then
		return parseFun(s, stopAtComma)
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
	if name == "table" and #args == 2 then
		return { kind = "map", key = args[1], value = args[2] }
	end
	return { kind = "name", name = name :: string, args = args }
end

local function parsePostfix(s: State, stopAtComma: boolean): Type?
	local t = parsePrimary(s, stopAtComma)
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

function parseUnion(s: State, stopAtComma: boolean): Type?
	local first = parsePostfix(s, stopAtComma)
	if first == nil then
		return nil
	end
	local types = { first }
	while true do
		local save = s.pos
		skipSpace(s)
		if take(s, "|") then
			skipSpace(s)
			local nextType = parsePostfix(s, stopAtComma)
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
function TypeParse.parsePrefix(text: string): (Type?, string)
	local s: State = { src = text, pos = 1 }
	skipSpace(s)
	local t = parseUnion(s, false)
	if t == nil then
		return nil, text
	end
	return t, string.sub(text, s.pos)
end

-- Parses a whole type expression; nil if it is not one (or has text after it).
function TypeParse.parse(text: string): Type?
	local t, rest = TypeParse.parsePrefix(text)
	if t == nil or string.match(rest, "^%s*$") == nil then
		return nil
	end
	return t
end

return TypeParse
