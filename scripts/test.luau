--!strict
-- Type-checks the samples against the generated definitions with luau-lsp and Luau's new solver.
--   tests/pass/<addon>/, templates/<name>/   every .luau file must get zero diagnostics (a .d.luau there is loaded as
--                         that addon's own definitions file)
-- luau-lsp gets the generated definitions and settings (definitions/luau-lsp.settings.json), as an editor would.
--   tests/fail/*.luau     the diagnostics must equal tests/fail/<name>.expected exactly (line,
--                         column and full message), and every line marked `-- expect-error: <text>`
--                         must be among them
-- `lune run scripts/test -- --update` rewrites the .expected files; review the diff.

local fs = require("@lune/fs")
local process = require("@lune/process")

local config = require("../packages/generator/src/config")

local update = table.find(process.args, "--update") ~= nil

type Diagnostic = { file: string, line: number, column: number, text: string }

-- Files under `dir` ending in `suffix`, sorted; with `recursive`, subfolders too (not hidden ones).
local function listFiles(dir: string, suffix: string, recursive: boolean?): { string }
	local out = {}
	local entries = fs.readDir(dir)
	table.sort(entries)
	for _, entry in entries do
		local path = dir .. "/" .. entry
		if fs.isFile(path) and string.sub(entry, -#suffix) == suffix then
			table.insert(out, path)
		elseif recursive and fs.isDir(path) and string.sub(entry, 1, 1) ~= "." then
			for _, nested in listFiles(path, suffix, true) do
				table.insert(out, nested)
			end
		end
	end
	return out
end

local function isDefinitions(path: string): boolean
	return string.sub(path, -7) == ".d.luau"
end

-- A template's types/wow-forever.d.luau is this repository's generated file (users download it into their addon); the
-- tests load definitions/ instead, so a stale copy there is never read.
local function isGeneratedCopy(path: string): boolean
	return string.sub(path, -#"/types/wow-forever.d.luau") == "/types/wow-forever.d.luau"
end

-- Runs luau-lsp analyze and returns its diagnostics, multi-line messages joined.
local function analyze(definitions: { string }, files: { string }): { Diagnostic }
	local args = {
		"analyze",
		"--platform=standard",
		"--flag:LuauSolverV2=true",
		"--definitions=@wow=" .. config.output,
		"--settings=" .. config.settings,
	}
	for i, def in definitions do
		table.insert(args, "--definitions=@addon" .. i .. "=" .. def)
	end
	for _, f in files do
		table.insert(args, f)
	end
	local result = process.exec("luau-lsp", args, { stdin = "" })
	local output = string.gsub(result.stdout .. "\n" .. result.stderr, "\r", "")
	local function broken(why: string): never
		print(output)
		error("luau-lsp " .. why)
	end
	local diagnostics: { Diagnostic } = {}
	local current: Diagnostic? = nil
	for line in string.gmatch(output, "[^\n]+") do
		local file, lineNo, column, text = string.match(line, "^(.-)%((%d+),(%d+)%): (.*)$")
		if file and lineNo and column and text then
			current = {
				file = (string.gsub(file, "\\", "/")),
				line = tonumber(lineNo) :: number,
				column = tonumber(column) :: number,
				text = text,
			}
			table.insert(diagnostics, current :: Diagnostic)
		elseif string.match(line, "^%[ERROR%]") then
			broken("failed: " .. line) -- e.g. a definitions file it could not read
		elseif string.match(line, "^%[") then
			continue -- [INFO] and [WARN] lines
		elseif current == nil or string.match(line, "^%S+: %a*Error: ") or string.match(line, "^Cannot get ") then
			-- Not the continuation of a message: a diagnostic without a position (a syntax error in a
			-- definitions file prints `file: SyntaxError: ...`), or a file luau-lsp could not open.
			broken("printed a line this script cannot parse: " .. line)
		else
			(current :: Diagnostic).text ..= "\n" .. line
		end
	end
	if not result.ok and #diagnostics == 0 then
		broken("exited with code " .. result.code .. " but reported no diagnostics")
	end
	table.sort(diagnostics, function(a: Diagnostic, b: Diagnostic): boolean
		if a.line ~= b.line then
			return a.line < b.line
		end
		if a.column ~= b.column then
			return a.column < b.column
		end
		return a.text < b.text
	end)
	return diagnostics
end

local failures = 0
local function fail(message: string)
	failures += 1
	print("FAIL " .. message)
end

-- Passing samples and templates: each folder is one addon; its own definitions files are loaded with the generated
-- ones (not its copy of types/wow-forever.d.luau, see isGeneratedCopy).
local passDirs: { string } = {}
for _, root in { "tests/pass", "templates" } do
	local names = fs.readDir(root)
	table.sort(names)
	for _, name in names do
		if fs.isDir(root .. "/" .. name) then
			table.insert(passDirs, root .. "/" .. name)
		end
	end
end
for _, dir in passDirs do
	local definitions: { string }, sources: { string } = {}, {}
	for _, f in listFiles(dir, ".luau", true) do
		if isGeneratedCopy(f) then
			continue
		end
		table.insert(if isDefinitions(f) then definitions else sources, f)
	end
	local diagnostics = analyze(definitions, sources)
	for _, d in diagnostics do
		fail(string.format("%s:%d:%d: unexpected diagnostic: %s", d.file, d.line, d.column, d.text))
	end
	print(string.format("%s %s (%d files)", if #diagnostics == 0 then "ok  " else "FAIL", dir, #sources))
end

-- Failing samples: exactly the expected diagnostics.
for _, file in listFiles("tests/fail", ".luau") do
	local diagnostics = analyze({}, { file })
	local lines = {}
	for _, d in diagnostics do
		table.insert(lines, string.format("%d:%d: %s", d.line, d.column, d.text))
	end
	local actual = table.concat(lines, "\n") .. "\n"
	local expectedPath = string.gsub(file, "%.luau$", ".expected")
	local ok = true
	if update then
		fs.writeFile(expectedPath, actual)
	else
		local expected = if fs.isFile(expectedPath) then string.gsub(fs.readFile(expectedPath), "\r\n", "\n") else nil
		if expected ~= actual then
			ok = false
			fail(file .. ": diagnostics differ from " .. expectedPath .. ". Actual:\n" .. actual)
		end
	end
	-- Every marked line must produce an error containing its phrase, and only marked lines may.
	local sourceLines = string.split(string.gsub(fs.readFile(file), "\r", ""), "\n")
	local byLine: { [number]: { string } } = {}
	for _, d in diagnostics do
		byLine[d.line] = byLine[d.line] or {}
		table.insert(byLine[d.line], d.text)
	end
	local marked = 0
	for lineNo, line in sourceLines do
		local phrase = string.match(line, "%-%- expect%-error: (.-)%s*$")
		if phrase then
			marked += 1
			local found = false
			for _, text in (byLine[lineNo] or {}) :: { string } do
				if string.find(text, phrase, 1, true) then
					found = true
				end
			end
			if not found then
				ok = false
				fail(string.format("%s:%d: expected an error containing %q", file, lineNo, phrase))
			end
		end
	end
	for lineNo in byLine do
		local text = sourceLines[lineNo] or ""
		if not string.find(text, "expect-error:", 1, true) then
			ok = false
			fail(string.format("%s:%d: a diagnostic on a line not marked expect-error", file, lineNo))
		end
	end
	print(
		string.format(
			"%s %s (%d diagnostics, %d marked lines)",
			if ok then "ok  " else "FAIL",
			file,
			#diagnostics,
			marked
		)
	)
end

if failures > 0 then
	print(failures .. " failure(s)")
	process.exit(1)
end
