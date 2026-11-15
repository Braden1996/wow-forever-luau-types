--!strict
-- Widgets: the client's hierarchy, per-widget script names and the generic CreateFrame.

local frame = CreateFrame("Frame")
local button = CreateFrame("Button")

-- Methods exist only where the client has them.
frame:SetText("not a button") -- expect-error: SetText
local _bad = CreateFrame("Fraem") -- expect-error: Fraem

-- Inheritance runs one way: a Button is a Frame, a Frame is not a Button.
local _asFrame: Frame = button
local _asButton: Button = frame -- expect-error: Button

-- Script names are the widget's own: a plain Frame has no OnClick, a Button does.
frame:SetScript("OnClick", function() end) -- expect-error: OnClick
button:SetScript("OnClick", function() end)
frame:SetScript("OnUpdte", function() end) -- expect-error: OnUpdte

-- Closed string unions for anchor points, strata and draw layers.
frame:SetPoint("CENTRE") -- expect-error: CENTRE
frame:SetFrameStrata("HIGHEST") -- expect-error: HIGHEST
