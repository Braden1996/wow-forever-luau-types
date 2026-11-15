--!strict
-- Events: each handler is checked against its event's documented payload, and only events the client sends can
-- be registered.

local ADDON: string, ns: MyAddonNamespace = ...

local onAddonLoaded: EventHandler<"ADDON_LOADED"> = function(addOnName: string)
	if addOnName == ADDON then
		ns.load()
	end
end

local onLevelUp: EventHandler<"PLAYER_LEVEL_UP"> = function(level: number)
	ns.print(format("Reached level %d", level))
end

local handlers: { [FrameEvent]: (...any) -> () } = {
	ADDON_LOADED = onAddonLoaded,
	PLAYER_LEVEL_UP = onLevelUp,
}

local frame = CreateFrame("Frame")
for event in pairs(handlers) do
	frame:RegisterEvent(event)
end
frame:SetScript("OnEvent", function(_self: Frame, event: FrameEvent, ...: any)
	local handler = handlers[event]
	if handler then
		handler(...)
	end
end)
