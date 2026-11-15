--!strict
-- Global functions: existence follows the WoW: Forever client, types follow Blizzard's documentation.
-- Every marked line must error (see scripts/test.luau); globals.expected holds the exact diagnostics.

-- Classic Era globals that the Forever client replaced with C_ namespaces.
GetQuestLogTitle(1) -- expect-error: Unknown global 'GetQuestLogTitle'
local _info = GetItemInfo(6948) -- expect-error: Unknown global 'GetItemInfo'

-- An annotated API the client does not have (arena teams are a TBC feature).
ArenaTeamDisband() -- expect-error: Unknown global 'ArenaTeamDisband'
NotARealWowApi() -- expect-error: Unknown global 'NotARealWowApi'

-- Wrong argument and result types.
local _level: string = UnitLevel("player") -- expect-error: Expected this to be 'string', but got 'number'
local _name: number = UnitName("player") -- expect-error: Expected this to be 'number', but got 'string'
UnitXP(42) -- expect-error: Expected this to be 'string', but got 'number'

-- Missing arguments and unknown namespace members.
C_Timer.After(5) -- expect-error: Function expects 2 arguments, but only 1 is specified
C_Timer.Afterr(5, function() end) -- expect-error: Key 'Afterr' not found

-- A function with no type source returns unknown, which must be refined before use.
local _key: string = GetBindingKeyForAction("JUMP") -- expect-error: Expected this to be 'string', but got 'unknown'
