--!strict
-- The first file in the .toc: fills in the shared namespace (its type is in addon.d.luau) that other files extend.

local ADDON: string, ns: Namespace = ...

ns.name = ADDON
ns.version = "0.1.0"
ns.money = 0
ns.dirtyBags = {}
ns.enabled = true

-- A fresh table each call: Lua 5.1 has no table.clone (a Luau addition WoW lacks).
local function defaults(): SampleDB
	return { enabled = true, runs = 0, lastZone = nil }
end

function ns.print(message: string)
	DEFAULT_CHAT_FRAME:AddMessage(format("|cff33ff99%s|r: %s", ADDON, message))
end

function ns.onPlayerLevel(level: number)
	local xp, xpMax = UnitXP("player"), UnitXPMax("player")
	local percent = if xpMax > 0 then floor(xp / xpMax * 100) else 0
	ns.print(format("level %d, %d%% of the way to %d", level, percent, level + 1))
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
events:SetScript("OnEvent", function(_self: Frame, event: string, ...: any)
	if event == "ADDON_LOADED" then
		local loaded: string = ...
		if loaded ~= ADDON then
			return
		end
		local saved = SampleAddonDB or defaults()
		saved.runs += 1
		_G.SampleAddonDB = saved -- declared globals are read-only in Luau; write through _G
		ns.db = saved
		ns.print(format("loaded (run %d)", saved.runs))
	elseif event == "PLAYER_LEVEL_UP" then
		local level: number = ...
		ns.onPlayerLevel(level)
	elseif event == "ZONE_CHANGED_NEW_AREA" then
		local db = ns.db
		if db then
			db.lastZone = GetRealZoneText()
		end
	end
end)
