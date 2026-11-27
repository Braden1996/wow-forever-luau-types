--!strict
-- Stage 5 and the globals section of the output: every function the client has (typed from the docs, the
-- annotations or Luau's standard library, else untyped), named frames, mixins, Enum, Constants and the LE_*
-- values, emitted as `declare` statements.

local Common = require("./common")
local Decls = require("../luacats/decls")
local Signatures = require("./signatures")

type Context = Common.Context
type Node = Common.Node
type Signature = Decls.Signature

local Globals = {}

-- The global namespace tree, and which client list each function came from.
export type Tree = {
	root: Node,
	clientFunctions: { [string]: string }, -- qualified name -> "C API" | "Lua" | "FrameXML"
}

local function nodeAt(root: Node, path: { string }, upto: number): Node?
	local node: Node = root
	for i = 1, upto do
		local child = node.children[path[i]]
		if child == nil then
			child = { kind = "ns", children = {}, sigs = {} } :: Node
			node.children[path[i]] = child :: Node
		elseif (child :: Node).kind ~= "ns" then
			return nil
		end
		node = child :: Node
	end
	return node
end

-- How one client function is declared, and how coverage records it.
type Source =
	{ kind: "excluded", note: string }
	| { kind: "typed", sigs: { Signature }, source: string }
	| { kind: "value", valueType: string, source: string } -- `typeof(table.insert)` for `tinsert`
	| { kind: "untyped", note: string }

local function functionSource(ctx: Context, qualified: string, path: { string }, list: string): Source
	local config, ann = ctx.config, ctx.ann
	local head = path[1]
	if not Common.isIdentifierPath(qualified) then
		return { kind = "excluded", note = "not a Luau identifier path" }
	elseif ctx.reserved[head] then
		return { kind = "typed", sigs = {}, source = "supplements" } -- declared by supplements/
	elseif ctx.luauGlobals[head] then
		-- A Luau global, or a member of a Luau library table: Luau declares it, or it is a WoW extension
		-- that a definitions file cannot add to Luau's table.
		if config.luauStdlib[qualified] then
			return { kind = "excluded", note = "provided by Luau's standard library" }
		elseif config.luauConflicts[qualified] then
			return { kind = "excluded", note = config.luauConflicts[qualified] }
		end
		return {
			kind = "excluded",
			note = "a WoW extension of Luau's " .. head .. " library; a definitions file cannot add to it",
		}
	elseif ann.globalClass[head] and #path > 1 then
		return { kind = "excluded", note = "a method of the mixin " .. head .. " (typed with it)" }
	end
	local doc = ctx.docs.functions[qualified]
	local f = ann.functions[qualified]
	if doc then
		local sigs, source = Signatures.reconcile(ctx, doc, if f then Common.withOverloads(f) else nil)
		return { kind = "typed", sigs = sigs, source = source }
	elseif f and f.signature.untagged and #f.overloads == 0 then
		-- Declared without a single tag: its `()` result would claim the function returns nothing.
		return { kind = "untyped", note = "the annotations declare it without types (" .. list .. ")" }
	elseif f then
		return { kind = "typed", sigs = Common.withOverloads(f), source = "annotations" }
	end
	-- A WoW alias of a standard-library function (`tinsert = table.insert`, `strsplit = string.split`).
	local alias = ann.values[qualified]
	local tbl, fn = string.match(alias or "", "^([%w_]+)%.([%w_]+)$")
	if tbl and fn then
		local target = (config.stdlibAliases[tbl] or tbl) .. "." .. fn
		local s = ann.stdlib[target]
		if s then
			return { kind = "typed", sigs = Common.withOverloads(s), source = "annotations" }
		elseif config.luauStdlib[target] then
			return { kind = "value", valueType = "typeof(" .. target .. ")", source = "luau-stdlib" }
		end
		return { kind = "untyped", note = "aliases " .. target .. ", which has no annotation" }
	end
	return { kind = "untyped", note = "no type source (" .. list .. ")" }
end

function Globals.collect(ctx: Context): Tree
	local res, config = ctx.res, ctx.config
	local root: Node = { kind = "ns", children = {}, sigs = {} }

	local clientFunctions: { [string]: string } = {}
	for name in res.frameXml do
		clientFunctions[name] = "FrameXML"
	end
	for name in res.luaApi do
		clientFunctions[name] = "Lua"
	end
	for name in res.globalApi do
		clientFunctions[name] = "C API"
	end

	for _, qualified in Common.sortedKeys(clientFunctions) do
		local path = string.split(qualified, ".")
		local found = functionSource(ctx, qualified, path, clientFunctions[qualified])
		if found.kind == "excluded" then
			ctx.cover("functions", qualified, "excluded", nil, found.note)
			continue
		elseif found.kind == "typed" and #found.sigs == 0 then
			ctx.cover("functions", qualified, "typed", found.source) -- declared by a supplement
			continue
		end
		-- The one insertion path: a name another global already holds is a clash.
		local parent = nodeAt(root, path, #path - 1)
		if parent == nil or parent.children[path[#path]] ~= nil then
			ctx.cover("functions", qualified, "excluded", nil, "its name clashes with another global")
			continue
		end
		local leaf = path[#path]
		if found.kind == "typed" then
			local sigs = Signatures.applyOverrides(ctx, qualified, found.sigs)
			parent.children[leaf] = { kind = "func", children = {}, sigs = sigs }
			ctx.apis.functions[qualified] = { sigs = sigs, doc = ctx.docs.functions[qualified] }
			ctx.cover("functions", qualified, "typed", found.source)
		elseif found.kind == "value" then
			parent.children[leaf] = { kind = "value", children = {}, sigs = {}, valueType = found.valueType }
			ctx.apis.functions[qualified] = { sigs = {}, opaque = "declared as " .. found.valueType }
			ctx.cover("functions", qualified, "typed", found.source)
		elseif found.kind == "untyped" then
			parent.children[leaf] = { kind = "func", children = {}, sigs = { Common.UNTYPED_SIGNATURE } }
			ctx.cover("functions", qualified, "untyped", nil, found.note)
		end
	end
	for qualified in ctx.ann.functions do
		if clientFunctions[qualified] == nil and ctx.coverage.functions[qualified] == nil then
			ctx.cover("functions", qualified, "excluded", "annotations", "not in the " .. config.gameName .. " client")
		end
	end
	for qualified in ctx.docs.functions do
		if clientFunctions[qualified] == nil and ctx.coverage.functions[qualified] == nil then
			ctx.cover("functions", qualified, "excluded", "docs", "documented, but absent from the client's API dump")
		end
	end

	-- Named frames, mixins and LuaEnum constants.
	local typeNames, widgetAliases = ctx.typeNames, ctx.widgetAliases
	for _, name in Common.sortedKeys(res.frames) do
		local free = root.children[name] == nil and not ctx.reserved[name] and not ctx.luauGlobals[name]
		if free and Common.isIdentifierPath(name) then
			local class = ctx.ann.globalClass[name]
			local typeName = if class then (typeNames[class] or typeNames[widgetAliases[class] or ""]) else nil
			root.children[name] = { kind = "value", children = {}, sigs = {}, valueType = typeName or "Frame" }
		end
	end
	for _, name in Common.sortedKeys(ctx.ann.globalClass) do
		local class = ctx.ann.globalClass[name]
		if root.children[name] == nil and res.mixins[name] and ctx.structs[class] and not ctx.reserved[name] then
			root.children[name] = { kind = "value", children = {}, sigs = {}, valueType = typeNames[class] }
		end
	end
	for _, e in res.enums do
		local enumNode = nodeAt(root, { "Enum" }, 1)
		assert(enumNode, "a client function or value is named Enum")
		local opaque = not Common.isNumericEnum(config, e)
		enumNode.children[e.name] = {
			kind = "enum",
			children = {},
			sigs = {},
			entries = e.entries,
			enumType = if opaque then ctx.typeNames["Enum." .. e.name] else nil,
		}
		ctx.cover("enums", "Enum." .. e.name, "typed", "client")
	end
	for _, c in res.constants do
		local constNode = nodeAt(root, { "Constants" }, 1)
		assert(constNode, "a client function or value is named Constants")
		constNode.children[c.name] = { kind = "enum", children = {}, sigs = {}, entries = c.entries }
	end
	for _, c in res.globalConstants do
		if root.children[c.key] == nil and not ctx.reserved[c.key] then
			local valueType = if tonumber(c.value) ~= nil then "number" else "unknown"
			root.children[c.key] = { kind = "value", children = {}, sigs = {}, valueType = valueType }
		end
	end
	for qualified, value in ctx.ann.values do
		local path = string.split(qualified, ".")
		if #path == 1 and root.children[qualified] == nil and not ctx.luauGlobals[qualified] then
			if tonumber(value) ~= nil or value == "math.pi" then
				root.children[qualified] = { kind = "value", children = {}, sigs = {}, valueType = "number" }
			end
		end
	end
	return { root = root, clientFunctions = clientFunctions }
end

-- CreateFrame's lookup table: the widget returned for each frame type.
local function emitFrameTypeMap(ctx: Context)
	local frameTypes = {}
	local alias = ctx.ann.aliases[Common.FRAME_TYPE_ALIAS]
	if alias then
		for _, v in alias.variants do
			if v.kind == "string" and ctx.res.widgets[v.value] then
				table.insert(frameTypes, "\t" .. v.value .. ": " .. ctx.typeNames[v.value] .. ",")
			end
		end
	end
	table.sort(frameTypes)
	ctx.emit("-- The widget CreateFrame returns for each frame type.")
	ctx.emit("export type " .. Common.FRAME_TYPE_MAP .. " = {")
	for _, line in frameTypes do
		ctx.emit(line)
	end
	ctx.emit("}")
	ctx.emit("")
end

-- The type of one enum or constants entry, from its value in the client's LuaEnum.lua.
local function entryType(value: string): string
	if string.match(value, "^[\"']") then
		return "string"
	elseif value == "true" or value == "false" then
		return "boolean"
	elseif tonumber(value) ~= nil then
		return "number"
	end
	return "unknown" -- an expression or a reference the dump did not evaluate
end

export type Counts = { functions: number, tables: number, values: number }

-- Emits FrameTypeMap and every global; returns how many functions, tables and values it declared.
function Globals.emit(ctx: Context, tree: Tree): Counts
	local emit, root = ctx.emit, tree.root
	-- Frames built from a template with a mixin have the mixin's type (config.widgetMixins, emitted by
	-- stages/widgets.luau, which runs after Globals.collect).
	for _, mixin in Common.sortedKeys(ctx.config.widgetMixins) do
		if ctx.overridesUsed["widgetMixins." .. mixin] then
			for _, frame in ctx.config.widgetMixins[mixin].globals do
				local node = root.children[frame]
				if node and node.kind == "value" and ctx.res.frames[frame] then
					node.valueType = mixin
				end
			end
		end
	end
	emitFrameTypeMap(ctx)
	emit("-- Globals ------------------------------------------------------------------------------------")
	local counts: Counts = { functions = 0, tables = 0, values = 0 }
	local function valueType(node: Node): string
		if node.kind == "func" then
			return Signatures.overloadSet(ctx, node.sigs, nil, nil)
		end
		return node.valueType or "unknown"
	end
	local function emitTable(node: Node, indent: string)
		for _, key in Common.sortedKeys(node.children) do
			local child = node.children[key]
			local field = indent .. Common.identifierKey(key) .. ": "
			if child.kind == "ns" then
				emit(field .. "{")
				emitTable(child, indent .. "\t")
				emit(indent .. "},")
			elseif child.kind == "enum" then
				emit(field .. "{")
				local seen = {}
				for _, entry in child.entries or {} do
					if not seen[entry.key] then
						seen[entry.key] = true
						local t = child.enumType or entryType(entry.value)
						emit(indent .. "\t" .. Common.identifierKey(entry.key) .. ": " .. t .. ",")
					end
				end
				emit(indent .. "},")
			else
				emit(field .. valueType(child) .. ",")
			end
		end
	end
	-- CreateFrame: the frame type picks the returned widget.
	if root.children[Common.CREATE_FRAME] then
		root.children[Common.CREATE_FRAME] = nil
		emit(
			"declare function CreateFrame<K>(frameType: K & keyof<FrameTypeMap>, name: string?, parent: Frame?, "
				.. "template: string?, id: number?): index<FrameTypeMap, K>"
		)
		counts.functions += 1
		ctx.cover("functions", Common.CREATE_FRAME, "typed", "generator", "generic over FrameTypeMap")
		ctx.apis.functions[Common.CREATE_FRAME] = { sigs = {}, opaque = "generic over FrameTypeMap" }
	end
	for _, key in Common.sortedKeys(root.children) do
		local node = root.children[key]
		if node.kind == "func" then
			counts.functions += 1
			local printed = Signatures.printAll(ctx, node.sigs, nil, false)
			if #printed == 1 and printed[1].generics == "" then
				local p = printed[1]
				emit("declare function " .. key .. Signatures.renderParams(p, nil, true) .. ": " .. p.returns)
			else
				emit("declare " .. key .. ": " .. Signatures.renderOverloadSet(printed, nil))
			end
		elseif node.kind == "ns" or node.kind == "enum" then
			counts.tables += 1
			emit("declare " .. key .. ": {")
			emitTable(node, "\t")
			emit("}")
		else
			counts.values += 1
			emit("declare " .. key .. ": " .. valueType(node))
		end
	end
	emit("")
	return counts
end

return Globals
