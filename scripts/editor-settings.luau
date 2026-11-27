--!strict
-- Keeps the editors' `disabledGlobals` lists equal to the generated definitions/luau-lsp.settings.json. Editors
-- cannot include another settings file, so each config carries a copy:
--   lune run scripts/editor-settings              fail if any copy differs
--   lune run scripts/editor-settings -- --write   rewrite the copies

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local config = require("../packages/generator/src/config")

-- Each editor config, the key its list sits under, and the indentation of the list's entries.
local TARGETS: { { path: string, key: string } } = {
	{ path = ".vscode/settings.json", key = '"luau-lsp.types.disabledGlobals": ' },
	{ path = "templates/addon/.vscode/settings.json", key = '"luau-lsp.types.disabledGlobals": ' },
	{ path = ".zed/settings.json", key = '"disabledGlobals": ' },
	{ path = "templates/addon/.zed/settings.json", key = '"disabledGlobals": ' },
}

local write = table.find(process.args, "--write") ~= nil
local generated = serde.decode("json", fs.readFile(config.settings)) :: { [string]: { string } }
local names = generated["luau-lsp.types.disabledGlobals"]
assert(names, config.settings .. " has no luau-lsp.types.disabledGlobals")

local failures = 0
for _, target in TARGETS do
	local text = string.gsub(fs.readFile(target.path), "\r\n", "\n")
	local start = string.find(text, target.key, 1, true)
	if start == nil then
		print("FAIL " .. target.path .. ": no " .. target.key .. "list")
		failures += 1
		continue
	end
	local open = start + #target.key
	assert(string.sub(text, open, open) == "[", target.path .. ": the list must follow " .. target.key)
	local close = string.find(text, "]", open, true) :: number
	-- Indent entries one level (two spaces) deeper than the key's line.
	local lineStart = (string.match(string.sub(text, 1, start), ".*\n()") or 1) :: number
	local indent = string.match(string.sub(text, lineStart, start - 1), "^%s*") :: string
	local entries = {}
	for _, name in names do
		table.insert(entries, indent .. '  "' .. name .. '"')
	end
	-- Compare the names, not the layout: dprint owns the formatting.
	local current = {}
	for name in string.gmatch(string.sub(text, open, close), '"([^"]+)"') do
		table.insert(current, name)
	end
	if table.concat(current, "\n") ~= table.concat(names, "\n") then
		if write then
			local list = "[\n" .. table.concat(entries, ",\n") .. "\n" .. indent .. "]"
			fs.writeFile(target.path, string.sub(text, 1, open - 1) .. list .. string.sub(text, close + 1))
			print("wrote " .. target.path)
		else
			print("FAIL " .. target.path .. ": disabledGlobals differs from " .. config.settings)
			failures += 1
		end
	end
end

if failures > 0 then
	print("Run `lune run scripts/editor-settings -- --write`.")
	process.exit(1)
end
print("Editor disabledGlobals lists match " .. config.settings .. ".")
