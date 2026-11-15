-- This addon's own types and globals, loaded by luau-lsp next to wow-forever.d.luau.

-- The SavedVariables listed in MyAddon.toc. Read them as declared here, and write them through `_G` (Luau treats
-- declared globals as read-only). WoW sets them just before this addon's ADDON_LOADED, so they are nil until then
-- and on the first login.
export type MyAddonDB = {
	enabled: boolean,
	logins: number,
}

declare MyAddonDB: MyAddonDB?

-- The namespace WoW passes to every file as `...` (`local ADDON: string, ns: MyAddonNamespace = ...`). Declaring
-- it here lets every file share one type without a `require`.
export type MyAddonNamespace = {
	version: string,
	-- nil until ADDON_LOADED runs ns.load(): check it (`local db = ns.db; if db then ... end`) before use.
	db: MyAddonDB?,
	print: (message: string) -> (),
	load: () -> (),
}
