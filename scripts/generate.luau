--!strict
-- Regenerates every generated file from the pinned upstream commits in upstream.toml:
--   definitions/wow-forever.d.luau, definitions/report.json, definitions/coverage.json,
--   definitions/COVERAGE.md and .github/banner.svg.
--   lune run scripts/generate              fetch upstream (cached in .upstream/) and write the files
--   lune run scripts/generate -- --check   fail if any committed file is stale

local fs = require("@lune/fs")
local process = require("@lune/process")

local Pipeline = require("../generator/pipeline")

local check = table.find(process.args, "--check") ~= nil
local result = Pipeline.run()

local paths = {}
for path in result.files do
	table.insert(paths, path)
end
table.sort(paths)

if check then
	local stale = {}
	for _, path in paths do
		local actual = if fs.isFile(path) then string.gsub(fs.readFile(path), "\r\n", "\n") else nil
		if actual ~= result.files[path] then
			table.insert(stale, path)
		end
	end
	if #stale > 0 then
		print("Stale: " .. table.concat(stale, ", ") .. ". Run `lune run scripts/generate` and commit the result.")
		process.exit(1)
	end
	print("All generated files are up to date with upstream.toml.")
else
	for _, path in paths do
		local dir = string.match(path, "^(.*)/[^/]+$")
		if dir then
			fs.writeDir(dir)
		end
		fs.writeFile(path, result.files[path])
	end
	print(result.summaryLine)
end
