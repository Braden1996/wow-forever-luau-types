--!strict
-- Result shapes (stages/shapes.luau): how each signature is classified for wrapping libraries.

local ApiDocs = require("./apidocs")
local Decls = require("./luacats/decls")
local SpecCase = require("./spec-case")
local Shapes = require("./stages/shapes")
local TypeExpr = require("./typeexpr")

type Type = TypeExpr.Type
type Signature = Decls.Signature

local function resolve(name: string, _args: { Type }): string
	return name
end

local lens: Shapes.Lens = {
	print = function(t: Type): string
		return TypeExpr.print(t, resolve)
	end,
	parameters = function(sigs: { Signature }): { { Shapes.Parameter } }
		local out: { { Shapes.Parameter } } = {}
		for _, s in sigs do
			local params: { Shapes.Parameter } = {}
			for _, p in s.params do
				local text = TypeExpr.print(p.type, resolve)
				table.insert(params, { name = p.name, type = if p.optional then text .. "?" else text })
			end
			table.insert(out, params)
		end
		return out
	end,
	isCallbackName = function(name: string): boolean
		return name == "TimerCallback"
	end,
	failureModes = {
		IsProtectedFunction = "ReturnNothing",
		RequiresValidSlot = "ReturnNothing",
		RequiresIndex = "Error",
	},
}

local function named(name: string): Type
	return { kind = "name", name = name, args = {} }
end

local function optional(inner: Type): Type
	return { kind = "optional", inner = inner }
end

local function sig(returns: { Type }, returnNames: { string }?, params: { TypeExpr.Param }?): Signature
	return { params = params or {}, returns = returns, returnNames = returnNames, generics = {} }
end

local function doc(nilable: { boolean }, mayReturnNothing: boolean, predicates: { string }): ApiDocs.DocFunction
	local returns: { ApiDocs.DocReturn } = {}
	for i, n in nilable do
		table.insert(returns, { name = "r" .. i, nilable = n })
	end
	return {
		qualified = "X",
		signature = sig({}),
		returns = returns,
		mayReturnNothing = mayReturnNothing,
		predicates = predicates,
	}
end

local function case(name: string, actual: () -> Shapes.Shape, expected: Shapes.Shape): SpecCase.Case
	return {
		name = name,
		run = function()
			local shape = actual()
			if expected.parameters == nil then
				shape.parameters = nil
			end
			return shape, expected
		end,
	}
end

local cases: { SpecCase.Case } = {
	case("no results is void", function()
		return Shapes.classify({ sig({}) }, nil, lens)
	end, { kind = "void" }),
	case("one result that is never nil is a value", function()
		return Shapes.classify({ sig({ named("number") }, { "level" }) }, nil, lens)
	end, { kind = "value", results = { { name = "level", type = "number", nilable = false } } }),
	case("one optional result is a maybe", function()
		return Shapes.classify({ sig({ optional(named("QuestInfo")) }, { "info" }) }, nil, lens)
	end, { kind = "maybe", results = { { name = "info", type = "QuestInfo", nilable = true } } }),
	case("MayReturnNothing makes a single never-nil result a maybe, nilable only as documented", function()
		return Shapes.classify({ sig({ optional(named("string")) }, { "name" }) }, doc({ false }, true, {}), lens)
	end, {
		kind = "maybe",
		absent = { "MayReturnNothing" },
		results = { { name = "name", type = "string", nilable = false } },
	}),
	case("several results are a record; a leading boolean marks a Result candidate", function()
		return Shapes.classify(
			{ sig({ named("boolean"), optional(named("string")) }, { "loaded", "reason" }) },
			nil,
			lens
		)
	end, {
		kind = "record",
		booleanFirst = true,
		results = {
			{ name = "loaded", type = "boolean", nilable = false },
			{ name = "reason", type = "string", nilable = true },
		},
	}),
	case("a ReturnNothing precondition is a reason to be absent; an Error one is not", function()
		local d = doc({ false, false }, false, { "RequiresIndex", "RequiresValidSlot" })
		return Shapes.classify({ sig({ named("string"), named("number") }, { "kind", "id" }) }, d, lens)
	end, {
		kind = "record",
		absent = { "RequiresValidSlot" },
		predicates = { "RequiresIndex", "RequiresValidSlot" },
		results = {
			{ name = "kind", type = "string", nilable = false },
			{ name = "id", type = "number", nilable = false },
		},
	}),
	case("IsProtectedFunction is protected whatever it returns", function()
		local d = doc({ false }, false, { "IsProtectedFunction" })
		return Shapes.classify({ sig({ named("boolean") }, { "cleared" }) }, d, lens)
	end, { kind = "protected", predicates = { "IsProtectedFunction" } }),
	case("missing, reserved and repeated result names become resultN", function()
		local returns = { named("number"), named("number"), named("number"), named("number") }
		return Shapes.classify({ sig(returns, { "", "end", "x", "x" }) }, nil, lens)
	end, {
		kind = "record",
		results = {
			{ name = "result1", type = "number", nilable = false },
			{ name = "result2", type = "number", nilable = false },
			{ name = "x", type = "number", nilable = false },
			{ name = "result4", type = "number", nilable = false },
		},
	}),
	case("a variadic result list is variadic", function()
		return Shapes.classify({ sig({ named("string"), { kind = "variadic", inner = named("string") } }) }, nil, lens)
	end, { kind = "variadic" }),
	case("function-typed and documented callback parameters are listed", function()
		local params: { TypeExpr.Param } = {
			{ name = "seconds", type = named("number"), optional = false },
			{ name = "callback", type = named("TimerCallback"), optional = false },
			{ name = "onDone", type = optional({ kind = "fun", params = {}, returns = {} }), optional = true },
		}
		return Shapes.classify({ sig({}, nil, params) }, nil, lens)
	end, {
		kind = "void",
		callbacks = { "callback", "onDone" },
		parameters = {
			{
				{ name = "seconds", type = "number" },
				{ name = "callback", type = "TimerCallback" },
				{ name = "onDone", type = "(() -> ())??" },
			},
		},
	}),
	case("call shapes with different results are overloaded", function()
		return Shapes.classify({ sig({ named("number") }), sig({ named("string") }) }, nil, lens)
	end, { kind = "overloaded" }),
	case("call shapes with the same results classify as one", function()
		local params: { TypeExpr.Param } = { { name = "a", type = named("string"), optional = false } }
		return Shapes.classify({ sig({ named("number") }), sig({ named("number") }, nil, params) }, nil, lens)
	end, { kind = "value", results = { { name = "result1", type = "number", nilable = false } } }),
	case("a generic signature is generic", function()
		local s = sig({ named("T") })
		s.generics = { "T" }
		return Shapes.classify({ s }, nil, lens)
	end, { kind = "generic" }),
}

return SpecCase.specs(cases)
