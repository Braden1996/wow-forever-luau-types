--!strict
-- Downloads one release of the WoW: Forever definitions into types/wow-forever.d.luau and verifies it: the file's
-- SHA-256 must equal the hash pinned in mise.toml, and the release's SHA256SUMS must list that same hash.
-- Run it as `mise run types`, which sets WOW_TYPES_VERSION (a release tag) and WOW_TYPES_SHA256.

local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")
local serde = require("@lune/serde")

local RELEASES = "https://github.com/Braden1996/wow-forever-luau-types/releases/download/"
local FILE = "wow-forever.d.luau"
local OUT = "types/" .. FILE

local version = process.env.WOW_TYPES_VERSION
local pinned = process.env.WOW_TYPES_SHA256
if not version or not string.match(version, "^v%d+%.%d+%.%d+$") then
	error("set WOW_TYPES_VERSION to a release tag such as v0.2.0 (run this as `mise run types`)")
end
if not pinned or not string.match(pinned, "^%x+$") or #pinned ~= 64 then
	error("set WOW_TYPES_SHA256 to the sha256 of " .. FILE .. " in release " .. version)
end
local expected = string.lower(pinned)

if fs.isFile(OUT) and serde.hash("sha256", fs.readFile(OUT)) == expected then
	print(OUT .. " is already release " .. version)
	return
end

local function download(name: string): string
	local url = RELEASES .. version .. "/" .. name
	local response = net.request({ url = url, method = "GET" })
	if not response.ok then
		error(string.format("GET %s failed: %d %s", url, response.statusCode, response.statusMessage))
	end
	return response.body
end

local sums = download("SHA256SUMS")
local escaped = string.gsub(FILE, "%p", "%%%0")
local listed = string.match("\n" .. sums .. "\n", "\n(%x+)%s+%*?" .. escaped .. "%s*\n")
if listed == nil or string.lower(listed) ~= expected then
	error(string.format("SHA256SUMS of %s lists %s for %s, but mise.toml pins %s", version, tostring(listed), FILE, expected))
end

local body = download(FILE)
local actual = serde.hash("sha256", body)
if actual ~= expected then
	error(string.format("%s from %s has sha256 %s, expected %s", FILE, version, actual, expected))
end

fs.writeFile(OUT, body)
print(string.format("%s: release %s, sha256 %s", OUT, version, actual))
