# MyAddon: a strict-Luau addon template for WoW: Forever

A starting point for an addon written in strict [Luau](https://luau.org) and type-checked against
[wow-forever-luau-types](https://github.com/Braden1996/wow-forever-luau-types). CI there type-checks this template
and builds it to Lua 5.1 on every change, so it always works with the latest definitions.

## Use it

1. Copy just this folder (it needs [Node.js](https://nodejs.org) for `npx`; works in PowerShell, cmd and bash):

   ```sh
   npx degit Braden1996/wow-forever-luau-types/templates/addon MyAddon
   ```

   Without Node.js, `git clone --depth 1 --filter=blob:none --sparse` the repository, run
   `git sparse-checkout set templates/addon` inside it, and copy `templates/addon` out.

2. Rename `MyAddon` everywhere it appears (a find-and-replace of `MyAddon` across the folder covers all of them):
   - the folder, and `MyAddon.toc` (WoW requires the `.toc` to be named like the folder);
   - in `MyAddon.toc`: the `## Title:` line and the `## SavedVariables: MyAddonDB` line;
   - `MyAddonDB` (the SavedVariables global and its type) in `types/addon.d.luau` and `src/Core.luau`
     (`MyAddonDB` and `_G.MyAddonDB`);
   - `MyAddonNamespace` in `types/addon.d.luau`, `src/Core.luau` and `src/Events.luau`;
   - the comments that mention `MyAddon.toc` in `src/Core.luau`, `types/addon.d.luau` and `mise.toml`.

3. Install [mise](https://mise.jdx.dev), then in the folder run `mise trust` (mise ignores a config file you have
   not trusted) and `mise install` for the pinned type checker (luau-lsp), compiler (darklua), formatter (StyLua)
   and script runner (Lune). `mise.lock` holds their checksums.

4. `mise run types` downloads the definitions, `wow-forever.d.luau`, into `types/` from the release pinned in
   `mise.toml` (`WOW_TYPES_VERSION`), and fails unless the file's SHA-256 matches both the pinned
   `WOW_TYPES_SHA256` and the release's `SHA256SUMS`. To upgrade, set both values from a newer
   [release](https://github.com/Braden1996/wow-forever-luau-types/releases). `mise run check` runs it first.

5. Open the folder in your editor. Settings are included for:
   - **VS Code**: `.vscode/settings.json`; install the recommended extensions (Luau Language Server, StyLua).
   - **Zed**: `.zed/settings.json`; install the "Luau" extension.
   - **Other editors**: run `luau-lsp lsp` with the same settings: standard platform, new type solver, all FFlags
     enabled and none synced, and the two definitions files `@wow` and `@addon`.

   The settings make the editor match `mise run check`, but editor extensions download and run their own luau-lsp
   version, not the one pinned in `mise.toml`, so the two can disagree after a luau-lsp release. `mise run check`
   (and CI) is the reference.

## Work on it

| Command          | What it does                                                                                    |
| ---------------- | ----------------------------------------------------------------------------------------------- |
| `mise run types` | Downloads and verifies the pinned definitions release into `types/`                             |
| `mise run check` | Type-checks and lints `src/` (any diagnostic fails, lint warnings included), then checks format |
| `mise run fmt`   | Formats `src/` with StyLua                                                                      |
| `mise run build` | Compiles each `src/*.luau` to `build/*.lua` (Lua 5.1), the files `MyAddon.toc` loads            |

Lint warnings fail `check` because `.luaurc` sets `"lintErrors": true`. `.github/workflows/check.yml` runs `types`,
`check` and `build` on every push and pull request.

Add a source file: create `src/Name.luau`, add `build/Name.lua` to `MyAddon.toc`, and add its line to the `build`
task in `mise.toml`. Copy `build/`, `MyAddon.toc` and nothing else into `Interface/AddOns/MyAddon` to play.

## Patterns

- **Only what WoW has.** `luau-lsp.settings.json` (passed by `mise run check`, mirrored in the editor settings)
  disables Luau standard-library names WoW's Lua 5.1 lacks, such as `table.clone` and `typeof`.
- **Shared namespace.** `types/addon.d.luau` declares `MyAddonNamespace`; each file starts with
  `local ADDON: string, ns: MyAddonNamespace = ...`.
- **SavedVariables.** Declared in `types/addon.d.luau`; read them directly, write them through `_G`. They are `nil`
  until the addon's `ADDON_LOADED` (and on a first login), so `ns.db` is typed `MyAddonDB?`: check it before use.
- **Events.** `EventHandler<"EVENT_NAME">` checks a handler against the event's documented payload; annotate its
  parameters.
- **Lua 5.1 only.** darklua removes Luau syntax but not Luau semantics. Iterate tables with `pairs`/`ipairs`, never
  `for k, v in t do`, and do not call Luau-only library functions such as `table.clone`, `table.find` or
  `string.split`: WoW runs Lua 5.1 and has none of them.
- **Untyped APIs.** A few client functions have no types yet and return `unknown`: cast what you use,
  `local key = GetBindingKeyForAction("JUMP") :: string?`.
