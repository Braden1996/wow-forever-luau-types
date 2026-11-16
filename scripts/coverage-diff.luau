--!strict
-- Compares definitions/coverage.json against a base version of it:
--   lune run scripts/coverage-diff                         base: definitions/coverage.json at the git ref
--                                                           $COVERAGE_BASE (default origin/main)
--   lune run scripts/coverage-diff -- <base.json> [current.json]
-- Fails if definitions/api-shapes.json does not shape exactly the functions and widget methods listed, or if
-- an API that the base typed is untyped now (a coverage regression), unless scripts/coverage-accepted.json
-- lists it: a reviewed list of regressions the maintainer accepted, with the reason (emptied once merged). APIs that left the
-- client, newly typed APIs and new untyped APIs are reported, not failed. Writes a Markdown summary
-- to $GITHUB_STEP_SUMMARY when set.

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local config = require("../generator/config")

type Entry = { status: string, source: string?, note: string? }
type Coverage = { [string]: { [string]: Entry } }

local args: { string } = {}
for _, a in process.args do
	if a ~= "--" then
		table.insert(args, a)
	end
end
local currentPath = args[2] or config.coverage
local current = serde.decode("json", fs.readFile(currentPath)) :: Coverage

local function fail(message: string): never
	print("coverage-diff: " .. message)
	process.exit(1)
	error(message) -- unreachable: process.exit does not return
end

-- api-shapes.json classifies exactly the functions and widget methods coverage.json lists.
local function shapeMismatches(): { string }
	local shapes = serde.decode("json", fs.readFile(config.shapes)) :: { [string]: { [string]: unknown } }
	local out: { string } = {}
	for _, category in { "functions", "widgetMethods" } do
		local listed = current[category] or {}
		local shaped = shapes[category] or {}
		for name in listed do
			if shaped[name] == nil then
				table.insert(out, category .. ": " .. name .. " has no shape")
			end
		end
		for name in shaped do
			if listed[name] == nil then
				table.insert(out, category .. ": " .. name .. " has a shape but no coverage entry")
			end
		end
	end
	table.sort(out)
	return out
end
local mismatches = if args[2] then {} :: { string } else shapeMismatches() -- a given current.json has no shapes beside it
if #mismatches > 0 then
	fail(config.shapes .. " and " .. currentPath .. " disagree:\n" .. table.concat(mismatches, "\n"))
end

local function git(gitArgs: { string }): (boolean, string)
	local result = process.exec("git", gitArgs, { stdin = "" })
	return result.ok, result.stdout
end

-- The base coverage: a file given on the command line (it must exist), or the committed file at a git ref.
-- A ref that does not resolve is an error when the base was asked for ($COVERAGE_BASE) or in CI, where a
-- shallow clone would otherwise skip the comparison silently; locally, without origin/main, it is skipped.
-- A ref that resolves but predates the coverage file is the one case with nothing to compare.
local baseText: string
if args[1] then
	if not fs.isFile(args[1]) then
		fail("base file " .. args[1] .. " does not exist")
	end
	baseText = fs.readFile(args[1])
else
	local ref = process.env.COVERAGE_BASE or "origin/main"
	local required = process.env.COVERAGE_BASE ~= nil or process.env.CI ~= nil
	if not git({ "rev-parse", "--verify", "--quiet", ref .. "^{commit}" }) then
		if required then
			fail("base ref " .. ref .. " does not resolve to a commit (fetch it, or set COVERAGE_BASE)")
		end
		print("No base ref " .. ref .. " here; nothing to compare.")
		process.exit(0)
	end
	local ok, shown = git({ "show", ref .. ":" .. config.coverage })
	if not ok then
		print(ref .. " has no " .. config.coverage .. "; nothing to compare.")
		process.exit(0)
	end
	baseText = shown
end
local base = serde.decode("json", baseText) :: Coverage

-- Regressions the maintainer accepted, by category: { reason: string, [category]: { name } }.
local ACCEPTED_PATH = "scripts/coverage-accepted.json"
local acceptedFile = serde.decode("json", fs.readFile(ACCEPTED_PATH)) :: { [string]: any }
local accepted: { [string]: { [string]: boolean } } = {}
for key, names in acceptedFile do
	if key ~= "reason" then
		local set: { [string]: boolean } = {}
		for _, name in names :: { string } do
			set[name] = true
		end
		accepted[key] = set
	end
end

local function sortedKeys<V>(t: { [string]: V }): { string }
	local keys = {}
	for k in t do
		table.insert(keys, k)
	end
	table.sort(keys)
	return keys
end

local lines = {
	"## Coverage change",
	"",
	"| Category | Typed (base → now) | Newly typed | Regressed | Left the client |",
	"| --- | --- | ---: | ---: | ---: |",
}
local regressions: { string } = {}
local acceptedCount = 0
for _, category in sortedKeys(current) do
	local now = current[category]
	local before = base[category] or {}
	local typedBefore, typedNow, gained, lost, gone = 0, 0, 0, 0, 0
	for _, e in before do
		if e.status == "typed" then
			typedBefore += 1
		end
	end
	for name, e in now do
		if e.status == "typed" then
			typedNow += 1
			if before[name] == nil or before[name].status ~= "typed" then
				gained += 1
			end
		end
	end
	for _, name in sortedKeys(before) do
		local b = before[name]
		local n = now[name]
		if b.status == "typed" then
			if n == nil or n.status == "excluded" then
				gone += 1
			elseif n.status == "untyped" then
				lost += 1
				if (accepted[category] or {})[name] then
					acceptedCount += 1
				else
					table.insert(regressions, category .. ": " .. name .. " (was " .. (b.source or "?") .. ")")
				end
			end
		end
	end
	table.insert(
		lines,
		string.format("| %s | %d → %d | %d | %d | %d |", category, typedBefore, typedNow, gained, lost, gone)
	)
end

if acceptedCount > 0 then
	table.insert(lines, "")
	table.insert(
		lines,
		string.format("%d regression(s) accepted by %s: %s", acceptedCount, ACCEPTED_PATH, acceptedFile.reason)
	)
end
if #regressions > 0 then
	table.insert(lines, "")
	table.insert(lines, "### Regressions (typed before, untyped now)")
	table.insert(lines, "")
	for _, r in regressions do
		table.insert(lines, "- " .. r)
	end
end

local summary = table.concat(lines, "\n") .. "\n"
print(summary)
local stepSummary = process.env.GITHUB_STEP_SUMMARY
if stepSummary then
	local existing = if fs.isFile(stepSummary) then fs.readFile(stepSummary) else ""
	fs.writeFile(stepSummary, existing .. summary)
end
if #regressions > 0 then
	print(
		#regressions
			.. " API(s) lost their types. Fix the cause, or, if the maintainer accepts the loss, list them in "
			.. ACCEPTED_PATH
			.. " with the reason."
	)
	process.exit(1)
end
