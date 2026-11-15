# Contributing

Thanks for helping. Issues and pull requests are welcome, from one-line fixes to new converter rules.

## Where does the fix belong?

| Problem | Where to fix it |
| --- | --- |
| A wrong type for a documented C API (most `C_*` functions, widget methods, event payloads) | Blizzard's documentation is authoritative; if it is wrong, add a narrow rule in `generator/` (see "Merge rules") |
| A wrong or missing type for an undocumented global, FrameXML mixin or Lua extension | Upstream annotations: [Ketho/vscode-wow-api](https://github.com/Ketho/vscode-wow-api) |
| An API Forever has but the definitions lack (or the reverse) | Client dump: [Ketho/BlizzardInterfaceResources](https://github.com/Ketho/BlizzardInterfaceResources) (`forever` branch) |
| A construct converted wrongly, or invalid Luau | Here: `generator/`, with a snapshot case |
| A FrameXML table or frame global no source declares | Here: `supplements/framexml.d.luau` |
| A false or missed error in real addon code | Here: a sample under `tests/`, then fix the cause |

Never edit generated files by hand: `definitions/` and `.github/banner.svg` come from `lune run scripts/generate`,
and CI fails if they differ from a fresh generation.

## Setup

1. Install [mise](https://mise.jdx.dev).
2. `mise install` installs the pinned tools: Lune, luau-lsp, StyLua, selene, typos and actionlint (versions in
   `mise.toml`, checksums in `mise.lock`).
3. `mise exec -- lune setup` writes Lune's type definitions, which `.luaurc` points at, so the generator type-checks
   in your editor. Enable luau-lsp's new solver (`luau-lsp.fflags.enableNewSolver`).

## The checks

CI runs all of these; run them before you push.

```bash
mise exec -- lune run scripts/generate -- --check     # generated files match upstream.toml
mise exec -- lune run scripts/test                    # samples: zero errors in tests/pass, exact errors in tests/fail
mise exec -- lune run scripts/snapshot                # converter snapshot cases
mise exec -- luau-lsp analyze --platform=standard --flag:LuauSolverV2=true --base-luaurc=.luaurc generator/ scripts/
mise exec -- stylua --check .
mise exec -- selene .
mise exec -- typos
mise exec -- actionlint
```

The `coverage` job also compares `definitions/coverage.json` with the base branch:

```bash
git show origin/main:definitions/coverage.json > base.json
mise exec -- lune run scripts/coverage-diff -- base.json
```

## Tests

- **`tests/pass/<addon>/`** is a sample addon. Every `.luau` file must type-check with zero diagnostics; a `.d.luau`
  there is loaded as that addon's own definitions (its SavedVariables).
- **`tests/fail/*.luau`** are negative fixtures. Each must produce exactly the diagnostics in its `.expected` file
  (line, column, full message), and every line marked `-- expect-error: <text>` must be among them. After an
  intended change, run `lune run scripts/test -- --update` and review the `.expected` diff.
- **`tests/snapshots/<case>/`** are converter cases: small inputs in upstream formats (`annotations/`, `docs/`,
  `client/`) and the expected `expected.d.luau` and `expected.coverage.json`. Each expected file must also load in
  luau-lsp. Refresh with `lune run scripts/snapshot -- --update`. Keep inputs byte-for-byte in upstream style (they
  are excluded from StyLua).

## Merge rules

`generator/build.luau` merges the sources; the rules are listed at `reconcile`. In short: the client decides what
exists; Blizzard's documentation gives types first; an argument is optional if either source says so; the
annotations' extra call shapes are kept; a documented result typed as a callback takes the annotation's type.
`generator/config.luau` holds the data-only rules (which documented script object describes which widget, basic
types, closed string unions, parameter overrides). Every rule needs a comment saying why, and a snapshot case.

## Bumping upstream

Renovate opens a pull request when any of the three upstream commits moves. The `fresh` job then fails until
someone regenerates:

```bash
mise exec -- lune run scripts/generate
mise exec -- lune run scripts/test -- --update   # only if diagnostics legitimately changed
```

Read the diffs of `definitions/COVERAGE.md` and `definitions/report.json` first. Commit everything together as
`feat(upstream): …`.

## Pull requests

- One concern per pull request.
- Title: `type(scope): summary`, checked by CI. Types: feat fix perf refactor test docs build ci chore style revert.
  Scopes: generator definitions upstream supplements tests ci docs deps repo.
- Note user-visible changes in `CHANGELOG.md` under "Unreleased".

## Releases

Maintainers move the "Unreleased" notes in `CHANGELOG.md` under a version heading, then tag `vX.Y.Z` on `main`. The
release workflow re-verifies the tagged commit from a cold start and publishes `wow-forever.d.luau`, `report.json`,
`coverage.json`, `COVERAGE.md` and `SHA256SUMS`. Versioning: a minor version for an upstream bump or any change that
can break existing code (types only get stricter or move), a patch for fixes that only remove false errors.

## Conduct

This project follows the [Code of Conduct](CODE_OF_CONDUCT.md).
