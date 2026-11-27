--!strict
-- Reconciling the documentation with the annotations (stages/signatures.luau), and why a documented call may
-- return nothing at all (apidocs.luau): such a call has every result optional, in every call shape.

local ApiDocs = require("./apidocs")
local Common = require("./stages/common")
local Decls = require("./luacats/decls")
local Signatures = require("./stages/signatures")
local SpecCase = require("./spec-case")
local TypeExpr = require("./typeexpr")

type Type = TypeExpr.Type
type Param = TypeExpr.Param
type Signature = Decls.Signature

local FAILURE_MODES: { [string]: string } = {
	IsProtectedFunction = "ReturnNothing",
	RequiresValidSlot = "ReturnNothing",
	RequiresClubs = "ReturnNothing",
	RequiresIndex = "Error",
}

local function named(name: string): Type
	return { kind = "name", name = name, args = {} }
end

local function optional(inner: Type): Type
	return { kind = "optional", inner = inner }
end

local function variadic(inner: Type): Type
	return { kind = "variadic", inner = inner }
end

local function param(name: string, t: Type): Param
	return { name = name, type = t, optional = false }
end

local function sig(params: { Param }, returns: { Type }): Signature
	return { params = params, returns = returns, generics = {} }
end

local function docFunction(signature: Signature, mayReturnNothing: boolean, predicates: { string }): ApiDocs.DocFunction
	return {
		qualified = "X",
		signature = signature,
		returns = {},
		mayReturnNothing = mayReturnNothing,
		predicates = predicates,
	}
end

local function context(apis: Common.ApiRecords?): Common.Context
	local docs = {
		functions = {},
		scriptObjects = {},
		events = {},
		structures = {},
		callbacks = { DemoTimerCallback = { name = "DemoTimerCallback", type = named("function") } },
		enumerations = {},
		predicates = FAILURE_MODES,
		errors = {},
	} :: ApiDocs.DocSet
	local partial = { docs = docs, apis = apis or { functions = {}, widgetMethods = {} } }
	return (partial :: any) :: Common.Context
end

local function resolve(name: string, _args: { Type }): string
	return name
end

local function reconciled(doc: ApiDocs.DocFunction, ann: { Signature }?): ({ string }, string)
	local sigs, source = Signatures.reconcile(context(), doc, ann)
	local printed: { string } = {}
	for _, s in sigs do
		local params: { string } = {}
		for _, p in s.params do
			table.insert(params, p.name .. ": " .. TypeExpr.print(p.type, resolve))
		end
		table.insert(printed, "(" .. table.concat(params, ", ") .. ") -> " .. TypeExpr.printReturns(s.returns, resolve))
	end
	return printed, source
end

local function reconcileCase(
	name: string,
	doc: ApiDocs.DocFunction,
	ann: { Signature }?,
	expected: { shapes: { string }, source: string }
): SpecCase.Case
	return {
		name = name,
		run = function()
			local shapes, source = reconciled(doc, ann)
			return { shapes = shapes, source = source }, expected
		end,
	}
end

local slot = { param("slot", named("number")) }

local cases: { SpecCase.Case } = {
	{
		name = "absentReasons: MayReturnNothing first, then each ReturnNothing precondition in order",
		run = function()
			local doc = docFunction(sig({}, {}), true, { "RequiresClubs", "RequiresIndex", "RequiresValidSlot" })
			return ApiDocs.absentReasons(doc, FAILURE_MODES),
				{ "MayReturnNothing", "RequiresClubs", "RequiresValidSlot" }
		end,
	},
	{
		name = "absentReasons: none for Error preconditions or IsProtectedFunction",
		run = function()
			local doc = docFunction(sig({}, {}), false, { "IsProtectedFunction", "RequiresIndex" })
			return { reasons = ApiDocs.absentReasons(doc, FAILURE_MODES) }, {}
		end,
	},
	reconcileCase(
		"a call that always returns keeps its results as documented",
		docFunction(sig(slot, { named("string"), optional(named("number")) }), false, {}),
		nil,
		{ shapes = { "(slot: number) -> (string, number?)" }, source = "docs" }
	),
	reconcileCase(
		"an Error precondition leaves the results as documented",
		docFunction(sig(slot, { named("boolean") }), false, { "RequiresIndex" }),
		nil,
		{ shapes = { "(slot: number) -> boolean" }, source = "docs" }
	),
	reconcileCase(
		"a ReturnNothing precondition makes every result optional",
		docFunction(sig(slot, { named("string"), named("number") }), false, { "RequiresValidSlot" }),
		nil,
		{ shapes = { "(slot: number) -> (string?, number?)" }, source = "docs" }
	),
	reconcileCase(
		"MayReturnNothing makes every result optional",
		docFunction(sig(slot, { named("number") }), true, {}),
		nil,
		{ shapes = { "(slot: number) -> number?" }, source = "docs" }
	),
	reconcileCase(
		"results that already admit nil, and variadic results, are kept",
		docFunction(
			sig(slot, { optional(named("string")), named("unknown"), variadic(named("number")) }),
			false,
			{ "RequiresValidSlot" }
		),
		nil,
		{ shapes = { "(slot: number) -> (string?, unknown, ...number)" }, source = "docs" }
	),
	reconcileCase(
		"the annotations' extra call shapes get optional results too (rules 3 and 5)",
		docFunction(sig(slot, { named("string") }), false, { "RequiresValidSlot" }),
		{
			sig({ param("slot", named("number")) }, { named("string") }),
			sig({ param("name", named("string")) }, { named("number") }),
		},
		{ shapes = { "(slot: number) -> string?", "(name: string) -> number?" }, source = "docs+annotations" }
	),
	reconcileCase(
		"a callback result takes the annotation's type, then becomes optional (rules 4 and 5)",
		docFunction(sig({}, { named("DemoTimerCallback") }), true, {}),
		{ sig({}, { named("DemoTimerHandle") }) },
		{ shapes = { "() -> DemoTimerHandle?" }, source = "docs+annotations" }
	),
	{
		name = "absentSummary counts declared APIs with fixed results by reason, per category",
		run = function()
			local function record(returns: { Type }, doc: ApiDocs.DocFunction?): Common.ApiRecord
				return { sigs = { sig({}, returns) }, doc = doc }
			end
			local apis: Common.ApiRecords = {
				functions = {
					GetSlot = record({ named("string") }, docFunction(sig({}, {}), true, { "RequiresValidSlot" })),
					GetClub = record({ named("number") }, docFunction(sig({}, {}), false, { "RequiresClubs" })),
					ClearSlot = record({}, docFunction(sig({}, {}), false, { "RequiresValidSlot" })),
					ListSlots = record({ variadic(named("number")) }, docFunction(sig({}, {}), true, {})),
					GetIndex = record({ named("number") }, docFunction(sig({}, {}), false, { "RequiresIndex" })),
					Annotated = record({ named("number") }, nil),
				},
				widgetMethods = {
					["Frame:GetText"] = record({ named("string") }, docFunction(sig({}, {}), true, {})),
				},
			}
			return Signatures.absentSummary(context(apis)),
				{
					functions = { MayReturnNothing = 1, RequiresClubs = 1, RequiresValidSlot = 1 },
					widgetMethods = { MayReturnNothing = 1 },
				}
		end,
	},
}

return SpecCase.specs(cases)
