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
local paramTypeOverrides: { [string]: { [string]: string } } = {
	["Frame:IsEventRegistered"] = { eventName = "FrameEvent" },
	["Frame:RegisterEvent"] = { eventName = "FrameEvent" },
	["Frame:RegisterUnitEvent"] = { eventName = "FrameEvent" },
	["Frame:UnregisterEvent"] = { eventName = "FrameEvent" },
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
	scriptMethods = scriptMethods,
}
