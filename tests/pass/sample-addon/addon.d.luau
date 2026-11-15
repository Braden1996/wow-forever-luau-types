-- An addon's own globals: the SavedVariables listed in its .toc. Addons keep a file like this next to
-- their code and pass it to luau-lsp as a second definitions file. Write them through `_G`.

export type SampleDB = {
	enabled: boolean,
	runs: number,
	lastZone: string?,
}

declare SampleAddonDB: SampleDB?
