-- An addon's own types and globals: the SavedVariables listed in its .toc and the namespace its files share.
-- Addons keep a file like this next to their code and pass it to luau-lsp as a second definitions file.

-- SavedVariables: read them as declared here, and write them through `_G` (declared globals are read-only).
export type SampleDB = {
	enabled: boolean,
	runs: number,
	lastZone: string?,
}

declare SampleAddonDB: SampleDB?

-- The namespace WoW passes to every file as `...`; each file annotates it: `local ADDON: string, ns: Namespace = ...`.
export type Namespace = {
	name: string,
	version: string,
	-- nil until ADDON_LOADED, when WoW has loaded the SavedVariables.
	db: SampleDB?,
	money: number,
	dirtyBags: { [number]: boolean },
	enabled: boolean,
	print: (message: string) -> (),
	onPlayerLevel: (level: number) -> (),
	bags: {
		countFreeSlots: () -> number,
		describeItem: (link: string) -> string,
		questTitles: () -> { string },
		remember: (text: string) -> (),
		bindingFor: (action: string) -> string?,
	},
}
