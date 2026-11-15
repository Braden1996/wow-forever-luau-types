--!strict
-- Merges the three inputs into one luau-lsp definitions file plus a coverage record:
--   the client dump      decides what EXISTS (functions, widgets and their methods, events, enums)
--   Blizzard's API docs  give types first (functions, widget methods, event payloads, structures)
--   LuaCATS annotations  give types for the rest (wiki-documented globals, FrameXML, Lua extensions)
-- Anything the client has but no source types is declared `(...unknown) -> ...unknown`.

local ApiDocs = require("./apidocs")
local Parse = require("./parse")
local Resources = require("./resources")
local TypeExpr = require("./typeexpr")

type Type = TypeExpr.Type
type Param = TypeExpr.Param
type Signature = Parse.Signature
type Func = Parse.Func

export type Config = {
	sources: { string },
	gameName: string,
	closedAliases: { [string]: boolean },
	closedAliasPattern: string,
	luauGlobals: { string },
	stdlibAliases: { [string]: string },
	luauStdlib: { [string]: boolean },
	basicTypes: { [string]: string },
	scriptObjectWidgets: { [string]: { string } },
	ignoredScriptObjects: { [string]: string },
	docWidgetAliases: { [string]: string },
	widgetParentOverrides: { [string]: { string } },
	scriptMethods: { [string]: boolean },
	paramTypeOverrides: { [string]: { [string]: string } },
	derivedMinFields: number,
}

type Pin = { repository: string, commit: string }

export type Input = {
	files: { { path: string, source: string } }, -- annotation files, in priority order
	docs: ApiDocs.DocSet,
	resources: Resources.Resources,
	reserved: { [string]: boolean }, -- names the hand-written supplements declare
	upstream: { annotations: Pin, docs: Pin, resources: Pin },
	config: Config,
}

export type CoverageEntry = { status: string, source: string?, reason: string? }
export type Coverage = { [string]: { [string]: CoverageEntry } }

type AnnClass = {
	name: string,
	parents: { string },
	fields: { Parse.Field },
	methods: { [string]: { Signature } },
	statics: { [string]: { Signature } },
	file: string,
}

type Node = {
	kind: "ns" | "func" | "enum" | "value",
	children: { [string]: Node },
	sigs: { Signature },
	entries: { { key: string, value: string } }?,
	valueType: string?,
	doc: string?,
}

local BUILTIN_TYPES: { [string]: string } = {
	-- `any` in an annotation becomes `unknown`: accepted as an argument, refined before use as a result.
	any = "unknown",
	unknown = "unknown",
	number = "number",
	integer = "number",
	float = "number",
	string = "string",
	boolean = "boolean",
	bool = "boolean",
	["nil"] = "nil",
	void = "nil",
	-- Documented exceptions: `{ [any]: any }` is the only table type every table (array, map or record)
	-- is assignable to, and `(...any) -> ...any` the only function type every function is.
	table = "{ [any]: any }",
	["function"] = "(...any) -> ...any",
	userdata = "unknown",
	lightuserdata = "unknown",
	thread = "thread",
}

local RESERVED_TYPE_NAMES: { [string]: boolean } = {
	any = true,
	boolean = true,
	buffer = true,
	never = true,
	["nil"] = true,
	number = true,
	string = true,
	thread = true,
	typeof = true,
	unknown = true,
	vector = true,
	table = true,
	self = true,
}

local UNTYPED_SIGNATURE: Signature = {
	params = { { name = "...", type = { kind = "name", name = "unknown", args = {} }, optional = false } },
	returns = { { kind = "name", name = "...", args = { { kind = "name", name = "unknown", args = {} } } } },
	generics = {},
	deprecated = false,
	doc = nil,
}

local Build = {}

local function sortedKeys<V>(t: { [string]: V }): { string }
	local keys = {}
	for k in t do
		table.insert(keys, k)
	end
	table.sort(keys)
	return keys
end

local function identifierKey(name: string): string
	if string.match(name, "^[%a_][%w_]*$") and not TypeExpr.RESERVED[name] then
		return name
	end
	return '["' .. name .. '"]'
end

local function isIdentifierPath(qualified: string): boolean
	for _, part in string.split(qualified, ".") do
		if not string.match(part, "^[%a_][%w_]*$") then
			return false
		end
	end
	return true
end

function Build.run(input: Input): (string, { [string]: any }, Coverage)
	local config = input.config
	local res = input.resources
	local docs = input.docs
	local unresolvedTypes: { [string]: number } = {}
	local parseErrors: { string } = table.clone(docs.errors)

	local coverage: Coverage = {
		functions = {},
		widgetMethods = {},
		events = {},
		structures = {},
		enums = {},
		widgets = {},
	}
	local function cover(category: string, name: string, status: string, source: string?, reason: string?)
		coverage[category][name] = { status = status, source = source, reason = reason }
	end

	local luauGlobals: { [string]: boolean } = {}
	for _, name in config.luauGlobals do
		luauGlobals[name] = true
	end

	-- 1. Annotations ---------------------------------------------------------------------------------
	local annClasses: { [string]: AnnClass } = {}
	local annAliases: { [string]: Parse.Alias } = {}
	local annFunctions: { [string]: Func } = {}
	local annValues: { [string]: string } = {} -- "tinsert" -> "tab.insert"
	local annGlobalClass: { [string]: string } = {} -- global table name -> its ---@class
	local stdlib: { [string]: Func } = {} -- "string.split" -> signature

	local function annClass(name: string, file: string): AnnClass
		local c = annClasses[name]
		if c == nil then
			c = { name = name, parents = {}, fields = {}, methods = {}, statics = {}, file = file }
			annClasses[name] = c
		end
		return c :: AnnClass
	end

	local function withOverloads(f: Func): { Signature }
		local sigs = { f.signature }
		for _, o in f.overloads do
			table.insert(sigs, o)
		end
		return sigs
	end

	for _, file in input.files do
		local decls = Parse.file(file.path, file.source)
		for _, e in decls.errors do
			table.insert(parseErrors, e)
		end
		for _, cls in decls.classes do
			local c = annClass(cls.name, decls.file)
			for _, p in cls.parents do
				if not table.find(c.parents, p) and p ~= cls.name then
					table.insert(c.parents, p)
				end
			end
			local seen = {}
			for _, f in c.fields do
				seen[f.name] = true
			end
			for _, f in cls.fields do
				if f.visibility ~= "private" and f.visibility ~= "protected" and not seen[f.name] then
					seen[f.name] = true
					table.insert(c.fields, f)
				end
			end
		end
		for _, a in decls.aliases do
			if annAliases[a.name] == nil then
				annAliases[a.name] = a
			end
		end
		for _, g in decls.globals do
			local path = g.path
			if path[1] == "_G" and #path > 1 then
				path = table.move(path, 2, #path, 1, {})
			end
			local qualified = table.concat(path, ".")
			if g.class then
				decls.locals[qualified] = g.class
				if #path == 1 then
					annGlobalClass[qualified] = g.class
				end
			elseif g.value ~= "{}" and annValues[qualified] == nil then
				annValues[qualified] = g.value
			end
		end
		for _, f in decls.funcs do
			local head = f.path[1]
			local qualified = table.concat(f.path, ".")
			local ownerPath = table.concat(f.path, ".", 1, #f.path - 1)
			local owner = if #f.path > 1 then decls.locals[ownerPath] else nil
			if #f.path == 2 and config.stdlibAliases[head] == head then
				owner = nil -- string.split, table.wipe: WoW's extensions of the standard tables
			end
			if owner == nil and #f.path > 1 and annClasses[ownerPath] and f.method then
				owner = ownerPath -- `function Frame:SetPoint()` with the class name used directly
			end
			if owner then
				local c = annClass(owner, decls.file)
				local bucket = if f.method then c.methods else c.statics
				local name = f.path[#f.path]
				bucket[name] = bucket[name] or {}
				for _, sig in withOverloads(f) do
					table.insert(bucket[name], sig)
				end
			elseif #f.path == 2 and config.stdlibAliases[head] == head then
				stdlib[qualified] = stdlib[qualified] or f
			elseif annFunctions[qualified] == nil then
				annFunctions[qualified] = f
			end
		end
	end

	-- 2. Widgets: the client's own hierarchy --------------------------------------------------------
	local widgetParents: { [string]: { string } } = {}
	for name, w in res.widgets do
		local parents = {}
		for _, p in config.widgetParentOverrides[name] or w.inherits do
			if p ~= name and res.widgets[p] then
				table.insert(parents, p)
			end
		end
		widgetParents[name] = parents
	end
	local function ancestors(name: string): { string }
		local out, seen, queue = {}, { [name] = true }, table.clone(widgetParents[name] or {})
		while #queue > 0 do
			local p = table.remove(queue, 1) :: string
			if not seen[p] then
				seen[p] = true
				table.insert(out, p)
				for _, pp in widgetParents[p] or {} do
					table.insert(queue, pp)
				end
			end
		end
		return out
	end
	-- Every method a widget has, own and inherited.
	local function allMethods(name: string): { [string]: boolean }
		local out = table.clone(res.widgets[name].methods)
		for _, a in ancestors(name) do
			for m in res.widgets[a].methods do
				out[m] = true
			end
		end
		return out
	end
	local function allHandlers(name: string): { string }
		local set: { [string]: boolean } = {}
		for _, h in res.widgets[name].handlers do
			set[h] = true
		end
		for _, a in ancestors(name) do
			for _, h in res.widgets[a].handlers do
				set[h] = true
			end
		end
		return sortedKeys(set)
	end

	-- Blizzard's documented methods per widget, and the documented non-widget script objects.
	local docWidgetMethods: { [string]: { [string]: ApiDocs.DocFunction } } = {}
	local objectTypes: { [string]: { [string]: ApiDocs.DocFunction } } = {}
	for _, system in sortedKeys(docs.scriptObjects) do
		local methods = docs.scriptObjects[system]
		local targets = config.scriptObjectWidgets[system]
		if targets then
			for _, w in targets do
				docWidgetMethods[w] = docWidgetMethods[w] or {}
				for m, fn in methods do
					if docWidgetMethods[w][m] == nil then
						docWidgetMethods[w][m] = fn
					end
				end
			end
		elseif not config.ignoredScriptObjects[system] then
			local typeName = string.gsub(system, "API$", "")
			objectTypes[typeName] = methods
		end
	end

	-- An annotation widget class that is not a client widget resolves to its nearest client ancestor.
	local function clientWidgetFor(name: string, depth: number): string?
		if res.widgets[name] then
			return name
		end
		local c = annClasses[name]
		if c == nil or depth > 16 then
			return nil
		end
		for _, p in c.parents do
			local w = clientWidgetFor(p, depth + 1)
			if w then
				return w
			end
		end
		return nil
	end

	-- Annotation methods for a widget: its annotation class and that class's annotation ancestors.
	-- The annotations hang some methods on helper classes (SetPoint on ScriptRegionResizing, which only
	-- their Region and Frame inherit), so the search covers the widget, its ancestors, then its
	-- descendants, each with its annotation ancestors.
	local function annotatedMethod(widget: string, method: string): { Signature }?
		local seen: { [string]: boolean } = {}
		local queue = { widget }
		for _, a in ancestors(widget) do
			table.insert(queue, a)
		end
		for _, d in sortedKeys(res.widgets) do
			if table.find(ancestors(d), widget) then
				table.insert(queue, d)
			end
		end
		while #queue > 0 do
			local name = table.remove(queue, 1) :: string
			if not seen[name] then
				seen[name] = true
				local c = annClasses[name]
				if c then
					if c.methods[method] then
						return c.methods[method]
					end
					for _, p in c.parents do
						table.insert(queue, p)
					end
				end
			end
		end
		return nil
	end

	-- 3. Structures ----------------------------------------------------------------------------------
	type Struct = {
		name: string,
		fields: { Parse.Field },
		parents: { string },
		source: string,
		methods: { [string]: { Signature } },
	}
	local structs: { [string]: Struct } = {}
	for name, s in docs.structures do
		structs[name] = { name = name, fields = s.fields, parents = {}, source = "docs", methods = {} }
	end
	for name, c in annClasses do
		local isObject = objectTypes[name] ~= nil or objectTypes[name .. "Object"] ~= nil
		if structs[name] == nil and res.widgets[name] == nil and not isObject and clientWidgetFor(name, 0) == nil then
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

	-- 4. Type names ----------------------------------------------------------------------------------
	local typeNames: { [string]: string } = {}
	local usedNames: { [string]: boolean } = {}
	local function claim(sourceName: string, preferred: string?)
		if typeNames[sourceName] then
			return
		end
		local name: string = preferred or (string.gsub(sourceName, "[^%w_]", "_"))
		local reserved = RESERVED_TYPE_NAMES[name] or TypeExpr.RESERVED[name]
		if reserved then
			name ..= "_"
		end
		local unique = name
		local n = 1
		while usedNames[unique] do
			n += 1
			unique = name .. "_" .. n
		end
		usedNames[unique] = true
		typeNames[sourceName] = unique
	end
	for _, name in sortedKeys(res.widgets) do
		claim(name)
	end
	for _, name in sortedKeys(objectTypes) do
		claim(name)
	end
	for _, e in res.enums do
		claim("Enum." .. e.name)
	end
	for _, name in sortedKeys(structs) do
		claim(name)
	end
	local callbacks = docs.callbacks
	for _, name in sortedKeys(callbacks) do
		claim(name)
	end
	for _, name in sortedKeys(annAliases) do
		claim(name)
	end
	-- Names that refer to a widget: Blizzard's `SimpleFrame`, annotation-only bases like
	-- `ScriptRegionResizing`.
	local widgetAliases: { [string]: string } = {}
	for alias, target in config.docWidgetAliases do
		if res.widgets[target] then
			widgetAliases[alias] = target
		end
	end
	for name in annClasses do
		local w = clientWidgetFor(name, 0)
		if w and w ~= name and res.widgets[name] == nil then
			widgetAliases[name] = w
		end
	end

	local function makeResolver(generics: { [string]: string }?, selfName: string?): TypeExpr.Resolver
		local resolve: TypeExpr.Resolver
		function resolve(name: string, args: { Type }): string
			if name == "..." then
				return "..." .. TypeExpr.wrap(TypeExpr.print(args[1], resolve))
			end
			if generics and generics[name] then
				return generics[name]
			end
			if name == "self" and selfName then
				return selfName
			end
			if name == "table" and #args == 2 then
				return "{ [" .. TypeExpr.print(args[1], resolve) .. "]: " .. TypeExpr.print(args[2], resolve) .. " }"
			elseif name == "table" and #args == 1 then
				return "{ " .. TypeExpr.print(args[1], resolve) .. " }"
			end
			local builtin = BUILTIN_TYPES[name]
			if builtin then
				return builtin
			end
			if widgetAliases[name] then
				return typeNames[widgetAliases[name]]
			end
			local declared = typeNames[name] or typeNames["Enum." .. name]
			if declared then
				return declared
			end
			local basic = config.basicTypes[name]
			if basic then
				return basic
			end
			unresolvedTypes[name] = (unresolvedTypes[name] or 0) + 1
			return "unknown"
		end
		return resolve
	end

	local function genericScope(sig: Signature, erase: boolean?): ({ [string]: string }?, string)
		if #sig.generics == 0 then
			return nil, ""
		end
		local scope = {}
		local names = {}
		for _, g in sig.generics do
			scope[g] = if erase then "unknown" else g
			table.insert(names, g)
		end
		if erase then
			return scope, ""
		end
		return scope, "<" .. table.concat(names, ", ") .. ">"
	end

	-- Printed signatures; overloads with one result are merged (see mergeOverloads).
	type PrintedParam = { name: string, type: string, vararg: boolean }
	type Printed = { generics: string, params: { PrintedParam }, returns: string }

	local function printSig(sig: Signature, selfName: string?, erase: boolean): Printed
		local scope, genericText = genericScope(sig, erase)
		local resolve = makeResolver(scope, selfName)
		local params = {}
		for _, p in sig.params do
			if p.name == "..." then
				local text = TypeExpr.printParam(p, resolve, false, false)
				table.insert(params, { name = "...", type = string.sub(text, 4), vararg = true })
			else
				local text = TypeExpr.printParam(p, resolve, true, false)
				local colon = string.find(text, ": ", 1, true) :: number
				table.insert(params, {
					name = string.sub(text, 1, colon - 1),
					type = string.sub(text, colon + 2),
					vararg = false,
				})
			end
		end
		return { generics = genericText, params = params, returns = TypeExpr.printReturns(sig.returns, resolve) }
	end

	local function unionMembers(t: string): ({ string }, boolean)
		local optional = false
		if string.sub(t, -1) == "?" then
			optional = true
			t = string.sub(t, 1, -2)
			if string.sub(t, 1, 1) == "(" and string.sub(t, -1) == ")" and #TypeExpr.splitUnion(t) == 1 then
				local inner = string.sub(t, 2, -2)
				if not string.find(inner, "->", 1, true) then
					t = inner
				end
			end
		end
		return TypeExpr.splitUnion(t), optional
	end

	-- Overloads that return the same thing are merged into one signature (each position's types
	-- unioned, optional when some overload lacks it): Luau infers string literals against a single
	-- signature, and the new solver rejects large overload sets as too complex.
	local function mergeOverloads(sigs: { Printed }): { Printed }
		local groups: { { Printed } } = {}
		local byKey: { [string]: { Printed } } = {}
		for _, p in sigs do
			local mergeable = p.generics == ""
			for _, param in p.params do
				if param.vararg then
					mergeable = false
				end
			end
			local key = if mergeable then p.returns else tostring(#groups + 1) .. "\0unmergeable"
			local group = byKey[key]
			if group == nil then
				group = {}
				byKey[key] = group
				table.insert(groups, group)
			end
			table.insert(group :: { Printed }, p)
		end
		local out = {}
		for _, group in groups do
			if #group == 1 then
				table.insert(out, group[1])
				continue
			end
			local width = 0
			for _, p in group do
				width = math.max(width, #p.params)
			end
			local params = {}
			for i = 1, width do
				local parts = {}
				local name: string? = nil
				for _, p in group do
					local param = p.params[i]
					if param then
						name = name or param.name
						local members, optional = unionMembers(param.type)
						for _, m in members do
							table.insert(parts, m)
						end
						if optional then
							table.insert(parts, "nil")
						end
					else
						table.insert(parts, "nil")
					end
				end
				table.insert(params, { name = name :: string, type = TypeExpr.unionOf(parts), vararg = false })
			end
			table.insert(out, { generics = "", params = params, returns = group[1].returns })
		end
		return out
	end

	local function printSigs(sigs: { Signature }, selfName: string?, erase: boolean): { Printed }
		local printed = {}
		local seen: { [string]: boolean } = {}
		for _, sig in sigs do
			local p = printSig(sig, selfName, erase)
			local parts = {}
			for _, param in p.params do
				table.insert(parts, param.name .. ":" .. param.type)
			end
			local key = p.generics .. "(" .. table.concat(parts, ",") .. ")" .. p.returns
			if not seen[key] then
				seen[key] = true
				table.insert(printed, p)
			end
		end
		return mergeOverloads(printed)
	end

	local function renderParams(p: Printed, selfParam: string?, declaration: boolean): string
		local parts = {}
		if selfParam then
			table.insert(parts, selfParam)
		end
		for _, param in p.params do
			if param.vararg then
				table.insert(parts, if declaration then "...: " .. param.type else "..." .. TypeExpr.wrap(param.type))
			else
				table.insert(parts, param.name .. ": " .. param.type)
			end
		end
		return "(" .. table.concat(parts, ", ") .. ")"
	end

	local function overloadSet(sigs: { Signature }, selfType: string?, selfName: string?): string
		local parts = {}
		for _, p in printSigs(sigs, selfName, false) do
			table.insert(parts, p.generics .. renderParams(p, selfType, false) .. " -> " .. p.returns)
		end
		if #parts == 1 then
			return parts[1]
		end
		local wrapped = {}
		for _, p in parts do
			table.insert(wrapped, "(" .. p .. ")")
		end
		return table.concat(wrapped, " & ")
	end

	-- Reconciling Blizzard's documentation with the annotations, for an API both describe:
	--   1. Types come from the documentation.
	--   2. An argument is optional if either source says so: the documentation marks some arguments
	--      required that the game treats as optional (MessageFrame:AddMessage's colours).
	--   3. The annotations' extra call shapes (`---@overload`) are kept: the documentation lists one
	--      signature per function (ScriptRegion:SetPoint(point, x, y) is real).
	--   4. A documented result typed as a callback (C_Timer.NewTicker's ticker handle) takes the
	--      annotation's type, which describes the object actually returned.
	local function reconcile(doc: Signature, ann: { Signature }?): ({ Signature }, string)
		if ann == nil or #ann == 0 then
			return { doc }, "docs"
		end
		local a = ann[1]
		local params = {}
		for i, p in doc.params do
			local ap = a.params[i]
			local sameSlot = ap ~= nil and (ap.name == p.name or #a.params == #doc.params)
			if sameSlot and (ap :: Param).optional and not p.optional then
				table.insert(params, { name = p.name, type = p.type, optional = true })
			else
				table.insert(params, p)
			end
		end
		local returns = {}
		for i, r in doc.returns do
			local base: Type = if r.kind == "optional" then r.inner else r
			if base.kind == "name" and callbacks[base.name] and a.returns[i] then
				table.insert(returns, a.returns[i])
			else
				table.insert(returns, r)
			end
		end
		local out: { Signature } = {
			{ params = params, returns = returns, generics = {}, deprecated = doc.deprecated, doc = doc.doc },
		}
		for i = 2, #ann do
			table.insert(out, ann[i])
		end
		return out, if #ann > 1 then "docs+annotations" else "docs"
	end

	-- Parameter types that neither source states precisely enough, keyed "Widget:Method" or a function.
	local function applyOverrides(key: string, p: Printed)
		local overrides = config.paramTypeOverrides[key]
		if overrides then
			for _, param in p.params do
				local t = overrides[param.name]
				if t then
					param.type = if string.sub(param.type, -1) == "?" then TypeExpr.wrap(t) .. "?" else t
				end
			end
		end
	end

	-- 5. Global functions and values: everything the client has -------------------------------------
	local root: Node = { kind = "ns", children = {}, sigs = {} }
	local function nodeAt(path: { string }, upto: number): Node?
		local node: Node = root
		for i = 1, upto do
			local child = node.children[path[i]]
			if child == nil then
				child = { kind = "ns", children = {}, sigs = {} } :: Node
				node.children[path[i]] = child :: Node
			elseif (child :: Node).kind ~= "ns" then
				return nil
			end
			node = child :: Node
		end
		return node
	end

	local clientFunctions: { [string]: string } = {} -- qualified -> which client list
	for name in res.frameXml do
		clientFunctions[name] = "FrameXML"
	end
	for name in res.luaApi do
		clientFunctions[name] = "Lua"
	end
	for name in res.globalApi do
		clientFunctions[name] = "C API"
	end

	local declaredGlobals: { [string]: boolean } = {}
	for _, qualified in sortedKeys(clientFunctions) do
		local path = string.split(qualified, ".")
		local head = path[1]
		if not isIdentifierPath(qualified) then
			cover("functions", qualified, "excluded", nil, "not a Luau identifier path")
			continue
		elseif luauGlobals[head] or (#path == 2 and config.stdlibAliases[head] == head) then
			cover("functions", qualified, "excluded", nil, "provided by Luau's standard library")
			continue
		elseif input.reserved[head] then
			cover("functions", qualified, "typed", "supplements")
			continue
		elseif annGlobalClass[head] and #path > 1 then
			cover("functions", qualified, "excluded", nil, "a method of the mixin " .. head .. " (typed with it)")
			continue
		end
		local sigs: { Signature }
		local source: string
		local doc = docs.functions[qualified]
		local ann = annFunctions[qualified]
		local alias = annValues[qualified]
		if doc then
			sigs, source = reconcile(doc.signature, if ann then withOverloads(ann) else nil)
		elseif ann then
			sigs, source = withOverloads(ann), "annotations"
		elseif alias and string.match(alias, "^[%w_]+%.[%w_]+$") then
			local tbl, fn = string.match(alias, "^([%w_]+)%.([%w_]+)$")
			local target = (config.stdlibAliases[tbl :: string] or (tbl :: string)) .. "." .. (fn :: string)
			local s = stdlib[target]
			if s then
				sigs, source = withOverloads(s), "annotations"
			else
				-- `tinsert = table.insert`: Luau's own signature is the right one, when Luau has it.
				if not config.luauStdlib[target] then
					sigs, source = { UNTYPED_SIGNATURE }, ""
					local parent = nodeAt(path, #path - 1)
					if parent and parent.children[path[#path]] == nil then
						parent.children[path[#path]] = { kind = "func", children = {}, sigs = sigs }
						declaredGlobals[head] = true
					end
					cover("functions", qualified, "untyped", nil, "aliases " .. target .. ", which has no annotation")
					continue
				end
				local parent = nodeAt(path, #path - 1)
				if parent then
					parent.children[path[#path]] =
						{ kind = "value", children = {}, sigs = {}, valueType = "typeof(" .. target .. ")" }
					cover("functions", qualified, "typed", "luau-stdlib")
					declaredGlobals[head] = true
				end
				continue
			end
		else
			sigs, source = { UNTYPED_SIGNATURE }, ""
		end
		local parent = nodeAt(path, #path - 1)
		if parent == nil or parent.children[path[#path]] ~= nil then
			cover("functions", qualified, "excluded", nil, "its name clashes with another global")
			continue
		end
		parent.children[path[#path]] = { kind = "func", children = {}, sigs = sigs, doc = nil }
		declaredGlobals[head] = true
		if source == "" then
			cover("functions", qualified, "untyped", nil, "no type source (" .. clientFunctions[qualified] .. ")")
		else
			cover("functions", qualified, "typed", source)
		end
	end
	for qualified in annFunctions do
		if clientFunctions[qualified] == nil and coverage.functions[qualified] == nil then
			cover("functions", qualified, "excluded", "annotations", "not in the " .. config.gameName .. " client")
		end
	end
	for qualified in docs.functions do
		if clientFunctions[qualified] == nil and coverage.functions[qualified] == nil then
			cover("functions", qualified, "excluded", "docs", "documented, but absent from the client's API dump")
		end
	end

	-- Named frames, mixins and LuaEnum constants.
	for _, name in sortedKeys(res.frames) do
		if
			root.children[name] == nil
			and not input.reserved[name]
			and not luauGlobals[name]
			and isIdentifierPath(name)
		then
			local class = annGlobalClass[name]
			local typeName = if class then (typeNames[class] or typeNames[widgetAliases[class] or ""]) else nil
			root.children[name] = { kind = "value", children = {}, sigs = {}, valueType = typeName or "Frame" }
		end
	end
	for _, name in sortedKeys(annGlobalClass) do
		local class = annGlobalClass[name]
		if root.children[name] == nil and res.mixins[name] and structs[class] and not input.reserved[name] then
			root.children[name] = { kind = "value", children = {}, sigs = {}, valueType = typeNames[class] }
		end
	end
	for _, e in res.enums do
		local enumNode = nodeAt({ "Enum" }, 1) :: Node
		enumNode.children[e.name] = { kind = "enum", children = {}, sigs = {}, entries = e.entries }
		cover("enums", "Enum." .. e.name, "typed", "client")
	end
	for _, c in res.constants do
		local constNode = nodeAt({ "Constants" }, 1) :: Node
		constNode.children[c.name] = { kind = "enum", children = {}, sigs = {}, entries = c.entries }
	end
	for _, c in res.globalConstants do
		if root.children[c.key] == nil and not input.reserved[c.key] then
			local isNumber = string.match(c.value, "^%-?[%dx%.a-fA-F]+$") ~= nil
			root.children[c.key] =
				{ kind = "value", children = {}, sigs = {}, valueType = if isNumber then "number" else "unknown" }
		end
	end
	for qualified, value in annValues do
		local path = string.split(qualified, ".")
		if #path == 1 and root.children[qualified] == nil and not luauGlobals[qualified] then
			if string.match(value, "^%-?[%d%.]+$") or string.match(value, "^math%.pi$") then
				root.children[qualified] = { kind = "value", children = {}, sigs = {}, valueType = "number" }
			end
		end
	end

	-- 6. Emission ------------------------------------------------------------------------------------
	local out: { string } = {}
	local function emit(line: string)
		table.insert(out, line)
	end
	local up = input.upstream
	emit("-- World of Warcraft: Forever API definitions for luau-lsp (requires Luau's new type solver).")
	emit("-- GENERATED FILE: do not edit. Regenerate with `lune run scripts/generate`.")
	emit("-- Existence: " .. up.resources.repository .. "@" .. up.resources.commit)
	emit("-- Types:     " .. up.docs.repository .. "@" .. up.docs.commit .. " (Blizzard_APIDocumentationGenerated)")
	emit("--            " .. up.annotations.repository .. "@" .. up.annotations.commit .. " (MIT licence)")
	emit("")

	-- Luau rejects very long type annotations, so a big union is declared in chunks.
	local CHUNK = 250
	local function emitUnion(typeName: string, text: string)
		if text == "" then
			emit("export type " .. typeName .. " = never")
			return
		end
		local members = TypeExpr.splitUnion(text)
		if #members <= CHUNK then
			emit("export type " .. typeName .. " = " .. text)
			return
		end
		local chunkNames = {}
		for start = 1, #members, CHUNK do
			local chunkName = typeName .. "_" .. (#chunkNames + 1)
			table.insert(chunkNames, chunkName)
			emit(
				"export type "
					.. chunkName
					.. " = "
					.. table.concat(members, " | ", start, math.min(start + CHUNK - 1, #members))
			)
		end
		emit("export type " .. typeName .. " = " .. table.concat(chunkNames, " | "))
	end

	-- Events: the client's names, closed; payloads from Blizzard's documentation.
	emit("-- Events -------------------------------------------------------------------------------------")
	local eventLiterals = {}
	for _, e in res.events do
		table.insert(eventLiterals, '"' .. e .. '"')
	end
	emitUnion("FrameEvent", table.concat(eventLiterals, " | "))
	emit("-- Each event's payload as a handler type: `EventPayloads.PLAYER_LEVEL_UP` is `(level: number, ...) -> ()`.")
	emit("export type EventPayloads = {")
	for _, e in res.events do
		local d = docs.events[e]
		local sig: Signature = if d
			then { params = d.payload, returns = {}, generics = {}, deprecated = false, doc = nil }
			else {
				params = { UNTYPED_SIGNATURE.params[1] },
				returns = {},
				generics = {},
				deprecated = false,
				doc = nil,
			}
		local p = printSig(sig, nil, true)
		emit("\t" .. identifierKey(e) .. ": " .. renderParams(p, nil, false) .. " -> (),")
		if d then
			cover("events", e, "typed", "docs")
		else
			cover("events", e, "untyped", nil, "no documented payload")
		end
	end
	emit("}")
	emit('-- The handler type for one event: `local onLevel: EventHandler<"PLAYER_LEVEL_UP"> = function(level) end`.')
	emit("export type EventHandler<E> = index<EventPayloads, E>")
	for e in docs.events do
		if coverage.events[e] == nil then
			cover("events", e, "excluded", "docs", "documented, but absent from the client's event list")
		end
	end
	emit("")

	-- Aliases.
	emit("-- Aliases ------------------------------------------------------------------------------------")
	local function aliasText(a: Parse.Alias): string
		local resolve = makeResolver(nil, nil)
		local closed = config.closedAliases[a.name] == true or string.match(a.name, config.closedAliasPattern) ~= nil
		local parts: { string } = {}
		if a.base then
			local base = a.base :: Type
			local isPlainString = base.kind == "name" and base.name == "string"
			if not (closed and isPlainString and #a.variants > 0) then
				table.insert(parts, TypeExpr.print(base, resolve))
			end
		end
		for _, v in a.variants do
			if v.kind == "string" and not closed then
				table.insert(parts, "string") -- an open alias's listed strings are hints only
			else
				table.insert(parts, TypeExpr.print(v, resolve))
			end
		end
		local flat = {}
		for _, p in parts do
			for _, piece in TypeExpr.splitUnion(p) do
				table.insert(flat, piece)
			end
		end
		local result = if #flat == 0 then "unknown" else TypeExpr.unionOf(flat)
		if result == typeNames[a.name] then
			return "unknown"
		end
		return result
	end
	for _, name in sortedKeys(annAliases) do
		local shadowed = structs[name]
			or res.widgets[name]
			or callbacks[name]
			or objectTypes[name]
			or widgetAliases[name]
		if name ~= "FrameEvent" and typeNames[name] and not shadowed then
			local a = annAliases[name]
			if name == "FrameType" then
				local kept: { Type } = {}
				for _, v in a.variants do
					if v.kind == "string" and res.widgets[v.value] then
						table.insert(kept, v)
					end
				end
				local filtered: Parse.Alias = { name = a.name, base = nil, variants = kept, file = a.file }
				a = filtered
			end
			emitUnion(typeNames[name], aliasText(a))
		end
	end
	for _, alias in sortedKeys(widgetAliases) do
		if typeNames[alias] == nil then
			emit("export type " .. alias .. " = " .. typeNames[widgetAliases[alias]])
		end
	end
	for _, name in sortedKeys(callbacks) do
		if structs[name] or objectTypes[name] then
			continue
		end
		emit("export type " .. typeNames[name] .. " = " .. TypeExpr.print(callbacks[name].type, makeResolver(nil, nil)))
	end
	emit("")

	-- Enum value types: the client's enums are numbers.
	emit("-- Enum value types ---------------------------------------------------------------------------")
	for _, e in res.enums do
		emit("export type " .. typeNames["Enum." .. e.name] .. " = number")
	end
	emit("")

	-- Structures and mixins, derived from one another where one's fields are a subset of another's.
	emit("-- Structures and mixins ----------------------------------------------------------------------")
	type FieldText = { key: string, text: string }
	local function fieldTexts(s: Struct): { FieldText }
		local resolve = makeResolver(nil, typeNames[s.name])
		local list: { FieldText } = {}
		local seen: { [string]: boolean } = {}
		local indexer = false
		for _, f in s.fields do
			if seen[f.name] then
				continue
			end
			seen[f.name] = true
			local t = TypeExpr.print(f.type, resolve)
			if f.optional and string.sub(t, -1) ~= "?" and t ~= "unknown" and t ~= "any" then
				t = TypeExpr.wrap(t) .. "?"
			end
			if string.sub(f.name, 1, 1) == "[" then
				if not indexer then
					indexer = true
					local keyType = TypeExpr.parse(string.sub(f.name, 2, -2))
					local key = if keyType then TypeExpr.print(keyType, resolve) else "unknown"
					table.insert(list, { key = "[" .. key .. "]", text = "[" .. key .. "]: " .. t })
				end
			else
				table.insert(list, { key = f.name, text = identifierKey(f.name) .. ": " .. t })
			end
		end
		for _, m in sortedKeys(s.methods) do
			if not seen[m] then
				seen[m] = true
				local selfType = "self: " .. typeNames[s.name]
				table.insert(list, {
					key = m,
					text = identifierKey(m) .. ": " .. overloadSet(s.methods[m], selfType, typeNames[s.name]),
				})
			end
		end
		table.sort(list, function(a: FieldText, b: FieldText): boolean
			return a.key < b.key
		end)
		return list
	end
	local structFields: { [string]: { FieldText } } = {}
	for name, s in structs do
		structFields[name] = fieldTexts(s)
	end
	-- For each documented structure, the largest other documented structure whose fields it contains.
	local function subsetOf(small: { FieldText }, big: { FieldText }): boolean
		local set: { [string]: boolean } = {}
		for _, f in big do
			set[f.text] = true
		end
		for _, f in small do
			if not set[f.text] then
				return false
			end
		end
		return true
	end
	local derivedFrom: { [string]: string } = {}
	local docNames = {}
	for _, name in sortedKeys(structs) do
		if structs[name].source == "docs" and #structFields[name] >= config.derivedMinFields then
			table.insert(docNames, name)
		end
	end
	for _, b in docNames do
		local best: string? = nil
		for _, a in docNames do
			if a ~= b and #structFields[a] <= #structFields[b] and subsetOf(structFields[a], structFields[b]) then
				-- Equal shapes: the alphabetically first is the base; never derive from a later twin.
				local equal = #structFields[a] == #structFields[b]
				if not (equal and a > b) and derivedFrom[a] ~= b then
					if best == nil or #structFields[a] > #structFields[best :: string] then
						best = a
					end
				end
			end
		end
		if best then
			derivedFrom[b] = best
		end
	end
	for _, name in sortedKeys(structs) do
		local s = structs[name]
		local typeName = typeNames[name]
		local fields = structFields[name]
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
		local own = fields
		if base then
			own = {}
			local inherited: { [string]: boolean } = {}
			for _, f in structFields[base] do
				inherited[f.text] = true
			end
			for _, f in fields do
				if not inherited[f.text] then
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
		emit("export type " .. typeName .. " = " .. table.concat(parts, " & "))
		cover(
			"structures",
			name,
			"typed",
			s.source,
			if base then "derived: " .. base .. " & { " .. #own .. " more fields }" else nil
		)
	end
	emit("")

	-- Widgets, parents first.
	emit("-- Widgets (the client's own hierarchy) ---------------------------------------------------------")
	local scriptTypes: { [string]: string } = {}
	for _, w in sortedKeys(res.widgets) do
		local handlers = allHandlers(w)
		if #handlers > 0 then
			local literals = {}
			for _, h in handlers do
				table.insert(literals, '"' .. h .. '"')
			end
			scriptTypes[w] = typeNames[w] .. "ScriptType"
			emit("export type " .. scriptTypes[w] .. " = " .. table.concat(literals, " | "))
		end
	end
	local emitted: { [string]: boolean } = {}
	local function emitWidget(w: string)
		if emitted[w] then
			return
		end
		emitted[w] = true
		local parents = widgetParents[w]
		local primary = parents[1]
		if primary then
			emitWidget(primary)
		end
		local typeName = typeNames[w]
		emit(
			"declare extern type " .. typeName .. (if primary then " extends " .. typeNames[primary] else "") .. " with"
		)
		-- Own methods, plus those of secondary parents (ScriptObject, FontInstance) the extends chain lacks.
		local inherited = if primary then allMethods(primary) else {}
		local names: { [string]: boolean } = table.clone(res.widgets[w].methods)
		for i = 2, #parents do
			for m in allMethods(parents[i]) do
				if not inherited[m] then
					names[m] = true
				end
			end
		end
		-- Script methods are re-declared on every widget so the script names are that widget's own.
		if scriptTypes[w] then
			for m in config.scriptMethods do
				if allMethods(w)[m] then
					names[m] = true
				end
			end
		end
		for _, m in sortedKeys(names) do
			local sigs: { Signature }?
			local source = ""
			local d = (docWidgetMethods[w] or {})[m]
			if d == nil then
				for _, a in ancestors(w) do
					d = (docWidgetMethods[a] or {})[m]
					if d then
						break
					end
				end
			end
			if d then
				sigs, source = reconcile(d.signature, annotatedMethod(w, m))
			else
				local a = annotatedMethod(w, m)
				if a then
					sigs, source = a, "annotations"
				end
			end
			local printed = if sigs
				then printSigs(sigs, typeName, true)
				else { printSig(UNTYPED_SIGNATURE, typeName, true) }
			if config.scriptMethods[m] and scriptTypes[w] and sigs == nil then
				-- No source types this script method: its shape is known, so it is written out.
				local handler = "((self: " .. typeName .. ", ...any) -> ())?"
				local scriptParam = { name = "scriptType", type = scriptTypes[w], vararg = false }
				local shapes: { [string]: Printed } = {
					GetScript = { generics = "", params = { scriptParam }, returns = handler },
					HasScript = { generics = "", params = { scriptParam }, returns = "boolean" },
					HookScript = {
						generics = "",
						params = { scriptParam, { name = "handler", type = handler, vararg = false } },
						returns = "()",
					},
					SetScript = {
						generics = "",
						params = { scriptParam, { name = "handler", type = handler, vararg = false } },
						returns = "()",
					},
				}
				printed = { shapes[m] }
				source = "generator"
			end
			for _, p in printed do
				applyOverrides(w .. ":" .. m, p)
				if config.scriptMethods[m] and scriptTypes[w] then
					-- The script name is this widget's closed set; handlers receive the widget.
					local handler = "((self: " .. typeName .. ", ...any) -> ())?"
					if p.params[1] then
						p.params[1].type = scriptTypes[w]
					end
					if p.params[2] and (m == "SetScript" or m == "HookScript") then
						p.params[2].type = handler
					end
					if m == "GetScript" then
						p.returns = handler
					end
				end
				emit("\tfunction " .. m .. renderParams(p, "self", true) .. ": " .. p.returns)
			end
			do
				local key = w .. ":" .. m
				if source == "" then
					cover("widgetMethods", key, "untyped", nil, "no type source")
				else
					cover("widgetMethods", key, "typed", source)
				end
			end
		end
		emit("end")
		emit("")
		cover("widgets", w, "typed", "client", if primary then "extends " .. primary else nil)
	end
	for _, w in sortedKeys(res.widgets) do
		emitWidget(w)
	end

	-- Documented script objects that are not widgets (curves, durations, formatters).
	emit("-- Script objects -----------------------------------------------------------------------------")
	for _, name in sortedKeys(objectTypes) do
		emit("declare extern type " .. typeNames[name] .. " with")
		local methods = objectTypes[name]
		for _, m in sortedKeys(methods) do
			for _, p in printSigs({ methods[m].signature }, typeNames[name], true) do
				emit("\tfunction " .. m .. renderParams(p, "self", true) .. ": " .. p.returns)
			end
			cover("widgetMethods", name .. ":" .. m, "typed", "docs")
		end
		emit("end")
		emit("")
	end

	-- CreateFrame: the frame type picks the returned widget.
	local frameTypes = {}
	local frameTypeAlias = annAliases.FrameType
	if frameTypeAlias then
		for _, v in frameTypeAlias.variants do
			if v.kind == "string" and res.widgets[v.value] then
				table.insert(frameTypes, "\t" .. v.value .. ": " .. typeNames[v.value] .. ",")
			end
		end
	end
	table.sort(frameTypes)
	emit("-- The widget CreateFrame returns for each frame type.")
	emit("export type FrameTypeMap = {")
	for _, line in frameTypes do
		emit(line)
	end
	emit("}")
	emit("")

	-- Globals.
	emit("-- Globals ------------------------------------------------------------------------------------")
	local counts = { functions = 0, tables = 0, values = 0 }
	local function valueType(node: Node): string
		if node.kind == "func" then
			return overloadSet(node.sigs, nil, nil)
		end
		return node.valueType or "unknown"
	end
	local function emitTable(node: Node, indent: string)
		for _, key in sortedKeys(node.children) do
			local child = node.children[key]
			if child.kind == "ns" then
				emit(indent .. identifierKey(key) .. ": {")
				emitTable(child, indent .. "\t")
				emit(indent .. "},")
			elseif child.kind == "enum" then
				emit(indent .. identifierKey(key) .. ": {")
				local seen = {}
				for _, entry in child.entries or {} do
					if not seen[entry.key] then
						seen[entry.key] = true
						local v = entry.value
						local t = if string.match(v, "^[\"']")
							then "string"
							elseif v == "true" or v == "false" then "boolean"
							else "number"
						emit(indent .. "\t" .. identifierKey(entry.key) .. ": " .. t .. ",")
					end
				end
				emit(indent .. "},")
			else
				emit(indent .. identifierKey(key) .. ": " .. valueType(child) .. ",")
			end
		end
	end
	if root.children.CreateFrame then
		root.children.CreateFrame = nil
		emit(
			"declare function CreateFrame<K>(frameType: K & keyof<FrameTypeMap>, name: string?, parent: Frame?, "
				.. "template: string?, id: number?): index<FrameTypeMap, K>"
		)
		counts.functions += 1
		cover("functions", "CreateFrame", "typed", "generator", "generic over FrameTypeMap")
	end
	for _, key in sortedKeys(root.children) do
		local node = root.children[key]
		if node.kind == "func" then
			counts.functions += 1
			local printed = printSigs(node.sigs, nil, false)
			if #printed == 1 and printed[1].generics == "" then
				emit("declare function " .. key .. renderParams(printed[1], nil, true) .. ": " .. printed[1].returns)
			else
				emit("declare " .. key .. ": " .. overloadSet(node.sigs, nil, nil))
			end
		elseif node.kind == "ns" or node.kind == "enum" then
			counts.tables += 1
			emit("declare " .. key .. ": {")
			emitTable(node, "\t")
			emit("}")
		else
			counts.values += 1
			emit("declare " .. key .. ": " .. valueType(node))
		end
	end
	emit("")

	-- Report ----------------------------------------------------------------------------------------
	local summary: { [string]: { [string]: number } } = {}
	for category, entries in coverage do
		local s = { typed = 0, untyped = 0, excluded = 0 }
		for _, e in entries do
			s[e.status] = (s[e.status] or 0) + 1
		end
		summary[category] = s
	end
	-- Functions by the client list they come from (C API, Lua library, FrameXML).
	local byList: { [string]: { [string]: number } } = {}
	for qualified, list in clientFunctions do
		local e = coverage.functions[qualified]
		if e then
			local s = byList[list] or { typed = 0, untyped = 0, excluded = 0 }
			s[e.status] = (s[e.status] or 0) + 1
			byList[list] = s
		end
	end
	local unresolved = {}
	for _, name in sortedKeys(unresolvedTypes) do
		table.insert(unresolved, { name = name, uses = unresolvedTypes[name] })
	end
	local text = table.concat(out, "\n")
	local _, anyCount = string.gsub(text, "%f[%w_]any%f[^%w_]", "")
	local report = {
		upstream = input.upstream,
		game = config.gameName,
		summary = summary,
		functionsByClientList = byList,
		counts = {
			annotationFiles = #input.files,
			globalFunctions = counts.functions,
			globalTables = counts.tables,
			globalValues = counts.values,
			structures = #sortedKeys(structs),
			derivedStructures = #sortedKeys(derivedFrom),
			widgets = #sortedKeys(res.widgets),
			scriptObjects = #sortedKeys(objectTypes),
			anyOccurrences = anyCount,
		},
		parseErrors = parseErrors,
		unresolvedTypes = unresolved,
	}
	return text, report, coverage
end

return Build
