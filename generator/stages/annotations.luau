--!strict
-- Stage 1: reads every LuaCATS annotation file into one model: classes (merged across files), aliases,
-- global and namespaced functions, global values, and WoW's extensions of the standard tables.

local Common = require("./common")
local File = require("../luacats/file")

type AnnClass = Common.AnnClass

local Annotations = {}

-- stdTables: the Luau library tables WoW extends (`string`, `table`, `math`); `string.split` and `table.wipe`
-- are recorded as such extensions, not as namespaced functions. Parse errors are appended to `parseErrors`.
function Annotations.collect(
	files: { { path: string, source: string } },
	stdTables: { [string]: boolean },
	parseErrors: { string }
): Common.Annotations
	local ann: Common.Annotations = {
		classes = {},
		aliases = {},
		functions = {},
		values = {},
		globalClass = {},
		stdlib = {},
	}

	local function annClass(name: string, file: string): AnnClass
		local c = ann.classes[name]
		if c == nil then
			c = { name = name, parents = {}, fields = {}, methods = {}, statics = {}, file = file }
			ann.classes[name] = c
		end
		return c :: AnnClass
	end

	for _, file in files do
		local decls = File.read(file.path, file.source)
		for _, e in decls.errors do
			table.insert(parseErrors, e)
		end
		for _, cls in decls.classes do
			local c = annClass(cls.name, decls.file)
			for _, p in cls.parents do
				if not table.find(c.parents, p) and p ~= cls.name then
					table.insert(c.parents, p)
				end
			end
			local seen = {}
			for _, f in c.fields do
				seen[f.name] = true
			end
			for _, f in cls.fields do
				if f.visibility ~= "private" and f.visibility ~= "protected" and not seen[f.name] then
					seen[f.name] = true
					table.insert(c.fields, f)
				end
			end
		end
		for _, a in decls.aliases do
			if ann.aliases[a.name] == nil then
				ann.aliases[a.name] = a
			end
		end
		-- Which class each table variable holds: the file's locals, plus global tables with a ---@class.
		local holds: { [string]: string } = table.clone(decls.locals)
		for _, g in decls.globals do
			local path = g.path
			if path[1] == "_G" and #path > 1 then
				path = table.move(path, 2, #path, 1, {})
			end
			local qualified = table.concat(path, ".")
			if g.class then
				holds[qualified] = g.class
				if #path == 1 then
					ann.globalClass[qualified] = g.class
				end
			elseif g.value ~= "{}" and ann.values[qualified] == nil then
				ann.values[qualified] = g.value
			end
		end
		for _, f in decls.funcs do
			local qualified = table.concat(f.path, ".")
			local ownerPath = table.concat(f.path, ".", 1, #f.path - 1)
			local isStdExtension = #f.path == 2 and stdTables[f.path[1]] == true
			local owner = if #f.path > 1 and not isStdExtension then holds[ownerPath] else nil
			if owner == nil and #f.path > 1 and ann.classes[ownerPath] and f.method then
				owner = ownerPath -- `function Frame:SetPoint()` with the class name used directly
			end
			if owner then
				local c = annClass(owner, decls.file)
				local bucket = if f.method then c.methods else c.statics
				local name = f.path[#f.path]
				bucket[name] = bucket[name] or {}
				for _, sig in Common.withOverloads(f) do
					table.insert(bucket[name], sig)
				end
			elseif isStdExtension then
				ann.stdlib[qualified] = ann.stdlib[qualified] or f
			elseif ann.functions[qualified] == nil then
				ann.functions[qualified] = f
			end
		end
	end
	return ann
end

return Annotations
