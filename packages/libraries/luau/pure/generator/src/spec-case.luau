--!strict
-- Helper converting JSON-compared unit cases into Sergeant spec entries (`{ name, run }`).

local Json = require("./json")

export type Case = { name: string, run: () -> (unknown, unknown) }
export type Spec = { name: string, run: () -> () }

local function specs(cases: { Case }): { Spec }
	local out: { Spec } = {}
	for _, case in cases do
		table.insert(out, {
			name = case.name,
			run = function()
				local actual, expected = case.run()
				local got = Json.encode(actual)
				local want = Json.encode(expected)
				if got ~= want then
					error(string.format("expected %s\n  actual   %s", want, got))
				end
			end,
		})
	end
	return out
end

return {
	specs = specs,
}
