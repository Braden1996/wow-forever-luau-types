-- World of Warcraft: Forever API definitions for luau-lsp (requires Luau's new type solver).
-- GENERATED FILE: do not edit. Regenerate with `moon run generator:generate`.
-- Existence: example/snapshot@0000000000000000000000000000000000000000
-- Types:     example/snapshot@0000000000000000000000000000000000000000 (Blizzard_APIDocumentationGenerated)
--            example/snapshot@0000000000000000000000000000000000000000 (MIT licence)

-- Events -------------------------------------------------------------------------------------
export type FrameEvent = "PLAYER_LOGIN"
-- Each event's payload as a handler type: `EventPayloads.PLAYER_LEVEL_UP` is `(level: number, ...) -> ()`.
export type EventPayloads = {
	PLAYER_LOGIN: (...unknown) -> (),
}
-- The handler type for one event: `local onLevel: EventHandler<"PLAYER_LEVEL_UP"> = function(level) end`.
export type EventHandler<E> = index<EventPayloads, E>

-- Aliases ------------------------------------------------------------------------------------
export type FramePoint = "CENTER" | "TOP"
export type FrameType = "Frame" | "Button"
export type ScriptRegionResizing = Object
export type SimpleButton = Button
export type SimpleFrame = Frame
export type SimpleWindow = Frame

-- Enum value types ---------------------------------------------------------------------------

-- Structures and mixins ----------------------------------------------------------------------

-- Widgets (the client's own hierarchy) ---------------------------------------------------------
export type ButtonScriptType = "OnClick" | "OnEvent" | "OnHide" | "OnShow"
export type FrameScriptType = "OnEvent" | "OnHide" | "OnShow"
export type RegionScriptType = "OnHide" | "OnShow"
export type ScriptRegionScriptType = "OnHide" | "OnShow"
declare extern type FrameScriptObject with
	function GetName(self): string?
end

declare extern type Object extends FrameScriptObject with
	function GetParent(self, ...: unknown): (...unknown)
end

declare extern type ScriptRegion extends Object with
	function GetScript(self, scriptType: ScriptRegionScriptType): ((self: ScriptRegion, ...any) -> ())?
	function HasScript(self, scriptType: ScriptRegionScriptType): boolean
	function HookScript(self, scriptType: ScriptRegionScriptType, handler: ((self: ScriptRegion, ...any) -> ())?): ()
	function SetPoint(self, point: FramePoint, relativeTo: (ScriptRegion | number)?, relativePoint: (FramePoint | number)?, offsetX: number?, offsetY: number?): ()
	function SetScript(self, scriptTypeName: ScriptRegionScriptType, script: ((self: ScriptRegion, ...any) -> ())?): ()
	function Show(self, ...: unknown): (...unknown)
end

declare extern type Frame extends ScriptRegion with
	function GetScript(self, scriptType: FrameScriptType): ((self: Frame, ...any) -> ())?
	function HasScript(self, scriptType: FrameScriptType): boolean
	function HookScript(self, scriptType: FrameScriptType, handler: ((self: Frame, ...any) -> ())?): ()
	function RegisterEvent(self, eventName: FrameEvent): boolean
	function SetScript(self, scriptTypeName: FrameScriptType, script: ((self: Frame, ...any) -> ())?): ()
	function Undocumented(self, ...: unknown): (...unknown)
end

declare extern type Button extends Frame with
	function GetScript(self, scriptType: ButtonScriptType): ((self: Button, ...any) -> ())?
	function HasScript(self, scriptType: ButtonScriptType): boolean
	function HookScript(self, scriptType: ButtonScriptType, handler: ((self: Button, ...any) -> ())?): ()
	function SetScript(self, scriptTypeName: ButtonScriptType, script: ((self: Button, ...any) -> ())?): ()
	function SetText(self, text: string?): ()
end

declare extern type Region extends ScriptRegion with
	function GetScript(self, scriptType: RegionScriptType): ((self: Region, ...any) -> ())?
	function HasScript(self, scriptType: RegionScriptType): boolean
	function HookScript(self, scriptType: RegionScriptType, handler: ((self: Region, ...any) -> ())?): ()
	function SetDrawLayer(self, layer: string): ()
	function SetScript(self, scriptTypeName: RegionScriptType, script: ((self: Region, ...any) -> ())?): ()
end

declare extern type ScriptObject with
	function GetScript(self, ...: unknown): (...unknown)
	function HasScript(self, ...: unknown): (...unknown)
	function HookScript(self, ...: unknown): (...unknown)
	function SetScript(self, scriptTypeName: string, script: unknown): ()
end

-- Script objects -----------------------------------------------------------------------------
-- The widget CreateFrame returns for each frame type.
export type FrameTypeMap = {
	Button: Button,
	Frame: Frame,
}

-- Globals ------------------------------------------------------------------------------------
declare function CreateFrame<K>(frameType: K & keyof<FrameTypeMap>, name: string?, parent: Frame?, template: string?, id: number?): index<FrameTypeMap, K>

