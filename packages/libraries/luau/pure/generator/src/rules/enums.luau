--!strict
-- Enum rules: which client enums are opaque types, and the API slots that carry an enum's values where the
-- documentation says only `number`. Part of generator/config.luau (assembled there).
--
-- Each non-flag enum is an opaque type (`Enum_ItemQuality`): a function that takes one accepts only that enum's
-- values, never a bare number or another enum's value. For that to hold, every slot that carries the enum's
-- values must say so, or a correct program would compare an `Enum_ItemQuality` with a `number` and fail. The
-- documentation types most of them; the rest are below. build.luau checks that every `number` slot named like an
-- opaque enum (`powerType`, `itemQuality`) is either typed here or listed in notEnumSlots with the reason.

-- Enums whose values are bit flags stay plain numbers, because addons combine and test them with bit.band. An
-- enum is a flag set when the client's dump writes its values in hex (it does so for every mask) or its name
-- matches one of these patterns (ClubFinderSettingFlags, Itemsetflags, SoftTargetEnableFlags are decimal).
local flagEnumPatterns: { string } = { "[Ff]lag", "Mask$" }

-- Enums whose values are plain integers in the API's own use, so they stay numbers too.
local numericEnums: { [string]: boolean } = {
	-- Container IDs are iterated as a range (`for bag = 0, NUM_BAG_SLOTS do`).
	BagIndex = true,
	-- Expansion levels are ordinals: GetExpansionLevel, GetMaximumExpansionLevel and six more return a number,
	-- the LE_EXPANSION_* globals are numbers, and addons compare them with `>=`.
	ExpansionLevel = true,
	-- Mythic+ season IDs are counters (C_MythicPlus.GetCurrentSeason returns a number), used as table keys.
	SeasonID = true,
}

-- Arguments the documentation types as `number` that take an enum's values, keyed like
-- config.paramTypeOverrides ("Function", "Widget:Method", "event:NAME").
local enumParams: { [string]: { [string]: string } } = {
	EJ_GetInvTypeSortOrder = { invType = "Enum.InventoryType" },
	GetPowerRegenForPowerType = { powerType = "Enum.PowerType" },
	LoadBindings = { bindingSet = "Enum.BindingSet" },
	["C_Item.GetFirstTriggeredSpellForItem"] = { itemQuality = "Enum.ItemQuality" },
	["C_ItemUpgrade.GetHighWatermarkForSlot"] = { itemRedundancySlot = "Enum.ItemRedundancySlot" },
	["C_TooltipInfo.GetItemByID"] = { quality = "Enum.ItemQuality" },
	["C_Transmog.GetSlotForInventoryType"] = { inventoryType = "Enum.InventoryType" },
	["C_TransmogOutfitInfo.GetTransmogOutfitSlotForInventoryType"] = { inventoryType = "Enum.InventoryType" },
	["event:CONFIRM_SUMMON"] = { summonReason = "Enum.SummonReason" },
	["event:CONFIRM_TALENT_WIPE"] = { respecType = "Enum.RespecType" },
	["event:GARRISON_BUILDING_ACTIVATABLE"] = { garrisonType = "Enum.GarrisonType" },
}

-- Results the documentation types as `number` that are an enum's values, by result position.
local enumResults: { [string]: { [number]: string } } = {
	GetCurrentBindingSet = { [1] = "Enum.BindingSet" },
	GetGuildBankItemInfo = { [5] = "Enum.ItemQuality" },
	GetInboxItem = { [5] = "Enum.ItemQuality" },
	GetLootRollItemInfo = { [4] = "Enum.ItemQuality" },
	GetLootSlotInfo = { [5] = "Enum.ItemQuality" },
	GetQuestLogRewardInfo = { [4] = "Enum.ItemQuality" },
	GetTradeTargetItemInfo = { [4] = "Enum.ItemQuality" },
	["C_ArtifactUI.GetArtifactInfo"] = { [7] = "Enum.ItemQuality" },
	["C_ArtifactUI.GetEquippedArtifactInfo"] = { [7] = "Enum.ItemQuality" },
	["C_ArtifactUI.GetRespecArtifactInfo"] = { [7] = "Enum.ItemQuality" },
	["C_BlackMarket.GetHotItem"] = { [17] = "Enum.ItemQuality" },
	["C_BlackMarket.GetItemInfoByID"] = { [17] = "Enum.ItemQuality" },
	["C_BlackMarket.GetItemInfoByIndex"] = { [17] = "Enum.ItemQuality" },
	["C_Garrison.GetGarrisonTalentTreeType"] = { [1] = "Enum.GarrTalentTreeType" },
	["C_Garrison.GetLandingPageShipmentInfo"] = { [11] = "Enum.ItemQuality" },
	["C_ItemUpgrade.GetHighWatermarkSlotForItem"] = { [1] = "Enum.ItemRedundancySlot" },
	["C_SummonInfo.GetSummonReason"] = { [1] = "Enum.SummonReason" },
}

-- `number` slots named like an opaque enum that do not carry its values: "<key>.<name>" -> why.
local notEnumSlots: { [string]: string } = {
	["C_CurrencyInfo.GetBasicCurrencyInfo.currencyType"] = "a currency ID",
	["C_CurrencyInfo.GetCurrencyContainerInfo.currencyType"] = "a currency ID",
	["C_CurrencyInfo.SetCurrencyBackpackByID.currencyType"] = "a currency ID",
	["C_TradeSkillUI.GetConcentrationCurrencyID.currencyType"] = "a currency ID",
	["CraftingOrderRewardInfo.currencyType"] = "a currency ID",
	["CurrencyTransferTransaction.currencyType"] = "a currency ID",
	["GarrisonTalentCurrencyCostInfo.currencyType"] = "a currency ID",
	["PVPPostMatchCurrencyReward.currencyType"] = "a currency ID",
	["VendorTrackingInfo.currencyType"] = "a currency ID",
	["event:CURRENCY_DISPLAY_UPDATE.currencyType"] = "a currency ID",
	["GetCompanionInfo.mountType"] = "the companion's mount flags, not one Enum.MountType value",
}

return {
	flagEnumPatterns = flagEnumPatterns,
	numericEnums = numericEnums,
	enumParams = enumParams,
	enumResults = enumResults,
	notEnumSlots = notEnumSlots,
}
