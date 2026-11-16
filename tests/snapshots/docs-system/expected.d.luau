-- World of Warcraft: Forever API definitions for luau-lsp (requires Luau's new type solver).
-- GENERATED FILE: do not edit. Regenerate with `moon run generator:generate`.
-- Existence: example/snapshot@0000000000000000000000000000000000000000
-- Types:     example/snapshot@0000000000000000000000000000000000000000 (Blizzard_APIDocumentationGenerated)
--            example/snapshot@0000000000000000000000000000000000000000 (MIT licence)

-- Events -------------------------------------------------------------------------------------
export type FrameEvent = "DEMO_RETIRED" | "DEMO_UNDOCUMENTED" | "DEMO_UPDATED"
-- Each event's payload as a handler type: `EventPayloads.PLAYER_LEVEL_UP` is `(level: number, ...) -> ()`.
export type EventPayloads = {
	DEMO_RETIRED: () -> (),
	DEMO_UNDOCUMENTED: (...unknown) -> (),
	DEMO_UPDATED: (demoID: number, name: string?) -> (),
}
-- The handler type for one event: `local onLevel: EventHandler<"PLAYER_LEVEL_UP"> = function(level) end`.
export type EventHandler<E> = index<EventPayloads, E>

-- Aliases ------------------------------------------------------------------------------------

-- Enum value types ---------------------------------------------------------------------------
declare extern type Enum_DemoKind with
	function __lt(self, other: Enum_DemoKind): boolean
	function __le(self, other: Enum_DemoKind): boolean
end

-- Structures and mixins ----------------------------------------------------------------------
-- The fields every structure matching `VisualizationInfo$` has in common.
export type UIWidgetVisualizationInfoBase = {
	orderIndex: number,
	textureKit: string,
	widgetTag: string,
}
export type DemoBarVisualizationInfo = UIWidgetVisualizationInfoBase & {
	barValue: number,
}
export type DemoInfo = {
	demoID: number,
	kind: Enum_DemoKind,
	name: string,
}
export type DemoInfoExtended = {
	demoID: number,
	kind: Enum_DemoKind,
	name: string,
	owner: string?,
}
export type DemoTextVisualizationInfo = UIWidgetVisualizationInfoBase & {
	text: string,
}

-- Widgets (the client's own hierarchy) ---------------------------------------------------------
-- Script objects -----------------------------------------------------------------------------
-- The widget CreateFrame returns for each frame type.
export type FrameTypeMap = {
}

-- Globals ------------------------------------------------------------------------------------
declare C_Demo: {
	GetInfo: (demoID: number, kind: Enum_DemoKind?) -> DemoInfoExtended?,
	GetNames: () -> ({ string }, { [number]: DemoInfo }),
	ListIDs: () -> (number, ...number),
	Undocumented: (...unknown) -> (...unknown),
}
declare Constants: {
	DemoConstants: {
		BASE: number,
	},
}
declare Enum: {
	DemoKind: {
		Small: Enum_DemoKind,
		Large: Enum_DemoKind,
	},
}
declare LE_DEMO_MODE: number

