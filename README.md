<p align="center">
  <img
    src=".github/banner.svg"
    alt="wow-forever-luau-types: strict Luau type definitions for the World of Warcraft: Forever API"
    width="100%"
  >
</p>

<p align="center">
  <a href="https://braden1996.github.io/wow-forever-luau-types/"><img alt="Documentation" src="https://img.shields.io/badge/docs-API%20reference-d9a441"></a>
  <a href="https://github.com/Braden1996/wow-forever-luau-types/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/Braden1996/wow-forever-luau-types/actions/workflows/ci.yml/badge.svg"></a>
  <a href="https://github.com/Braden1996/wow-forever-luau-types/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/Braden1996/wow-forever-luau-types?sort=semver"></a>
  <a href="definitions/COVERAGE.md"><img alt="C API typed" src="https://img.shields.io/badge/C%20API%20typed-83.4%25-2f6bff"></a>
  <a href="LICENSE"><img alt="MIT licence" src="https://img.shields.io/badge/licence-MIT-blue"></a>
  <img alt="WoW: Forever 1.60.1" src="https://img.shields.io/badge/WoW%3A%20Forever-1.60.1%20(16001)-d9a441">
</p>

**Write World of Warcraft addons in strict [Luau](https://luau.org) and have every API call checked.**
This repository publishes one definitions file, `wow-forever.d.luau`, for the
[luau-lsp](https://github.com/JohnnyMorganz/luau-lsp) language server and type checker. It covers everything the
**WoW: Forever** client (1.60.1, interface 16001) offers addons: global functions, `C_*` namespaces, widgets with
their real inheritance, events with their payloads, structures and enums.

**Documentation: [braden1996.github.io/wow-forever-luau-types](https://braden1996.github.io/wow-forever-luau-types/)**.
It has guides and a searchable API reference generated from the definitions, with every type cross-linked.

```luau
--!strict
local frame = CreateFrame("Frame")            -- a Frame; CreateFrame("Button") is a Button
frame:RegisterEvent("PLAYER_LOGN")             -- error: not an event the client sends
frame:SetScript("OnClick", onClick)            -- error: a plain Frame has no OnClick script
frame:SetPoint("CENTRE")                       -- error: not an anchor point
local info = C_QuestLog.GetInfo(1)
print(info.title)                              -- error: info may be nil
GetQuestLogTitle(1)                            -- error: Forever replaced it with C_QuestLog
```

## Quick start

**With [woof](https://github.com/Braden1996/woof) (recommended):** add to `woof.toml` and run `woof install` (or `sgt install` with
[Sergeant](https://github.com/Braden1996/sergeant) runs the workspace checks, tests, and builds. The pure Luau
generator lives in `packages/libraries/luau/pure/generator/`, the Lune CLI in `packages/runtimes/cli/`, and the
Astro documentation site in `packages/runtimes/docs/`. See [Contributing](CONTRIBUTING.md) for setup.

| Command            | What it verifies                                                                                                                 |
| ------------------ | -------------------------------------------------------------------------------------------------------------------------------- |
| `sgt check`        | Formatting, lint, types, workflow audits, generated files, coverage, samples, snapshots, editor settings, and the addon template |
| `sgt test`         | Converter specs, docs tests, and agreement between the docs checker and luau-lsp                                                 |
| `sgt build`        | The static docs site, including internal links and Luau examples                                                                 |
| `sgt run generate` | Regenerates the definitions and reports from the pinned upstream commits                                                         |

A scheduled workflow updates upstream pins and opens a pull request with the regenerated files.

## Editors

| Editor  | Using the definitions in an addon                                                            | Working on this repository                                                            |
| ------- | -------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| VS Code | [`templates/addon/.vscode/`](templates/addon/.vscode/settings.json)                          | [`.vscode/`](.vscode/settings.json): settings, recommended extensions, Sergeant tasks |
| Zed     | [`templates/addon/.zed/`](templates/addon/.zed/settings.json) (install the "Luau" extension) | [`.zed/settings.json`](.zed/settings.json)                                            |
| Others  | Run `luau-lsp lsp` with: standard platform, new type solver, definitions `@wow` and `@addon` | Same, plus `.editorconfig`                                                            |

## Limitations

- **New solver only.** The definitions use `keyof`, `index` and generic lookups, which need Luau's new type solver
  (`luau-lsp.fflags.enableNewSolver`, `--flag:LuauSolverV2=true`; the default in `luau-analyze`).
- Luau does not infer a lambda's parameters through `EventHandler<...>`; annotate them.
- Numeric enums are `number`: Luau has no numeric literal types.
- Libraries (Ace3, LibStub and others) are not included.

## Contributing

A wrong type for a documented C API is fixed here, as a converter rule; one for an undocumented global, FrameXML
mixin or Lua extension belongs upstream in [Ketho/vscode-wow-api](https://github.com/Ketho/vscode-wow-api). This
repository owns the converter, its rules, the tests, the template and the small supplements. See
[CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md).

## Licence and credits

MIT, see [LICENSE](LICENSE). The definitions are derived from [Ketho/vscode-wow-api](https://github.com/Ketho/vscode-wow-api)
(MIT, © Ketho), Blizzard's API documentation as published in [Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source),
and client data from [Ketho/BlizzardInterfaceResources](https://github.com/Ketho/BlizzardInterfaceResources). The last
two carry no licence file; only API names and documented types from them reach the output. Thanks to Ketho, Gethe
and their contributors.

World of Warcraft is a trademark of Blizzard Entertainment, Inc. This project is not affiliated with or endorsed by
Blizzard Entertainment.
