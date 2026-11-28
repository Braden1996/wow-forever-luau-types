# Contributing

Follow the [Sergeant playbook](https://github.com/Braden1996/sergeant#readme) for tool setup and the `sgt install`,
`sgt doctor`, `sgt check`, `sgt test`, and `sgt build` workflow. Run `lune setup` to install the editor typedefs.
The Bun workspace expects the three Sergeant v0.15.0 preset tarballs in `../sergeant/dist/npm/`.

- Fix documented C APIs in [the generator rules](packages/libraries/luau/pure/generator/src/rules). Report
  undocumented global, FrameXML mixin, and Lua extension types to [Ketho/vscode-wow-api](https://github.com/Ketho/vscode-wow-api).
  Report discrepancies with the live client's list of APIs to [Ketho/BlizzardInterfaceResources](https://github.com/Ketho/BlizzardInterfaceResources).
- Reproduce conversion errors in `tests/snapshots/` and addon type errors in `tests/pass/` or `tests/fail/`.
  After an expected change, run `lune run packages/runtimes/cli/src/snapshot.effect.luau -- --update` or
  `lune run packages/runtimes/cli/src/test.effect.luau -- --update` and review the diff.
- After changing generator inputs, run `sgt run generate` and `sgt run editor-settings-write`. Review
  `definitions/COVERAGE.md` and `definitions/report.json`. CI compares coverage with the base branch.
- Edit guides in `packages/runtimes/docs/src/content/docs/` and run `sgt dev docs` to preview the site.
- Use `type(scope): summary` for pull request titles and record user-visible changes in `CHANGELOG.md`.

See [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) and [SECURITY.md](SECURITY.md).
