-- The guides' running example addon, "MyAddon": its addon.d.luau, as the saved-variables guide and the addon template
-- describe it. The docs checker loads it as `@example` next to the generated definitions, so code blocks can use the
-- addon's SavedVariables and namespace types the way an addon's own files do.

export type MyAddonDB = {
	enabled: boolean,
	logins: number,
}

declare MyAddonDB: MyAddonDB?

export type MyAddonNamespace = {
	version: string,
	-- nil until ADDON_LOADED runs ns.load(): check it before use.
	db: MyAddonDB?,
	print: (message: string) -> (),
	load: () -> (),
}
