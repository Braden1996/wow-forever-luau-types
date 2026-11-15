-- World of Warcraft: Forever API definitions for luau-lsp (requires Luau's new type solver).
-- GENERATED FILE: do not edit. Regenerate with `lune run scripts/generate`.
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
export type Enum_DemoKind = number

-- Structures and mixins ----------------------------------------------------------------------
export type DemoInfo = {
	demoID: number,
	kind: Enum_DemoKind,
	name: string,
}
export type DemoInfoExtended = DemoInfo & {
	owner: string?,
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
		Small: number,
		Large: number,
	},
}
declare LE_DEMO_MODE: number

