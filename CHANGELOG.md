# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org).

## [Unreleased]

## [0.2.0] - 2026-11-15

### Changed (breaking)

- The definitions now require Luau's **new type solver** (`luau-lsp.fflags.enableNewSolver`,
  `--flag:LuauSolverV2=true`, the default in `luau-analyze`). v0.1.0 failed to load under the new solver.
- Types come first from Blizzard's own API documentation for the Forever client (`Gethe/wow-ui-source`, `forever`),
  reconciled with the LuaCATS annotations by explicit rules; the C API is 99.8% typed.
- Widgets follow the client's real hierarchy (`Button → Frame → ScriptRegion → Object → FrameScriptObject`).
  `SetScript`, `HookScript`, `GetScript` and `HasScript` accept only that widget's own script names.
- `CreateFrame` is generic: `CreateFrame("Button")` returns a `Button`.
- No `any` in results: untyped APIs are `(...unknown) -> ...unknown`, and annotation `any` became `unknown`. The
  remaining `any` is limited to documented exceptions ("any table", "any function", script handler arguments).

### Added

- `EventPayloads` (every event's documented payload) and `EventHandler<E>`; `FrameEvent` is the client's event list.
- Structures that contain another's fields are derived (`Base & { ... }`).
- `coverage.json` and `COVERAGE.md`: every function, widget method, event, structure, enum and widget type is typed,
  untyped or excluded with a reason. CI fails if a typed API loses its types.
- Converter snapshot tests, negative fixtures with exact expected diagnostics, a generated banner, a PR-title check
  and CODEOWNERS.

## [0.1.0] - 2026-11-15

### Added

- `wow-forever.d.luau`: luau-lsp definitions for the WoW: Forever client (1.60.1, interface 16001), converted from
  Ketho/vscode-wow-api's LuaCATS annotations and filtered against Ketho/BlizzardInterfaceResources' `forever` dump.
  It covers global functions and `C_*` namespaces, widgets as extern types with inheritance, structures and mixins,
  `Enum` and `Constants` from the client, and the client's event names as a closed `FrameEvent` union.
- Client APIs without an upstream annotation are declared untyped, so real APIs are never unknown globals.
- `report.json`: counts, dropped APIs, untyped APIs and unresolved annotation types.
- The converter (`generator/`, strict Luau run by Lune), a sample addon that type-checks with zero diagnostics, and
  negative samples that must produce specific errors.
- CI (freshness, samples, strict generator, StyLua, selene, typos, actionlint, zizmor), a tag-triggered release, and
  Renovate for tools, actions and both upstream pins.

[Unreleased]: https://github.com/Braden1996/wow-forever-luau-types/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/Braden1996/wow-forever-luau-types/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/Braden1996/wow-forever-luau-types/releases/tag/v0.1.0
