--!strict
-- Converts Blizzard_APIDocumentationGenerated (the client's own API documentation) into the generator's
-- declarations: functions, script-object (widget) methods, events with payloads, structures, callback
-- types and enumeration names.

local LuaTable = require("./luatable")
local Parse = require("./parse")
local TypeExpr = require("./typeexpr")

type Type = TypeExpr.Type
type Param = TypeExpr.Param
type Signature = Parse.Signature
type Table = LuaTable.Table

export type DocFunction = { qualified: string, signature: Signature, system: string }
export type DocEvent = { name: string, payload: { Param }, system: string, documentation: string? }
export type DocStruct = { name: string, fields: { Parse.Field }, system: string }
export type DocCallback = { name: string, type: Type, system: string }

export type DocSet = {
	functions: { [string]: DocFunction }, -- "C_QuestLog.GetInfo", "UnitLevel"
	scriptObjects: { [string]: { [string]: DocFunction } }, -- "SimpleFrameAPI" -> method -> function
	scriptObjectKinds: { [string]: string }, -- "LuaCurveObjectAPI" -> "Userdata"
	events: { [string]: DocEvent },
	structures: { [string]: DocStruct },
	callbacks: { [string]: DocCallback },
	enumerations: { [string]: boolean },
	errors: { string },
}

local ApiDocs = {}

local function named(name: string, args: { Type }?): Type
	return { kind = "name", name = name, args = args or {} }
end

-- One documented argument, return, payload or field.
local function fieldType(f: Table, enums: { [string]: boolean }): (Type, boolean, boolean)
	local m = f.map
	local function ref(typeName: string): Type
		if enums[typeName] then
			return named("Enum." .. typeName)
		end
		return named(typeName)
	end
	local typeName = LuaTable.str(m.Type) or "unknown"
	local t: Type
	local mixin = LuaTable.str(m.Mixin)
	if typeName == "table" then
		local inner = LuaTable.str(m.InnerType)
		local key = LuaTable.str(m.KeyType)
		if inner and key then
			t =
				{ kind = "table", fields = { { key = "[" .. key .. "]", type = ref(inner), optional = false } } } :: Type
		elseif inner then
			local element: Type = ref(inner)
			if LuaTable.bool(m.NilableContents) then
				element = { kind = "optional", inner = element } :: Type
			end
			t = { kind = "array", inner = element } :: Type
		else
			t = named("table")
		end
	elseif mixin then
		t = named(mixin)
	else
		t = ref(typeName)
	end
	local nilable = LuaTable.bool(m.Nilable)
	local variadic = m.StrideIndex ~= nil
	return t, nilable, variadic
end

local function params(list: Table?, enums: { [string]: boolean }, isArgument: boolean): { Param }
	local out: { Param } = {}
	if list == nil then
		return out
	end
	for _, v in list.array do
		local f = LuaTable.tbl(v)
		if f then
			local t, nilable, variadic = fieldType(f, enums)
			local name = LuaTable.str(f.map.Name) or ("arg" .. #out + 1)
			if variadic then
				table.insert(out, { name = "...", type = t, optional = false })
				break -- a variadic covers the rest
			end
			local optional = nilable or (isArgument and f.map.Default ~= nil)
			table.insert(out, { name = name, type = t, optional = optional })
		end
	end
	return out
end

local function returns(list: Table?, enums: { [string]: boolean }, mayReturnNothing: boolean): { Type }
	local out: { Type } = {}
	if list == nil then
		return out
	end
	for _, v in list.array do
		local f = LuaTable.tbl(v)
		if f then
			local t, nilable, variadic = fieldType(f, enums)
			if variadic then
				table.insert(out, named("...", { t }))
				break
			end
			local result: Type = t
			if nilable or mayReturnNothing then
				result = { kind = "optional", inner = t } :: Type
			end
			table.insert(out, result)
		end
	end
	return out
end

local function docText(m: { [string]: LuaTable.Value }): string?
	local d = LuaTable.tbl(m.Documentation)
	if d and #d.array > 0 then
		local parts = {}
		for _, line in d.array do
			if type(line) == "string" then
				table.insert(parts, line)
			end
		end
		return table.concat(parts, " ")
	end
	return nil
end

local function signatureOf(fn: Table, enums: { [string]: boolean }): Signature
	local m = fn.map
	return {
		params = params(LuaTable.tbl(m.Arguments), enums, true),
		returns = returns(LuaTable.tbl(m.Returns), enums, LuaTable.bool(m.MayReturnNothing)),
		generics = {},
		deprecated = false,
		doc = docText(m),
	}
end

-- files: documentation file name -> source, already sorted by the caller.
function ApiDocs.parse(files: { { name: string, source: string } }): DocSet
	local set: DocSet = {
		functions = {},
		scriptObjects = {},
		scriptObjectKinds = {},
		events = {},
		structures = {},
		callbacks = {},
		enumerations = {},
		errors = {},
	}

	-- Pass 1: the documents, and every enumeration name (types refer to enums by bare name).
	local docs: { Table } = {}
	for _, file in files do
		local ok, result = pcall(LuaTable.parseFile, file.source)
		if not ok then
			table.insert(set.errors, file.name .. ": " .. tostring(result))
			continue
		end
		for _, doc in result :: { Table } do
			if LuaTable.str(doc.map.Name) then
				table.insert(docs, doc)
				for _, entry in (LuaTable.tbl(doc.map.Tables) or { array = {}, map = {} }).array do
					local t = LuaTable.tbl(entry)
					if t and t.map.Type == "Enumeration" then
						set.enumerations[LuaTable.str(t.map.Name) :: string] = true
					end
				end
			end
		end
	end
	local enums = set.enumerations

	-- Pass 2: everything else.
	for _, doc in docs do
		local m = doc.map
		local system = LuaTable.str(m.Name) :: string
		local kind = LuaTable.str(m.Type)
		local namespace = LuaTable.str(m.Namespace)
		for _, entry in (LuaTable.tbl(m.Functions) or { array = {}, map = {} }).array do
			local fn = LuaTable.tbl(entry)
			local name = fn and LuaTable.str(fn.map.Name)
			if fn and name then
				local df: DocFunction = { qualified = name, signature = signatureOf(fn, enums), system = system }
				if kind == "ScriptObject" then
					set.scriptObjects[system] = set.scriptObjects[system] or {}
					set.scriptObjects[system][name] = df
					set.scriptObjectKinds[system] = LuaTable.str(m.ObjectType) or "Widget"
				else
					df.qualified = if namespace then namespace .. "." .. name else name
					set.functions[df.qualified] = df
				end
			end
		end
		for _, entry in (LuaTable.tbl(m.Events) or { array = {}, map = {} }).array do
			local ev = LuaTable.tbl(entry)
			local literal = ev and LuaTable.str(ev.map.LiteralName)
			if ev and literal then
				set.events[literal] = {
					name = literal,
					payload = params(LuaTable.tbl(ev.map.Payload), enums, false),
					system = system,
					documentation = docText(ev.map),
				}
			end
		end
		for _, entry in (LuaTable.tbl(m.Tables) or { array = {}, map = {} }).array do
			local t = LuaTable.tbl(entry)
			local name = t and LuaTable.str(t.map.Name)
			if t == nil or name == nil then
				continue
			end
			if t.map.Type == "Structure" then
				local fields: { Parse.Field } = {}
				for _, p in params(LuaTable.tbl(t.map.Fields), enums, false) do
					if p.name ~= "..." then
						table.insert(fields, { name = p.name, type = p.type, optional = p.optional })
					end
				end
				set.structures[name] = { name = name, fields = fields, system = system }
			elseif t.map.Type == "CallbackType" then
				local args = params(LuaTable.tbl(t.map.Arguments), enums, false)
				set.callbacks[name] = {
					name = name,
					type = { kind = "fun", params = args, returns = {} },
					system = system,
				}
			end
		end
	end
	return set
end

return ApiDocs
