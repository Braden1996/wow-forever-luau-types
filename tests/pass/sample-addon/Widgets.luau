--!strict
-- Everyday widget calls that must type-check: texture file IDs, typed animations, font names, formatted text and
-- attributes of any value.

local frame = CreateFrame("Frame", nil, UIParent)

local icon = frame:CreateTexture(nil, "ARTWORK")
icon:SetTexture(134400)
icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark", "CLAMP", "CLAMP", "LINEAR")
icon:SetBlendMode("ADD")

local group = frame:CreateAnimationGroup()
local fade = group:CreateAnimation("Alpha")
fade:SetFromAlpha(0)
fade:SetToAlpha(1)
local plain = group:CreateAnimation()
plain:SetDuration(0.5)

local label = frame:CreateFontString(nil, "OVERLAY")
label:SetFontObject("GameFontNormal")
label:SetFormattedText("%d of %d", 1, 2)

frame:SetAttribute("showRaid", true)
frame:SetAttribute("unit", nil)
local unit = frame:GetAttribute("unit")
if type(unit) == "string" then
	label:SetText(unit)
end

local curve = C_CurveUtil.CreateCurve()
curve:SetType(Enum.LuaCurveType.Linear)

-- An input-only structure leaves out the fields the documentation gives a default.
local talent = C_SpecializationInfo.GetTalentInfo({ tier = 1, column = 2 })
if talent then
	label:SetText(talent.name)
end
