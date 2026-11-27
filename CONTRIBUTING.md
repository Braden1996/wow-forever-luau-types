# Contributing

Thanks for helping. Issues and pull requests are welcome, from one-line fixes to new converter rules.

## Where does the fix belong?

| Problem                                                                                    | Where to fix it                                                                                                               |
| ------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------- |
| A wrong type for a documented C API (most `C_*` functions, widget methods, event payloads) | Blizzard's documentation is authoritative; if it is wrong, add a narrow rule in `packages/generator/src/` (see "Merge rules") |
| A wrong or missing type for an undocumented global, FrameXML mixin or Lua extension        | Upstream annotations: [Ketho/vscode-wow-api](https://github.com/Ketho/vscode-wow-api)                                         |
| An API Forever has but the definitions lack (or the reverse)                               | Client dump: [Ketho/BlizzardInterfaceResources](https://github.com/Ketho/BlizzardInterfaceResources) (`forever` branch)       |
| A construct converted wrongly, or invalid Luau                                             | Here: `packages/generator/src/`, with a snapshot case                                                                         |
| A FrameXML table or frame global no source declares                                        | Here: `supplements/framexml.d.luau`                                                                                           |
| A false or missed error in real addon code                                                 | Here: a sample under `tests/`, then fix the cause                                                                             |
| The addon template                                                                         | Here: `templates/addon/` (CI type-checks and builds it)                                                                       |

Never edit generated files by hand: `definitions/` and `.github/banner.svg` come from `sgt run generate`,
and CI fails if they differ from a fresh generation.

## Setup

1. Install [mise](https://mise.jdx.dev). `mise install` installs every pinned tool: Sergeant (`sgt`), `woof`, Lune, luau-lsp, StyLua,
   selene, darklua, typos, actionlint, zizmor, lychee, lefthook, and Bun and Node for the docs site (versions in `mise.toml`, checksums in
   `mise.lock`).
2. `mise exec -- lefthook install` installs the git hooks: formatting and spelling on commit, `sgt check && sgt test` on push. Never bypass them with `--no-verify`.
3. Open the folder in **VS Code** (install the recommended extensions; `.vscode/tasks.json` runs the Sergeant targets)
   or **Zed** (install the "Luau" extension). Both are set up for luau-lsp with the new type solver and the
   generated definitions, so `tests/` and `templates/` show the diagnostics CI does. Run
   `mise exec -- lune setup` once so the scripts' `@lune/*` requires resolve.

## Tasks

[Sergeant](https://github.com/Braden1996/sergeant) (`sgt`) orchestrates checks, tests, and commands:

| Command                                              | What it does                                                                      |
| ---------------------------------------------------- | --------------------------------------------------------------------------------- |
| `mise exec -- sgt check`                             | Format, lint, typecheck, boundaries, and hermetic sample/snapshot/template checks |
| `mise exec -- sgt test`                              | Run all colocated converter `*.spec.luau` unit suites with caching                |
| `mise exec -- sgt doctor`                            | Verify toolchain, workspace config, and `woof` state                              |
| `mise exec -- sgt run generate`                      | Fetch the pinned upstreams into `.upstream/` and regenerate every generated file  |
| `mise exec -- sgt fmt`                               | Format Markdown/JSON/YAML/TOML and Luau                                           |
| `mise exec -- sgt run docs-check`                    | The docs site: lint and type check, astro check, format, tests, build and links   |
| `mise exec -- sgt run docs-dev`                      | Serve the docs site locally                                                       |
| `mise exec -- lune run scripts/test -- --update`     | Rewrite the negative fixtures' `.expected` files after an intended change         |
| `mise exec -- lune run scripts/snapshot -- --update` | Rewrite the snapshot cases' expected files after an intended change               |

`sgt run coverage-diff` compares `definitions/coverage.json` with the same file at `$COVERAGE_BASE` (default
`origin/main`) and fails if an API that was typed there is untyped now. It also fails unless
`definitions/api-shapes.json` shapes exactly the functions and widget methods `coverage.json` lists.

### The documentation site

`docs/` is the site at [braden1996.github.io/wow-forever-luau-types](https://braden1996.github.io/wow-forever-luau-types/):
Astro and Starlight on Bun. Its API reference is generated from `definitions/` at build time, so a change to the
definitions needs no docs change, but it does rebuild and re-check the site. `docs:check` runs:

- oxlint, type-aware, with the strict TypeScript type check in the same pass (tsrs, the Rust port of TypeScript 7);
- `astro check` over the `.astro` files, and oxfmt;
- the unit tests (the definitions parser, cross-references, search ranking);
- the static build of every page, then a check that every internal link and anchor resolves.

The `pages` workflow deploys `main` to GitHub Pages.

## Tests

- **`tests/pass/<addon>/`** and **`templates/<name>/`** must type-check with zero diagnostics; a `.d.luau` there
  (other than the downloaded definitions) is loaded as that addon's own definitions.
- **`tests/fail/*.luau`** are negative fixtures. Each must produce exactly the diagnostics in its `.expected` file
  (line, column, full message), and every line marked `-- expect-error: <text>` must be among them.
- **`tests/snapshots/<case>/`** are converter cases: small inputs in upstream formats (`annotations/`, `docs/`,
  `client/`) with `expected.d.luau` and `expected.coverage.json`. Keep the inputs byte-for-byte in upstream style
  (they are excluded from StyLua and dprint).
- **`templates/<name>/`** must also build: darklua compiles each file its `.toc` loads to valid Lua 5.1.

## Merge rules

[`packages/generator/src/build.luau`](packages/generator/src/build.luau) runs the stages in [`packages/generator/src/stages/`](packages/generator/src/stages); the merge rules are
documented at `Signatures.reconcile` in [`packages/generator/src/stages/signatures.luau`](packages/generator/src/stages/signatures.luau). In short: the client decides what
exists; Blizzard's documentation gives types first; an argument is optional if either source says so; the
annotations' extra call shapes are kept; a documented result typed as a callback takes the annotation's type.
[`packages/generator/src/config.luau`](packages/generator/src/config.luau) and [`packages/generator/src/rules/`](packages/generator/src/rules) hold the data-only rules (which documented script object describes which widget, basic types,
closed string unions, parameter overrides). Every rule needs a comment saying why, and a snapshot case.

## Dependencies

- **Upstream sources:** the weekly `upstream` workflow moves the three pins in `upstream.toml` to their branch
  heads, regenerates, and opens a pull request (`feat(upstream): …`). Review `definitions/COVERAGE.md` and
  `definitions/report.json` in its diff. If `tests` fails, update the fixtures or fix the generator on that branch;
  the workflow will not overwrite a branch that has your commits.
  To bump by hand: `mise exec -- lune run scripts/bump-upstream`, then `mise exec -- sgt run generate`.
- **GitHub Actions:** Dependabot opens grouped pull requests for the SHA-pinned actions.
- **The docs site's npm packages:** Dependabot (Bun ecosystem, `docs/`), grouped, after a seven-day cooldown.
- **Tools:** edit the version in `mise.toml`, then `mise lock` and `sgt check`.

## Pull requests

- One concern per pull request.
- Title: `type(scope): summary`, checked by CI. Types: feat fix perf refactor test docs build ci chore style revert.
  Scopes: generator definitions upstream supplements template tests ci docs deps repo.
- Note user-visible changes in `CHANGELOG.md` under "Unreleased".

## Releases

Maintainers move the "Unreleased" notes in `CHANGELOG.md` under a version heading, update `version` in `woof.toml`,
then tag `vX.Y.Z` on `main`. The release workflow re-runs the full Sergeant gate from a cold start and publishes
`wow-forever.d.luau`, `report.json`, `coverage.json`, `api-shapes.json`, `COVERAGE.md`, `luau-lsp.settings.json`,
a `woof`-native `.zip` archive, and `SHA256SUMS`. Versioning: a minor version for an upstream bump or any change that
can break existing code (types only get stricter or move), a patch for fixes that only remove false errors.

## Conduct

This project follows the [Code of Conduct](CODE_OF_CONDUCT.md).
