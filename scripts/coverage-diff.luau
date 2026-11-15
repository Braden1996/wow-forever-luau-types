--!strict
-- Compares definitions/coverage.json against a base version of it:
--   lune run scripts/coverage-diff -- <base coverage.json> [current coverage.json]
-- Fails if an API that the base typed is untyped now (a coverage regression). APIs that left the
-- client, newly typed APIs and new untyped APIs are reported, not failed. Writes a Markdown summary
-- to $GITHUB_STEP_SUMMARY when set.

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local config = require("../generator/config")

type Entry = { status: string, source: string?, reason: string? }
type Coverage = { [string]: { [string]: Entry } }

local args: { string } = {}
for _, a in process.args do
	if a ~= "--" then
		table.insert(args, a)
	end
end
local basePath = args[1]
local currentPath = args[2] or config.coverage
if basePath == nil then
	print("usage: lune run scripts/coverage-diff -- <base coverage.json>")
	process.exit(2)
end

local current = serde.decode("json", fs.readFile(currentPath)) :: Coverage
if not fs.isFile(basePath :: string) then
	print("No base coverage at " .. (basePath :: string) .. "; nothing to compare.")
	process.exit(0)
end
local base = serde.decode("json", fs.readFile(basePath :: string)) :: Coverage

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
				table.insert(regressions, category .. ": " .. name .. " (was " .. (b.source or "?") .. ")")
			end
		end
	end
	table.insert(
		lines,
		string.format("| %s | %d → %d | %d | %d | %d |", category, typedBefore, typedNow, gained, lost, gone)
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
	print(#regressions .. " API(s) lost their types. Fix the cause, or explain the loss in the pull request.")
	process.exit(1)
end
