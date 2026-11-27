--!strict
-- Stage 6: the shape of every function's and widget method's results (definitions/api-shapes.json), for
-- libraries that wrap the API: `maybe` for one nilable result, `record` for several (each named, with its own
-- nilability), `protected` for what must never be wrapped. Facts from the sources only: whether a boolean-first
-- result means success, or a nil means "not cached yet", is the wrapping library's reviewed decision.

local ApiDocs = require("../apidocs")
local Common = require("./common")
local Decls = require("../luacats/decls")
local Json = require("../json")
local Names = require("./names")
local Signatures = require("./signatures")
local TypeExpr = require("../typeexpr")

type Context = Common.Context
type Type = TypeExpr.Type
type Signature = Decls.Signature

export type Kind =
	"excluded" -- not declared (coverage.json says why)
	| "untyped" -- declared with no type source
	| "opaque" -- typed, but not by a signature this stage reads (supplements, aliases, script methods)
	| "protected" -- Blizzard's docs flag IsProtectedFunction: never wrap
	| "generic" -- a generic signature: its results name type parameters
	| "overloaded" -- call shapes that return different results
	| "void" -- no results
	| "value" -- one result that is never nil
	| "variadic" -- a variadic result list
	| "maybe" -- one result that may be nil
	| "record" -- two or more results

export type Result = { name: string, type: string, nilable: boolean }

-- A parameter as the definitions declare it; `variadic` for a trailing `...: type`.
export type Parameter = { name: string, type: string, variadic: boolean? }

-- `absent`: why the call may return nothing at all (`MayReturnNothing`, or a precondition whose FailureMode is
-- ReturnNothing); `booleanFirst`: two or more results and the first is a boolean (a Result candidate);
-- `callbacks`: the parameters that take a function; `parameters`: each call shape left after overloads that
-- return the same results are merged (most APIs have one).
export type Shape = {
	kind: Kind,
	parameters: { { Parameter } }?,
	results: { Result }?,
	absent: { string }?,
	booleanFirst: boolean?,
	callbacks: { string }?,
	predicates: { string }?,
	note: string?,
}

export type Shapes = { functions: { [string]: Shape }, widgetMethods: { [string]: Shape } }

-- What `classify` needs besides the signatures: how a type and a call shape print, and which names are callback
-- types.
export type Lens = {
	print: (t: Type) -> string,
	parameters: (sigs: { Signature }) -> { { Parameter } },
	isCallbackName: (name: string) -> boolean,
	failureModes: { [string]: string },
}

local Shapes = {}

Shapes.PROTECTED = ApiDocs.PROTECTED
Shapes.WRAPPABLE = { maybe = true, record = true } :: { [Kind]: boolean }

local function strip(t: Type): Type
	return if t.kind == "optional" then t.inner else t
end

local function isCallback(t: Type, lens: Lens): boolean
	local base = strip(t)
	if base.kind == "fun" then
		return true
	elseif base.kind == "name" then
		return base.name == "function" or lens.isCallbackName(base.name)
	elseif base.kind == "union" then
		for _, member in base.types do
			if isCallback(member, lens) then
				return true
			end
		end
	end
	return false
end

local function callbacksOf(sigs: { Signature }, lens: Lens): { string }?
	local seen: { [string]: boolean } = {}
	for _, sig in sigs do
		for _, p in sig.params do
			if isCallback(p.type, lens) then
				seen[p.name] = true
			end
		end
	end
	local names = Common.sortedKeys(seen)
	return if #names > 0 then names else nil
end

local function printedReturns(sig: Signature, lens: Lens): string
	local parts = {}
	for _, r in sig.returns do
		table.insert(parts, lens.print(r))
	end
	return table.concat(parts, ", ")
end

-- A result's field name: the source's, when it is a usable identifier not taken by an earlier result.
local function fieldName(raw: string?, index: number, taken: { [string]: boolean }): string
	local name = raw or ""
	local usable = string.match(name, "^[%a_][%w_]*$") ~= nil and not TypeExpr.RESERVED[name] and not taken[name]
	return if usable then name else "result" .. index
end

-- The shape of one API's final signatures. `doc` is the documentation entry the first signature came from.
function Shapes.classify(sigs: { Signature }, doc: ApiDocs.DocFunction?, lens: Lens): Shape
	local predicates = if doc and #doc.predicates > 0 then doc.predicates else nil
	if doc and table.find(doc.predicates, Shapes.PROTECTED) then
		return { kind = "protected", predicates = predicates }
	end
	local callbacks = callbacksOf(sigs, lens)
	local sig = sigs[1]
	if sig == nil then
		return { kind = "opaque", note = "no signature" }
	elseif #sig.generics > 0 then
		return { kind = "generic", callbacks = callbacks, predicates = predicates }
	end
	local first = printedReturns(sig, lens)
	for i = 2, #sigs do
		if printedReturns(sigs[i], lens) ~= first then
			return { kind = "overloaded", callbacks = callbacks, predicates = predicates }
		end
	end
	local absent = if doc then ApiDocs.absentReasons(doc, lens.failureModes) else nil
	local base: Shape = {
		kind = "void",
		parameters = lens.parameters(sigs),
		absent = absent,
		callbacks = callbacks,
		predicates = predicates,
	}
	local returns = sig.returns
	if #returns == 0 then
		return base
	elseif returns[#returns].kind == "variadic" then
		base.kind = "variadic"
		return base
	end
	local results: { Result } = {}
	local taken: { [string]: boolean } = {}
	for i, r in returns do
		local documented = if doc then doc.returns[i] else nil
		local nilable = if documented then documented.nilable else r.kind == "optional"
		local name = fieldName(if sig.returnNames then sig.returnNames[i] else nil, i, taken)
		taken[name] = true
		table.insert(results, { name = name, type = lens.print(strip(r)), nilable = nilable })
	end
	base.results = results
	if #results == 1 then
		base.kind = if results[1].nilable or absent then "maybe" else "value"
	else
		base.kind = "record"
		base.booleanFirst = if results[1].type == "boolean" then true else nil
	end
	return base
end

-- The lens for real output: types print as the definitions declare them (`self` resolved for methods).
local function lensFor(ctx: Context, sig: Signature?, selfName: string?): Lens
	local scope = if sig then (Names.genericScope(sig, true)) else nil
	local resolve = Names.resolver(ctx, scope, selfName)
	return {
		print = function(t: Type): string
			return TypeExpr.print(t, resolve)
		end,
		parameters = function(sigs: { Signature }): { { Parameter } }
			local out: { { Parameter } } = {}
			for _, printed in Signatures.printAll(ctx, sigs, selfName, true) do
				local params: { Parameter } = {}
				for _, p in printed.params do
					table.insert(params, { name = p.name, type = p.type, variadic = if p.vararg then true else nil })
				end
				table.insert(out, params)
			end
			return out
		end,
		isCallbackName = function(name: string): boolean
			return ctx.docs.callbacks[name] ~= nil
		end,
		failureModes = ctx.docs.predicates,
	}
end

local function shapeOf(ctx: Context, record: Common.ApiRecord?, entry: Common.CoverageEntry): Shape
	if entry.status == "excluded" or entry.status == "untyped" then
		return { kind = entry.status } -- coverage.json says why
	elseif record == nil or record.opaque then
		local note = if record then record.opaque else "typed by " .. (entry.source or "an unknown source")
		return { kind = "opaque", note = note }
	end
	local r = record :: Common.ApiRecord
	return Shapes.classify(r.sigs, r.doc, lensFor(ctx, r.sigs[1], r.selfName))
end

-- One shape per coverage entry of the two categories, so api-shapes.json and coverage.json list the same APIs.
-- Printing types counts unresolved names for the report; emission already counted these, so the counts are
-- restored afterwards.
function Shapes.collect(ctx: Context): Shapes
	local counted = table.clone(ctx.unresolvedTypes)
	local out: Shapes = { functions = Json.object({}), widgetMethods = Json.object({}) }
	for name, entry in ctx.coverage.functions do
		out.functions[name] = shapeOf(ctx, ctx.apis.functions[name], entry)
	end
	for name, entry in ctx.coverage.widgetMethods do
		out.widgetMethods[name] = shapeOf(ctx, ctx.apis.widgetMethods[name], entry)
	end
	table.clear(ctx.unresolvedTypes)
	for name, uses in counted do
		ctx.unresolvedTypes[name] = uses
	end
	return out
end

-- How many APIs of each kind, per category.
function Shapes.summary(shapes: Shapes): { [string]: { [string]: number } }
	local function count(entries: { [string]: Shape }): { [string]: number }
		local counts: { [string]: number } = Json.object({})
		for _, s in entries do
			counts[s.kind] = (counts[s.kind] or 0) + 1
		end
		return counts
	end
	return Json.object({ functions = count(shapes.functions), widgetMethods = count(shapes.widgetMethods) })
end

return Shapes
