## What and why

<!-- One concern per pull request. Title: type(scope): summary. -->

## Checklist

- [ ] `mise exec -- moon run :check` passes locally
- [ ] Generated files were regenerated with `mise exec -- moon run generator:generate`, not edited by hand
- [ ] A new fixture, snapshot case or template change covers any behaviour change
- [ ] No API lost its types (`generator:coverage`), or the pull request explains why
- [ ] `CHANGELOG.md` has a line under "Unreleased" if users will notice the change
