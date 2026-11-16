--!strict
-- Enum values: compared with each other, used as table keys, passed back to the client.

local qualityNames: { [Enum_ItemQuality]: string } = {
	[Enum.ItemQuality.Poor] = "grey",
	[Enum.ItemQuality.Epic] = "purple",
}

local quality = C_Item.GetItemQualityByID(19019)
if quality and quality >= Enum.ItemQuality.Rare then
	local r, g, b = C_Item.GetItemQualityColor(quality)
	print(qualityNames[quality], r, g, b)
end
if quality == Enum.ItemQuality.Legendary then
	print("legendary")
end

-- Flag enums and container IDs stay numbers.
local slots = C_Container.GetContainerNumSlots(Enum.BagIndex.Backpack)
for bag = 0, 4 do
	print(C_Container.GetContainerNumSlots(bag), slots)
end

-- Results the documentation types as a number carry the enum where they hold its values.
local _icon, _name, _count, _currencyID, lootQuality = GetLootSlotInfo(1)
if lootQuality >= Enum.ItemQuality.Uncommon then
	print(UnitPower("player", Enum.PowerType.Mana))
end
LoadBindings(GetCurrentBindingSet())

-- Expansion levels stay numbers: they are ordinals.
if GetExpansionLevel() >= 0 then
	print(GetMaxLevelForExpansionLevel(GetExpansionLevel()))
end
