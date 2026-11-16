--!strict
-- Merges the three inputs into one luau-lsp definitions file plus a coverage record:
--   the client dump      decides what EXISTS (functions, widgets and their methods, events, enums)
--   Blizzard's API docs  give types first (functions, widget methods, event payloads, structures)
--   LuaCATS annotations  give types for the rest (wiki-documented globals, FrameXML, Lua extensions)
-- Anything the client has but no source types is declared `(...unknown) -> ...unknown`.
-- The stages live in generator/stages/; this file runs them in order and assembles the report.

local Annotations = require("./stages/annotations")
local Decls = require("./luacats/decls")
local Common = require("./stages/common")
local Globals = require("./stages/globals")
local Json = require("./json")
local Names = require("./stages/names")
local Shapes = require("./stages/shapes")
local Signatures = require("./stages/signatures")
local Structs = require("./stages/structs")
local TypeExpr = require("./typeexpr")
local Types = require("./stages/types")
local Widgets = require("./stages/widgets")

export type Config = Common.Config
export type Input = Common.Input
export type Coverage = Common.Coverage
export type CoverageEntry = Common.CoverageEntry
export type Category = Common.Category
export type Status = Common.Status
export type StatusCounts = Common.StatusCounts
export type Report = Common.Report
export type ShapeSet = Shapes.Shapes
type Signature = Decls.Signature

local Build = {}

Build.entries = Common.entries

local CATEGORIES: { Common.Category } = { "functions", "widgetMethods", "events", "structures", "enums", "widgets" }

local function emitHeader(ctx: Common.Context, upstream: Common.Input)
	local up = upstream.upstream
	ctx.emit("-- World of Warcraft: Forever API definitions for luau-lsp (requires Luau's new type solver).")
	ctx.emit("-- GENERATED FILE: do not edit. Regenerate with `moon run generator:generate`.")
	ctx.emit("-- Existence: " .. up.resources.repository .. "@" .. up.resources.commit)
	ctx.emit("-- Types:     " .. up.docs.repository .. "@" .. up.docs.commit .. " (Blizzard_APIDocumentationGenerated)")
	ctx.emit("--            " .. up.annotations.repository .. "@" .. up.annotations.commit .. " (MIT licence)")
	ctx.emit("")
end

local function newCounts(): Common.StatusCounts
	return { typed = 0, untyped = 0, excluded = 0 }
end

local function bump(counts: Common.StatusCounts, status: Common.Status)
	if status == "typed" then
		counts.typed += 1
	elseif status == "untyped" then
		counts.untyped += 1
	else
		counts.excluded += 1
	end
end

function Build.run(input: Input): (string, Report, Coverage, ShapeSet)
	local config = input.config
	local parseErrors: { string } = table.clone(input.docs.errors)
	table.move(input.resources.errors, 1, #input.resources.errors, #parseErrors + 1, parseErrors)

	-- Model: each collect stage returns its result.
	local luauGlobals: { [string]: boolean } = {}
	for _, name in config.luauGlobals do
		luauGlobals[name] = true
	end
	local stdTables: { [string]: boolean } = {} -- the Luau tables WoW extends: `string`, `table`, `math`
	for name, target in config.stdlibAliases do
		if name == target then
			stdTables[name] = true
		end
	end
	local ann = Annotations.collect(input.files, stdTables, parseErrors)
	local widgets = Widgets.collect(input.resources, config, input.docs, ann)
	local structs = Structs.collect(input.docs, ann, widgets)
	local names, kinds = Names.claim(input.resources, config, ann, widgets, structs, input.docs.callbacks)

	-- Each category is a map; an empty one must still encode as a JSON object.
	local coverage: Coverage = {
		functions = Json.object({}),
		widgetMethods = Json.object({}),
		events = Json.object({}),
		structures = Json.object({}),
		enums = Json.object({}),
		widgets = Json.object({}),
	}
	local out: { string } = {}
	local ctx: Common.Context = {
		config = config,
		apis = { functions = {}, widgetMethods = {} },
		res = input.resources,
		docs = input.docs,
		reserved = input.reserved,
		coverage = coverage,
		cover = function(
			category: Common.Category,
			name: string,
			status: Common.Status,
			source: string?,
			note: string?
		)
			Common.entries(coverage, category)[name] = { status = status, source = source, note = note }
		end,
		unresolvedTypes = {},
		overridesUsed = {},
		luauGlobals = luauGlobals,
		stdTables = stdTables,
		ann = ann,
		widgets = widgets,
		structs = structs,
		typeNames = names.typeNames,
		typeKinds = kinds :: { [string]: string },
		widgetAliases = names.widgetAliases,
		out = out,
		emit = function(line: string)
			table.insert(out, line)
		end,
	}
	local tree = Globals.collect(ctx)

	-- Output, in file order.
	emitHeader(ctx, input)
	Types.emitEvents(ctx)
	Types.emitAliases(ctx)
	Types.emitEnumValueTypes(ctx)
	local derivedCount, unusedBases = Structs.emit(ctx)
	Widgets.emit(ctx)
	local counts = Globals.emit(ctx, tree)
	local shapes = Shapes.collect(ctx)

	-- Parameter overrides that matched nothing: stale rules. The pipeline rejects them for the real inputs
	-- (the snapshot cases use only a few APIs, so most rules match nothing there).
	local unusedOverrides: { string } = {}
	for _, key in Common.sortedKeys(config.paramTypeOverrides) do
		if not ctx.overridesUsed[key] then
			table.insert(unusedOverrides, key)
		end
	end
	for _, key in Common.sortedKeys(config.resultTypeOverrides) do
		if not ctx.overridesUsed[key] then
			table.insert(unusedOverrides, "resultTypeOverrides." .. key)
		end
	end
	-- Every `number` slot named like an opaque enum (`powerType`, `itemQuality`) must be typed with the enum
	-- (generator/rules/enums.luau) or listed in config.notEnumSlots: otherwise a correct program compares the
	-- enum's value with a number and fails. Such a slot, and a notEnumSlots entry that names nothing, are reported.
	local opaqueEnums: { [string]: string } = {} -- lowercased enum name -> enum name
	for _, e in input.resources.enums do
		if not Common.isNumericEnum(config, e) then
			opaqueEnums[string.lower(e.name)] = e.name
		end
	end
	local slotsSeen: { [string]: boolean } = {}
	local function checkSlot(key: string, name: string?, t: TypeExpr.Type)
		if name == nil then
			return
		end
		local inner = if t.kind == "optional" then t.inner else t
		if inner.kind ~= "name" or inner.name ~= "number" or opaqueEnums[string.lower(name)] == nil then
			return
		end
		local slot = key .. "." .. name
		slotsSeen[slot] = true
		if config.notEnumSlots[slot] == nil then
			table.insert(unusedOverrides, "enum slot typed number: " .. slot)
		end
	end
	local function checkSigs(key: string, sigs: { Signature })
		for _, sig in sigs do
			for _, p in sig.params do
				checkSlot(key, p.name, p.type)
			end
			for i, r in sig.returns do
				checkSlot(key, if sig.returnNames then sig.returnNames[i] else nil, r)
			end
		end
	end
	for _, key in Common.sortedKeys(ctx.apis.functions) do
		checkSigs(key, ctx.apis.functions[key].sigs)
	end
	for _, key in Common.sortedKeys(ctx.apis.widgetMethods) do
		checkSigs(key, ctx.apis.widgetMethods[key].sigs)
	end
	for _, e in input.resources.events do
		local d = ctx.docs.events[e]
		if d then
			local sig: Signature = { params = d.payload, returns = {}, generics = {} }
			checkSigs("event:" .. e, Signatures.applyOverrides(ctx, "event:" .. e, { sig }))
		end
	end
	for _, name in Common.sortedKeys(structs) do
		if structs[name].source == "docs" then
			for _, f in structs[name].fields do
				checkSlot(name, f.name, f.type)
			end
		end
	end
	for _, slot in Common.sortedKeys(config.notEnumSlots) do
		if not slotsSeen[slot] then
			table.insert(unusedOverrides, "notEnumSlots." .. slot)
		end
	end

	local mixinsUnused: { string } = {}
	for _, name in Common.sortedKeys(config.widgetMixins) do
		if not ctx.overridesUsed["widgetMixins." .. name] then
			table.insert(mixinsUnused, name)
			table.insert(unusedOverrides, "widgetMixins." .. name)
		end
	end
	-- Likewise for config.scriptObjectParents: both ends must be documented script objects.
	for _, name in Common.sortedKeys(config.scriptObjectParents) do
		local parent = config.scriptObjectParents[name]
		if ctx.widgets.objectTypes[name] == nil or ctx.widgets.objectTypes[parent] == nil then
			table.insert(unusedOverrides, "scriptObjectParents." .. name)
		end
	end

	for _, rule in unusedBases do
		table.insert(unusedOverrides, rule)
	end

	local summary: { [Common.Category]: Common.StatusCounts } = Json.object({})
	for _, category in CATEGORIES do
		local s = newCounts()
		for _, e in Common.entries(coverage, category) do
			bump(s, e.status)
		end
		summary[category] = s
	end
	local byList: { [string]: Common.StatusCounts } = Json.object({})
	for qualified, list in tree.clientFunctions do
		local e = coverage.functions[qualified]
		if e then
			local s = byList[list] or newCounts()
			bump(s, e.status)
			byList[list] = s
		end
	end
	local unresolved = {}
	for _, name in Common.sortedKeys(ctx.unresolvedTypes) do
		table.insert(unresolved, { name = name, uses = ctx.unresolvedTypes[name] })
	end
	local text = table.concat(out, "\n")
	local _, anyCount = string.gsub(text, "%f[%w_]any%f[^%w_]", "")
	local function occurrences(plain: string): number
		local n, at = 0, 1
		while true do
			local s, e = string.find(text, plain, at, true)
			if s == nil then
				return n
			end
			n += 1
			at = (e :: number) + 1
		end
	end
	local anyTable = occurrences("{ [any]: any }")
	local anyFunction = occurrences("(...any) -> ...any")
	local handlerArgs = occurrences("...any") - 2 * anyFunction
	local report: Report = {
		upstream = input.upstream,
		game = config.gameName,
		summary = summary,
		functionsByClientList = byList,
		counts = {
			annotationFiles = #input.files,
			globalFunctions = counts.functions,
			globalTables = counts.tables,
			globalValues = counts.values,
			structures = Common.count(structs),
			derivedStructures = derivedCount,
			widgets = Common.count(input.resources.widgets),
			scriptObjects = Common.count(widgets.objectTypes),
			widgetMixins = #Common.sortedKeys(config.widgetMixins) - #mixinsUnused,
			anyOccurrences = anyCount,
		},
		anyByForm = {
			anyTable = anyTable,
			anyFunction = anyFunction,
			handlerArgs = handlerArgs,
			other = anyCount - 2 * anyTable - 2 * anyFunction - handlerArgs,
		},
		shapes = Shapes.summary(shapes),
		absentResults = Signatures.absentSummary(ctx),
		unusedOverrides = unusedOverrides,
		parseErrors = parseErrors,
		unresolvedTypes = unresolved,
	}
	return text, report, coverage, shapes
end

return Build
