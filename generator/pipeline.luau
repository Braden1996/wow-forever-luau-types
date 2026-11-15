--!strict
-- Fetches the pinned inputs and produces every generated file's contents (path -> text).

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local ApiDocs = require("./apidocs")
local Banner = require("./banner")
local Build = require("./build")
local CoverageReport = require("./coverage")
local Resources = require("./resources")
local config = require("./config")
local json = require("./json")

export type Pin = { repository: string, commit: string, sparse: string? }
export type Pins = { annotations: Pin, docs: Pin, resources: Pin }

local Pipeline = {}

local function git(args: { string }, cwd: string)
	local result = process.exec("git", args, { cwd = cwd })
	if not result.ok then
		error("git " .. table.concat(args, " ") .. " failed:\n" .. result.stderr)
	end
end

-- A shallow (optionally sparse) checkout of one commit, cached under .upstream/<owner>/<repo>/<commit>.
function Pipeline.fetch(pin: Pin): string
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
	if pin.sparse then
		git({ "sparse-checkout", "set", "--no-cone", "/" .. pin.sparse .. "/" }, tmp)
		git({ "fetch", "--quiet", "--depth", "1", "--filter=blob:none", "origin", pin.commit }, tmp)
	else
		git({ "fetch", "--quiet", "--depth", "1", "origin", pin.commit }, tmp)
	end
	git({ "-c", "advice.detachedHead=false", "checkout", "--quiet", "FETCH_HEAD" }, tmp)
	fs.move(tmp, dir)
	return dir
end

local function readAll(dir: string, pattern: string): { { name: string, source: string } }
	local out = {}
	local entries = fs.readDir(dir)
	table.sort(entries)
	for _, entry in entries do
		if string.match(entry, pattern) and fs.isFile(dir .. "/" .. entry) then
			table.insert(out, { name = entry, source = (string.gsub(fs.readFile(dir .. "/" .. entry), "\r\n", "\n")) })
		end
	end
	return out
end

export type Result = { files: { [string]: string }, summaryLine: string }

function Pipeline.run(): Result
	local pins = serde.decode("toml", fs.readFile("upstream.toml")) :: Pins
	local annotationsDir = Pipeline.fetch(pins.annotations)
	local docsDir = Pipeline.fetch(pins.docs)
	local resourcesDir = Pipeline.fetch(pins.resources)

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
	local docs = ApiDocs.parse(readAll(docsDir .. "/" .. config.docsPath, "%.lua$"))

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

	local definitions, report, coverage = Build.run({
		files = files,
		docs = docs,
		resources = resources,
		reserved = supplementNames,
		upstream = { annotations = pins.annotations, docs = pins.docs, resources = pins.resources },
		config = config :: any,
	})
	definitions ..= "\n" .. supplementText

	local summary = report.summary :: { [string]: { [string]: number } }
	local out: { [string]: string } = {
		[config.output] = definitions,
		[config.report] = json.encode(report) .. "\n",
		[config.coverage] = json.encode(coverage) .. "\n",
		[config.coverageSummary] = CoverageReport.markdown(report, coverage),
		[".github/banner.svg"] = Banner.svg(summary),
	}
	local f = summary.functions
	return {
		files = out,
		summaryLine = string.format(
			"Wrote %s: %d functions typed, %d untyped, %d excluded; see %s.",
			config.output,
			f.typed,
			f.untyped,
			f.excluded,
			config.coverageSummary
		),
	}
end

return Pipeline
