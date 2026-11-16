--!strict
-- How Blizzard's documented script objects and the client's widgets map onto each other, and the widget
-- rules the generator applies (generator/stages/widgets.luau). Part of generator/config.luau (assembled there).

-- Blizzard documents widget methods per "script object" API. Each maps onto the client widget
-- type(s) whose methods it describes.
local scriptObjectWidgets: { [string]: { string } } = {
	FrameAPIArchaeologyDigsite = { "ArchaeologyDigSiteFrame" },
	FrameAPIBlob = { "Blob" },
	FrameAPICharacterModelBase = { "PlayerModel" },
	FrameAPICinematicModel = { "CinematicModel" },
	FrameAPICooldown = { "Cooldown" },
	FrameAPIDressUpModel = { "DressUpModel" },
	FrameAPIFogOfWarFrame = { "FogOfWarFrame" },
	FrameAPIModelSceneFrame = { "ModelScene" },
	FrameAPIModelSceneFrameActor = { "ModelSceneActor" },
	FrameAPIModelSceneFrameActorBase = { "ModelSceneActor" },
	FrameAPIQuestPOI = { "QuestPOIFrame" },
	FrameAPIScenarioPOI = { "ScenarioPOIFrame" },
	FrameAPISimpleCheckout = { "Checkout" },
	FrameAPITabardModel = { "TabardModel" },
	FrameAPITabardModelBase = { "TabardModel" },
	FrameAPITooltip = { "GameTooltip" },
	FrameAPIUnitPositionFrame = { "UnitPositionFrame" },
	MinimapFrameAPI = { "Minimap" },
	SimpleAnimAPI = { "Animation" },
	SimpleAnimAlphaAPI = { "Alpha" },
	SimpleAnimFlipBookAPI = { "FlipBook" },
	SimpleAnimGroupAPI = { "AnimationGroup" },
	SimpleAnimPathAPI = { "Path" },
	SimpleAnimRadialProgressAPI = { "RadialProgress" },
	SimpleAnimRotationAPI = { "Rotation" },
	SimpleAnimScaleAPI = { "Scale" },
	SimpleAnimScaleLineAPI = { "LineScale" },
	SimpleAnimTextureCoordTranslationAPI = { "TextureCoordTranslation" },
	SimpleAnimTranslationAPI = { "Translation" },
	SimpleAnimTranslationLineAPI = { "LineTranslation" },
	SimpleAnimVertexColorAPI = { "VertexColor" },
	SimpleAnimatableObjectAPI = { "ScriptRegion" },
	SimpleBrowserAPI = { "Browser" },
	SimpleButtonAPI = { "Button" },
	SimpleCheckboxAPI = { "CheckButton" },
	SimpleColorSelectAPI = { "ColorSelect" },
	SimpleControlPointAPI = { "ControlPoint" },
	SimpleEditBoxAPI = { "EditBox" },
	SimpleFontAPI = { "Font", "FontInstance" },
	SimpleFontStringAPI = { "FontString" },
	SimpleFrameAPI = { "Frame" },
	SimpleFrameScriptObjectAPI = { "FrameScriptObject", "ScriptObject" },
	SimpleHTMLAPI = { "SimpleHTML" },
	SimpleLineAPI = { "Line" },
	SimpleMaskTextureAPI = { "MaskTexture" },
	SimpleMessageFrameAPI = { "MessageFrame" },
	SimpleModelAPI = { "Model" },
	SimpleModelFFXAPI = { "Model" },
	SimpleMovieAPI = { "MovieFrame" },
	SimpleObjectAPI = { "Object" },
	SimpleOffScreenFrameAPI = { "OffScreenFrame" },
	SimpleRegionAPI = { "Region" },
	SimpleScriptRegionAPI = { "ScriptRegion" },
	SimpleScriptRegionResizingAPI = { "ScriptRegion" },
	SimpleScrollFrameAPI = { "ScrollFrame" },
	SimpleSliderAPI = { "Slider" },
	SimpleStatusBarAPI = { "StatusBar" },
	SimpleTextureAPI = { "Texture" },
	SimpleTextureBaseAPI = { "TextureBase" },
	SimpleVectorGraphicsAPI = { "VectorGraphics" },
}
-- Documented script objects that belong to no client widget type (the Forever client has no such
-- frame type); the rest become `declare extern type`s named without the `API` suffix.
local ignoredScriptObjects: { [string]: string } = {
	FrameAPINamePlate = "no NamePlate widget type in the client",
	HousingFixturePointFrameAPI = "no housing frame types in the client",
	HousingLayoutPinFrameAPI = "no housing frame types in the client",
	PingPinFrameAPI = "no ping pin frame type in the client",
	SimpleMapSceneAPI = "no MapScene widget type in the client",
}
-- Blizzard's documentation names some widgets differently.
local docWidgetAliases: { [string]: string } = {
	SimpleAnim = "Animation",
	SimpleAnimGroup = "AnimationGroup",
	SimpleButton = "Button",
	SimpleCheckbox = "CheckButton",
	SimpleControlPoint = "ControlPoint",
	SimpleEditBox = "EditBox",
	SimpleFont = "Font",
	SimpleFontString = "FontString",
	SimpleFrame = "Frame",
	SimpleLine = "Line",
	SimpleMaskTexture = "MaskTexture",
	SimpleTexture = "Texture",
	SimpleVectorGraphics = "VectorGraphics",
	SimpleWindow = "Frame",
}
-- The client dump lists Region as its own parent; Region is a ScriptRegion with draw layers.
local widgetParentOverrides: { [string]: { string } } = {
	Region = { "ScriptRegion" },
}
-- Documented script objects that are not widgets but share a documented base: Blizzard documents
-- LuaCurveObjectBase separately, and the functions that take any curve (`LuaDurationObject:EvaluateRemainingPercent`)
-- take the base. The annotations declare `CurveObject : CurveObjectBase` and `ColorCurveObject : CurveObjectBase`.
local scriptObjectParents: { [string]: string } = {
	LuaColorCurveObject = "LuaCurveObjectBase",
	LuaCurveObject = "LuaCurveObjectBase",
}
-- Parameters both sources type too loosely (Blizzard documents event names as plain strings), keyed
-- "Widget:Method" or a qualified function name. A key that matches nothing is an error.
--
-- SetTexture's `cstring` texture also takes a file ID (`SetTexture(134400)`, as the annotations say), and its
-- wrap and filter modes are the closed WrapMode and FilterMode the annotations list. An attribute's value is
-- any Lua value (`SetAttribute("unit", nil)`, `SetAttribute("showRaid", true)`), not the documented `cstring`.
local paramTypeOverrides: { [string]: { [string]: string } } = {
	["Frame:IsEventRegistered"] = { eventName = "FrameEvent" },
	["Frame:RegisterEvent"] = { eventName = "FrameEvent" },
	["Frame:RegisterEventCallback"] = { eventName = "FrameEvent" },
	["Frame:RegisterUnitEvent"] = { eventName = "FrameEvent" },
	["Frame:RegisterUnitEventCallback"] = { eventName = "FrameEvent" },
	["Frame:UnregisterEvent"] = { eventName = "FrameEvent" },
	["Frame:SetAttribute"] = { value = "unknown" },
	["Frame:SetAttributeNoHandler"] = { value = "unknown" },
	["RegisterEventCallback"] = { eventName = "FrameEvent" },
	["RegisterUnitEventCallback"] = { eventName = "FrameEvent" },
	["UnregisterEventCallback"] = { eventName = "FrameEvent" },
	["UnregisterUnitEventCallback"] = { eventName = "FrameEvent" },
	-- A font is set by object or by the name of a global font object (`SetFontObject("GameFontNormal")`), as the
	-- annotations say; Blizzard's documentation names only the object.
	["Button:SetDisabledFontObject"] = { font = "FontObject" },
	["Button:SetHighlightFontObject"] = { font = "FontObject" },
	["Button:SetNormalFontObject"] = { font = "FontObject" },
	["EditBox:SetFontObject"] = { font = "FontObject" },
	["Font:SetFontObject"] = { font = "FontObject" },
	["FontInstance:SetFontObject"] = { font = "FontObject" },
	["FontString:SetFontObject"] = { font = "FontObject" },
	["MessageFrame:SetFontObject"] = { font = "FontObject" },
	["SimpleHTML:SetFontObject"] = { font = "FontObject" },
	["TextureBase:SetTexture"] = {
		textureAsset = "TextureAssetDisk",
		wrapModeHorizontal = "WrapMode",
		wrapModeVertical = "WrapMode",
		filterMode = "FilterMode",
	},
}
-- Result types both sources state wrongly, keyed like paramTypeOverrides, by result position. An attribute
-- holds any Lua value, or nil when it was never set (`GetAttribute("unit")`), not the documented `cstring`.
local resultTypeOverrides: { [string]: { [number]: string } } = {
	["Frame:GetAttribute"] = { [1] = "unknown" },
}
-- Factory methods whose result type follows a string argument naming a widget type, like CreateFrame's:
-- one overload per value of the closed alias that names a widget, then the call without the argument.
-- `AnimationGroup:CreateAnimation("Alpha")` returns an Alpha, and a misspelt type is an error.
local factoryMethods: { [string]: { param: string, alias: string } } = {
	["AnimationGroup:CreateAnimation"] = { param = "animationType", alias = "AnimationType" },
}
-- Lua mixins that a template adds to a widget, declared as a widget type that extends it. GameTooltipTemplate
-- mixes GameTooltipDataMixin into GameTooltip and ItemRefTooltip: one `Set<X>` method per C API accessor
-- `C_TooltipInfo.Get<X>`, called with the accessor's arguments. A method is declared only where the annotations
-- name `GameTooltip:Set<X>` and the client has the accessor; its parameters are the accessor's, and its result is
-- untyped, because no source documents it. `untyped` lists the mixin's other methods that the annotations name
-- without types. `globals` are the named frames built from the template.
export type WidgetMixin = {
	widget: string,
	accessors: { prefix: string, namespace: string, getter: string },
	untyped: { string },
	globals: { string },
}
local widgetMixins: { [string]: WidgetMixin } = {
	GameTooltipDataMixin = {
		widget = "GameTooltip",
		accessors = { prefix = "Set", namespace = "C_TooltipInfo", getter = "Get" },
		untyped = { "GetItem", "GetSpell", "GetUnit" },
		globals = { "GameTooltip", "ItemRefTooltip" },
	},
}
-- Methods whose first argument is a script name: typed per widget with that widget's handlers.
local scriptMethods: { [string]: boolean } = { GetScript = true, HasScript = true, HookScript = true, SetScript = true }

return {
	scriptObjectWidgets = scriptObjectWidgets,
	ignoredScriptObjects = ignoredScriptObjects,
	docWidgetAliases = docWidgetAliases,
	widgetParentOverrides = widgetParentOverrides,
	scriptObjectParents = scriptObjectParents,
	paramTypeOverrides = paramTypeOverrides,
	resultTypeOverrides = resultTypeOverrides,
	factoryMethods = factoryMethods,
	scriptMethods = scriptMethods,
	widgetMixins = widgetMixins,
}
