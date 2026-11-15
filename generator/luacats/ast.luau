--!strict
-- The AST of a LuaCATS type expression, shared by the parser (luacats/typeparse.luau), the printer
-- (luacats/print.luau) and the documentation reader (apidocs.luau).

export type Param = {
	name: string, -- "..." for a variadic parameter
	type: Type,
	optional: boolean,
}

-- A key in a table type literal: a named property (`name` or `["name"]`), an indexer over a key type
-- (`[string]`), or an array position (`[1]`).
export type TableKey =
	{ kind: "prop", name: string }
	| { kind: "index", type: Type }
	| { kind: "position", index: number }

export type TableField = { key: TableKey, type: Type, optional: boolean }

export type Type =
	{ kind: "name", name: string, args: { Type } }
	| { kind: "string", value: string } -- the unescaped value
	| { kind: "number" }
	| { kind: "bool", value: boolean }
	| { kind: "backtick", name: string }
	| { kind: "union", types: { Type } }
	| { kind: "optional", inner: Type }
	| { kind: "array", inner: Type }
	| { kind: "map", key: Type, value: Type }
	| { kind: "variadic", inner: Type } -- a variadic result tail: `...T`
	| { kind: "fun", params: { Param }, returns: { Type } }
	| { kind: "table", fields: { TableField } }

return {}
