--!strict
-- Prints signatures as Luau, merges overloads, and reconciles Blizzard's documentation with the
-- annotations for an API both describe.

local ApiDocs = require("../apidocs")
local Common = require("./common")
local Names = require("./names")
local Decls = require("../luacats/decls")
local Json = require("../json")
local TypeExpr = require("../typeexpr")

type Context = Common.Context
type Printed = Common.Printed
type Type = TypeExpr.Type
type Param = TypeExpr.Param
type Signature = Decls.Signature

local Signatures = {}

function Signatures.print(ctx: Context, sig: Signature, selfName: string?, erase: boolean): Printed
	local scope, genericText = Names.genericScope(sig, erase)
	local resolve = Names.resolver(ctx, scope, selfName)
	local params = {}
	for _, p in sig.params do
		if p.name == "..." then
			local text = TypeExpr.printParam(p, resolve, false, false)
			table.insert(params, { name = "...", type = string.sub(text, 4), vararg = true })
		else
			local text = TypeExpr.printParam(p, resolve, true, false)
			local colon = string.find(text, ": ", 1, true) :: number
			table.insert(params, {
				name = string.sub(text, 1, colon - 1),
				type = string.sub(text, colon + 2),
				vararg = false,
			})
		end
	end
	return { generics = genericText, params = params, returns = TypeExpr.printReturns(sig.returns, resolve) }
end

-- The members of a printed union, and whether it includes nil.
local function unionMembers(t: string): ({ string }, boolean)
	local optional = false
	if string.sub(t, -1) == "?" then
		optional = true
		t = string.sub(t, 1, -2)
		if string.sub(t, 1, 1) == "(" and string.sub(t, -1) == ")" and #TypeExpr.splitUnion(t) == 1 then
			local inner = string.sub(t, 2, -2)
			if not string.find(inner, "->", 1, true) then
				t = inner
			end
		end
	end
	return TypeExpr.splitUnion(t), optional
end

-- Overloads that return the same thing are merged into one signature (each position's types
-- unioned, optional when some overload lacks it): Luau infers string literals against a single
-- signature, and the new solver rejects large overload sets as too complex.
local function mergeOverloads(sigs: { Printed }): { Printed }
	local groups: { { Printed } } = {}
	local byKey: { [string]: { Printed } } = {}
	for _, p in sigs do
		local mergeable = p.generics == ""
		for _, param in p.params do
			if param.vararg then
				mergeable = false
			end
		end
		local key = if mergeable then p.returns else tostring(#groups + 1) .. "\0unmergeable"
		local group = byKey[key]
		if group == nil then
			group = {}
			byKey[key] = group
			table.insert(groups, group)
		end
		table.insert(group :: { Printed }, p)
	end
	local out = {}
	for _, group in groups do
		if #group == 1 then
			table.insert(out, group[1])
			continue
		end
		local width = 0
		for _, p in group do
			width = math.max(width, #p.params)
		end
		local params = {}
		for i = 1, width do
			local parts = {}
			local name: string? = nil
			for _, p in group do
				local param = p.params[i]
				if param then
					name = name or param.name
					local members, optional = unionMembers(param.type)
					for _, m in members do
						table.insert(parts, m)
					end
					if optional then
						table.insert(parts, "nil")
					end
				else
					table.insert(parts, "nil")
				end
			end
			table.insert(params, { name = name :: string, type = TypeExpr.unionOf(parts), vararg = false })
		end
		table.insert(out, { generics = "", params = params, returns = group[1].returns })
	end
	return out
end

-- Every signature printed, duplicates dropped, overloads merged.
function Signatures.printAll(ctx: Context, sigs: { Signature }, selfName: string?, erase: boolean): { Printed }
	local printed = {}
	local seen: { [string]: boolean } = {}
	for _, sig in sigs do
		local p = Signatures.print(ctx, sig, selfName, erase)
		local parts = {}
		for _, param in p.params do
			table.insert(parts, param.name .. ":" .. param.type)
		end
		local key = p.generics .. "(" .. table.concat(parts, ",") .. ")" .. p.returns
		if not seen[key] then
			seen[key] = true
			table.insert(printed, p)
		end
	end
	return mergeOverloads(printed)
end

-- `(a: T, ...: V)` for declarations, `(a: T, ...V)` for function types.
function Signatures.renderParams(p: Printed, selfParam: string?, declaration: boolean): string
	local parts = {}
	if selfParam then
		table.insert(parts, selfParam)
	end
	for _, param in p.params do
		if param.vararg then
			table.insert(parts, if declaration then "...: " .. param.type else "..." .. TypeExpr.wrap(param.type))
		else
			table.insert(parts, param.name .. ": " .. param.type)
		end
	end
	return "(" .. table.concat(parts, ", ") .. ")"
end

-- Renders printed signatures as one function type, or an intersection when overloads remain after merging.
function Signatures.renderOverloadSet(printed: { Printed }, selfType: string?): string
	local parts = {}
	for _, p in printed do
		table.insert(parts, p.generics .. Signatures.renderParams(p, selfType, false) .. " -> " .. p.returns)
	end
	if #parts == 1 then
		return parts[1]
	end
	local wrapped = {}
	for _, p in parts do
		table.insert(wrapped, "(" .. p .. ")")
	end
	return table.concat(wrapped, " & ")
end

-- A function type, or an intersection of them when overloads remain after merging.
function Signatures.overloadSet(ctx: Context, sigs: { Signature }, selfType: string?, selfName: string?): string
	return Signatures.renderOverloadSet(Signatures.printAll(ctx, sigs, selfName, false), selfType)
end

-- Rules 1 to 4 of Signatures.reconcile.
local function reconcileSources(ctx: Context, doc: Signature, ann: { Signature }?): ({ Signature }, string)
	if ann == nil or #ann == 0 then
		return { doc }, "docs"
	end
	local a = ann[1]
	local usedAnnotations = #ann > 1
	local params = {}
	for i, p in doc.params do
		local ap = a.params[i]
		local sameSlot = ap ~= nil and (ap.name == p.name or #a.params == #doc.params)
		if sameSlot and (ap :: Param).optional and not (ap :: Param).implicit and not p.optional then
			table.insert(params, { name = p.name, type = p.type, optional = true })
			usedAnnotations = true
		else
			table.insert(params, p)
		end
	end
	local returns = {}
	for i, r in doc.returns do
		local base: Type = if r.kind == "optional" then r.inner else r
		if base.kind == "name" and ctx.docs.callbacks[base.name] and a.returns[i] then
			table.insert(returns, a.returns[i])
			usedAnnotations = true
		else
			table.insert(returns, r)
		end
	end
	local out: { Signature } = {
		{ params = params, returns = returns, returnNames = doc.returnNames, generics = {} },
	}
	for i = 2, #ann do
		table.insert(out, ann[i])
	end
	return out, if usedAnnotations then "docs+annotations" else "docs"
end

-- A result type that admits nil: optional results, variadic results (they may be empty) and the types that
-- already include nil are kept as they are.
local function optionalResult(t: Type): Type
	if t.kind == "variadic" or Common.acceptsNil(t) then
		return t
	end
	return { kind = "optional", inner = t }
end

-- Each signature with every result optional.
local function withOptionalResults(sigs: { Signature }): { Signature }
	local out: { Signature } = {}
	for _, sig in sigs do
		local returns: { Type } = {}
		for _, r in sig.returns do
			table.insert(returns, optionalResult(r))
		end
		table.insert(out, {
			params = sig.params,
			returns = returns,
			returnNames = sig.returnNames,
			generics = sig.generics,
		})
	end
	return out
end

-- Reconciling Blizzard's documentation with the annotations, for an API both describe:
--   1. Types come from the documentation.
--   2. An argument is optional if either source says so: the documentation marks some arguments
--      required that the game treats as optional (MessageFrame:AddMessage's colours). Only an
--      annotated parameter counts: a parameter the annotations name but do not annotate says nothing.
--   3. The annotations' extra call shapes (`---@overload`) are kept: the documentation lists one
--      signature per function (ScriptRegion:SetPoint(point, x, y) is real).
--   4. A documented result typed as a callback (C_Timer.NewTicker's ticker handle) takes the
--      annotation's type, which describes the object actually returned.
--   5. A call the documentation says may return nothing at all (ApiDocs.absentReasons: `MayReturnNothing`, or a
--      precondition such as RequiresValidActionSlot that fails by returning nothing) has every result optional,
--      in every call shape, including the results rules 3 and 4 take from the annotations.
-- The source is "docs+annotations" whenever rule 2, 3 or 4 changed anything, else "docs".
function Signatures.reconcile(ctx: Context, docFn: ApiDocs.DocFunction, ann: { Signature }?): ({ Signature }, string)
	local sigs, source = reconcileSources(ctx, docFn.signature, ann)
	if ApiDocs.absentReasons(docFn, ctx.docs.predicates) then
		return withOptionalResults(sigs), source
	end
	return sigs, source
end

-- Parameter types that neither source states precisely enough (config.paramTypeOverrides), keyed
-- "Widget:Method" or a qualified function name. The override replaces the parameter's type in the source
-- signature, so optionality still comes from the source. Each key used is recorded; build.luau rejects
-- keys that matched nothing.
function Signatures.applyOverrides(ctx: Context, key: string, sigs: { Signature }): { Signature }
	local overrides = ctx.config.paramTypeOverrides[key]
	if overrides == nil then
		return sigs
	end
	ctx.overridesUsed[key] = true
	local out: { Signature } = {}
	for _, sig in sigs do
		local params: { Param } = {}
		for _, p in sig.params do
			local t = overrides[p.name]
			if t then
				local named: Type = { kind = "name", name = t, args = {} }
				table.insert(params, { name = p.name, type = named, optional = p.optional })
			else
				table.insert(params, p)
			end
		end
		table.insert(out, {
			params = params,
			returns = sig.returns,
			returnNames = sig.returnNames,
			generics = sig.generics,
		})
	end
	return out
end

-- Whether some call shape has a result rule 5 can make optional (a variadic result list may already be empty).
local function hasFixedResults(sigs: { Signature }): boolean
	for _, sig in sigs do
		for _, r in sig.returns do
			if r.kind ~= "variadic" then
				return true
			end
		end
	end
	return false
end

-- How many declared functions and widget methods rule 5 of Signatures.reconcile applies to, by reason, per category
-- (report.json's `absentResults`; api-shapes.json lists each API's reasons).
function Signatures.absentSummary(ctx: Context): { [string]: { [string]: number } }
	local function count(records: { [string]: Common.ApiRecord }): { [string]: number }
		local counts: { [string]: number } = Json.object({})
		for _, record in records do
			local reasons = if record.doc then ApiDocs.absentReasons(record.doc, ctx.docs.predicates) else nil
			if reasons and hasFixedResults(record.sigs) then
				for _, reason in reasons do
					counts[reason] = (counts[reason] or 0) + 1
				end
			end
		end
		return counts
	end
	return Json.object({ functions = count(ctx.apis.functions), widgetMethods = count(ctx.apis.widgetMethods) })
end

return Signatures
