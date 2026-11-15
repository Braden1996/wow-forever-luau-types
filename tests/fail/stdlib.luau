--!strict
-- Luau's standard library minus what the WoW: Forever client lacks (definitions/luau-lsp.settings.json).

-- Whole libraries the client does not have.
local _os = os.time() -- expect-error: Unknown global 'os'
local _buffer = buffer.create(4) -- expect-error: Unknown global 'buffer'
local _utf8 = utf8.len("x") -- expect-error: Unknown global 'utf8'

-- Globals and library members the client does not have.
local _typeof = typeof(1) -- expect-error: Unknown global 'typeof'
local _pack = string.pack("i4", 1) -- expect-error: Key 'pack' not found
local _find = table.find({ 1 }, 1) -- expect-error: Key 'find' not found
local _tau = math.tau -- expect-error: Key 'tau' not found

-- What the client has is unchanged.
local _format: string = string.format("%d", 1)
local _pi: number = math.pi
local _insert = table.insert
local _clamp: number = math.clamp(2, 0, 1)
print(_G, _VERSION)
