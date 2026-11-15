--!strict
-- Stage 2 and the widget section of the output: the client's widget hierarchy, where each widget method's
-- type comes from (Blizzard's script-object docs, then annotations), and the `declare extern type`s.

local ApiDocs = require("../apidocs")
local Common = require("./common")
local Decls = require("../luacats/decls")
local Resources = require("../resources")
local Signatures = require("./signatures")

type Context = Common.Context
type Printed = Common.Printed
type Signature = Decls.Signature

local Widgets = {}

function Widgets.collect(
	res: Resources.Resources,
	config: Common.Config,
	docs: ApiDocs.DocSet,
	ann: Common.Annotations
): Common.Widgets
	local annClasses = ann.classes

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
	-- Each widget's descendants, in name order.
	local descendants: { [string]: { string } } = {}
	for _, d in Common.sortedKeys(res.widgets) do
		for _, a in ancestors(d) do
			descendants[a] = descendants[a] or {}
			table.insert(descendants[a], d)
		end
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
		return Common.sortedKeys(set)
	end

	-- Blizzard's documented methods per widget, and the documented non-widget script objects.
	local docMethods: { [string]: { [string]: ApiDocs.DocFunction } } = {}
	local objectTypes: { [string]: { [string]: ApiDocs.DocFunction } } = {}
	for _, system in Common.sortedKeys(docs.scriptObjects) do
		local methods = docs.scriptObjects[system]
		local targets = config.scriptObjectWidgets[system]
		if targets then
			for _, w in targets do
				docMethods[w] = docMethods[w] or {}
				for m, fn in methods do
					if docMethods[w][m] == nil then
						docMethods[w][m] = fn
					end
				end
			end
		elseif not config.ignoredScriptObjects[system] then
			local typeName: string = (string.gsub(system, "API$", ""))
			assert(objectTypes[typeName] == nil, "two documented script objects are both named " .. typeName)
			assert(res.widgets[typeName] == nil, "the script object " .. typeName .. " has a widget's name")
			objectTypes[typeName] = methods
		end
	end

	-- An annotation widget class that is not a client widget resolves to its nearest client ancestor.
	local function clientWidgetFor(name: string): string?
		local seen: { [string]: boolean } = {}
		local function walk(n: string): string?
			if res.widgets[n] then
				return n
			end
			local c = annClasses[n]
			if c == nil or seen[n] then
				return nil
			end
			seen[n] = true
			for _, p in c.parents do
				local w = walk(p)
				if w then
					return w
				end
			end
			return nil
		end
		return walk(name)
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
		for _, d in descendants[widget] or {} do
			table.insert(queue, d)
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

	return {
		parents = widgetParents,
		ancestors = ancestors,
		descendants = descendants,
		allMethods = allMethods,
		allHandlers = allHandlers,
		docMethods = docMethods,
		objectTypes = objectTypes,
		clientWidgetFor = clientWidgetFor,
		annotatedMethod = annotatedMethod,
	}
end

-- The handler a widget's script methods take and return: it receives the widget; its other arguments
-- depend on the script, so they are `...any` (a documented exception).
local function handlerType(typeName: string): string
	return "((self: " .. typeName .. ", ...any) -> ())?"
end

-- A script method's printed signature, typed for one widget: the script name is that widget's closed set of
-- script names, and the handler receives the widget. `p` is the documented or annotated signature; nil when
-- no source types the method, in which case its known shape is written out.
local function scriptMethod(m: string, typeName: string, scriptType: string, p: Printed?): Printed
	local handler = handlerType(typeName)
	if p == nil then
		local scriptParam = { name = "scriptType", type = scriptType, vararg = false }
		local handlerParam = { name = "handler", type = handler, vararg = false }
		local shapes: { [string]: Printed } = {
			GetScript = { generics = "", params = { scriptParam }, returns = handler },
			HasScript = { generics = "", params = { scriptParam }, returns = "boolean" },
			HookScript = { generics = "", params = { scriptParam, handlerParam }, returns = "()" },
			SetScript = { generics = "", params = { scriptParam, handlerParam }, returns = "()" },
		}
		local shape = shapes[m]
		assert(shape, "no known shape for the script method " .. m .. " (generator/rules/widgets.luau)")
		return shape
	end
	local typed = p :: Printed
	if typed.params[1] then
		typed.params[1].type = scriptType
	end
	if typed.params[2] and (m == "SetScript" or m == "HookScript") then
		typed.params[2].type = handler
	end
	if m == "GetScript" then
		typed.returns = handler
	end
	return typed
end

-- Widgets, parents first, then the documented script objects that are not widgets.
function Widgets.emit(ctx: Context)
	local res, config, emit, typeNames, model = ctx.res, ctx.config, ctx.emit, ctx.typeNames, ctx.widgets
	emit("-- Widgets (the client's own hierarchy) ---------------------------------------------------------")
	local scriptTypes: { [string]: string } = {}
	for _, w in Common.sortedKeys(res.widgets) do
		local handlers = model.allHandlers(w)
		if #handlers > 0 then
			local literals = {}
			for _, h in handlers do
				table.insert(literals, Common.quote(h))
			end
			scriptTypes[w] = typeNames[w] .. Common.SCRIPT_TYPE_SUFFIX
			emit("export type " .. scriptTypes[w] .. " = " .. table.concat(literals, " | "))
		end
	end

	-- Where widget `w`'s method `m` gets its type: documentation (its own, then its ancestors'),
	-- reconciled with the annotations; then the annotations alone.
	local function sourceOf(w: string, m: string): ({ Signature }?, string, ApiDocs.DocFunction?)
		local function documented(): ApiDocs.DocFunction?
			local own = (model.docMethods[w] or {})[m]
			if own then
				return own
			end
			for _, a in model.ancestors(w) do
				local inherited = (model.docMethods[a] or {})[m]
				if inherited then
					return inherited
				end
			end
			return nil
		end
		local d = documented()
		if d then
			local sigs, source = Signatures.reconcile(ctx, d.signature, model.annotatedMethod(w, m))
			return sigs, source, d
		end
		local a = model.annotatedMethod(w, m)
		if a then
			return a, "annotations", nil
		end
		return nil, "", nil
	end

	local emitted: { [string]: boolean } = {}
	local function emitWidget(w: string)
		if emitted[w] then
			return
		end
		emitted[w] = true
		local parents = model.parents[w]
		local primary = parents[1]
		if primary then
			emitWidget(primary)
		end
		local typeName = typeNames[w]
		emit(
			"declare extern type " .. typeName .. (if primary then " extends " .. typeNames[primary] else "") .. " with"
		)
		-- Own methods, plus those of secondary parents (ScriptObject, FontInstance) the extends chain lacks.
		local inherited = if primary then model.allMethods(primary) else {}
		local names: { [string]: boolean } = table.clone(res.widgets[w].methods)
		for i = 2, #parents do
			for m in model.allMethods(parents[i]) do
				if not inherited[m] then
					names[m] = true
				end
			end
		end
		-- Script methods are re-declared on every widget so the script names are that widget's own.
		local scriptType = scriptTypes[w]
		if scriptType then
			local all = model.allMethods(w)
			for m in config.scriptMethods do
				if all[m] then
					names[m] = true
				end
			end
		end
		for _, m in Common.sortedKeys(names) do
			local key = w .. ":" .. m
			local sigs, source, doc = sourceOf(w, m)
			local printed: { Printed }
			if sigs then
				local final = Signatures.applyOverrides(ctx, key, sigs)
				printed = Signatures.printAll(ctx, final, typeName, true)
				ctx.apis.widgetMethods[key] = { sigs = final, doc = doc, selfName = typeName }
			else
				printed = { Signatures.print(ctx, Common.UNTYPED_SIGNATURE, typeName, true) }
			end
			if config.scriptMethods[m] and scriptType then
				ctx.apis.widgetMethods[key] = { sigs = {}, opaque = "a script method, typed per widget" }
				if sigs == nil then
					printed = { scriptMethod(m, typeName, scriptType, nil) }
					source = "generator"
				else
					for i, p in printed do
						printed[i] = scriptMethod(m, typeName, scriptType, p)
					end
				end
			end
			for _, p in printed do
				emit("\tfunction " .. m .. Signatures.renderParams(p, "self", true) .. ": " .. p.returns)
			end
			if source == "" then
				ctx.cover("widgetMethods", key, "untyped", nil, "no type source")
			else
				ctx.cover("widgetMethods", key, "typed", source)
			end
		end
		emit("end")
		emit("")
		ctx.cover("widgets", w, "typed", "client", if primary then "extends " .. primary else nil)
	end
	for _, w in Common.sortedKeys(res.widgets) do
		emitWidget(w)
	end

	-- Documented script objects that are not widgets (curves, durations, formatters), reconciled with the
	-- annotation class of the same name where there is one (AbbreviateConfig, UnitHealPredictionCalculator).
	emit("-- Script objects -----------------------------------------------------------------------------")
	for _, name in Common.sortedKeys(model.objectTypes) do
		emit("declare extern type " .. typeNames[name] .. " with")
		local methods = model.objectTypes[name]
		local annClass = ctx.ann.classes[name]
		for _, m in Common.sortedKeys(methods) do
			local annotated = if annClass then annClass.methods[m] else nil
			local sigs, source = Signatures.reconcile(ctx, methods[m].signature, annotated)
			ctx.apis.widgetMethods[name .. ":" .. m] = { sigs = sigs, doc = methods[m], selfName = typeNames[name] }
			for _, p in Signatures.printAll(ctx, sigs, typeNames[name], true) do
				emit("\tfunction " .. m .. Signatures.renderParams(p, "self", true) .. ": " .. p.returns)
			end
			ctx.cover("widgetMethods", name .. ":" .. m, "typed", source)
		end
		emit("end")
		emit("")
	end
end

return Widgets
