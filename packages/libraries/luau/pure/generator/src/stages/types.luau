--!strict
-- The type-alias sections of the output: events (FrameEvent, EventPayloads, EventHandler), annotation
-- aliases, widget aliases, documented callback types and enum value types.

local Decls = require("../luacats/decls")
local TypeExpr = require("../typeexpr")
local Common = require("./common")
local Names = require("./names")
local Signatures = require("./signatures")

type Context = Common.Context
type Type = TypeExpr.Type
type Signature = Decls.Signature

local Types = {}

-- A union type alias, declared in chunks when it is too long for Luau (stages/names.luau reserves the
-- chunk names).
local function emitUnion(ctx: Context, typeName: string, text: string)
	if text == "" then
		ctx.emit("export type " .. typeName .. " = never")
		return
	end
	local members = TypeExpr.splitUnion(text)
	if #members <= Common.UNION_CHUNK then
		ctx.emit("export type " .. typeName .. " = " .. text)
		return
	end
	local chunkNames = {}
	for start = 1, #members, Common.UNION_CHUNK do
		local chunkName = typeName .. "_" .. (#chunkNames + 1)
		table.insert(chunkNames, chunkName)
		local chunk = table.concat(members, " | ", start, math.min(start + Common.UNION_CHUNK - 1, #members))
		ctx.emit("export type " .. chunkName .. " = " .. chunk)
	end
	ctx.emit("export type " .. typeName .. " = " .. table.concat(chunkNames, " | "))
end

-- Events: the client's names, closed; payloads from Blizzard's documentation.
function Types.emitEvents(ctx: Context)
	local emit, res, docs = ctx.emit, ctx.res, ctx.docs
	emit("-- Events -------------------------------------------------------------------------------------")
	local eventLiterals = {}
	for _, e in res.events do
		table.insert(eventLiterals, Common.quote(e))
	end
	emitUnion(ctx, Common.FRAME_EVENT, table.concat(eventLiterals, " | "))
	emit("-- Each event's payload as a handler type: `EventPayloads.PLAYER_LEVEL_UP` is `(level: number, ...) -> ()`.")
	emit("export type " .. Common.EVENT_PAYLOADS .. " = {")
	for _, e in res.events do
		local d = docs.events[e]
		local params = if d then d.payload else { Common.UNTYPED_SIGNATURE.params[1] }
		local sig: Signature = { params = params, returns = {}, generics = {} }
		-- Payload rules use the key `event:<NAME>` in config.paramTypeOverrides.
		sig = Signatures.applyOverrides(ctx, "event:" .. e, { sig })[1]
		local p = Signatures.print(ctx, sig, nil, true)
		emit("\t" .. Common.identifierKey(e) .. ": " .. Signatures.renderParams(p, nil, false) .. " -> (),")
		if d then
			ctx.cover("events", e, "typed", "docs")
		else
			ctx.cover("events", e, "untyped", nil, "no documented payload")
		end
	end
	emit("}")
	emit('-- The handler type for one event: `local onLevel: EventHandler<"PLAYER_LEVEL_UP"> = function(level) end`.')
	emit("export type " .. Common.EVENT_HANDLER .. "<E> = index<" .. Common.EVENT_PAYLOADS .. ", E>")
	for e in docs.events do
		if ctx.coverage.events[e] == nil then
			ctx.cover("events", e, "excluded", "docs", "documented, but absent from the client's event list")
		end
	end
	emit("")
end

-- An annotation alias as Luau. A closed alias (config.closedAliases, closedAliasPattern) is the union of its
-- listed values; an open one keeps its base type, and its listed strings are hints only.
local function aliasText(ctx: Context, a: Decls.Alias): string
	local config = ctx.config
	local resolve = Names.resolver(ctx, nil, nil)
	local closed = config.closedAliases[a.name] == true or string.match(a.name, config.closedAliasPattern) ~= nil
	local parts: { string } = {}
	if a.base then
		local base = a.base :: Type
		local isPlainString = base.kind == "name" and base.name == "string"
		if not (closed and isPlainString and #a.variants > 0) then
			table.insert(parts, TypeExpr.print(base, resolve))
		end
	end
	for _, v in a.variants do
		if v.kind == "string" and not closed then
			table.insert(parts, "string")
		else
			table.insert(parts, TypeExpr.print(v, resolve))
		end
	end
	local flat = {}
	for _, p in parts do
		for _, piece in TypeExpr.splitUnion(p) do
			table.insert(flat, piece)
		end
	end
	local result = if #flat == 0 then "unknown" else TypeExpr.unionOf(flat)
	if result == ctx.typeNames[a.name] then
		return "unknown" -- an alias of itself
	end
	return result
end

function Types.emitAliases(ctx: Context)
	local emit, res, typeNames, kinds = ctx.emit, ctx.res, ctx.typeNames, ctx.typeKinds
	emit("-- Aliases ------------------------------------------------------------------------------------")
	-- Annotation aliases; one that shares a name with a generated, documented or widget type yields to it
	-- (stages/names.luau).
	for _, name in Common.sortedKeys(ctx.ann.aliases) do
		if kinds[name] == "alias" then
			local a = ctx.ann.aliases[name]
			if name == Common.FRAME_TYPE_ALIAS then
				-- CreateFrame accepts only the widget types the client has.
				local kept: { Type } = {}
				for _, v in a.variants do
					if v.kind == "string" and res.widgets[v.value] then
						table.insert(kept, v)
					end
				end
				local filtered: Decls.Alias = { name = a.name, base = nil, variants = kept, file = a.file }
				a = filtered
			end
			emitUnion(ctx, typeNames[name], aliasText(ctx, a))
		end
	end
	for _, alias in Common.sortedKeys(ctx.widgetAliases) do
		if kinds[alias] == "widgetAlias" then
			emit("export type " .. typeNames[alias] .. " = " .. typeNames[ctx.widgetAliases[alias]])
		end
	end
	for _, name in Common.sortedKeys(ctx.docs.callbacks) do
		if kinds[name] == "callback" then
			local fn = TypeExpr.print(ctx.docs.callbacks[name].type, Names.resolver(ctx, nil, nil))
			emit("export type " .. typeNames[name] .. " = " .. fn)
		end
	end
	emit("")
end

-- Enum value types. Luau has no numeric literal types, so each enum is an opaque type of its own: only its own
-- values (`Enum.ItemQuality.Epic`) are accepted where the client takes it, a bare number is not, and two of its
-- values compare with `<` and `<=`. Flag enums (config.flagEnumPatterns) stay numbers for bit operations.
function Types.emitEnumValueTypes(ctx: Context)
	ctx.emit("-- Enum value types ---------------------------------------------------------------------------")
	for _, e in ctx.res.enums do
		local typeName = ctx.typeNames["Enum." .. e.name]
		if Common.isNumericEnum(ctx.config, e) then
			ctx.emit("export type " .. typeName .. " = number")
		else
			ctx.emit("declare extern type " .. typeName .. " with")
			ctx.emit("\tfunction __lt(self, other: " .. typeName .. "): boolean")
			ctx.emit("\tfunction __le(self, other: " .. typeName .. "): boolean")
			ctx.emit("end")
		end
	end
	ctx.emit("")
end

return Types
