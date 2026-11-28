--!strict
-- Stage 4: gives every declared type a unique Luau name, records names that are aliases of a widget, and
-- builds the resolver that prints a source type name as a Luau type.

local ApiDocs = require("../apidocs")
local Decls = require("../luacats/decls")
local Resources = require("../resources")
local TypeExpr = require("../typeexpr")
local Common = require("./common")

type Context = Common.Context
type Type = TypeExpr.Type
type Signature = Decls.Signature

-- What a source name declares, in claiming order (an earlier kind is claimed first).
export type Kind = "generated" | "widget" | "object" | "enum" | "struct" | "callback" | "widgetAlias" | "alias"

local Names = {}

-- The type names the generator declares itself; references to them resolve to themselves.
local GENERATED: { [string]: boolean } = {
	[Common.FRAME_EVENT] = true,
	[Common.EVENT_PAYLOADS] = true,
	[Common.EVENT_HANDLER] = true,
	[Common.FRAME_TYPE_MAP] = true,
}

-- Documented shadowing: a source name may also be declared as `shadowed` when it is already declared as
-- one of `by`, and the later declaration is not emitted (stages/types.luau skips it). Any other clash is an
-- error. An annotation alias yields to every other kind; a documented callback type yields to a documented
-- structure or script object of the same name.
local SHADOWED_BY: { [Kind]: { [Kind]: boolean } } = {
	alias = {
		generated = true,
		widget = true,
		object = true,
		enum = true,
		struct = true,
		callback = true,
		widgetAlias = true,
	},
	callback = { struct = true, object = true },
}

-- Claims a Luau name for every declared type. Returns the names, the kind each source name was claimed as,
-- and the widget aliases.
function Names.claim(
	res: Resources.Resources,
	config: Common.Config,
	ann: Common.Annotations,
	widgets: Common.Widgets,
	structs: { [string]: Common.Struct },
	callbacks: { [string]: ApiDocs.DocCallback }
): (Common.Names, { [string]: Kind })
	local typeNames: { [string]: string } = {}
	local kinds: { [string]: Kind } = {}
	local usedNames: { [string]: boolean } = {}

	local function reserve(name: string)
		assert(not usedNames[name], "the generated type name " .. name .. " is already taken")
		usedNames[name] = true
	end

	local function claim(sourceName: string, kind: Kind)
		local existing = kinds[sourceName]
		if existing then
			local yields = SHADOWED_BY[kind]
			if yields == nil or not yields[existing] then
				error(string.format("%s is declared both as %s and as %s", sourceName, existing, kind))
			end
			return -- documented shadowing: the earlier declaration stands
		end
		kinds[sourceName] = kind
		local name: string = (string.gsub(sourceName, "[^%w_]", "_"))
		if string.match(name, "^%d") then
			name = "_" .. name
		end
		if Common.RESERVED_TYPE_NAMES[name] or TypeExpr.RESERVED[name] then
			name ..= "_"
		end
		local unique = name
		local n = 1
		while usedNames[unique] do
			n += 1
			unique = name .. "_" .. n
		end
		usedNames[unique] = true
		typeNames[sourceName] = unique
	end

	-- The generator's own names come first, so no upstream type can take them: FrameEvent (and the chunks a
	-- long event union is split into), EventPayloads, EventHandler and FrameTypeMap.
	for name in GENERATED do
		reserve(name)
		kinds[name] = "generated"
	end
	for i = 1, math.ceil(#res.events / Common.UNION_CHUNK) do
		reserve(Common.FRAME_EVENT .. "_" .. i)
	end
	for _, name in Common.sortedKeys(res.widgets) do
		claim(name, "widget")
		reserve(typeNames[name] .. Common.SCRIPT_TYPE_SUFFIX) -- `<Widget>ScriptType`, a widget's script names
	end
	for _, name in Common.sortedKeys(widgets.objectTypes) do
		claim(name, "object")
	end
	for _, e in res.enums do
		claim("Enum." .. e.name, "enum")
	end
	for _, name in Common.sortedKeys(structs) do
		claim(name, "struct")
	end
	for _, name in Common.sortedKeys(callbacks) do
		claim(name, "callback")
	end
	-- Names that refer to a widget: Blizzard's `SimpleFrame`, annotation-only bases like
	-- `ScriptRegionResizing`.
	local widgetAliases: { [string]: string } = {}
	for alias, target in config.docWidgetAliases do
		if res.widgets[target] then
			widgetAliases[alias] = target
		end
	end
	for name in ann.classes do
		local w = widgets.clientWidgetFor(name)
		if w and w ~= name then
			widgetAliases[name] = w
		end
	end
	for _, alias in Common.sortedKeys(widgetAliases) do
		claim(alias, "widgetAlias")
	end
	for _, name in Common.sortedKeys(ann.aliases) do
		claim(name, "alias")
	end
	return { typeNames = typeNames, widgetAliases = widgetAliases }, kinds
end

-- Prints a source type name as Luau. A name nothing declares is `unknown`, and counted for the report.
function Names.resolver(ctx: Context, generics: { [string]: string }?, selfName: string?): TypeExpr.Resolver
	local typeNames, widgetAliases = ctx.typeNames, ctx.widgetAliases
	local resolve: TypeExpr.Resolver
	function resolve(name: string, args: { Type }): string
		if generics and generics[name] then
			return generics[name]
		end
		if name == "self" and selfName then
			return selfName
		end
		if name == "table" and #args == 1 then
			return "{ " .. TypeExpr.print(args[1], resolve) .. " }"
		end
		local builtin = Common.BUILTIN_TYPES[name]
		if builtin then
			return builtin
		end
		if GENERATED[name] then
			return name
		end
		if widgetAliases[name] then
			return typeNames[widgetAliases[name]]
		end
		local override = ctx.config.docTypeOverrides[name]
		if override then
			return resolve(override, args)
		end
		local declared = typeNames[name] or typeNames["Enum." .. name]
		if declared then
			return declared
		end
		local basic = ctx.config.basicTypes[name]
		if basic then
			return basic
		end
		ctx.unresolvedTypes[name] = (ctx.unresolvedTypes[name] or 0) + 1
		return "unknown"
	end
	return resolve
end

-- A signature's generic parameters: their scope for the resolver and the `<T, U>` prefix. Declarations
-- (`declare function`, extern methods) cannot be generic, so `erase` maps them to `unknown`.
function Names.genericScope(sig: Signature, erase: boolean?): ({ [string]: string }?, string)
	if #sig.generics == 0 then
		return nil, ""
	end
	local scope = {}
	local names = {}
	for _, g in sig.generics do
		scope[g] = if erase then "unknown" else g
		table.insert(names, g)
	end
	if erase then
		return scope, ""
	end
	return scope, "<" .. table.concat(names, ", ") .. ">"
end

return Names
