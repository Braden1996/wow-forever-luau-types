--!strict
-- Global functions: existence follows the WoW: Forever client, types follow Blizzard's documentation.
-- Every marked line must error (see scripts/test.luau); globals.expected holds the exact diagnostics.

-- Classic Era globals that the Forever client replaced with C_ namespaces.
GetQuestLogTitle(1) -- expect-error: GetQuestLogTitle
local _info = GetItemInfo(6948) -- expect-error: GetItemInfo

-- An annotated API the client does not have (arena teams are a TBC feature).
ArenaTeamDisband() -- expect-error: ArenaTeamDisband
NotARealWowApi() -- expect-error: NotARealWowApi

-- Wrong argument and result types.
local _level: string = UnitLevel("player") -- expect-error: string
local _name: number = UnitName("player") -- expect-error: number
UnitXP(42) -- expect-error: number

-- Missing arguments and unknown namespace members.
C_Timer.After(5) -- expect-error: argument
C_Timer.Afterr(5, function() end) -- expect-error: Afterr

-- A function with no type source returns unknown, which must be refined before use.
local _key: string = GetBindingKeyForAction("JUMP") -- expect-error: unknown
