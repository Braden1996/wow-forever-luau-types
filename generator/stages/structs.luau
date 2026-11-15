--!strict
-- Stage 3 and the structures section of the output: Blizzard's documented structures and the annotation
-- classes that are neither widgets nor script objects, each derived from another where it contains all of
-- that one's fields (`Base & { extra }`).

local ApiDocs = require("../apidocs")
local Common = require("./common")
local Names = require("./names")
local Signatures = require("./signatures")
local TypeExpr = require("../typeexpr")

type Context = Common.Context
type Struct = Common.Struct

local Structs = {}

function Structs.collect(docs: ApiDocs.DocSet, ann: Common.Annotations, widgets: Common.Widgets): { [string]: Struct }
	local structs: { [string]: Struct } = {}
	for name, s in docs.structures do
		structs[name] = { name = name, fields = s.fields, parents = {}, source = "docs", methods = {} }
	end
	for name, c in ann.classes do
		-- Widget classes (and annotation-only widget bases) are extern types, and a class named like a
		-- documented script object is that object's annotation (stages/widgets.luau reconciles them).
		local isWidget = widgets.clientWidgetFor(name) ~= nil
		local isObject = widgets.objectTypes[name] ~= nil
		if structs[name] == nil and not isWidget and not isObject then
			local methods = table.clone(c.methods)
			for m, sigs in c.statics do
				if methods[m] == nil then
					methods[m] = sigs
				end
			end
			structs[name] =
				{ name = name, fields = c.fields, parents = c.parents, source = "annotations", methods = methods }
		end
	end
	return structs
end

type FieldText = { key: string, text: string }
type Fields = { list: { FieldText }, set: { [string]: boolean } } -- printed entries, and the set of texts

-- A structure's fields and methods as printed `key: type` entries, sorted by key.
local function fieldTexts(ctx: Context, s: Struct): Fields
	local typeName = ctx.typeNames[s.name]
	local resolve = Names.resolver(ctx, nil, typeName)
	local list: { FieldText } = {}
	local seen: { [string]: boolean } = {}
	local indexer = false
	for _, f in s.fields do
		if seen[f.name] then
			continue
		end
		seen[f.name] = true
		local t = TypeExpr.print(f.type, resolve)
		if f.optional and not Common.acceptsNil(f.type) then
			t = TypeExpr.wrap(t) .. "?"
		end
		local keyType = f.keyType
		if keyType then
			if not indexer then
				indexer = true -- Luau allows one indexer per table type; keep the first
				local key = TypeExpr.print(keyType, resolve)
				table.insert(list, { key = "[" .. key .. "]", text = "[" .. key .. "]: " .. t })
			end
		else
			table.insert(list, { key = f.name, text = Common.identifierKey(f.name) .. ": " .. t })
		end
	end
	for _, m in Common.sortedKeys(s.methods) do
		if not seen[m] then
			seen[m] = true
			local fn = Signatures.overloadSet(ctx, s.methods[m], "self: " .. typeName, typeName)
			table.insert(list, { key = m, text = Common.identifierKey(m) .. ": " .. fn })
		end
	end
	table.sort(list, function(a: FieldText, b: FieldText): boolean
		return a.key < b.key
	end)
	local set: { [string]: boolean } = {}
	for _, f in list do
		set[f.text] = true
	end
	return { list = list, set = set }
end

local function subsetOf(small: Fields, big: Fields): boolean
	for _, f in small.list do
		if not big.set[f.text] then
			return false
		end
	end
	return true
end

-- For each documented structure, the largest other documented structure whose fields it contains.
local function derivations(ctx: Context, fields: { [string]: Fields }): { [string]: string }
	local derivedFrom: { [string]: string } = {}
	local docNames = {}
	for _, name in Common.sortedKeys(ctx.structs) do
		if ctx.structs[name].source == "docs" and #fields[name].list >= ctx.config.derivedMinFields then
			table.insert(docNames, name)
		end
	end
	for _, b in docNames do
		local best: string? = nil
		for _, a in docNames do
			local sizeA, sizeB = #fields[a].list, #fields[b].list
			if a ~= b and sizeA <= sizeB and subsetOf(fields[a], fields[b]) then
				-- Equal shapes: the alphabetically first is the base; never derive from a later twin.
				local equal = sizeA == sizeB
				if not (equal and a > b) and derivedFrom[a] ~= b then
					if best == nil or sizeA > #fields[best :: string].list then
						best = a
					end
				end
			end
		end
		if best then
			derivedFrom[b] = best
		end
	end
	return derivedFrom
end

-- Emits every structure; returns how many are derived from another.
function Structs.emit(ctx: Context): number
	local structs, typeNames, widgetAliases, res = ctx.structs, ctx.typeNames, ctx.widgetAliases, ctx.res
	ctx.emit("-- Structures and mixins ----------------------------------------------------------------------")
	local fields: { [string]: Fields } = {}
	for name, s in structs do
		fields[name] = fieldTexts(ctx, s)
	end
	local derivedFrom = derivations(ctx, fields)
	for _, name in Common.sortedKeys(structs) do
		local s = structs[name]
		local base = derivedFrom[name]
		local parents: { string } = {}
		if base then
			table.insert(parents, typeNames[base])
		else
			for _, p in s.parents do
				local resolved = if structs[p]
					then typeNames[p]
					elseif widgetAliases[p] or res.widgets[p] then typeNames[widgetAliases[p] or p]
					else nil
				if resolved then
					table.insert(parents, resolved)
				end
			end
		end
		local own = fields[name].list
		if base then
			own = {}
			for _, f in fields[name].list do
				if not fields[base].set[f.text] then
					table.insert(own, f)
				end
			end
		end
		local body: string
		if #own == 0 then
			body = if #parents > 0 then "" else "{}"
		else
			local lines = {}
			for _, f in own do
				table.insert(lines, "\t" .. f.text .. ",")
			end
			body = "{\n" .. table.concat(lines, "\n") .. "\n}"
		end
		local parts = table.clone(parents)
		if body ~= "" then
			table.insert(parts, body)
		end
		ctx.emit("export type " .. typeNames[name] .. " = " .. table.concat(parts, " & "))
		local note: string? = nil
		if base and #own == 0 then
			note = "same fields as " .. base
		elseif base then
			note = "derived: " .. base .. " & { " .. #own .. " more fields }"
		end
		ctx.cover("structures", name, "typed", s.source, note)
	end
	ctx.emit("")
	return Common.count(derivedFrom)
end

return Structs
