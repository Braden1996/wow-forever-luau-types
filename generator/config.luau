--!strict
-- What the generator reads from upstream and how it maps it. Changing this file (or generator/rules/)
-- changes the output: run `moon run generator:generate` and commit the regenerated files with it.

local stdlib = require("./rules/stdlib")
local types = require("./rules/types")
local widgets = require("./rules/widgets")

local config = {
	-- Output files, relative to the repository root.
	output = "definitions/wow-forever.d.luau",
	report = "definitions/report.json",
	-- luau-lsp settings that disable the Luau standard-library globals and members the client lacks
	-- (`luau-lsp.types.disabledGlobals`); editors and `luau-lsp analyze --settings` load it with the definitions.
	settings = "definitions/luau-lsp.settings.json",
	-- The same settings, copied into the addon template (its `check` task passes them to luau-lsp).
	templateSettings = "templates/addon/luau-lsp.settings.json",

	-- Hand-written declarations appended to the output, for globals neither upstream types nor lists
	-- (FrameXML tables such as SlashCmdList). Keep them small and say why each exists.
	supplements = { "supplements/framexml.d.luau" } :: { string },

	-- Per-API coverage (every function, widget method, event, structure, enum and widget: typed,
	-- untyped or excluded with a note) and its human summary.
	coverage = "definitions/coverage.json",
	coverageSummary = "definitions/COVERAGE.md",

	-- The result shape of every function and widget method (generator/stages/shapes.luau), for wrapping libraries.
	shapes = "definitions/api-shapes.json",

	-- The client's own API documentation inside the docs repository (Gethe/wow-ui-source, `forever`).
	docsPath = "Interface/AddOns/Blizzard_APIDocumentationGenerated",

	-- Annotation folders, in priority order: when a global function is annotated twice, the first wins.
	-- Annotations only type what Blizzard's documentation does not. (`Data/Classic.lua` describes the
	-- old Classic client; WoW: Forever runs the modern client, so it gets no priority.)
	sources = {
		"Annotations/Core/Blizzard_APIDocumentationGenerated",
		"Annotations/Core/Data",
		"Annotations/Core/Lua",
		"Annotations/Core/Type",
		"Annotations/Core/Widget",
		"Annotations/Core/ScriptObject",
		"Annotations/Core/FrameXML",
	} :: { string },

	-- Files read from the resources repository's `Resources/` folder (see generator/resources.luau).
	-- An annotated function, widget method, event or enum is emitted only if the WoW: Forever client
	-- has it; a client API with no annotation is emitted untyped.
	resourceFiles = {
		"Events.lua",
		"FrameXML.lua",
		"Frames.lua",
		"GlobalAPI.lua",
		"LuaEnum.lua",
		"Mixins.lua",
		"WidgetAPI.lua",
	} :: { string },
	gameName = "WoW: Forever",

	-- Widgets and script objects (generator/rules/widgets.luau).
	scriptObjectWidgets = widgets.scriptObjectWidgets,
	ignoredScriptObjects = widgets.ignoredScriptObjects,
	docWidgetAliases = widgets.docWidgetAliases,
	widgetParentOverrides = widgets.widgetParentOverrides,
	paramTypeOverrides = widgets.paramTypeOverrides,
	scriptMethods = widgets.scriptMethods,

	-- Type names (generator/rules/types.luau).
	derivedMinFields = types.derivedMinFields,
	basicTypes = types.basicTypes,
	closedAliases = types.closedAliases,
	closedAliasPattern = types.closedAliasPattern,

	-- The standard library (generator/rules/stdlib.luau).
	luauGlobals = stdlib.luauGlobals,
	luauStdlib = stdlib.luauStdlib,
	luauLibraryMembers = stdlib.luauLibraryMembers,
	clientValues = stdlib.clientValues,
	luauConflicts = stdlib.luauConflicts,
	stdlibAliases = stdlib.stdlibAliases,
}

export type Config = typeof(config)

return config
