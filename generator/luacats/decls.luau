--!strict
-- What a LuaCATS annotation file declares (luacats/file.luau builds it), and the state the tag and
-- statement readers share while reading one file.

local Ast = require("./ast")

type Type = Ast.Type
type Param = Ast.Param

-- A `---@field`: a named property, or an indexer (`---@field [string] T`) with its key type.
export type Field = {
	name: string, -- the property name, or the indexer's text ("[string]") for de-duplication
	keyType: Type?, -- set for an indexer
	type: Type,
	optional: boolean,
	visibility: string?,
}

-- `returnNames`: each result's name where the source gives one ("" where it does not); absent for call
-- shapes with no names (`---@overload`, generated signatures).
export type Signature = {
	params: { Param },
	returns: { Type },
	returnNames: { string }?,
	generics: { string },
}

export type Func = {
	path: { string }, -- e.g. {"C_Container", "GetBagName"}
	method: boolean, -- defined with ':'
	signature: Signature,
	overloads: { Signature },
	file: string,
}

export type Class = {
	name: string,
	parents: { string },
	fields: { Field },
	file: string,
}

export type Alias = {
	name: string,
	base: Type?,
	variants: { Type },
	file: string,
}

export type EnumDecl = {
	path: { string },
	entries: { { key: string, value: string } }, -- value: the Lua literal or reference text
	file: string,
}

export type Global = {
	path: { string },
	class: string?, -- the ---@class annotating the assignment, if any
	value: string, -- the right-hand side text
	file: string,
}

export type FileDecls = {
	file: string,
	classes: { Class },
	aliases: { Alias },
	funcs: { Func },
	enums: { EnumDecl },
	globals: { Global },
	locals: { [string]: string }, -- local variable name -> class name it holds
	errors: { string },
}

-- The doc block read so far, waiting for the Lua statement it describes.
export type Pending = {
	params: { Param },
	returns: { Type },
	returnNames: { string },
	generics: { string },
	overloads: { Type },
	class: Class?,
	enum: string?,
}

-- One file's reading state, shared by luacats/tags.luau and luacats/statements.luau.
export type Reader = {
	file: string,
	source: string, -- CRLF-normalised
	lines: { string },
	lineStarts: { number }, -- offset in `source` of each line's first character
	out: FileDecls,
	pending: Pending,
	currentAlias: Alias?, -- the alias `---|` continuation lines extend
	fail: (lineNo: number, message: string) -> (),
	typeOrAny: (text: string, lineNo: number) -> (Type, string),
}

local Decls = {}

function Decls.newPending(): Pending
	return { params = {}, returns = {}, returnNames = {}, generics = {}, overloads = {}, class = nil, enum = nil }
end

return Decls
