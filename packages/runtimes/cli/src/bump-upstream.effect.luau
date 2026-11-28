--!strict
-- Moves each upstream pin in upstream.toml to the current head of its branch.
--   lune run packages/runtimes/cli/src/bump-upstream.effect.luau
-- Prints a Markdown summary of what moved. With $GITHUB_OUTPUT set, writes `changed=true|false` and the
-- summary (`summary<<EOF ... EOF`) for the scheduled `upstream` workflow.

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

type Pin = { repository: string, branch: string, commit: string }

local PATH = "upstream.toml"
local text = string.gsub(fs.readFile(PATH), "\r\n", "\n")
local pins = serde.decode("toml", text) :: { [string]: Pin }

local sections = {}
for name in pins do
	table.insert(sections, name)
end
table.sort(sections)

local moved = {}
for _, section in sections do
	local pin = pins[section]
	assert(string.match(pin.repository, "^[%w_.-]+/[%w_.-]+$"), PATH .. ": bad repository in [" .. section .. "]")
	assert(string.match(pin.branch, "^[%w_./-]+$"), PATH .. ": bad branch in [" .. section .. "]")
	local url = "https://github.com/" .. pin.repository .. ".git"
	local result = process.exec("git", { "ls-remote", url, "refs/heads/" .. pin.branch })
	local found: string? = if result.ok then (string.match(result.stdout, "^(%x+)%s")) else nil
	if found == nil or #found ~= 40 then
		error("cannot read " .. pin.repository .. "@" .. pin.branch .. ": " .. result.stderr)
	end
	local head: string = found
	if head ~= pin.commit then
		-- Replace the commit line inside this section only (from its `[section]` header line to the next header);
		-- everything else in the file stays as written.
		local header = "[" .. section .. "]"
		local start = string.find("\n" .. text, "\n" .. header .. "\n", 1, true)
		assert(start, PATH .. ": no " .. header .. " header line")
		local bodyStart = start + #header -- the newline ending the header line
		local bodyEnd = string.find(text, "\n%[", bodyStart + 1) or #text -- the newline before the next header
		local old = 'commit = "' .. pin.commit .. '"'
		local escaped = string.gsub(old, "%p", "%%%0")
		local body, count =
			string.gsub(string.sub(text, bodyStart, bodyEnd), "\n" .. escaped .. "\n", '\ncommit = "' .. head .. '"\n')
		assert(count == 1, string.format("%s: expected one %s line in %s, found %d", PATH, old, header, count))
		text = string.sub(text, 1, bodyStart - 1) .. body .. string.sub(text, bodyEnd + 1)
		table.insert(
			moved,
			string.format(
				"- %s (`%s`): [`%s` → `%s`](https://github.com/%s/compare/%s...%s)",
				pin.repository,
				pin.branch,
				string.sub(pin.commit, 1, 12),
				string.sub(head, 1, 12),
				pin.repository,
				pin.commit,
				head
			)
		)
	end
end

local summary = if #moved == 0 then "Every upstream pin is at its branch head." else table.concat(moved, "\n")
print(summary)
if #moved > 0 then
	fs.writeFile(PATH, text)
end

local output = process.env.GITHUB_OUTPUT
if output then
	local existing = if fs.isFile(output) then fs.readFile(output) else ""
	fs.writeFile(output, existing .. "changed=" .. tostring(#moved > 0) .. "\nsummary<<EOF\n" .. summary .. "\nEOF\n")
end
