## What and why

<!-- One concern per pull request. Title: type(scope): summary. -->

## Checklist

- [ ] Generated files were regenerated with `mise exec -- lune run scripts/generate`, not edited by hand
- [ ] `lune run scripts/test` and `lune run scripts/snapshot` pass, with a new fixture or snapshot case if behaviour changed
- [ ] No API lost its types (`coverage` job), or the pull request explains why
- [ ] `CHANGELOG.md` has a line under "Unreleased" if users will notice the change
