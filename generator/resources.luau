--!strict
-- Reads Ketho/BlizzardInterfaceResources dumps (Lua table literals) as data. They are parsed with
-- patterns, never executed.

export type Widget = { inherits: { string }, methods: { [string]: boolean } }

export type EnumTable = { name: string, entries: { { key: string, value: string } } }

export type Resources = {
	globalApi: { [string]: boolean }, -- C API functions, "UnitLevel", "C_Timer.After"
	luaApi: { [string]: boolean }, -- Lua and WoW Lua-library functions, "strsplit", "table.wipe"
	frameXml: { [string]: boolean }, -- FrameXML functions, "StaticPopup_Show", "ChatFrameUtil.AddMessageEventFilter"
	frames: { [string]: boolean }, -- named global frames, "UIParent"
	mixins: { [string]: boolean }, -- global mixin tables
	events: { string },
	widgets: { [string]: Widget },
	enums: { EnumTable }, -- Enum.*
	constants: { EnumTable }, -- Constants.*
	globalConstants: { { key: string, value: string } }, -- LE_* and NUM_LE_*
}

local Resources = {}

local function strings(source: string, into: { [string]: boolean })
	for name in string.gmatch(source, '"([^"]+)"') do
		into[name] = true
	end
end

-- A `return {A, B}` file: the first table is the main list, the second its load-on-demand part.
local function splitSections(source: string): { string }
	local sections = {}
	for body in string.gmatch(source, "\nlocal [%w_]+ = (%b{})") do
		table.insert(sections, body)
	end
	local first = string.match(source, "^local [%w_]+ = (%b{})")
	if first then
		table.insert(sections, 1, first)
	end
	return sections
end

-- `Name = { Key = value, ... }` blocks one level inside `Outer = { ... }`.
local function nestedTables(source: string, outer: string): { EnumTable }
	local body = string.match(source, "\n" .. outer .. " = (%b{})") or string.match(source, "^" .. outer .. " = (%b{})")
	local out = {}
	if body == nil then
		return out
	end
	for name, inner in string.gmatch(body :: string, "\n\t([%w_]+) = (%b{})") do
		local entries = {}
		for line in string.gmatch(inner :: string, "[^\n]+") do
			local key, value = string.match(line, "^\t\t([%w_]+) = (.-),?$")
			if key then
				table.insert(entries, { key = key, value = value :: string })
			end
		end
		table.insert(out, { name = name :: string, entries = entries })
	end
	return out
end

function Resources.parse(files: { [string]: string }): Resources
	local r: Resources = {
		globalApi = {},
		luaApi = {},
		frameXml = {},
		frames = {},
		mixins = {},
		events = {},
		widgets = {},
		enums = {},
		constants = {},
		globalConstants = {},
	}

	local api = splitSections(files["GlobalAPI.lua"])
	strings(api[1], r.globalApi)
	strings(api[2] or "", r.luaApi)
	for _, section in splitSections(files["FrameXML.lua"]) do
		strings(section, r.frameXml)
	end
	for _, section in splitSections(files["Frames.lua"]) do
		strings(section, r.frames)
	end
	strings(files["Mixins.lua"], r.mixins)

	local events: { [string]: boolean } = {}
	strings(files["Events.lua"], events)
	for name in events do
		table.insert(r.events, name)
	end
	table.sort(r.events)

	-- WidgetAPI: `\tName = {\n\t\tinherits = {"A"},\n\t\tmethods = {\n\t\t\t"M",`
	for name, body in string.gmatch(files["WidgetAPI.lua"], "\n\t([%w_]+) = (%b{})") do
		local inherits = {}
		local inheritList = string.match(body :: string, "inherits = (%b{})")
		if inheritList then
			for parent in string.gmatch(inheritList, '"([^"]+)"') do
				table.insert(inherits, parent)
			end
		end
		local methods = {}
		local methodList = string.match(body :: string, "methods = (%b{})")
		if methodList then
			strings(methodList, methods)
		end
		r.widgets[name :: string] = { inherits = inherits, methods = methods }
	end

	local enumSource = "\n" .. files["LuaEnum.lua"]
	r.enums = nestedTables(enumSource, "Enum")
	r.constants = nestedTables(enumSource, "Constants")
	for key, value in string.gmatch(enumSource, "\n([%u_][%u%d_]*) = ([^\n]+)") do
		table.insert(r.globalConstants, { key = key :: string, value = value :: string })
	end
	return r
end

return Resources
