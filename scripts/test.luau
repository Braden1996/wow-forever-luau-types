--!strict
-- Type-checks the samples against the generated definitions with luau-lsp.
--   tests/pass/<addon>/   every .luau file must have zero diagnostics (a .d.luau there is loaded as
--                         that addon's own definitions file)
--   tests/fail/*.luau     every line ending in `-- expect-error: <text>` must get a diagnostic that
--                         contains <text>, and no other line may get one
-- Run with `lune run scripts/test`; luau-lsp must be on PATH (`mise exec -- lune run scripts/test`).

local fs = require("@lune/fs")
local process = require("@lune/process")

local config = require("../generator/config")

type Diagnostic = { file: string, line: number, text: string }

local function listFiles(dir: string, suffix: string): { string }
	local out = {}
	local entries = fs.readDir(dir)
	table.sort(entries)
	for _, entry in entries do
		local path = dir .. "/" .. entry
		if fs.isFile(path) and string.sub(entry, -#suffix) == suffix then
			table.insert(out, path)
		end
	end
	return out
end

local function isDefinitions(path: string): boolean
	return string.sub(path, -7) == ".d.luau"
end

-- Runs luau-lsp analyze and returns its diagnostics, grouped from its multi-line output.
local function analyze(definitions: { string }, files: { string }): { Diagnostic }
	local args = { "analyze", "--platform=standard", "--definitions=@wow=" .. config.output }
	for i, def in definitions do
		table.insert(args, "--definitions=@addon" .. i .. "=" .. def)
	end
	for _, f in files do
		table.insert(args, f)
	end
	local result = process.exec("luau-lsp", args)
	local output = result.stdout .. "\n" .. result.stderr
	if string.find(output, "Failed to read definitions file", 1, true) then
		print(output)
		error("luau-lsp could not load the definitions")
	end
	local diagnostics: { Diagnostic } = {}
	local current: Diagnostic? = nil
	for line in string.gmatch(string.gsub(output, "\r", ""), "[^\n]+") do
		local file, lineNo, text = string.match(line, "^(.-)%((%d+),%d+%): (.*)$")
		if file and lineNo then
			current = { file = string.gsub(file, "\\", "/"), line = tonumber(lineNo) :: number, text = text :: string }
			table.insert(diagnostics, current :: Diagnostic)
		elseif current and not string.match(line, "^%[") then
			current.text ..= "\n" .. line
		end
	end
	return diagnostics
end

local failures = 0
local function fail(message: string)
	failures += 1
	print("FAIL " .. message)
end

-- Passing samples: each folder is one addon.
local passDirs = fs.readDir("tests/pass")
table.sort(passDirs)
for _, name in passDirs do
	local dir = "tests/pass/" .. name
	local definitions, sources = {}, {}
	for _, f in listFiles(dir, ".luau") do
		table.insert(if isDefinitions(f) then definitions else sources, f)
	end
	local diagnostics = analyze(definitions, sources)
	for _, d in diagnostics do
		fail(string.format("%s:%d: unexpected diagnostic: %s", d.file, d.line, d.text))
	end
	print(string.format("%s %s (%d files)", if #diagnostics == 0 then "ok  " else "FAIL", dir, #sources))
end

-- Failing samples: every expected error, and nothing else.
for _, file in listFiles("tests/fail", ".luau") do
	local expected: { [number]: string } = {}
	local lineNo = 0
	for line in string.gmatch(string.gsub(fs.readFile(file), "\r", "") .. "\n", "([^\n]*)\n") do
		lineNo += 1
		local phrase = string.match(line, "%-%- expect%-error: (.-)%s*$")
		if phrase then
			expected[lineNo] = phrase
		end
	end
	local byLine: { [number]: { string } } = {}
	for _, d in analyze({}, { file }) do
		byLine[d.line] = byLine[d.line] or {}
		table.insert(byLine[d.line], d.text)
	end
	local count, ok = 0, true
	for line, phrase in expected do
		count += 1
		local found = false
		for _, text in (byLine[line] or {}) :: { string } do
			if string.find(text, phrase, 1, true) then
				found = true
			end
		end
		if not found then
			ok = false
			fail(string.format("%s:%d: expected an error containing %q", file, line, phrase))
		end
	end
	for line, texts in byLine do
		if expected[line] == nil then
			ok = false
			fail(string.format("%s:%d: unexpected diagnostic: %s", file, line, texts[1]))
		end
	end
	print(string.format("%s %s (%d expected errors)", if ok then "ok  " else "FAIL", file, count))
end

if failures > 0 then
	print(failures .. " failure(s)")
	process.exit(1)
end
