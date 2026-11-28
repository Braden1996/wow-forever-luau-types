--!strict
-- A JSON encoder with sorted object keys, so every generated JSON file is byte-for-byte deterministic.
-- An empty table encodes as `[]` unless the caller marks it as an object with `Json.object`.

local Json = {}

-- Tables marked as objects; weak keys, so marking never keeps a table alive.
local objects: { [any]: boolean } = setmetatable({}, { __mode = "k" }) :: any

-- Marks `t` as a JSON object (so it encodes as `{}` when empty) and returns it.
function Json.object<T>(t: T): T
	objects[t] = true
	return t
end

local ESCAPES: { [string]: string } = {
	['"'] = '\\"',
	["\\"] = "\\\\",
	["\n"] = "\\n",
	["\r"] = "\\r",
	["\t"] = "\\t",
}

local function encodeString(s: string): string
	local escaped = string.gsub(s, '[%c"\\]', function(c: string): string
		return ESCAPES[c] or string.format("\\u%04x", string.byte(c))
	end)
	return '"' .. escaped .. '"'
end

local function encode(value: unknown, indent: string): string
	if type(value) == "string" then
		return encodeString(value)
	elseif type(value) == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			error("JSON cannot encode " .. tostring(value))
		end
		if value == math.floor(value) then
			return string.format("%d", value)
		end
		return tostring(value)
	elseif type(value) == "boolean" then
		return tostring(value)
	elseif value == nil then
		return "null"
	elseif type(value) == "table" then
		local t = value :: { [any]: unknown }
		local inner = indent .. "  "
		if next(t) == nil then
			return if objects[t] then "{}" else "[]"
		end
		if #t > 0 and not objects[t] then
			local parts = {}
			for _, item in ipairs(t) do
				table.insert(parts, inner .. encode(item, inner))
			end
			return "[\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "]"
		end
		local keys = {}
		for k in t do
			table.insert(keys, tostring(k))
		end
		table.sort(keys)
		local parts = {}
		for _, k in keys do
			table.insert(parts, inner .. encodeString(k) .. ": " .. encode(t[k], inner))
		end
		return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
	end
	error("cannot encode a " .. typeof(value))
end

function Json.encode(value: unknown): string
	return encode(value, "")
end

return Json
