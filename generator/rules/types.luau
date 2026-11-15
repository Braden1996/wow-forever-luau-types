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
	LuaValueVariant = "unknown",
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

-- String-literal aliases emitted as closed unions (a typo is a type error). Other aliases that list
-- suggested values but are based on `string` stay `string`, because their lists are retail-only
-- and incomplete for the Forever client. (FrameEvent is not listed: the generator builds it from the
-- client's own event list.)
local closedAliases: { [string]: boolean } = {
	AnimationType = true,
	DrawLayer = true,
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
	closedAliases = closedAliases,
	closedAliasPattern = closedAliasPattern,
}
