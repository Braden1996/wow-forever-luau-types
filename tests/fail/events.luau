--!strict
-- Events: the client's names are a closed union; payloads come from Blizzard's documentation.

local frame = CreateFrame("Frame")

frame:RegisterEvent("PLAYER_LOGN") -- expect-error: '"PLAYER_LOGN"'
frame:UnregisterEvent("PLAYER_LEVEL_UPP") -- expect-error: '"PLAYER_LEVEL_UPP"'

-- Classic Era events the modern Forever client does not send.
frame:RegisterEvent("UNIT_HEALTH_FREQUENT") -- expect-error: '"UNIT_HEALTH_FREQUENT"'

-- A handler checked against the event's documented payload (annotate the parameters: Luau does not
-- infer them through `EventHandler<...>`).
local onLevel: EventHandler<"PLAYER_LEVEL_UP"> = function(level: number)
	local _ = level + 1
end
local onLoaded: EventHandler<"ADDON_LOADED"> = function(addOnName: number) -- expect-error: parameter to be a supertype of `string`, but got `number`
	local _ = addOnName
end
local _ = onLevel
local _ = onLoaded
