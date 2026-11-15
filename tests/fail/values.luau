--!strict
-- Structures, enums and nil-safety.

-- A documented structure: misspelt and mistyped fields are errors.
local item = C_Container.GetContainerItemInfo(0, 1)
local _count = item.stackCount -- expect-error: nil
if item then
	local _a: number = item.stackCount
	local _b = item.stackCuont -- expect-error: stackCuont
	local _c: number = item.hyperlink -- expect-error: number
end

-- Enum tables are closed.
local _quality = Enum.ItemQuality.Legendaryy -- expect-error: Legendaryy

-- Quest log info is optional: the index may be out of range.
local quest = C_QuestLog.GetInfo(1)
local _title = quest.title -- expect-error: nil
