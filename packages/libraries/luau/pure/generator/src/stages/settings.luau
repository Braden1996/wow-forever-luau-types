--!strict
-- definitions/luau-lsp.settings.json: the Luau standard library the WoW: Forever client lacks. The standard
-- platform declares all of Luau's library (`buffer`, `string.pack`, `typeof`, ...), and a definitions file can
-- only add names, so luau-lsp would accept code that fails in game. `luau-lsp.types.disabledGlobals` removes
-- them: a library table the client has none of goes whole (`os`), otherwise each missing member does.

local Json = require("../json")
local Resources = require("../resources")
local Common = require("./common")

local Settings = {}

local KEY = "luau-lsp.types.disabledGlobals"

-- The sorted names to disable.
function Settings.disabledGlobals(res: Resources.Resources, config: Common.Config): { string }
	local function inClient(name: string): boolean
		return res.luaApi[name] or res.globalApi[name] or res.frameXml[name] or config.clientValues[name] or false
	end
	local members: { [string]: { string } } = {}
	for _, name in config.luauLibraryMembers do
		local lib = string.match(name, "^([%w_]+)%.") :: string
		members[lib] = members[lib] or {}
		table.insert(members[lib], name)
	end
	local out = {}
	for _, global in config.luauGlobals do
		local libMembers = members[global]
		if libMembers == nil then
			if not inClient(global) then
				table.insert(out, global)
			end
			continue
		end
		local missing = {}
		for _, name in libMembers do
			if not inClient(name) then
				table.insert(missing, name)
			end
		end
		if #missing == #libMembers then
			table.insert(out, global)
		else
			table.move(missing, 1, #missing, #out + 1, out)
		end
	end
	for lib in members do
		assert(table.find(config.luauGlobals, lib), "rules/stdlib.luau: library " .. lib .. " is not in luauGlobals")
	end
	table.sort(out)
	return out
end

-- The settings file's text.
function Settings.json(res: Resources.Resources, config: Common.Config): string
	return Json.encode({ [KEY] = Settings.disabledGlobals(res, config) }) .. "\n"
end

return Settings
