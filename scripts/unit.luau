--!strict
-- Unit tests of the generator's parsers: the case tables in tests/unit/. Each case returns its actual and
-- expected values, compared as JSON (sorted keys), so a failure prints both in full.

local process = require("@lune/process")

local Case = require("../tests/unit/case")
local Json = require("../generator/json")

local suites: { [string]: { Case.Case } } = {
	annotations = require("../tests/unit/annotations"),
	luatable = require("../tests/unit/luatable"),
	resources = require("../tests/unit/resources"),
	shapes = require("../tests/unit/shapes"),
	signatures = require("../tests/unit/signatures"),
	typeexpr = require("../tests/unit/typeexpr"),
}

local names = {}
for name in suites do
	table.insert(names, name)
end
table.sort(names)

local failures, total = 0, 0
for _, suite in names do
	for _, case in suites[suite] do
		total += 1
		local ok, actual, expected = pcall(case.run)
		local got = if ok then Json.encode(actual) else "error: " .. tostring(actual)
		local want = if ok then Json.encode(expected) else ""
		if not ok or got ~= want then
			failures += 1
			print(string.format("FAIL %s: %s\n  expected %s\n  actual   %s", suite, case.name, want, got))
		end
	end
end

print(string.format("%d of %d unit cases passed", total - failures, total))
if failures > 0 then
	process.exit(1)
end
