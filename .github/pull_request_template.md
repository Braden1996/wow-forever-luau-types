## What and why

<!-- One concern per pull request. Title: type(scope): summary. -->

## Checklist

- [ ] `mise exec -- sgt check` passes locally
- [ ] Generated files were regenerated with `mise exec -- sgt run generate`, not edited by hand
- [ ] A new fixture, snapshot case or template change covers any behaviour change
- [ ] The `coverage-diff` check passes, or the pull request explains the proposed exception
- [ ] `CHANGELOG.md` has a line under "Unreleased" if users will notice the change
