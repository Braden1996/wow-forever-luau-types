--!strict
-- Typed event dispatch: each handler is checked against its event's documented payload, and only
-- real event names can be registered.

local _, ns: Namespace = ...

local onMoney: EventHandler<"PLAYER_MONEY"> = function()
	ns.money = GetMoney()
end

local onLevel: EventHandler<"PLAYER_LEVEL_UP"> = function(level: number)
	ns.onPlayerLevel(level)
end

local onBag: EventHandler<"BAG_UPDATE"> = function(bagIndex: number)
	ns.dirtyBags[bagIndex] = true
end

local dispatch: { [FrameEvent]: (...any) -> () } = {
	PLAYER_MONEY = onMoney,
	PLAYER_LEVEL_UP = onLevel,
	BAG_UPDATE = onBag,
}

local frame = CreateFrame("Frame")
for event in pairs(dispatch) do
	frame:RegisterEvent(event)
end
frame:SetScript("OnEvent", function(_self: Frame, event: FrameEvent, ...: any)
	local handler = dispatch[event]
	if handler then
		handler(...)
	end
end)

-- CreateFrame returns the widget the frame type names; its script names are its own.
local check: CheckButton = CreateFrame("CheckButton", nil, UIParent, "UICheckButtonTemplate")
check:SetChecked(true)
check:SetScript("OnClick", function(self: CheckButton)
	ns.enabled = self:GetChecked()
end)
