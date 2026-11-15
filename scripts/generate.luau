--!strict
-- Regenerates definitions/ from the pinned upstream commits in upstream.toml.
--   lune run scripts/generate              fetch upstream (cached in .upstream/) and write the output
--   lune run scripts/generate -- --check   fail if the committed output is stale

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Build = require("../generator/build")
local Resources = require("../generator/resources")
local config = require("../generator/config")
local json = require("../generator/json")

local check = table.find(process.args, "--check") ~= nil

type Pin = { repository: string, commit: string }

local pins = serde.decode("toml", fs.readFile("upstream.toml")) :: { annotations: Pin, resources: Pin }

local function git(args: { string }, cwd: string)
	local result = process.exec("git", args, { cwd = cwd })
	if not result.ok then
		error("git " .. table.concat(args, " ") .. " failed:\n" .. result.stderr)
	end
end

-- A shallow checkout of one commit, cached under .upstream/<owner>/<repo>/<commit>.
local function fetch(pin: Pin): string
	assert(string.match(pin.commit, "^%x+$") and #pin.commit == 40, "upstream.toml: commit must be a full SHA")
	assert(string.match(pin.repository, "^[%w_.-]+/[%w_.-]+$"), "upstream.toml: repository must be owner/name")
	local dir = ".upstream/" .. pin.repository .. "/" .. pin.commit
	if fs.isDir(dir) then
		return dir
	end
	print("Fetching " .. pin.repository .. "@" .. pin.commit)
	local tmp = dir .. ".partial"
	if fs.isDir(tmp) then
		fs.removeDir(tmp)
	end
	fs.writeDir(tmp)
	git({ "init", "--quiet" }, tmp)
	git({ "remote", "add", "origin", "https://github.com/" .. pin.repository .. ".git" }, tmp)
	git({ "fetch", "--quiet", "--depth", "1", "origin", pin.commit }, tmp)
	git({ "-c", "advice.detachedHead=false", "checkout", "--quiet", "FETCH_HEAD" }, tmp)
	fs.move(tmp, dir)
	return dir
end

local annotationsDir = fetch(pins.annotations)
local resourcesDir = fetch(pins.resources)

-- Every .lua file under the configured annotation sources, in priority order, each folder sorted.
local files = {}
local seen = {}
local function walk(path: string)
	local full = annotationsDir .. "/" .. path
	if fs.isFile(full) then
		if string.match(path, "%.lua$") and not seen[path] then
			seen[path] = true
			table.insert(files, { path = path, source = fs.readFile(full) })
		end
		return
	end
	local entries = fs.readDir(full)
	table.sort(entries)
	for _, entry in entries do
		walk(path .. "/" .. entry)
	end
end
for _, source in config.sources do
	walk(source)
end

local resourceFiles = {}
for _, name in config.resourceFiles do
	resourceFiles[name] = string.gsub(fs.readFile(resourcesDir .. "/Resources/" .. name), "\r\n", "\n")
end
local resources = Resources.parse(resourceFiles)

-- Hand-written supplements are appended verbatim; the generator leaves the names they declare alone.
local supplementText = ""
local supplementNames: { [string]: boolean } = {}
for _, supplement in config.supplements do
	local text = string.gsub(fs.readFile(supplement), "\r\n", "\n")
	for name in string.gmatch("\n" .. text, "\ndeclare function ([%w_]+)") do
		if not (resources.globalApi[name] or resources.frameXml[name] or resources.luaApi[name]) then
			error(supplement .. ": " .. name .. " is not a function in the " .. config.gameName .. " client")
		end
		supplementNames[name] = true
	end
	for name in string.gmatch("\n" .. text, "\ndeclare ([%w_]+):") do
		supplementNames[name] = true
	end
	supplementText ..= "\n-- " .. string.rep("=", 97) .. "\n-- Appended from " .. supplement .. "\n" .. text
end

local definitions, report = Build.run({
	files = files,
	resources = resources,
	reserved = supplementNames,
	upstream = { annotations = pins.annotations, resources = pins.resources },
	config = config :: any,
})
definitions ..= "\n" .. supplementText
local reportText = json.encode(report) .. "\n"

if check then
	local stale = {}
	for path, expected in { [config.output] = definitions, [config.report] = reportText } do
		local actual = if fs.isFile(path) then string.gsub(fs.readFile(path), "\r\n", "\n") else nil
		if actual ~= expected then
			table.insert(stale, path)
		end
	end
	if #stale > 0 then
		table.sort(stale)
		print("Stale: " .. table.concat(stale, ", ") .. ". Run `lune run scripts/generate` and commit the result.")
		process.exit(1)
	end
	print("Definitions are up to date with upstream.toml.")
else
	fs.writeDir("definitions")
	fs.writeFile(config.output, definitions)
	fs.writeFile(config.report, reportText)
	local c = report.counts
	print(
		string.format(
			"Wrote %s: %d widgets, %d structures, %d typed and %d untyped functions; "
				.. "dropped %d annotated APIs that WoW: Forever does not have.",
			config.output,
			c.widgets,
			c.structures,
			c.functionsTyped,
			c.functionsUntyped,
			c.droppedNotInClient
		)
	)
	if #report.parseErrors > 0 then
		print(#report.parseErrors .. " upstream lines could not be parsed; see " .. config.report .. ".")
	end
end
