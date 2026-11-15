--!strict
-- Builds every addon template (each folder under templates/ with a .darklua.json) the way its users will, with
-- darklua (Luau -> Lua 5.1), and checks the template and the result:
--   * the template has exactly one .toc; every line of it that is not blank or a `#` comment is `build/<File>.lua`,
--     and it loads at least one file;
--   * the `build` task in the template's mise.toml compiles exactly the files the .toc loads, one line each:
--     `darklua process src/<File>.luau build/<File>.lua`;
--   * darklua compiles each `src/<File>.luau` the .toc names, with the template's .darklua.json;
--   * every output file parses as Lua 5.1 (StyLua with `--syntax Lua51`);
--   * no output `for ... in <expr> do` iterates a table directly (Luau's generalized iteration parses as Lua 5.1
--     but fails in WoW): the iterator must be a call such as `pairs(t)` or an explicit `f, s, var` list;
--   * selene, with the plain Lua 5.1 standard library, finds no Luau-only library call (`table.clone`,
--     `table.find`, `string.split`, ...) in the output. Undefined globals are allowed: WoW provides its own.
-- Run with `lune run scripts/template-build`; darklua, stylua and selene must be on PATH (mise).

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local OUT = ".upstream/template-build" -- ignored by git, like the upstream cache

-- Lua 5.1, as WoW runs it. Only standard-library misuse matters here; WoW's own globals are not in this std.
local SELENE_CONFIG = 'std = "lua51"\n\n[rules]\nundefined_variable = "allow"\n'

local function luaFiles(dir: string): { string }
	local out = {}
	local entries = fs.readDir(dir)
	table.sort(entries)
	for _, entry in entries do
		local path = dir .. "/" .. entry
		if fs.isDir(path) then
			for _, nested in luaFiles(path) do
				table.insert(out, nested)
			end
		elseif string.match(entry, "%.lua$") then
			table.insert(out, path)
		end
	end
	return out
end

-- Every `for <names> in <explist> do` whose explist is a single expression that does not end in a call.
local function bareIterations(source: string): { string }
	local found = {}
	for rawNames, rawExplist in string.gmatch(source, "%f[%w_]for%s+([%w_%s,]-)%s+in%f[^%w_](.-)%f[%w_]do%f[^%w_]") do
		local names, explist = rawNames :: string, rawExplist :: string
		local trimmed = string.match(explist, "^%s*(.-)%s*$") or explist
		if string.sub(trimmed, -1) ~= ")" and not string.find(trimmed, ",", 1, true) then
			table.insert(found, "for " .. names .. " in " .. trimmed .. " do")
		end
	end
	return found
end

-- The files a template's .toc loads, as `File` from `build/File.lua`, in load order.
local function tocFiles(dir: string, fail: (string) -> ()): { string }
	local tocs = {}
	for _, entry in fs.readDir(dir) do
		if string.match(entry, "%.toc$") then
			table.insert(tocs, entry)
		end
	end
	if #tocs ~= 1 then
		fail(string.format("%s: expected one .toc, found %d", dir, #tocs))
		return {}
	end
	local toc = dir .. "/" .. tocs[1]
	local files = {}
	for lineNo, line in string.split(string.gsub(fs.readFile(toc), "\r", ""), "\n") do
		local trimmed = string.match(line, "^%s*(.-)%s*$") or line
		if trimmed ~= "" and string.sub(trimmed, 1, 1) ~= "#" then
			local file = string.match(trimmed, "^build/([%w_]+)%.lua$")
			if file then
				table.insert(files, file)
			else
				fail(string.format("%s:%d: %q is not `build/<File>.lua`", toc, lineNo, trimmed))
			end
		end
	end
	if #files == 0 then
		fail(toc .. ": loads no files")
	end
	return files
end

-- The files the `build` task in the template's mise.toml compiles, as `File`, sorted.
local function buildTaskFiles(dir: string, fail: (string) -> ()): { string }
	local path = dir .. "/mise.toml"
	local decoded: any = serde.decode("toml", fs.readFile(path))
	local build = decoded.tasks and decoded.tasks.build
	local run: unknown = if type(build) == "table" then build.run else nil
	local commands: { unknown } = if type(run) == "string"
		then { run }
		elseif type(run) == "table" then run :: any
		else {}
	local files = {}
	for _, command in commands do
		local text = tostring(command)
		local src, built = string.match(text, "^darklua process src/([%w_]+)%.luau build/([%w_]+)%.lua$")
		if src and src == built then
			table.insert(files, src)
		else
			fail(
				string.format("%s: build line %q is not `darklua process src/<File>.luau build/<File>.lua`", path, text)
			)
		end
	end
	if #files == 0 then
		fail(path .. ": the build task compiles no files")
	end
	table.sort(files)
	return files
end

local failures = 0
local templates = fs.readDir("templates")
table.sort(templates)
for _, name in templates do
	local dir = "templates/" .. name
	if not fs.isFile(dir .. "/.darklua.json") then
		continue
	end
	local templateFailures = 0
	local function fail(message: string)
		templateFailures += 1
		print("FAIL " .. message)
	end

	local out = OUT .. "/" .. name
	if fs.isDir(out) then
		fs.removeDir(out)
	end
	fs.writeDir(out)

	local loaded = tocFiles(dir, fail)
	local sortedLoaded = table.clone(loaded)
	table.sort(sortedLoaded)
	local built = buildTaskFiles(dir, fail)
	if table.concat(sortedLoaded, ", ") ~= table.concat(built, ", ") then
		fail(
			string.format(
				"%s: the .toc loads {%s} but the mise.toml build task compiles {%s}",
				dir,
				table.concat(sortedLoaded, ", "),
				table.concat(built, ", ")
			)
		)
	end

	for _, file in loaded do
		local source = dir .. "/src/" .. file .. ".luau"
		if not fs.isFile(source) then
			fail(source .. " is missing (the .toc loads build/" .. file .. ".lua)")
			continue
		end
		local args = { "process", "--config", dir .. "/.darklua.json", source, out .. "/" .. file .. ".lua" }
		local result = process.exec("darklua", args)
		if not result.ok then
			fail(source .. ": darklua failed:\n" .. result.stderr)
		end
	end

	local files = luaFiles(out)
	for _, file in files do
		local source = fs.readFile(file)
		local parsed = process.exec("stylua", { "--syntax", "Lua51", "-" }, { stdin = source })
		if not parsed.ok then
			fail(file .. " is not valid Lua 5.1:\n" .. parsed.stderr)
		end
		for _, loop in bareIterations(source) do
			fail(file .. ": `" .. loop .. "` iterates a table directly; use pairs() or ipairs() (Lua 5.1)")
		end
	end
	if #files > 0 then
		local config = out .. "/selene.toml"
		fs.writeFile(config, SELENE_CONFIG)
		local args = { "--config", config, "--display-style", "quiet" }
		for _, file in files do
			table.insert(args, file)
		end
		-- Only errors count (Luau-only library calls, parse errors): selene's style warnings are about darklua's
		-- output, not the template's code.
		local linted = process.exec("selene", args)
		local output = linted.stdout .. linted.stderr
		local errors = {}
		for line in string.gmatch(output, "[^\r\n]+") do
			if string.find(line, ": error[", 1, true) then
				table.insert(errors, line)
			end
		end
		local parseErrors = tonumber(string.match(output, "(%d+) parse errors") or "")
		if #errors > 0 or parseErrors ~= 0 then
			local detail = if #errors > 0 then table.concat(errors, "\n") else output
			fail(dir .. ": selene (Lua 5.1 standard library) found errors in the build:\n" .. detail)
		end
	end

	failures += templateFailures
	print(string.format("%s %s (%d Lua 5.1 files)", if templateFailures == 0 then "ok  " else "FAIL", dir, #files))
end

if failures > 0 then
	process.exit(1)
end
