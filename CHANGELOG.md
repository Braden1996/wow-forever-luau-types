# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org).

## [Unreleased]

### Added

- A step-by-step tutorial on the documentation site, "Your first addon": saved data, typed events, a draggable window
  and a slash command, from the TOC file to playing it in game.

## [0.4.1] - 2026-11-16

### Fixed

- Unit tokens are strings (`UnitToken`), not `Enum.UnitTokenType` numbers, where the documentation names that
  enumeration: `Frame:RegisterUnitEvent` and `RegisterUnitEventCallback` accept `"player"`, `Frame:IsEventRegistered`
  and `UnitPositionFrame:GetMouseOverUnits` return strings, `UnitPositionFrame:SetUnitColor` takes one, and the
  `NAME_PLATE_UNIT_ADDED`/`_REMOVED` payloads (and their `FORBIDDEN_` twins) carry a string `unitToken`.

### Changed

- The documentation site takes its theme and components from the `starlight-warcraft` package.

## [0.4.0] - 2026-11-16

### Changed

- **Breaking:** every result of a call that may return nothing at all is optional (`T?`). Blizzard's documentation
  marks such calls with `MayReturnNothing` (already optional) or with a precondition whose FailureMode is ReturnNothing,
  such as `RequiresValidActionSlot`, `HasRestrictions` or `RequiresClubsInitialized`: about 150 functions and widget
  methods (`C_ActionBar.GetActionCharges`, `C_ActionBar.HasAction`, `C_CVar.SetCVar`, ...) that returned `T` now return
  `T?`, so strict code must check for nil before using the result. It applies to every call shape, including the
  annotations' overloads and callback results. These are the APIs `api-shapes.json` already marked `absent`; its
  shapes are unchanged. `report.json` (`absentResults`) and `COVERAGE.md` count them by reason.

## [0.3.0] - 2026-11-15

### Added

- `definitions/api-shapes.json`: the result shape of every function and widget method (`maybe`, `record` with named
  results, `value`, `void`, `variadic`, `protected`, ...), with `absent` reasons, callback parameters and a
  boolean-first marker, for libraries that wrap the API. `generator:coverage` checks it lists exactly what
  `coverage.json` lists; it ships with each release.
- A documentation site at [braden1996.github.io/wow-forever-luau-types](https://braden1996.github.io/wow-forever-luau-types/):
  guides, plus an API reference generated from the definitions, with cross-linked types, hover cards and symbol
  search.
- Every Luau example on the site is type-checked at build time by Luau's own checker (luau-web-checker, the new
  solver), and its identifiers show their types on hover; API symbols open their reference cards. A test keeps that
  checker in agreement with luau-lsp on `tests/pass`, `templates/` and `tests/fail`.
- `templates/addon`: a ready-to-copy addon with VS Code and Zed settings, a pinned type checker and darklua build
  (Luau to Lua 5.1), a typed shared namespace, SavedVariables and typed event handlers. CI type-checks and builds it.
- Contributor setup: moon task orchestration (`moon run :check` is the gate), lefthook git hooks, dprint and lychee,
  VS Code tasks and extensions, Zed settings.
- A weekly `upstream` workflow that moves the upstream pins and opens a pull request; Dependabot for actions.

### Changed

- CI is one cold `moon run :check` job (zizmor now part of the gate, pinned by mise); the coverage base falls back to
  main on dispatches and new branches; the release verifies on a read-only job, publishes from a separate one, and
  only from tags on main (pre-release tags publish as pre-releases).
- `SECURITY.md`, and an issue form for wrong types of documented APIs.

### Removed

- Renovate.

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

[Unreleased]: https://github.com/Braden1996/wow-forever-luau-types/compare/v0.4.1...HEAD
[0.4.1]: https://github.com/Braden1996/wow-forever-luau-types/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/Braden1996/wow-forever-luau-types/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/Braden1996/wow-forever-luau-types/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/Braden1996/wow-forever-luau-types/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/Braden1996/wow-forever-luau-types/releases/tag/v0.1.0
