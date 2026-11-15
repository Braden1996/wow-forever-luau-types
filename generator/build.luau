--!strict
-- Merges the three inputs into one luau-lsp definitions file plus a coverage record:
--   the client dump      decides what EXISTS (functions, widgets and their methods, events, enums)
--   Blizzard's API docs  give types first (functions, widget methods, event payloads, structures)
--   LuaCATS annotations  give types for the rest (wiki-documented globals, FrameXML, Lua extensions)
-- Anything the client has but no source types is declared `(...unknown) -> ...unknown`.
-- The stages live in generator/stages/; this file runs them in order and assembles the report.

local Annotations = require("./stages/annotations")
local Common = require("./stages/common")
local Globals = require("./stages/globals")
local Json = require("./json")
local Names = require("./stages/names")
local Shapes = require("./stages/shapes")
local Structs = require("./stages/structs")
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
	local derivedCount = Structs.emit(ctx)
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
			anyOccurrences = anyCount,
		},
		anyByForm = {
			anyTable = anyTable,
			anyFunction = anyFunction,
			handlerArgs = handlerArgs,
			other = anyCount - 2 * anyTable - 2 * anyFunction - handlerArgs,
		},
		shapes = Shapes.summary(shapes),
		unusedOverrides = unusedOverrides,
		parseErrors = parseErrors,
		unresolvedTypes = unresolved,
	}
	return text, report, coverage, shapes
end

return Build
