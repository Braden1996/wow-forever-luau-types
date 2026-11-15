--!strict
-- Turns parsed LuaCATS declarations into one luau-lsp definitions file.

local Parse = require("./parse")
local Resources = require("./resources")
local TypeExpr = require("./typeexpr")

type Type = TypeExpr.Type
type Param = TypeExpr.Param
type Signature = Parse.Signature
type Func = Parse.Func
type FileDecls = Parse.FileDecls

export type Config = {
	sources: { string },
	externSources: { string },
	gameName: string,
	closedAliases: { [string]: boolean },
	closedAliasPattern: string,
	luauGlobals: { string },
	stdlibAliases: { [string]: string },
}

type Pin = { repository: string, commit: string }

export type Input = {
	files: { { path: string, source: string } }, -- in priority order
	resources: Resources.Resources,
	reserved: { [string]: boolean }, -- names the hand-written supplements declare
	upstream: { annotations: Pin, resources: Pin },
	config: Config,
}

type Member =
	{ name: string, kind: "field", type: Type, optional: boolean }
	| {
		name: string,
		kind: "method",
		sigs: { Signature },
	}
	| { name: string, kind: "static", sigs: { Signature } }

type ClassInfo = {
	name: string,
	parents: { string },
	members: { [string]: Member },
	order: { string },
	extern: boolean,
	file: string,
	doc: string?,
	isGlobal: boolean,
}

type Node = {
	kind: "ns" | "func" | "enum" | "value" | "instance",
	children: { [string]: Node },
	sigs: { Signature },
	enum: Parse.EnumDecl?,
	valueType: string?,
	class: string?,
	doc: string?,
}

local BUILTIN_TYPES: { [string]: string } = {
	any = "any",
	unknown = "any",
	number = "number",
	integer = "number",
	float = "number",
	string = "string",
	boolean = "boolean",
	bool = "boolean",
	["nil"] = "nil",
	void = "nil",
	table = "{ [any]: any }",
	["function"] = "(...any) -> ...any",
	userdata = "any",
	lightuserdata = "any",
	thread = "thread",
}

-- Names that cannot be used for a declared type.
local RESERVED_TYPE_NAMES: { [string]: boolean } = {
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
}

local Build = {}

local function startsWith(s: string, prefix: string): boolean
	return string.sub(s, 1, #prefix) == prefix
end

local function sortedKeys<V>(t: { [string]: V }): { string }
	local keys = {}
	for k in t do
		table.insert(keys, k)
	end
	table.sort(keys)
	return keys
end

local function identifierKey(name: string): string
	if string.match(name, "^[%a_][%w_]*$") and not TypeExpr.RESERVED[name] then
		return name
	end
	return '["' .. name .. '"]'
end

function Build.run(input: Input): (string, { [string]: any })
	local config = input.config
	local stats = {
		parseErrors = {} :: { string },
		droppedNotInClient = 0,
		droppedApis = {} :: { string },
		droppedWidgetMethods = 0,
		duplicateFunctions = 0,
		unresolvedTypes = {} :: { [string]: number },
	}

	local luauGlobals: { [string]: boolean } = {}
	for _, name in config.luauGlobals do
		luauGlobals[name] = true
	end

	local parsed: { FileDecls } = {}
	for _, f in input.files do
		local decls = Parse.file(f.path, f.source)
		for _, e in decls.errors do
			table.insert(stats.parseErrors, e)
		end
		table.insert(parsed, decls)
	end

	local function isExternFile(path: string): boolean
		for _, prefix in config.externSources do
			if startsWith(path, prefix) then
				return true
			end
		end
		return false
	end

	-- Symbols ---------------------------------------------------------------------------------------
	local classes: { [string]: ClassInfo } = {}
	local aliases: { [string]: Parse.Alias } = {}
	local enumTypes: { [string]: Parse.EnumDecl } = {}
	local stdlib: { [string]: Func } = {} -- "string.split" -> annotated signature
	local root: Node = { kind = "ns", children = {}, sigs = {} }

	local function getClass(name: string, file: string): ClassInfo
		local c = classes[name]
		if c == nil then
			local created: ClassInfo = {
				name = name,
				parents = {},
				members = {},
				order = {},
				extern = isExternFile(file),
				file = file,
				doc = nil,
				isGlobal = false,
			}
			classes[name] = created
			return created
		end
		return c
	end

	local function addMember(c: ClassInfo, m: Member)
		local existing = c.members[m.name]
		if existing == nil then
			c.members[m.name] = m
			table.insert(c.order, m.name)
		elseif m.kind ~= "field" and existing.kind == m.kind then
			-- Two definitions of one method are overloads.
			for _, sig in (m :: any).sigs do
				table.insert((existing :: any).sigs, sig)
			end
		elseif m.kind ~= "field" and existing.kind == "field" then
			c.members[m.name] = m
		end
	end

	for _, decls in parsed do
		for _, cls in decls.classes do
			local c = getClass(cls.name, decls.file)
			if c.doc == nil then
				c.doc = cls.doc
			end
			for _, p in cls.parents do
				if not table.find(c.parents, p) and p ~= cls.name then
					table.insert(c.parents, p)
				end
			end
			for _, f in cls.fields do
				if f.visibility ~= "private" and f.visibility ~= "protected" then
					addMember(c, { name = f.name, kind = "field", type = f.type, optional = f.optional })
				end
			end
		end
		for _, a in decls.aliases do
			if aliases[a.name] == nil then
				aliases[a.name] = a
			end
		end
	end

	-- Namespace tree helpers.
	local function nodeAt(path: { string }, upto: number): Node
		local node = root
		for i = 1, upto do
			local key = path[i]
			local child = node.children[key]
			if child == nil then
				child = { kind = "ns", children = {}, sigs = {} }
				node.children[key] = child
			end
			node = child :: Node
		end
		return node
	end

	local res = input.resources
	-- Whether the client has a function, by its qualified name ("UnitLevel", "C_Timer.After").
	local function clientHas(qualified: string): boolean
		return res.globalApi[qualified] == true or res.luaApi[qualified] == true or res.frameXml[qualified] == true
	end
	-- Whether a global table, frame or mixin of this name exists in the client.
	local function clientHasGlobal(name: string): boolean
		return res.frames[name] == true or res.mixins[name] == true or clientHas(name)
	end
	-- Every method name any client widget type has. The client's widget hierarchy differs from the
	-- annotations' (in the client, Frame inherits ScriptRegion directly, not Region), so filtering per
	-- class would strip methods subclasses need. A widget method is dropped only when no client widget
	-- has a method of that name at all, which removes retail-only API safely.
	local anyWidgetMethod: { [string]: boolean } = {}
	for _, widget in res.widgets do
		for method in widget.methods do
			anyWidgetMethod[method] = true
		end
	end
	local function clientWidgetMethods(name: string): { [string]: boolean }?
		if res.widgets[name] == nil then
			return nil -- not a client widget type (an annotation-only base or mixin): trust it
		end
		return anyWidgetMethod
	end
	local function isLuaEnumGlobal(name: string): boolean
		return string.match(name, "^LE_") ~= nil or string.match(name, "^NUM_LE_") ~= nil
	end

	local function withOverloads(f: Func): { Signature }
		local sigs = { f.signature }
		for _, o in f.overloads do
			table.insert(sigs, o)
		end
		return sigs
	end

	for _, decls in parsed do
		-- Globals first, so functions defined on a global class table attach to the class.
		for _, g in decls.globals do
			if g.path[1] == "_G" and #g.path > 1 then
				-- `_G.Foo = ...` declares the global `Foo`; `_G` itself stays Luau's open table.
				g.path = table.move(g.path, 2, #g.path, 1, {})
			end
			local head = g.path[1]
			if
				luauGlobals[head]
				or input.reserved[head]
				or head == "Enum"
				or head == "Constants"
				or isLuaEnumGlobal(head)
			then
				-- Enum, Constants and LE_* come from the client's own dump instead.
				continue
			end
			if g.class then
				local c = getClass(g.class, decls.file)
				if #g.path == 1 then
					c.isGlobal = true
				end
				decls.locals[table.concat(g.path, ".")] = g.class
				if #g.path == 1 and not clientHasGlobal(head) then
					-- A retail-only mixin or frame: its type stays, the global does not exist.
					stats.droppedNotInClient += 1
					continue
				end
				local parent = nodeAt(g.path, #g.path - 1)
				local leaf = g.path[#g.path]
				if parent.children[leaf] == nil or parent.children[leaf].kind == "ns" then
					parent.children[leaf] = { kind = "instance", children = {}, sigs = {}, class = g.class }
				end
			elseif g.value == "{}" then
				nodeAt(g.path, #g.path)
			else
				local parent = nodeAt(g.path, #g.path - 1)
				local leaf = g.path[#g.path]
				if parent.children[leaf] == nil then
					local value = g.value
					local stdTable, stdName = string.match(value, "^([%w_]+)%.([%w_]+)$")
					local node: Node
					if stdTable and config.stdlibAliases[stdTable] then
						local target = config.stdlibAliases[stdTable] .. "." .. (stdName :: string)
						node = { kind = "value", children = {}, sigs = {}, valueType = "@stdlib:" .. target }
					elseif startsWith(value, "function") then
						local args = string.match(value, "^function%s*%(([^%)]*)%)") or ""
						local params = {}
						for _ in string.gmatch(args, "[%w_]+") do
							table.insert(params, "number")
						end
						node = {
							kind = "value",
							children = {},
							sigs = {},
							valueType = "(" .. table.concat(params, ", ") .. ") -> number",
						}
					elseif string.match(value, "^[\"']") then
						node = { kind = "value", children = {}, sigs = {}, valueType = "string" }
					elseif string.match(value, "^%-?[%d%.]+$") then
						node = { kind = "value", children = {}, sigs = {}, valueType = "number" }
					elseif value == "true" or value == "false" then
						node = { kind = "value", children = {}, sigs = {}, valueType = "boolean" }
					else
						node = { kind = "value", children = {}, sigs = {}, valueType = "any" }
					end
					local isFunction = startsWith(node.valueType :: string, "@stdlib:")
						or startsWith(node.valueType :: string, "(")
					if isFunction and not clientHas(table.concat(g.path, ".")) then
						stats.droppedNotInClient += 1
					else
						parent.children[leaf] = node
					end
				end
			end
		end

		for _, f in decls.funcs do
			local head = f.path[1]
			local qualified = table.concat(f.path, ".")
			local ownerPath = table.concat(f.path, ".", 1, #f.path - 1)
			local ownerClass = if #f.path > 1 then decls.locals[ownerPath] else nil
			if ownerClass == nil and #f.path > 1 and classes[ownerPath] and not decls.locals[head] then
				-- `function Frame:SetPoint()` where `Frame` is a class name used directly.
				local node = root.children[head]
				if f.method or (node == nil or node.kind ~= "ns") then
					ownerClass = ownerPath
				end
			end
			if ownerClass then
				local c = classes[ownerClass] or getClass(ownerClass, decls.file)
				addMember(
					c,
					{
						name = f.path[#f.path],
						kind = if f.method then "method" else "static",
						sigs = withOverloads(f),
					} :: any
				)
				continue
			end
			if #f.path == 2 and config.stdlibAliases[head] == head then
				-- string.split, table.wipe: indexed for the compat aliases, never declared.
				if stdlib[qualified] == nil then
					stdlib[qualified] = f
				end
				continue
			end
			if luauGlobals[head] or input.reserved[head] then
				continue
			end
			if not clientHas(qualified) then
				stats.droppedNotInClient += 1
				table.insert(stats.droppedApis, qualified)
				continue
			end
			local parent = nodeAt(f.path, #f.path - 1)
			local leaf = f.path[#f.path]
			local existing = parent.children[leaf]
			if existing and existing.kind == "func" then
				stats.duplicateFunctions += 1
				continue
			end
			parent.children[leaf] = {
				kind = "func",
				children = {},
				sigs = withOverloads(f),
				doc = f.signature.doc,
			}
		end

		for _, e in decls.enums do
			if e.path[1] == "Enum" or e.path[1] == "Constants" then
				continue -- the client dump has the authoritative tables
			end
			local parent = nodeAt(e.path, #e.path - 1)
			parent.children[e.path[#e.path]] = { kind = "enum", children = {}, sigs = {}, enum = e }
			enumTypes[table.concat(e.path, ".")] = e
		end
	end

	-- Enum, Constants and the LE_* globals, straight from the client.
	local function addClientTables(outer: string, tables: { Resources.EnumTable })
		for _, t in tables do
			local path = { outer, t.name }
			local decl: Parse.EnumDecl = { path = path, entries = t.entries, file = "resources:LuaEnum.lua" }
			nodeAt(path, 1).children[t.name] = { kind = "enum", children = {}, sigs = {}, enum = decl }
			if outer == "Enum" then
				enumTypes["Enum." .. t.name] = decl
			end
		end
	end
	addClientTables("Enum", res.enums)
	addClientTables("Constants", res.constants)
	for _, c in res.globalConstants do
		if root.children[c.key] == nil and not input.reserved[c.key] then
			local isNumber = string.match(c.value, "^%-?[%dx%.a-fA-F]+$") ~= nil
			root.children[c.key] =
				{ kind = "value", children = {}, sigs = {}, valueType = if isNumber then "number" else "any" }
		end
	end

	-- The client's event list is the closed set of FrameEvent names.
	if aliases.FrameEvent then
		local variants: { Type } = {}
		for _, event in res.events do
			table.insert(variants, { kind = "string", value = event })
		end
		aliases.FrameEvent = { name = "FrameEvent", base = nil, variants = variants, file = "resources:Events.lua" }
	end
	-- CreateFrame accepts only the widget types the client has.
	if aliases.FrameType then
		local kept: { Type } = {}
		for _, v in aliases.FrameType.variants do
			if v.kind == "string" and res.widgets[v.value] then
				table.insert(kept, v)
			end
		end
		aliases.FrameType = { name = "FrameType", base = nil, variants = kept, file = aliases.FrameType.file }
	end

	-- Drop namespaces the client filter emptied.
	local function prune(node: Node): boolean
		for _, key in sortedKeys(node.children) do
			local child = node.children[key]
			if child.kind == "ns" and not prune(child) then
				node.children[key] = nil
			end
		end
		return next(node.children) ~= nil
	end
	prune(root)

	-- Client APIs that upstream never annotates (Forever keeps old functions retail removed) get an
	-- untyped declaration, so calling a real API is never an "unknown global" error. The report lists
	-- them; each is a good first contribution upstream.
	local untyped: { string } = {}
	local clientFunctions: { [string]: boolean } = {}
	for name in res.globalApi do
		clientFunctions[name] = true
	end
	for name in res.frameXml do
		clientFunctions[name] = true
	end
	for _, qualified in sortedKeys(clientFunctions) do
		local path = string.split(qualified, ".")
		if input.reserved[path[1]] then
			continue
		end
		local valid = #path <= 2
		for _, part in path do
			if not string.match(part, "^[%a_][%w_]*$") then
				valid = false
			end
		end
		if not valid or luauGlobals[path[1]] or classes[path[1]] or config.stdlibAliases[path[1]] then
			continue
		end
		local parent = root
		local missing = false
		for i = 1, #path - 1 do
			local child = parent.children[path[i]]
			if child == nil then
				child = { kind = "ns", children = {}, sigs = {} }
				parent.children[path[i]] = child
			elseif child.kind ~= "ns" then
				missing = true -- e.g. a function and a namespace with one name; leave it alone
				break
			end
			parent = child :: Node
		end
		local leaf = path[#path]
		if not missing and parent.children[leaf] == nil then
			parent.children[leaf] = {
				kind = "func",
				children = {},
				sigs = {
					{
						params = {
							{ name = "...", type = { kind = "name", name = "any", args = {} }, optional = false },
						},
						returns = {
							{ kind = "name", name = "...", args = { { kind = "name", name = "any", args = {} } } },
						},
						generics = {},
						deprecated = false,
						doc = nil,
					},
				},
				doc = "Untyped: no upstream annotation for this " .. config.gameName .. " API.",
			}
			table.insert(untyped, qualified)
		end
	end

	-- Extern (widget) classes: a class is extern if any ancestor is.
	local externMemo: { [string]: boolean } = {}
	local function isExtern(name: string, depth: number): boolean
		if externMemo[name] ~= nil then
			return externMemo[name]
		end
		local c = classes[name]
		if c == nil or depth > 32 then
			return false
		end
		local result = c.extern
		if not result then
			for _, p in c.parents do
				if isExtern(p, depth + 1) then
					result = true
					break
				end
			end
		end
		externMemo[name] = result
		return result
	end
	for name, c in classes do
		c.extern = isExtern(name, 0)
	end

	-- Type names ------------------------------------------------------------------------------------
	local typeNames: { [string]: string } = {}
	local usedNames: { [string]: boolean } = {}
	local function claim(sourceName: string)
		if typeNames[sourceName] then
			return
		end
		local name: string = (string.gsub(sourceName, "[^%w_]", "_"))
		local reserved = RESERVED_TYPE_NAMES[name] or TypeExpr.RESERVED[name] or name == "table" or name == "self"
		if reserved then
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
	for _, name in sortedKeys(classes) do
		claim(name)
	end
	for _, name in sortedKeys(aliases) do
		if classes[name] == nil then
			claim(name)
		end
	end
	for _, name in sortedKeys(enumTypes) do
		if classes[name] == nil and aliases[name] == nil then
			claim(name)
		end
	end

	local function makeResolver(generics: { [string]: string }?, selfName: string?): TypeExpr.Resolver
		local resolve: TypeExpr.Resolver
		function resolve(name: string, args: { Type }): string
			if name == "..." then
				return "..." .. TypeExpr.wrap(TypeExpr.print(args[1], resolve))
			end
			if generics and generics[name] then
				return generics[name]
			end
			if name == "self" and selfName then
				return selfName
			end
			if name == "table" and #args == 2 then
				return "{ [" .. TypeExpr.print(args[1], resolve) .. "]: " .. TypeExpr.print(args[2], resolve) .. " }"
			elseif name == "table" and #args == 1 then
				return "{ " .. TypeExpr.print(args[1], resolve) .. " }"
			end
			local builtin = BUILTIN_TYPES[name]
			if builtin then
				return builtin
			end
			local declared = typeNames[name]
			if declared then
				return declared
			end
			stats.unresolvedTypes[name] = (stats.unresolvedTypes[name] or 0) + 1
			return "any"
		end
		return resolve
	end

	local function genericScope(sig: Signature, erase: boolean?): ({ [string]: string }?, string)
		if #sig.generics == 0 then
			return nil, ""
		end
		local scope = {}
		local names = {}
		for _, g in sig.generics do
			-- Declarations (`declare function`, extern methods) cannot be generic: erase to `any`.
			scope[g] = if erase then "any" else g
			table.insert(names, g)
		end
		if erase then
			return scope, ""
		end
		return scope, "<" .. table.concat(names, ", ") .. ">"
	end

	-- LuaCATS lets a backtick generic bind a string argument to the class of that name. Luau cannot,
	-- so `CreateFrame(frameType: `T` | FrameType, ...): T` becomes one overload per FrameType value.
	local function expandBacktick(sig: Signature): { Signature }
		for index, p in sig.params do
			local t = p.type
			if t.kind == "union" then
				local tick: string? = nil
				local aliasName: string? = nil
				for _, member in t.types do
					if member.kind == "backtick" then
						tick = member.name
					elseif member.kind == "name" and aliases[member.name] then
						aliasName = member.name
					end
				end
				if tick and aliasName then
					local out: { Signature } = {}
					for _, variant in (aliases[aliasName] :: Parse.Alias).variants do
						if variant.kind == "string" then
							local className = if classes[variant.value] then variant.value else "Frame"
							local params = table.clone(sig.params)
							params[index] = { name = p.name, type = variant, optional = false }
							for j, other in params do
								if other.type.kind == "union" then
									-- Drop the remaining backtick generics (`Tp` | Template -> Template).
									local kept = {}
									for _, member in other.type.types do
										if member.kind ~= "backtick" then
											table.insert(kept, member)
										end
									end
									params[j] = {
										name = other.name,
										type = { kind = "union", types = kept },
										optional = other.optional,
									}
								end
							end
							local returnType: Type = { kind = "name", name = className, args = {} }
							table.insert(out, {
								params = params,
								returns = { returnType },
								generics = {},
								deprecated = sig.deprecated,
								doc = sig.doc,
							})
						end
					end
					return out
				end
			end
		end
		return { sig }
	end

	-- A signature with its types already printed; overloads are merged at this level.
	type PrintedParam = { name: string, type: string, vararg: boolean }
	type Printed = { generics: string, params: { PrintedParam }, returns: string }

	local function printSig(sig: Signature, selfName: string?, erase: boolean): Printed
		local scope, genericText = genericScope(sig, erase)
		local resolve = makeResolver(scope, selfName)
		local params = {}
		for _, p in sig.params do
			if p.name == "..." then
				local text = TypeExpr.printParam(p, resolve, false, false) -- "...T"
				table.insert(params, { name = "...", type = string.sub(text, 4), vararg = true })
			else
				local text = TypeExpr.printParam(p, resolve, true, false) -- "name: T"
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

	-- The members of a printed union, plus whether it includes nil.
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

	-- Luau cannot infer a string literal argument as a singleton when the parameter is overloaded, so
	-- `SetPoint("CENTER")` against two `point: FramePoint` overloads fails. Overloads that return the
	-- same thing are therefore merged into one signature, with each position's types unioned (and
	-- optional when some overload lacks it). Overloads with different results stay overloads.
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

	local function printSigs(sigs: { Signature }, selfName: string?, erase: boolean): { Printed }
		local printed = {}
		local seen: { [string]: boolean } = {}
		for _, sig in sigs do
			for _, e in expandBacktick(sig) do
				local p = printSig(e, selfName, erase)
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
		end
		return mergeOverloads(printed)
	end

	-- `(a: T, ...: V)` for declarations, `(a: T, ...V)` for function types.
	local function renderParams(p: Printed, selfParam: string?, declaration: boolean): string
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

	local function overloadSet(sigs: { Signature }, selfType: string?, selfName: string?): string
		local parts = {}
		for _, p in printSigs(sigs, selfName, false) do
			table.insert(parts, p.generics .. renderParams(p, selfType, false) .. " -> " .. p.returns)
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

	-- Emission --------------------------------------------------------------------------------------
	local out: { string } = {}
	local function emit(line: string)
		table.insert(out, line)
	end

	emit("-- World of Warcraft: Forever API definitions for luau-lsp.")
	emit("-- GENERATED FILE: do not edit. Regenerate with `lune run scripts/generate`.")
	emit("-- Types: the LuaCATS annotations of " .. input.upstream.annotations.repository .. " (MIT licence),")
	emit("--   commit " .. input.upstream.annotations.commit .. ".")
	emit("-- Filtered to what the client has: " .. input.upstream.resources.repository .. ",")
	emit("--   commit " .. input.upstream.resources.commit .. ".")
	emit("")

	-- Aliases and enum types.
	local aliasStack: { [string]: boolean } = {}
	local function aliasType(a: Parse.Alias): string
		local resolve = makeResolver(nil, nil)
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
			-- An open alias keeps its listed strings as hints only: they widen to `string`.
			if v.kind == "string" and not closed then
				table.insert(parts, "string")
			else
				table.insert(parts, TypeExpr.print(v, resolve))
			end
		end
		if #parts == 0 then
			return "any"
		end
		local flat = {}
		for _, p in parts do
			for _, piece in TypeExpr.splitUnion(p) do
				table.insert(flat, piece)
			end
		end
		local result = TypeExpr.unionOf(flat)
		if result == typeNames[a.name] then
			return "any"
		end
		return result
	end

	-- Luau rejects very long type annotations, so a big union is declared in chunks.
	local CHUNK = 250
	local function emitAlias(typeName: string, text: string)
		local members = TypeExpr.splitUnion(text)
		if #members <= CHUNK then
			emit("export type " .. typeName .. " = " .. text)
			return
		end
		local chunkNames = {}
		for start = 1, #members, CHUNK do
			local chunkName = typeName .. "_" .. (#chunkNames + 1)
			table.insert(chunkNames, chunkName)
			emit(
				"export type "
					.. chunkName
					.. " = "
					.. table.concat(members, " | ", start, math.min(start + CHUNK - 1, #members))
			)
		end
		emit("export type " .. typeName .. " = " .. table.concat(chunkNames, " | "))
	end

	emit("-- Aliases ----------------------------------------------------------------------------------")
	for _, name in sortedKeys(aliases) do
		if classes[name] == nil and not aliasStack[name] then
			emitAlias(typeNames[name], aliasType(aliases[name]))
		end
	end
	emit("")
	emit("-- Enum value types ---------------------------------------------------------------------------")
	for _, name in sortedKeys(enumTypes) do
		if classes[name] == nil and aliases[name] == nil then
			local e = enumTypes[name]
			local allStrings = #e.entries > 0
			local literals = {}
			for _, entry in e.entries do
				if string.match(entry.value, "^[\"']") then
					table.insert(literals, '"' .. string.sub(entry.value, 2, -2) .. '"')
				else
					allStrings = false
				end
			end
			emitAlias(typeNames[name], if allStrings then TypeExpr.unionOf(literals) else "number")
		end
	end
	emit("")

	-- Collect every member of a class, own members first, then ancestors (stopping at `stopAt`).
	local function collectMembers(
		name: string,
		stopAt: { [string]: boolean },
		into: { Member },
		seen: { [string]: boolean },
		visited: { [string]: boolean }
	)
		if visited[name] or stopAt[name] then
			return
		end
		visited[name] = true
		local c = classes[name]
		if c == nil then
			return
		end
		for _, memberName in c.order do
			if not seen[memberName] then
				seen[memberName] = true
				table.insert(into, c.members[memberName])
			end
		end
		for _, p in c.parents do
			collectMembers(p, stopAt, into, seen, visited)
		end
	end

	local function chainOf(name: string): { [string]: boolean }
		local chain = {}
		local cursor: string? = name
		while cursor and not chain[cursor] do
			chain[cursor] = true
			local c = classes[cursor]
			local nextName: string? = nil
			if c then
				for _, p in c.parents do
					if classes[p] and classes[p].extern then
						nextName = p
						break
					end
				end
			end
			cursor = nextName
		end
		return chain
	end

	local function externParent(c: ClassInfo): string?
		for _, p in c.parents do
			if classes[p] and classes[p].extern then
				return p
			end
		end
		return nil
	end

	-- Table classes.
	emit("-- Structures and mixins ---------------------------------------------------------------------")
	for _, name in sortedKeys(classes) do
		local c = classes[name]
		if not c.extern then
			local typeName = typeNames[name]
			local members: { Member } = {}
			collectMembers(name, {}, members, {}, {})
			if #members == 0 then
				emit("export type " .. typeName .. " = { [any]: any }")
			else
				emit("export type " .. typeName .. " = {")
				table.sort(members, function(a, b)
					return a.name < b.name
				end)
				local indexer: string? = nil
				for _, m in members do
					if m.kind == "field" then
						local resolve = makeResolver(nil, typeName)
						local t = TypeExpr.print(m.type, resolve)
						if m.optional and t ~= "any" and string.sub(t, -1) ~= "?" then
							t = TypeExpr.wrap(t) .. "?"
						end
						if string.sub(m.name, 1, 1) == "[" then
							local keyType = TypeExpr.parse(string.sub(m.name, 2, -2))
							if indexer == nil and keyType then
								indexer = "\t[" .. TypeExpr.print(keyType, resolve) .. "]: " .. t .. ","
							end
						else
							emit("\t" .. identifierKey(m.name) .. ": " .. t .. ",")
						end
					else
						local selfType = if m.kind == "method" then "self: " .. typeName else nil
						emit(
							"\t"
								.. identifierKey(m.name)
								.. ": "
								.. overloadSet((m :: any).sigs, selfType, typeName)
								.. ","
						)
					end
				end
				if indexer then
					emit(indexer)
				end
				emit("}")
			end
		end
	end
	emit("")

	-- Extern (widget) classes, parents before children.
	emit("-- Widgets ------------------------------------------------------------------------------------")
	local emitted: { [string]: boolean } = {}
	local function emitExtern(name: string)
		if emitted[name] then
			return
		end
		emitted[name] = true
		local c = classes[name]
		local parent = externParent(c)
		if parent then
			emitExtern(parent)
		end
		local typeName = typeNames[name]
		if c.doc then
			emit("-- " .. c.doc)
		end
		if parent then
			emit("declare extern type " .. typeName .. " extends " .. typeNames[parent] .. " with")
		else
			emit("declare extern type " .. typeName .. " with")
		end
		local members: { Member } = {}
		local stop = if parent then chainOf(parent) else {}
		collectMembers(name, stop, members, {}, {})
		local allowed = clientWidgetMethods(name)
		if allowed then
			local kept = {}
			for _, m in members do
				if m.kind == "field" or (allowed :: { [string]: boolean })[m.name] then
					table.insert(kept, m)
				else
					stats.droppedWidgetMethods += 1
				end
			end
			members = kept
		end
		table.sort(members, function(a, b)
			return a.name < b.name
		end)
		for _, m in members do
			if m.kind == "field" then
				if string.sub(m.name, 1, 1) ~= "[" then
					local t = TypeExpr.print(m.type, makeResolver(nil, typeName))
					if m.optional and t ~= "any" and string.sub(t, -1) ~= "?" then
						t = TypeExpr.wrap(t) .. "?"
					end
					emit("\t" .. identifierKey(m.name) .. ": " .. t)
				end
			elseif m.kind == "method" then
				for _, p in printSigs((m :: any).sigs, typeName, true) do
					emit("\tfunction " .. m.name .. renderParams(p, "self", true) .. ": " .. p.returns)
				end
			else
				emit("\t" .. identifierKey(m.name) .. ": " .. overloadSet((m :: any).sigs, nil, typeName))
			end
		end
		emit("end")
		emit("")
	end
	for _, name in sortedKeys(classes) do
		if classes[name].extern then
			emitExtern(name)
		end
	end

	-- Globals.
	local function valueType(node: Node): string
		if node.kind == "func" then
			return overloadSet(node.sigs, nil, nil)
		elseif node.kind == "instance" then
			return typeNames[node.class :: string] or "any"
		elseif node.kind == "value" then
			local v = node.valueType :: string
			if startsWith(v, "@stdlib:") then
				local target = string.sub(v, 9)
				local f = stdlib[target]
				if f then
					return overloadSet(withOverloads(f), nil, nil)
				end
				return "typeof(" .. target .. ")"
			end
			return v
		end
		return "any"
	end

	local function emitTable(node: Node, indent: string)
		for _, key in sortedKeys(node.children) do
			local child = node.children[key]
			if child.kind == "ns" then
				emit(indent .. identifierKey(key) .. ": {")
				emitTable(child, indent .. "\t")
				emit(indent .. "},")
			elseif child.kind == "enum" then
				local e = child.enum :: Parse.EnumDecl
				emit(indent .. identifierKey(key) .. ": {")
				local seen = {}
				for _, entry in e.entries do
					if not seen[entry.key] then
						seen[entry.key] = true
						local t = if string.match(entry.value, "^[\"']") then "string" else "number"
						emit(indent .. "\t" .. identifierKey(entry.key) .. ": " .. t .. ",")
					end
				end
				emit(indent .. "},")
			else
				emit(indent .. identifierKey(key) .. ": " .. valueType(child) .. ",")
			end
		end
	end

	emit("-- Globals ------------------------------------------------------------------------------------")
	local counts = { functions = 0, namespaces = 0, values = 0 }
	for _, key in sortedKeys(root.children) do
		local node = root.children[key]
		if node.kind == "func" then
			counts.functions += 1
			if node.doc then
				emit("-- " .. node.doc)
			end
			local printed = printSigs(node.sigs, nil, false)
			if #printed == 1 and printed[1].generics == "" then
				emit("declare function " .. key .. renderParams(printed[1], nil, true) .. ": " .. printed[1].returns)
			else
				emit("declare " .. key .. ": " .. overloadSet(node.sigs, nil, nil))
			end
		elseif node.kind == "ns" or node.kind == "enum" then
			counts.namespaces += 1
			emit("declare " .. key .. ": {")
			if node.kind == "enum" then
				emitTable({ kind = "ns", children = { [key] = node }, sigs = {} }, "\t")
			else
				emitTable(node, "\t")
			end
			emit("}")
		else
			counts.values += 1
			emit("declare " .. key .. ": " .. valueType(node))
		end
	end
	emit("")

	local externCount, tableCount = 0, 0
	for _, c in classes do
		if c.extern then
			externCount += 1
		else
			tableCount += 1
		end
	end

	local unresolved = {}
	for _, name in sortedKeys(stats.unresolvedTypes) do
		table.insert(unresolved, { name = name, uses = stats.unresolvedTypes[name] })
	end

	-- Every function in the global tree, top-level and namespaced (C_Timer.After).
	local function countFunctions(node: Node): number
		local n = 0
		for _, child in node.children do
			if child.kind == "func" then
				n += 1
			elseif child.kind == "ns" then
				n += countFunctions(child)
			end
		end
		return n
	end
	local allFunctions = countFunctions(root)

	local report = {
		upstream = input.upstream,
		game = config.gameName,
		counts = {
			files = #input.files,
			widgets = externCount,
			structures = tableCount,
			aliases = #sortedKeys(aliases),
			enums = #sortedKeys(enumTypes),
			functionsTyped = allFunctions - #untyped,
			functionsUntyped = #untyped,
			globalFunctions = counts.functions,
			globalTables = counts.namespaces,
			globalValues = counts.values,
			droppedNotInClient = stats.droppedNotInClient,
			droppedWidgetMethods = stats.droppedWidgetMethods,
			duplicateFunctions = stats.duplicateFunctions,
		},
		droppedApis = (function()
			table.sort(stats.droppedApis)
			return stats.droppedApis
		end)(),
		parseErrors = stats.parseErrors,
		unresolvedTypes = unresolved,
		untypedApis = untyped,
	}
	return table.concat(out, "\n"), report
end

return Build
