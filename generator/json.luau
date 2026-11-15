--!strict
-- A JSON encoder with sorted object keys, so the report is byte-for-byte deterministic.

local Json = {}

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

local function encode(value: any, indent: string): string
	local kind = type(value)
	if kind == "string" then
		return encodeString(value)
	elseif kind == "number" then
		if value == math.floor(value) then
			return string.format("%d", value)
		end
		return tostring(value)
	elseif kind == "boolean" then
		return tostring(value)
	elseif value == nil then
		return "null"
	elseif kind == "table" then
		local inner = indent .. "  "
		if next(value) == nil then
			return "[]"
		end
		if #value > 0 then
			local parts = {}
			for _, item in value do
				table.insert(parts, inner .. encode(item, inner))
			end
			return "[\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "]"
		end
		local keys = {}
		for k in value do
			table.insert(keys, tostring(k))
		end
		table.sort(keys)
		local parts = {}
		for _, k in keys do
			table.insert(parts, inner .. encodeString(k) .. ": " .. encode(value[k], inner))
		end
		return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
	end
	error("cannot encode a " .. kind)
end

function Json.encode(value: any): string
	return encode(value, "")
end

return Json
