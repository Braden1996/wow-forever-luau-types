--!strict
-- Types, constants and helpers shared by the build stages, and the `Context` the emission stages read: the
-- inputs, the coverage recorder and every collect stage's result.

local ApiDocs = require("../apidocs")
local ConfigModule = require("../config")
local Decls = require("../luacats/decls")
local Resources = require("../resources")
local TypeExpr = require("../typeexpr")

type Type = TypeExpr.Type
type Signature = Decls.Signature
type Func = Decls.Func

export type Config = ConfigModule.Config

export type Pin = { repository: string, commit: string }

export type Input = {
	files: { { path: string, source: string } }, -- annotation files, in priority order
	docs: ApiDocs.DocSet,
	resources: Resources.Resources,
	reserved: { [string]: boolean }, -- names the hand-written supplements declare
	upstream: { annotations: Pin, docs: Pin, resources: Pin },
	config: Config,
}

-- Coverage: every API the client has, by category, with how it ended up.
export type Category = "functions" | "widgetMethods" | "events" | "structures" | "enums" | "widgets"
export type Status = "typed" | "untyped" | "excluded"
export type CoverageEntry = { status: Status, source: string?, note: string? }
export type Coverage = {
	functions: { [string]: CoverageEntry },
	widgetMethods: { [string]: CoverageEntry },
	events: { [string]: CoverageEntry },
	structures: { [string]: CoverageEntry },
	enums: { [string]: CoverageEntry },
	widgets: { [string]: CoverageEntry },
}
export type StatusCounts = { typed: number, untyped: number, excluded: number }

-- What `Build.run` reports next to the definitions (definitions/report.json).
export type Report = {
	upstream: { annotations: Pin, docs: Pin, resources: Pin },
	game: string,
	summary: { [Category]: StatusCounts },
	functionsByClientList: { [string]: StatusCounts },
	counts: {
		annotationFiles: number,
		globalFunctions: number,
		globalTables: number,
		globalValues: number,
		structures: number,
		derivedStructures: number,
		widgets: number,
		scriptObjects: number,
		anyOccurrences: number,
	},
	-- Every `any` in the definitions by form; `other` should stay 0 (COVERAGE.md shows it).
	anyByForm: { anyTable: number, anyFunction: number, handlerArgs: number, other: number },
	-- How many functions and widget methods have each result shape (definitions/api-shapes.json), per category.
	shapes: { [string]: { [string]: number } },
	-- How many functions and widget methods have every result optional because the call may return nothing
	-- (rule 5 of Signatures.reconcile), by reason (`MayReturnNothing`, a ReturnNothing precondition), per category.
	absentResults: { [string]: { [string]: number } },
	unusedOverrides: { string }, -- config.paramTypeOverrides keys that matched no function or method
	parseErrors: { string },
	unresolvedTypes: { { name: string, uses: number } },
}

-- One annotation class, merged across every file that mentions it.
export type AnnClass = {
	name: string,
	parents: { string },
	fields: { Decls.Field },
	methods: { [string]: { Signature } },
	statics: { [string]: { Signature } },
	file: string,
}

-- Everything the LuaCATS annotations declare (stages/annotations.luau).
export type Annotations = {
	classes: { [string]: AnnClass },
	aliases: { [string]: Decls.Alias },
	functions: { [string]: Func }, -- global and namespaced functions
	values: { [string]: string }, -- "tinsert" -> "tab.insert"
	globalClass: { [string]: string }, -- global table name -> its ---@class
	stdlib: { [string]: Func }, -- "string.split" -> WoW's extension of a standard table
}

-- The client's widget hierarchy and where each method's type comes from (stages/widgets.luau).
export type Widgets = {
	parents: { [string]: { string } },
	ancestors: (name: string) -> { string },
	descendants: { [string]: { string } },
	allMethods: (name: string) -> { [string]: boolean },
	allHandlers: (name: string) -> { string },
	docMethods: { [string]: { [string]: ApiDocs.DocFunction } },
	objectTypes: { [string]: { [string]: ApiDocs.DocFunction } },
	clientWidgetFor: (name: string) -> string?,
	annotatedMethod: (widget: string, method: string) -> { Signature }?,
}

-- A structure or mixin, from Blizzard's documentation or an annotation class.
export type Struct = {
	name: string,
	fields: { Decls.Field },
	parents: { string },
	source: string,
	methods: { [string]: { Signature } },
}

-- Luau names for every declared type (stages/names.luau).
export type Names = {
	typeNames: { [string]: string }, -- source name -> Luau type name
	widgetAliases: { [string]: string }, -- a name that means a widget -> the widget
}

-- A node of the global namespace tree (stages/globals.luau).
export type Node = {
	kind: "ns" | "func" | "enum" | "value",
	children: { [string]: Node },
	sigs: { Signature },
	entries: { { key: string, value: string } }?,
	valueType: string?,
}

-- A signature with its types already printed; overloads are merged at this level.
export type PrintedParam = { name: string, type: string, vararg: boolean }
export type Printed = { generics: string, params: { PrintedParam }, returns: string }

-- A declared function or method as the shapes stage reads it: its final signatures and the documentation
-- entry they came from. `opaque` says why its declaration is not one of those signatures.
export type ApiRecord = { sigs: { Signature }, doc: ApiDocs.DocFunction?, selfName: string?, opaque: string? }
export type ApiRecords = { functions: { [string]: ApiRecord }, widgetMethods: { [string]: ApiRecord } }

export type Context = {
	config: Config,
	apis: ApiRecords,
	res: Resources.Resources,
	docs: ApiDocs.DocSet,
	reserved: { [string]: boolean },
	coverage: Coverage,
	cover: (category: Category, name: string, status: Status, source: string?, note: string?) -> (),
	unresolvedTypes: { [string]: number },
	overridesUsed: { [string]: boolean },
	luauGlobals: { [string]: boolean },
	stdTables: { [string]: boolean }, -- "string", "table", "math": Luau library tables WoW extends
	ann: Annotations,
	widgets: Widgets,
	structs: { [string]: Struct },
	typeNames: { [string]: string },
	typeKinds: { [string]: string }, -- source name -> what it was claimed as (stages/names.luau Kind)
	widgetAliases: { [string]: string },
	out: { string },
	emit: (line: string) -> (),
}

local Common = {}

-- Type names the generator itself declares. Upstream types of the same name are not emitted (the
-- annotations' FrameEvent alias is replaced by the client's event list; FrameType only feeds FrameTypeMap).
Common.FRAME_EVENT = "FrameEvent"
Common.EVENT_PAYLOADS = "EventPayloads"
Common.EVENT_HANDLER = "EventHandler"
Common.FRAME_TYPE_MAP = "FrameTypeMap"
Common.FRAME_TYPE_ALIAS = "FrameType" -- the annotation alias listing CreateFrame's frame types
Common.SCRIPT_TYPE_SUFFIX = "ScriptType" -- `<Widget>ScriptType`, a widget's closed script names
Common.CREATE_FRAME = "CreateFrame"
-- Luau rejects very long type annotations, so a union longer than this is declared in chunks
-- (`FrameEvent_1 | FrameEvent_2 | ...`).
Common.UNION_CHUNK = 250

Common.BUILTIN_TYPES = {
	-- `any` in an annotation becomes `unknown`: accepted as an argument, refined before use as a result.
	any = "unknown",
	unknown = "unknown",
	number = "number",
	integer = "number",
	float = "number",
	string = "string",
	boolean = "boolean",
	bool = "boolean",
	["nil"] = "nil",
	void = "nil",
	-- Documented exceptions: `{ [any]: any }` is the only table type every table (array, map or record)
	-- is assignable to, and `(...any) -> ...any` the only function type every function is.
	table = "{ [any]: any }",
	["function"] = "(...any) -> ...any",
	userdata = "unknown",
	lightuserdata = "unknown",
	thread = "thread",
} :: { [string]: string }

-- Names that cannot be used for a declared type: Luau's own types and type functions.
Common.RESERVED_TYPE_NAMES = {
	any = true,
	boolean = true,
	buffer = true,
	never = true,
	["nil"] = true,
	number = true,
	string = true,
	thread = true,
	typeof = true,
	unknown = true,
	vector = true,
	table = true,
	self = true,
	keyof = true,
	index = true,
} :: { [string]: boolean }

-- What a client API with no type source is declared as: it takes anything and returns `unknown`.
Common.UNTYPED_SIGNATURE = {
	params = { { name = "...", type = { kind = "name", name = "unknown", args = {} }, optional = false } },
	returns = { { kind = "variadic", inner = { kind = "name", name = "unknown", args = {} } } },
	generics = {},
} :: Signature

-- One category's entries (a typed accessor: the solver cannot index the record with a `Category` union).
function Common.entries(coverage: Coverage, category: Category): { [string]: CoverageEntry }
	if category == "functions" then
		return coverage.functions
	elseif category == "widgetMethods" then
		return coverage.widgetMethods
	elseif category == "events" then
		return coverage.events
	elseif category == "structures" then
		return coverage.structures
	elseif category == "enums" then
		return coverage.enums
	end
	return coverage.widgets
end

function Common.sortedKeys<V>(t: { [string]: V }): { string }
	local keys = {}
	for k in t do
		table.insert(keys, k)
	end
	table.sort(keys)
	return keys
end

function Common.count<K, V>(t: { [K]: V }): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

-- A Luau string literal for an unescaped value (the type printer's quoting, so there is one escaping).
Common.quote = TypeExpr.quote

-- A table key as written in a type: `name`, or `["name"]` when it is not an identifier.
function Common.identifierKey(name: string): string
	if string.match(name, "^[%a_][%w_]*$") and not TypeExpr.RESERVED[name] then
		return name
	end
	return "[" .. Common.quote(name) .. "]"
end

function Common.isIdentifierPath(qualified: string): boolean
	for _, part in string.split(qualified, ".") do
		if not string.match(part, "^[%a_][%w_]*$") then
			return false
		end
	end
	return true
end

-- A function's signature followed by its `---@overload` signatures.
function Common.withOverloads(f: Func): { Signature }
	local sigs = { f.signature }
	for _, o in f.overloads do
		table.insert(sigs, o)
	end
	return sigs
end

-- Whether a source type already admits nil (so an optional field or parameter needs no `?`).
function Common.acceptsNil(t: Type): boolean
	if t.kind == "optional" then
		return true
	elseif t.kind == "name" then
		return t.name == "nil" or t.name == "any" or t.name == "unknown"
	elseif t.kind == "union" then
		for _, member in t.types do
			if Common.acceptsNil(member) then
				return true
			end
		end
	end
	return false
end

return Common
