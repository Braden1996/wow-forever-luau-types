--!strict
-- BlizzardInterfaceResources dumps (resources.luau).

local Resources = require("./resources")
local SpecCase = require("./spec-case")

local GLOBAL_API = 'local GlobalAPI = {\n\t"CreateFrame",\n\t"C_Timer.After",\n}\n\n'
	.. 'local LuaAPI = {\n\t"strsplit",\n}\n\nreturn {GlobalAPI, LuaAPI}\n'
local WIDGET_API = 'local WidgetAPI = {\n\tFrame = {\n\t\tinherits = {"Region"},\n'
	.. '\t\tmethods = {\n\t\t\t"Show",\n\t\t},\n\t\thandlers = {\n\t\t\t"OnShow",\n\t\t},\n\t},\n}\n'
local LUA_ENUM = "Enum = {\n\tAccountData = {\n\t\tConfig = 0,\n\t\tBindings = 2,\n\t},\n}\n\n"
	.. "Constants = {\n\tLevels = {\n\t\tMax = 60,\n\t},\n}\n"

local cases: { SpecCase.Case } = {
	{
		name = "a full set of dumps parses without errors",
		run = function()
			local r = Resources.parse({
				["GlobalAPI.lua"] = GLOBAL_API,
				["WidgetAPI.lua"] = WIDGET_API,
				["LuaEnum.lua"] = LUA_ENUM,
				["Events.lua"] = 'local Events = {\n\t"PLAYER_LOGIN",\n\t"ADDON_LOADED",\n}\n',
				["FrameXML.lua"] = 'local FrameXML = {\n\t"StaticPopup_Show",\n}\n',
				["Frames.lua"] = 'local Frames = {\n\t"UIParent",\n}\n',
			})
			local actual = {
				globalApi = r.globalApi,
				luaApi = r.luaApi,
				frameXml = r.frameXml,
				frames = r.frames,
				events = r.events,
				widgets = r.widgets,
				enums = r.enums,
				constants = r.constants,
				errors = r.errors,
			}
			return actual,
				{
					globalApi = { CreateFrame = true, ["C_Timer.After"] = true },
					luaApi = { strsplit = true },
					frameXml = { StaticPopup_Show = true },
					frames = { UIParent = true },
					events = { "ADDON_LOADED", "PLAYER_LOGIN" },
					widgets = {
						Frame = { inherits = { "Region" }, methods = { Show = true }, handlers = { "OnShow" } },
					},
					enums = {
						{
							name = "AccountData",
							entries = { { key = "Config", value = "0" }, { key = "Bindings", value = "2" } },
						},
					},
					constants = { { name = "Levels", entries = { { key = "Max", value = "60" } } } },
					errors = {},
				}
		end,
	},
	{
		name = "a dump without its section is reported",
		run = function()
			local r = Resources.parse({
				["GlobalAPI.lua"] = "local GlobalAPI = {\n}\n",
				["WidgetAPI.lua"] = "return {}\n",
				["Events.lua"] = "local Events = {}\n",
			})
			return r.errors,
				{
					"resources GlobalAPI.lua: no GlobalAPI and LuaAPI tables",
					"resources Events.lua: no event names",
					"resources WidgetAPI.lua: no widget tables",
				}
		end,
	},
}

return SpecCase.specs(cases)
