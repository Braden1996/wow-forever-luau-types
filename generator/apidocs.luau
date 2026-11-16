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

-- A documented result as written: its name, and whether the docs mark it nilable (MayReturnNothing aside).
export type DocReturn = { name: string, nilable: boolean }

-- `signature`: the call as documented, each result nilable only where the docs say so; whether the whole call
-- may return nothing (`MayReturnNothing`, a ReturnNothing precondition) is ApiDocs.absentReasons.
-- `predicates`: the documented preconditions the function declares (`IsProtectedFunction`,
-- `RequiresValidActionSlot`); DocSet.predicates says what each does when it fails.
export type DocFunction = {
	qualified: string,
	signature: Signature,
	returns: { DocReturn },
	mayReturnNothing: boolean,
	predicates: { string },
}
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
	predicates: { [string]: string }, -- precondition name -> FailureMode ("ReturnNothing", "Error", ...)
	errors: { string },
}

local ApiDocs = {}

-- The precondition of a protected function: it fails by doing nothing, but wrapping libraries treat it as its own
-- shape (never wrapped), so it is not a reason the call returns nothing.
ApiDocs.PROTECTED = "IsProtectedFunction"

-- Why a documented call may return nothing at all: `MayReturnNothing`, then each precondition whose FailureMode is
-- ReturnNothing, in the order the function lists them. nil when the call always returns its results.
function ApiDocs.absentReasons(doc: DocFunction, failureModes: { [string]: string }): { string }?
	local reasons: { string } = {}
	if doc.mayReturnNothing then
		table.insert(reasons, "MayReturnNothing")
	end
	for _, p in doc.predicates do
		if failureModes[p] == "ReturnNothing" and p ~= ApiDocs.PROTECTED then
			table.insert(reasons, p)
		end
	end
	return if #reasons > 0 then reasons else nil
end

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

local function returns(list: Table?, enums: { [string]: boolean }): { Type }
	local out: { Type } = {}
	for _, v in (list or EMPTY).array do
		local f = LuaTable.tbl(v)
		if f then
			local t, nilable, variadic = fieldType(f, enums)
			if variadic then
				table.insert(out, { kind = "variadic", inner = t } :: Type)
				break
			end
			if nilable then
				table.insert(out, { kind = "optional", inner = t } :: Type)
			else
				table.insert(out, t)
			end
		end
	end
	return out
end

local function returnInfo(list: Table?): { DocReturn }
	local out: { DocReturn } = {}
	for i, v in (list or EMPTY).array do
		local f = LuaTable.tbl(v)
		if f then
			local name = LuaTable.str(f.map.Name) or ("result" .. i)
			table.insert(out, { name = name, nilable = LuaTable.bool(f.map.Nilable) })
		end
	end
	return out
end

-- The predicates a function sets (`IsProtectedFunction = true`), sorted.
local function predicatesOf(fn: Table, known: { [string]: string }): { string }
	local out: { string } = {}
	for key, value in fn.map do
		if known[key] and value == true then
			table.insert(out, key)
		end
	end
	table.sort(out)
	return out
end

local function docFunction(qualified: string, fn: Table, set: DocSet): DocFunction
	local m = fn.map
	local mayReturnNothing = LuaTable.bool(m.MayReturnNothing)
	local info = returnInfo(LuaTable.tbl(m.Returns))
	local returnNames: { string } = {}
	for _, r in info do
		table.insert(returnNames, r.name)
	end
	return {
		qualified = qualified,
		signature = {
			params = params(LuaTable.tbl(m.Arguments), set.enumerations, true),
			returns = returns(LuaTable.tbl(m.Returns), set.enumerations),
			returnNames = returnNames,
			generics = {},
		},
		returns = info,
		mayReturnNothing = mayReturnNothing,
		predicates = predicatesOf(fn, set.predicates),
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
		predicates = {},
		errors = {},
	}
	local function report(where: string, message: string)
		table.insert(set.errors, where .. ": " .. message)
	end

	-- Pass 1: the documents, every enumeration name (types refer to enums by bare name) and every predicate.
	type Doc = { file: string, table: Table }
	local docs: { Doc } = {}
	local nameless: { Doc } = {}
	for _, file in files do
		local ok, result = pcall(LuaTable.parseFile, file.source)
		if not ok then
			report(file.name, tostring(result))
			continue
		end
		for _, doc in result :: { Table } do
			-- Predicates are often declared in a nameless shared file (UISharedDocumentation's IsProtectedFunction).
			for _, entry in (LuaTable.tbl(doc.map.Predicates) or EMPTY).array do
				local p = LuaTable.tbl(entry)
				local name = p and LuaTable.str(p.map.Name)
				if p and name then
					set.predicates[name] = LuaTable.str(p.map.FailureMode) or "unknown"
				else
					report(file.name, "a predicate has no Name")
				end
			end
			if LuaTable.str(doc.map.Name) == nil then
				-- A system with functions or events needs a Name. Shared and constants files hold only Tables and have
				-- none; they are skipped as before (their enums come from the client's LuaEnum dump). Taking their
				-- structures in is a separate change: BaseDocumentation's `ScriptObject` would clash with the widget.
				if doc.map.Functions ~= nil or doc.map.Events ~= nil then
					report(file.name, "a documentation system has no Name")
				end
				table.insert(nameless, { file = file.name, table = doc })
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

	-- Shared and constants files have no Name of their own, but their structures and callback types are
	-- documented like any other (DiscordConstantsDocumentation's DiscordInfo, the chat events' payload).
	-- ScriptObject is skipped: it is the widget of that name.
	for _, doc in nameless do
		for _, entry in (LuaTable.tbl(doc.table.map.Tables) or EMPTY).array do
			local t = LuaTable.tbl(entry)
			local name = t and LuaTable.str(t.map.Name)
			if t == nil or name == nil or name == "ScriptObject" then
				continue
			end
			if t.map.Type == "Structure" and set.structures[name] == nil then
				local fields: { Decls.Field } = {}
				for _, p in params(LuaTable.tbl(t.map.Fields), set.enumerations, false) do
					if p.name ~= "..." then
						table.insert(fields, { name = p.name, type = p.type, optional = p.optional })
					end
				end
				set.structures[name] = { name = name, fields = fields }
			elseif t.map.Type == "CallbackType" and set.callbacks[name] == nil then
				local args = params(LuaTable.tbl(t.map.Arguments), set.enumerations, false)
				set.callbacks[name] = { name = name, type = { kind = "fun", params = args, returns = {} } :: Type }
			end
		end
	end
	-- Pass 2 (functions read set.predicates, complete after pass 1): everything else. A name seen twice is reported and the first definition kept.
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
					methods[name] = docFunction(name, fn :: Table, set)
				end
			else
				local qualified = if namespace then namespace .. "." .. name else name
				if set.functions[qualified] then
					report(doc.file, "duplicate function " .. qualified)
				else
					set.functions[qualified] = docFunction(qualified, fn :: Table, set)
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
