--!strict
-- Reads text files with line endings normalised to LF, so the generator behaves the same on Windows
-- checkouts (core.autocrlf) and Linux CI.

local fs = require("@lune/fs")

local TextFile = {}

function TextFile.read(path: string): string
	return (string.gsub(fs.readFile(path), "\r\n", "\n"))
end

-- Every file in `dir` whose name matches `pattern`, sorted by name.
function TextFile.readAll(dir: string, pattern: string): { { name: string, source: string } }
	local out = {}
	local entries = fs.readDir(dir)
	table.sort(entries)
	for _, entry in entries do
		if string.match(entry, pattern) and fs.isFile(dir .. "/" .. entry) then
			table.insert(out, { name = entry, source = TextFile.read(dir .. "/" .. entry) })
		end
	end
	return out
end

return TextFile
