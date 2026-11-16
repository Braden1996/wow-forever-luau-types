--!strict
-- Widgets: the client's hierarchy, per-widget script names and the generic CreateFrame.

local frame = CreateFrame("Frame")
local button = CreateFrame("Button")

-- Methods exist only where the client has them.
frame:SetText("not a button") -- expect-error: Key 'SetText' not found in external type 'Frame'
local _bad = CreateFrame("Fraem") -- expect-error: Property '"Fraem"' does not exist on type 'FrameTypeMap'

-- Inheritance runs one way: a Button is a Frame, a Frame is not a Button.
local _asFrame: Frame = button
local _asButton: Button = frame -- expect-error: Expected this to be 'Button', but got 'Frame'

-- Script names are the widget's own: a plain Frame has no OnClick, a Button does.
frame:SetScript("OnClick", function() end) -- expect-error: but got '"OnClick"'
button:SetScript("OnClick", function() end)
frame:SetScript("OnUpdte", function() end) -- expect-error: but got '"OnUpdte"'

-- Closed string unions for anchor points, strata and draw layers.
frame:SetPoint("CENTRE") -- expect-error: but got '"CENTRE"'
frame:SetFrameStrata("HIGHEST") -- expect-error: but got '"HIGHEST"'

-- Widget constants the client defines in full are closed too.
local texture = frame:CreateTexture()
texture:SetBlendMode("ADDD") -- expect-error: but got '"ADDD"'
texture:SetTexture(134400, "CLAMPP") -- expect-error: but got '"CLAMPP"'

-- CreateAnimation returns the animation type it names, and only real types.
local group = frame:CreateAnimationGroup()
group:CreateAnimation("Alhpa") -- expect-error: None of the overloads

-- HookScript needs a handler; event callbacks take only real events.
frame:HookScript("OnShow", nil) -- expect-error: but got 'nil'
frame:RegisterEventCallback("PLAYER_LOGN", function() end) -- expect-error: Expected this to be
