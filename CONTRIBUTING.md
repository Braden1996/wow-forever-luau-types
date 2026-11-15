# Contributing

Thanks for helping. Issues and pull requests are welcome, from one-line fixes to new converter features.

## Where does the fix belong?

| Problem                                                    | Where to fix it                                                                                 |
| ---------------------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| A wrong or missing parameter, return or field type         | Upstream annotations: [Ketho/vscode-wow-api](https://github.com/Ketho/vscode-wow-api)            |
| An API Forever has but the definitions lack (or vice versa) | Client dump: [Ketho/BlizzardInterfaceResources](https://github.com/Ketho/BlizzardInterfaceResources) (`forever` branch) |
| A LuaCATS construct converted wrongly, or invalid Luau     | Here: `generator/`                                                                               |
| A FrameXML table or frame global with no upstream entry     | Here: `supplements/framexml.d.luau`                                                             |
| A false error or a missed error in real addon code          | Here: add a sample under `tests/`, then fix whichever of the above causes it                    |

Never edit `definitions/` by hand: it is generated, and CI fails if it differs from a fresh generation.

## Setup

1. Install [mise](https://mise.jdx.dev).
2. `mise install` installs the pinned tools: Lune, luau-lsp, StyLua, selene, typos and actionlint (versions in
   `mise.toml`, checksums in `mise.lock`).
3. `mise exec -- lune setup` writes Lune's type definitions, which `.luaurc` points at, so the generator type-checks
   in your editor.

## The checks

CI runs these; run them before you push.

```bash
mise exec -- lune run scripts/generate -- --check   # definitions/ matches upstream.toml
mise exec -- lune run scripts/test                  # samples: zero errors in tests/pass, expected errors in tests/fail
mise exec -- luau-lsp analyze --platform=standard --base-luaurc=.luaurc generator/ scripts/   # generator is --!strict clean
mise exec -- stylua --check .
mise exec -- selene .
mise exec -- typos
mise exec -- actionlint
```

## Changing the converter

1. Edit `generator/` (all of it is `--!strict` Luau).
2. Run `mise exec -- lune run scripts/generate` and review the diff of `definitions/`. Every changed line should be a
   change you meant.
3. Add or extend a sample: a passing case under `tests/pass/` or an `-- expect-error: <text>` line under
   `tests/fail/`.
4. Commit the generator change and the regenerated `definitions/` together.

## Bumping upstream

Renovate opens a pull request when either upstream commit moves. The `fresh` job then fails until someone
regenerates:

```bash
mise exec -- lune run scripts/generate
git add definitions && git commit -m "feat(upstream): regenerate for <repository>@<sha>"
```

Read the diff of `definitions/report.json` first: it shows which APIs appeared, disappeared or became untyped.

## Pull requests

- One concern per pull request.
- Use a conventional title, for example `fix(generator): keep varargs last in return lists`.
- Note the release-relevant change in `CHANGELOG.md` under "Unreleased".

## Releases

Maintainers move the "Unreleased" notes in `CHANGELOG.md` under a version heading, then tag `vX.Y.Z` on `main`. The
release workflow re-verifies the tagged commit and publishes `wow-forever.d.luau`, `report.json` and `SHA256SUMS`.
Versioning: a minor version for any upstream bump or type change that can break existing code (types only get
stricter or move), a patch for fixes that only remove false errors.

## Conduct

This project follows the [Code of Conduct](CODE_OF_CONDUCT.md).
