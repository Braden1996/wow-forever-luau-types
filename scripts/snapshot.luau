--!strict
-- Converter snapshot tests. Each folder in tests/snapshots/ is one case:
--   annotations/*.lua   LuaCATS annotations (as in Ketho/vscode-wow-api)
--   docs/*.lua          Blizzard_APIDocumentationGenerated tables
--   client/*.lua        BlizzardInterfaceResources dumps (GlobalAPI.lua, WidgetAPI.lua, ...)
--   expected.d.luau, expected.coverage.json   the converter's output
-- The case is built with the real generator config. Every expected.d.luau must also load in luau-lsp.
-- `lune run scripts/snapshot -- --update` rewrites the expected files; review the diff.

local fs = require("@lune/fs")
local process = require("@lune/process")

local ApiDocs = require("../generator/apidocs")
local Build = require("../generator/build")
local Resources = require("../generator/resources")
local TextFile = require("../generator/textfile")
local config = require("../generator/config")
local json = require("../generator/json")

local update = table.find(process.args, "--update") ~= nil
local ROOT = "tests/snapshots"
local PROBE_DIR = ".upstream/snapshot-probes" -- ignored by git, like the upstream cache

local function readDir(dir: string): { { name: string, source: string } }
	if not fs.isDir(dir) then
		return {}
	end
	return TextFile.readAll(dir, "%.lua$")
end

local PIN = { repository = "example/snapshot", commit = string.rep("0", 40) }

local failures = 0
local cases = fs.readDir(ROOT)
table.sort(cases)
for _, case in cases do
	local dir = ROOT .. "/" .. case
	if not fs.isDir(dir) then
		continue
	end
	local annotationFiles = {}
	for _, f in readDir(dir .. "/annotations") do
		table.insert(annotationFiles, { path = "annotations/" .. f.name, source = f.source })
	end
	local client = {}
	for _, f in readDir(dir .. "/client") do
		client[f.name] = f.source
	end
	local definitions, _, coverage = Build.run({
		files = annotationFiles,
		docs = ApiDocs.parse(readDir(dir .. "/docs")),
		resources = Resources.parse(client),
		reserved = {},
		upstream = { annotations = PIN, docs = PIN, resources = PIN },
		config = config,
	})
	local outputs: { [string]: string } = {
		["expected.d.luau"] = definitions .. "\n",
		["expected.coverage.json"] = json.encode(coverage) .. "\n",
	}
	local ok = true
	for name, actual in outputs do
		local path = dir .. "/" .. name
		if update then
			fs.writeFile(path, actual)
		else
			local expected = if fs.isFile(path) then TextFile.read(path) else nil
			if expected ~= actual then
				ok = false
				print("FAIL " .. path .. " differs. Actual:\n" .. actual)
			end
		end
	end
	-- The expected definitions must be valid for luau-lsp. The probe lives in the ignored .upstream/ cache,
	-- never in the tracked case folders; stdin is empty so luau-lsp cannot wait on the caller's console.
	fs.writeDir(PROBE_DIR)
	local probe = PROBE_DIR .. "/" .. case .. ".luau"
	fs.writeFile(probe, "--!strict\nlocal _ = 1\n")
	local result = process.exec("luau-lsp", {
		"analyze",
		"--platform=standard",
		"--flag:LuauSolverV2=true",
		"--definitions=@case=" .. dir .. "/expected.d.luau",
		probe,
	}, { stdin = "" })
	fs.removeFile(probe)
	local output = result.stdout .. result.stderr
	if string.find(output, "Failed to read definitions file", 1, true) or not result.ok then
		ok = false
		print("FAIL " .. dir .. "/expected.d.luau does not load in luau-lsp:\n" .. output)
	end
	if not ok then
		failures += 1
	end
	print(string.format("%s %s", if ok then "ok  " else "FAIL", dir))
end

if failures > 0 then
	print(failures .. " snapshot case(s) failed")
	process.exit(1)
end
