--!strict
-- Widgets: frames, buttons, font strings, tooltips, timers, hooks and slash commands.

local ADDON: string, ns = ...

local panel = CreateFrame("Frame", "SampleAddonPanel", UIParent, "BackdropTemplate")
panel:SetSize(240, 120)
panel:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
panel:SetFrameStrata("DIALOG")
panel:EnableMouse(true)
panel:SetMovable(true)
panel:RegisterForDrag("LeftButton")
panel:SetScript("OnDragStart", function(self: Frame)
	self:StartMoving()
end)
panel:SetScript("OnDragStop", function(self: Frame)
	self:StopMovingOrSizing()
end)
panel:Hide()
tinsert(UISpecialFrames, "SampleAddonPanel")

local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", 0, -12)
title:SetText(ADDON)

local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
button:SetSize(120, 24)
button:SetPoint("BOTTOM", 0, 12)
button:SetText("Close")
button:SetScript("OnClick", function()
	panel:Hide()
end)
button:SetScript("OnEnter", function(self: Button)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:AddLine("Close the panel", 1, 1, 1)
	if IsShiftKeyDown() then
		GameTooltip:AddLine(format("Shown at %.1f s", GetTime()))
	end
	GameTooltip:Show()
end)
button:SetScript("OnLeave", function()
	GameTooltip:Hide()
end)

local bar = CreateFrame("StatusBar", nil, panel)
bar:SetSize(200, 12)
bar:SetPoint("CENTER")
bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
bar:SetMinMaxValues(0, 1)

local ticker = C_Timer.NewTicker(1, function()
	if UnitExists("player") and not UnitAffectingCombat("player") then
		bar:SetValue(UnitXP("player") / math.max(UnitXPMax("player"), 1))
	end
end)

C_Timer.After(5, function()
	local name = UnitName("player")
	local _, class = UnitClass("player")
	ns.print(format("%s the %s is level %d", name, class, UnitLevel("player")))
end)

hooksecurefunc("ToggleGameMenu", function()
	panel:Hide()
end)

_G.SLASH_SAMPLEADDON1 = "/sample"
_G.SLASH_SAMPLEADDON2 = "/sa"
SlashCmdList.SAMPLEADDON = function(msg: string)
	local command = strlower(strtrim(msg))
	if command == "stop" then
		ticker:Cancel()
	elseif panel:IsShown() then
		panel:Hide()
	else
		panel:Show()
	end
end
