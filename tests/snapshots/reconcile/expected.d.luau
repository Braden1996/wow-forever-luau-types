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
export type DemoTimerCallback = (handle: DemoTimerHandle) -> ()

-- Enum value types ---------------------------------------------------------------------------

-- Structures and mixins ----------------------------------------------------------------------
export type DemoColor = {
	b: number,
	g: number,
	r: number,
}
export type DemoTimerHandle = {
	Cancel: (self: DemoTimerHandle) -> boolean,
}

-- Widgets (the client's own hierarchy) ---------------------------------------------------------
-- Script objects -----------------------------------------------------------------------------
-- The widget CreateFrame returns for each frame type.
export type FrameTypeMap = {
}

-- Globals ------------------------------------------------------------------------------------
declare function AnnotatedOnly(id: number): string?
declare function CheckDemoSlot(slot: number): boolean
declare function DemoPrint(text: string, r: (number | DemoColor)?, g: number?, b: number?): ()
declare function DocumentedOnly(): boolean
declare function FindDemo(name: string): (number?, string?)
declare GetDemoSlot: ((slot: number) -> (string?, number?)) & ((name: string) -> string?)
declare function NewDemoTimer(seconds: number, callback: DemoTimerCallback): DemoTimerHandle
declare function NoSourceAtAll(...: unknown): (...unknown)
declare tinsert: typeof(table.insert)
declare function wipe(tbl: { [any]: any }): { [any]: any }

