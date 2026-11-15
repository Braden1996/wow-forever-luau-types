--!strict
-- What the generator reads from upstream and how it maps it. Changing this file changes the output:
-- run `lune run scripts/generate` and commit the regenerated definitions with it.

return {
	-- Output file, relative to the repository root.
	output = "definitions/wow-forever.d.luau",
	report = "definitions/report.json",

	-- Hand-written declarations appended to the output, for globals neither upstream types nor lists
	-- (FrameXML tables such as SlashCmdList). Keep them small and say why each exists.
	supplements = { "supplements/framexml.d.luau" },

	-- Annotation folders, in priority order: when a global function is annotated twice, the first wins.
	-- Blizzard's generated API documentation comes first. (`Data/Classic.lua` describes the old Classic
	-- client; WoW: Forever runs the modern client, so it gets no priority.)
	sources = {
		"Annotations/Core/Blizzard_APIDocumentationGenerated",
		"Annotations/Core/Data",
		"Annotations/Core/Lua",
		"Annotations/Core/Type",
		"Annotations/Core/Widget",
		"Annotations/Core/ScriptObject",
		"Annotations/Core/FrameXML",
	},

	-- Classes defined under these folders are widgets: they become `declare extern type`s with
	-- inheritance. Every other class becomes a structural table type.
	externSources = {
		"Annotations/Core/Widget",
		"Annotations/Core/ScriptObject",
	},

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
	},
	gameName = "WoW: Forever",

	-- String-literal aliases emitted as closed unions (a typo is a type error). Other aliases that list
	-- suggested values but are based on `string` stay `string`, because their lists are retail-only
	-- and incomplete for Classic.
	closedAliases = {
		AnimationType = true,
		DrawLayer = true,
		FrameEvent = true,
		FramePoint = true,
		FrameStrata = true,
		FrameType = true,
		JustifyHorizontal = true,
		JustifyVertical = true,
	},
	-- Every widget script-handler alias (`ScriptFrame`, `ScriptButton`, ...) is closed too.
	closedAliasPattern = "^Script",

	-- Globals the Luau standard platform already declares; upstream's Lua 5.1 annotations for them are
	-- skipped. Functions on these tables (`string.split`, `table.wipe`) are still indexed so the WoW
	-- aliases that point at them (`strsplit`, `wipe`) get their signatures.
	luauGlobals = {
		"_G",
		"_VERSION",
		"assert",
		"bit32",
		"buffer",
		"coroutine",
		"debug",
		"error",
		"gcinfo",
		"getfenv",
		"getmetatable",
		"ipairs",
		"loadstring",
		"math",
		"newproxy",
		"next",
		"os",
		"pairs",
		"pcall",
		"print",
		"rawequal",
		"rawget",
		"rawlen",
		"rawset",
		"require",
		"select",
		"setfenv",
		"setmetatable",
		"string",
		"table",
		"tonumber",
		"tostring",
		"type",
		"typeof",
		"unpack",
		"utf8",
		"vector",
		"xpcall",
	},

	-- Local names upstream's compat.lua uses for the standard tables.
	stdlibAliases = { tab = "table", str = "string", math = "math", string = "string", table = "table" },
}
