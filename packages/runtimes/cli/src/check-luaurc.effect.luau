--!strict
-- Fails if .luaurc's `@lune` alias does not point at the type definitions of the Lune version that runs it.
--   lune run packages/runtimes/cli/src/check-luaurc.effect.luau
-- Bumping Lune in mise.toml without updating the alias would make the generator's `@lune/*` requires untyped.

local fs = require("@lune/fs")
local process = require("@lune/process")

local version = process.exec("lune", { "--version" })
if not version.ok then
	error("cannot run `lune --version`: " .. version.stderr)
end
local current = string.match(version.stdout, "(%d+%.%d+%.%d+)")
local luaurc = fs.readFile(".luaurc")
local aliased = string.match(luaurc, "%.typedefs/(%d+%.%d+%.%d+)/")

if current == nil or aliased ~= current then
	print(
		string.format(
			".luaurc's @lune alias points at %s, but Lune is %s: update the alias to `~/.lune/.typedefs/%s/`.",
			tostring(aliased),
			tostring(current),
			tostring(current)
		)
	)
	process.exit(1)
end
print(".luaurc's @lune alias matches Lune " .. (current :: string) .. ".")
