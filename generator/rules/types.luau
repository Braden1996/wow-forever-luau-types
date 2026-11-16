--!strict
-- Type-name rules: basic types the documentation leaves undefined, which string aliases are closed unions,
-- and when a structure is derived from another. Part of generator/config.luau (assembled there).

-- A documented structure is declared as `Base & { ... }` when it contains every field of another
-- documented structure with at least this many fields.
local derivedMinFields: number = 3

-- Basic types Blizzard's documentation uses without defining (after annotation aliases are tried).
local basicTypes: { [string]: string } = {
	cstring = "string",
	stringView = "string",
	luaIndex = "number",
	uiUnit = "number",
	size = "number",
	time_t = "number",
	BigInteger = "number",
	BigUInteger = "number",
	WOWGUID = "string",
	WOWMONEY = "number",
	fileID = "number",
	textureKit = "string",
	textureAtlas = "string",
	FileAsset = "string",
	normalizedValue = "number",
	SingleColorValue = "number",
	LuaValueReference = "unknown",
	LuaFunctionReference = "(...any) -> ...any",
	Milliseconds = "number",
	Seconds = "number",
	kstringAuroraName = "string",
	kstringLfgListChat = "string",
	KStringDiscordUserName = "string",
	UnitTokenVariant = "string",
	ScriptTypeName = "string",
	FontAsset = "string",
}

-- Type names the documentation uses for a value of another type, resolved before anything else declares
-- the name. The Forever documentation types unit tokens (`RegisterUnitEvent`'s units, the
-- NAME_PLATE_UNIT_ADDED payload) as the `UnitTokenType` enumeration, but the client passes and takes the
-- token strings ("player", "nameplate1"), as the annotations and Blizzard's own UI code do.
--
-- The rest are opaque in the documentation, which declares no type for them: the annotations type the
-- same positions `number` (voice channel and member IDs, cast bar IDs); a DurationTextBinding is the
-- DurationTextBindingObject its own `Assign` and `Copy` take and return; a LuaValueVariant is any Lua
-- value (the annotations' `table` alias would reject numbers and functions).
local docTypeOverrides: { [string]: string } = {
	UnitTokenType = "UnitToken",
	VoiceChatID = "number",
	ClubMemberOpaqueId = "number",
	UnitCastBarID = "number",
	DurationTextBinding = "DurationTextBindingObject",
	LuaValueVariant = "unknown",
}

-- String-literal aliases emitted as closed unions (a typo is a type error). Other aliases that list
-- suggested values but are based on `string` stay `string`, because their lists are retail-only
-- and incomplete for the Forever client. (FrameEvent is not listed: the generator builds it from the
-- client's own event list.)
--
-- The widget constants below are closed too: the client's own C code defines them and the annotations list
-- them in full (Annotations/Core/Widget/UIType/UIType.lua). TBFFlags (combinable flags), MouseButton and
-- ClickButton (Button6 and up, modifier prefixes) and UnitToken (numbered tokens) stay open.
local closedAliases: { [string]: boolean } = {
	AnimationType = true,
	BlendMode = true,
	CurveType = true,
	DrawLayer = true,
	FilterMode = true,
	FontAlphabet = true,
	InsertMode = true,
	LoopType = true,
	Orientation = true,
	SimpleButtonStateToken = true,
	SmoothingType = true,
	WrapMode = true,
	FramePoint = true,
	FrameStrata = true,
	FrameType = true,
	JustifyHorizontal = true,
	JustifyVertical = true,
}
-- Every widget script-handler alias (`ScriptFrame`, `ScriptButton`, ...) is closed too.
local closedAliasPattern: string = "^Script"

return {
	derivedMinFields = derivedMinFields,
	basicTypes = basicTypes,
	docTypeOverrides = docTypeOverrides,
	closedAliases = closedAliases,
	closedAliasPattern = closedAliasPattern,
}
