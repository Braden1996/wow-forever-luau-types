--!strict
-- Converts Blizzard_APIDocumentationGenerated (the client's own API documentation) into the generator's
-- declarations: functions, script-object (widget) methods, events with payloads, structures, callback
-- types and enumeration names. Problems (a file that does not parse, a nameless table, a duplicate) are
-- reported in `errors`; the first of two duplicates is kept.

local Decls = require("./luacats/decls")
local LuaTable = require("./luatable")
local TypeExpr = require("./typeexpr")

type Type = TypeExpr.Type
type Param = TypeExpr.Param
type Signature = Decls.Signature
type Table = LuaTable.Table

export type DocFunction = { qualified: string, signature: Signature }
export type DocEvent = { name: string, payload: { Param } }
export type DocStruct = { name: string, fields: { Decls.Field } }
export type DocCallback = { name: string, type: Type }

export type DocSet = {
	functions: { [string]: DocFunction }, -- "C_QuestLog.GetInfo", "UnitLevel"
	scriptObjects: { [string]: { [string]: DocFunction } }, -- "SimpleFrameAPI" -> method -> function
	events: { [string]: DocEvent },
	structures: { [string]: DocStruct },
	callbacks: { [string]: DocCallback },
	enumerations: { [string]: boolean },
	errors: { string },
}

local ApiDocs = {}

local EMPTY: Table = { kind = "table", array = {}, map = {} }

local function named(name: string): Type
	return { kind = "name", name = name, args = {} }
end

-- A documented type name: enumerations are referred to by bare name but live under `Enum.`.
local function ref(typeName: string, enums: { [string]: boolean }): Type
	if enums[typeName] then
		return named("Enum." .. typeName)
	end
	return named(typeName)
end

-- One documented argument, return, payload or field: its type, and whether it is nilable or variadic.
local function fieldType(f: Table, enums: { [string]: boolean }): (Type, boolean, boolean)
	local m = f.map
	local typeName = LuaTable.str(m.Type) or "unknown"
	local mixin = LuaTable.str(m.Mixin)
	local t: Type
	if typeName == "table" then
		local inner = LuaTable.str(m.InnerType)
		local key = LuaTable.str(m.KeyType)
		if inner and key then
			t = { kind = "map", key = ref(key, enums), value = ref(inner, enums) } :: Type
		elseif inner then
			local element: Type = ref(inner, enums)
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
		t = ref(typeName, enums)
	end
	return t, LuaTable.bool(m.Nilable), m.StrideIndex ~= nil
end

local function params(list: Table?, enums: { [string]: boolean }, isArgument: boolean): { Param }
	local out: { Param } = {}
	for _, v in (list or EMPTY).array do
		local f = LuaTable.tbl(v)
		if f then
			local t, nilable, variadic = fieldType(f, enums)
			if variadic then
				table.insert(out, { name = "...", type = t, optional = false })
				break -- a variadic covers the rest
			end
			local name = LuaTable.str(f.map.Name) or ("arg" .. #out + 1)
			local optional = nilable or (isArgument and f.map.Default ~= nil)
			table.insert(out, { name = name, type = t, optional = optional })
		end
	end
	return out
end

local function returns(list: Table?, enums: { [string]: boolean }, mayReturnNothing: boolean): { Type }
	local out: { Type } = {}
	for _, v in (list or EMPTY).array do
		local f = LuaTable.tbl(v)
		if f then
			local t, nilable, variadic = fieldType(f, enums)
			if variadic then
				table.insert(out, { kind = "variadic", inner = t } :: Type)
				break
			end
			if nilable or mayReturnNothing then
				table.insert(out, { kind = "optional", inner = t } :: Type)
			else
				table.insert(out, t)
			end
		end
	end
	return out
end

local function signatureOf(fn: Table, enums: { [string]: boolean }): Signature
	local m = fn.map
	return {
		params = params(LuaTable.tbl(m.Arguments), enums, true),
		returns = returns(LuaTable.tbl(m.Returns), enums, LuaTable.bool(m.MayReturnNothing)),
		generics = {},
	}
end

-- files: documentation file name -> source, already sorted by the caller.
function ApiDocs.parse(files: { { name: string, source: string } }): DocSet
	local set: DocSet = {
		functions = {},
		scriptObjects = {},
		events = {},
		structures = {},
		callbacks = {},
		enumerations = {},
		errors = {},
	}
	local function report(where: string, message: string)
		table.insert(set.errors, where .. ": " .. message)
	end

	-- Pass 1: the documents, and every enumeration name (types refer to enums by bare name).
	type Doc = { file: string, table: Table }
	local docs: { Doc } = {}
	for _, file in files do
		local ok, result = pcall(LuaTable.parseFile, file.source)
		if not ok then
			report(file.name, tostring(result))
			continue
		end
		for _, doc in result :: { Table } do
			if LuaTable.str(doc.map.Name) == nil then
				-- A system with functions or events needs a Name. Shared and constants files hold only Tables and have
				-- none; they are skipped as before (their enums come from the client's LuaEnum dump). Taking their
				-- structures in is a separate change: BaseDocumentation's `ScriptObject` would clash with the widget.
				if doc.map.Functions ~= nil or doc.map.Events ~= nil then
					report(file.name, "a documentation system has no Name")
				end
				continue
			end
			table.insert(docs, { file = file.name, table = doc })
			for _, entry in (LuaTable.tbl(doc.map.Tables) or EMPTY).array do
				local t = LuaTable.tbl(entry)
				if t and t.map.Type == "Enumeration" then
					local name = LuaTable.str(t.map.Name)
					if name then
						set.enumerations[name] = true
					else
						report(file.name, "an Enumeration has no Name")
					end
				end
			end
		end
	end
	local enums = set.enumerations

	-- Pass 2: everything else. A name seen twice is reported and the first definition kept.
	for _, doc in docs do
		local m = doc.table.map
		local system = LuaTable.str(m.Name) :: string
		local isScriptObject = LuaTable.str(m.Type) == "ScriptObject"
		local namespace = LuaTable.str(m.Namespace)
		for _, entry in (LuaTable.tbl(m.Functions) or EMPTY).array do
			local fn = LuaTable.tbl(entry)
			local name = fn and LuaTable.str(fn.map.Name)
			if fn == nil or name == nil then
				report(doc.file, system .. ": a function has no Name")
				continue
			end
			if isScriptObject then
				local methods = set.scriptObjects[system] or {}
				set.scriptObjects[system] = methods
				if methods[name] then
					report(doc.file, "duplicate method " .. system .. ":" .. name)
				else
					methods[name] = { qualified = name, signature = signatureOf(fn, enums) }
				end
			else
				local qualified = if namespace then namespace .. "." .. name else name
				if set.functions[qualified] then
					report(doc.file, "duplicate function " .. qualified)
				else
					set.functions[qualified] = { qualified = qualified, signature = signatureOf(fn, enums) }
				end
			end
		end
		for _, entry in (LuaTable.tbl(m.Events) or EMPTY).array do
			local ev = LuaTable.tbl(entry)
			local literal = ev and LuaTable.str(ev.map.LiteralName)
			if ev == nil or literal == nil then
				report(doc.file, system .. ": an event has no LiteralName")
			elseif set.events[literal] then
				report(doc.file, "duplicate event " .. literal)
			else
				set.events[literal] = { name = literal, payload = params(LuaTable.tbl(ev.map.Payload), enums, false) }
			end
		end
		for _, entry in (LuaTable.tbl(m.Tables) or EMPTY).array do
			local t = LuaTable.tbl(entry)
			local name = t and LuaTable.str(t.map.Name)
			if t == nil or name == nil then
				continue -- reported in pass 1 for enumerations; other nameless tables carry nothing
			end
			if t.map.Type == "Structure" then
				if set.structures[name] then
					report(doc.file, "duplicate structure " .. name)
					continue
				end
				local fields: { Decls.Field } = {}
				for _, p in params(LuaTable.tbl(t.map.Fields), enums, false) do
					if p.name ~= "..." then
						table.insert(fields, { name = p.name, type = p.type, optional = p.optional })
					end
				end
				set.structures[name] = { name = name, fields = fields }
			elseif t.map.Type == "CallbackType" then
				if set.callbacks[name] then
					report(doc.file, "duplicate callback type " .. name)
					continue
				end
				local args = params(LuaTable.tbl(t.map.Arguments), enums, false)
				set.callbacks[name] = { name = name, type = { kind = "fun", params = args, returns = {} } :: Type }
			end
		end
	end
	return set
end

return ApiDocs
