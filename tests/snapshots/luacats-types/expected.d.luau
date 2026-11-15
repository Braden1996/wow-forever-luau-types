-- World of Warcraft: Forever API definitions for luau-lsp (requires Luau's new type solver).
-- GENERATED FILE: do not edit. Regenerate with `moon run generator:generate`.
-- Existence: example/snapshot@0000000000000000000000000000000000000000
-- Types:     example/snapshot@0000000000000000000000000000000000000000 (Blizzard_APIDocumentationGenerated)
--            example/snapshot@0000000000000000000000000000000000000000 (MIT licence)

-- Events -------------------------------------------------------------------------------------
export type FrameEvent = never
-- Each event's payload as a handler type: `EventPayloads.PLAYER_LEVEL_UP` is `(level: number, ...) -> ()`.
export type EventPayloads = {
}
-- The handler type for one event: `local onLevel: EventHandler<"PLAYER_LEVEL_UP"> = function(level) end`.
export type EventHandler<E> = index<EventPayloads, E>

-- Aliases ------------------------------------------------------------------------------------
export type CVar = string
export type DrawLayer = "BACKGROUND" | "ARTWORK"
export type ItemInfo = number | string

-- Enum value types ---------------------------------------------------------------------------

-- Structures and mixins ----------------------------------------------------------------------
export type BaseInfo = {
	id: number,
	name: string,
}
export type RichInfo = BaseInfo & {
	[string]: unknown,
	byKey: { [string]: boolean },
	level: number,
	tags: { string },
}

-- Widgets (the client's own hierarchy) ---------------------------------------------------------
-- Script objects -----------------------------------------------------------------------------
-- The widget CreateFrame returns for each frame type.
export type FrameTypeMap = {
}

-- Globals ------------------------------------------------------------------------------------
declare function DemoClasses(info: RichInfo, missing: unknown): ()
declare DemoFirst: <T>(list: { T }) -> T?
declare function DemoReserved(end_: string, async: () -> number): ()
declare function DemoUnions(layer: DrawLayer, cvar: CVar, item: ItemInfo, flag: (true | "yes")?, anything: unknown): { [any]: any }?
declare function DemoVarargs(callback: (id: number, ...string) -> boolean, ...: number): (string, ...number)

