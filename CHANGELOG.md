# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org).

## [Unreleased]

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

[Unreleased]: https://github.com/Braden1996/wow-forever-luau-types/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/Braden1996/wow-forever-luau-types/releases/tag/v0.1.0
