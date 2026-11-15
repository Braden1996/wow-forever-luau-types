--!strict
-- Every line marked `expect-error` must produce an error whose text contains the given phrase, and no
-- other line may produce one. `lune run scripts/test` enforces both.

local frame = CreateFrame("Frame")

frame:RegisterEvent("PLAYER_LOGN") -- expect-error: "PLAYER_LOGN"
frame:SetPoint("CENTRE") -- expect-error: "CENTRE"
frame:SetScript("OnClick", function() end) -- expect-error: "OnClick"
frame:SetText("not a button") -- expect-error: SetText
local _bad = CreateFrame("Fraem") -- expect-error: "Fraem"

local _button: Button = CreateFrame("Frame") -- expect-error: Button

local _level: string = UnitLevel("player") -- expect-error: string
local _name: number = UnitName("player") -- expect-error: number
UnitXP(42) -- expect-error: number

C_Timer.After(5) -- expect-error: argument
C_Timer.Afterr(5, function() end) -- expect-error: Afterr

local _quality = Enum.ItemQuality.Legendaryy -- expect-error: Legendaryy

-- APIs the WoW: Forever client does not have are filtered out (arena teams are a TBC feature).
ArenaTeamDisband() -- expect-error: ArenaTeamDisband
NotARealWowApi() -- expect-error: NotARealWowApi

-- Classic Era globals that the WoW: Forever client replaced with C_ namespaces.
GetQuestLogTitle(1) -- expect-error: GetQuestLogTitle
local _info = GetItemInfo(6948) -- expect-error: GetItemInfo
