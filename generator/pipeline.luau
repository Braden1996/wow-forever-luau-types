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
local Settings = require("./stages/settings")
local TextFile = require("./textfile")
local config = require("./config")
local json = require("./json")

export type Pin = { repository: string, commit: string, sparse: string? }
export type Pins = { annotations: Pin, docs: Pin, resources: Pin }

local Pipeline = {}

-- A path segment of an upstream name: no `.`/`..`, nothing that starts with `.` or `-` (a git option).
local function safeSegment(segment: string): boolean
	return string.match(segment, "^[%w_][%w_.-]*$") ~= nil
end

-- Checks upstream.toml's decoded contents and returns them typed; errors name the bad key.
function Pipeline.validatePins(raw: unknown): Pins
	if type(raw) ~= "table" then
		error("upstream.toml: expected tables [annotations], [docs] and [resources]")
	end
	local function pin(section: string): Pin
		local t = (raw :: { [string]: unknown })[section]
		if type(t) ~= "table" then
			error("upstream.toml: missing [" .. section .. "]")
		end
		local fields = t :: { [string]: unknown }
		local repository, commit, sparse = fields.repository, fields.commit, fields.sparse
		if type(repository) ~= "string" then
			error("upstream.toml: " .. section .. ".repository must be a string")
		end
		local owner, name = string.match(repository, "^([^/]+)/([^/]+)$")
		if owner == nil or name == nil or not safeSegment(owner) or not safeSegment(name) then
			error("upstream.toml: " .. section .. ".repository must be owner/name, got " .. repository)
		end
		if type(commit) ~= "string" or #commit ~= 40 or not string.match(commit, "^%x+$") then
			error("upstream.toml: " .. section .. ".commit must be a full 40-character SHA")
		end
		if sparse ~= nil then
			if type(sparse) ~= "string" then
				error("upstream.toml: " .. section .. ".sparse must be a string")
			end
			for _, segment in string.split(sparse, "/") do
				if not safeSegment(segment) then
					error("upstream.toml: " .. section .. ".sparse has an unsafe path segment: " .. segment)
				end
			end
		end
		return { repository = repository, commit = commit, sparse = sparse :: string? }
	end
	return { annotations = pin("annotations"), docs = pin("docs"), resources = pin("resources") }
end

local function git(args: { string }, cwd: string)
	local result = process.exec("git", args, { cwd = cwd, stdin = "" })
	if not result.ok then
		error("git " .. table.concat(args, " ") .. " failed:\n" .. result.stderr)
	end
end

-- A shallow (optionally sparse) checkout of one commit, cached under .upstream/<owner>/<repo>/<commit>.
-- `pin` must come from validatePins (its names are safe as paths).
function Pipeline.fetch(pin: Pin): string
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
	local sparse = pin.sparse
	if sparse then
		git({ "sparse-checkout", "set", "--no-cone", "/" .. sparse .. "/" }, tmp)
		git({ "fetch", "--quiet", "--depth", "1", "--filter=blob:none", "origin", pin.commit }, tmp)
	else
		git({ "fetch", "--quiet", "--depth", "1", "origin", pin.commit }, tmp)
	end
	git({ "-c", "advice.detachedHead=false", "checkout", "--quiet", "FETCH_HEAD" }, tmp)
	fs.move(tmp, dir)
	return dir
end

export type Result = { files: { [string]: string }, summaryLine: string }

function Pipeline.run(): Result
	local pins = Pipeline.validatePins(serde.decode("toml", TextFile.read("upstream.toml")))
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
				table.insert(files, { path = path, source = TextFile.read(full) })
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

	local resourceFiles: { [string]: string } = {}
	for _, name in config.resourceFiles do
		resourceFiles[name] = TextFile.read(resourcesDir .. "/Resources/" .. name)
	end
	local resources = Resources.parse(resourceFiles)
	local docs = ApiDocs.parse(TextFile.readAll(docsDir .. "/" .. config.docsPath, "%.lua$"))

	-- Hand-written supplements are appended verbatim; the generator leaves the names they declare alone.
	local supplementText = ""
	local supplementNames: { [string]: boolean } = {}
	for _, supplement in config.supplements do
		local text = TextFile.read(supplement)
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
		config = config,
	})
	if #report.unusedOverrides > 0 then
		error(
			"generator/rules/widgets.luau: these paramTypeOverrides match no typed function or method: "
				.. table.concat(report.unusedOverrides, ", ")
		)
	end
	definitions ..= "\n" .. supplementText

	local summary = report.summary
	local out: { [string]: string } = {
		[config.output] = definitions,
		[config.report] = json.encode(report) .. "\n",
		[config.coverage] = json.encode(coverage) .. "\n",
		[config.coverageSummary] = CoverageReport.markdown(report, coverage),
		[config.settings] = Settings.json(resources, config),
		[config.templateSettings] = Settings.json(resources, config),
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
