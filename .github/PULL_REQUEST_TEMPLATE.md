## Type of change

- [ ] Bug fix
- [ ] New feature
- [ ] Code quality / refactor
- [ ] Documentation
- [ ] Chore / dependency update

## Description

<!-- What changed and why. Link the related issue if one exists. -->

Closes #

## Testing

<!-- How did you verify this works? List manual steps and confirm CI. -->

- [ ] `make test` passes locally
- [ ] Tested manually on macOS 26+

**Steps to test:**

1.
2.

## Checklist

### All PRs

- [ ] No force unwraps introduced
- [ ] New credentials use `KeychainService`, not `UserDefaults`
- [ ] User-facing copy is short, punchy, and jargon-free

### Feature / Bug fix PRs

- [ ] `CHANGELOG.md` updated under the top unreleased `## [x.y.z]` heading
- [ ] `apps/docs/content/docs/changelog.mdx` updated under the top `## vX.Y.Z` block
- [ ] README + docs (`features` / `usage` / `bot-commands`) updated if behavior or structure changed
- [ ] `CLAUDE.md` updated if architecture, services, or counts changed

### Release PRs

- [ ] `MARKETING_VERSION` bumped in `project.pbxproj` (4 occurrences)
- [ ] `CURRENT_PROJECT_VERSION` bumped in `project.pbxproj` (4 occurrences)

### UI changes

- [ ] Screenshots or recording attached below
