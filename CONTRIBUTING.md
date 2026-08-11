# Contributing to WolfWave

Thanks for wanting to help. WolfWave is a native macOS menu bar app that bridges
Apple Music with Twitch, Discord, and OBS overlays, and it is free and open source
under GPL-3.0.

This file covers what you need to get building and what a reviewable PR looks like.
For the deeper architecture notes and house conventions, read
[`CLAUDE.md`](CLAUDE.md); it is the source of truth and this file does not duplicate it.

By participating you agree to the [Code of Conduct](CODE_OF_CONDUCT.md).

## Table of Contents

- [Before You Start](#before-you-start)
- [Getting Set Up](#getting-set-up)
- [Building and Testing](#building-and-testing)
- [Linting](#linting)
- [Code Conventions](#code-conventions)
- [Design System](#design-system)
- [Keeping Docs in Sync](#keeping-docs-in-sync)
- [Submitting a Pull Request](#submitting-a-pull-request)
- [Reporting Bugs](#reporting-bugs)
- [Security](#security)

## Before You Start

- **Bugs** go in [GitHub Issues](https://github.com/MrDemonWolf/WolfWave/issues) using the bug report template.
- **Feature ideas** go in [Discord](https://mrdwolf.net/discord), not Issues. They are triaged there.
- **Security vulnerabilities** never go in a public issue. See [Security](#security).

For anything larger than a bug fix, open an issue or say hello in Discord first.
It saves you building something that does not fit the roadmap.

## Getting Set Up

You need macOS 26.0+ (Tahoe) on Apple Silicon, Xcode 26+, and
[bun](https://bun.sh) if you are touching the docs site, the OBS widget, the
Stream Deck plugin, or design tokens. Contributors who only touch Swift do not
need bun.

```bash
git clone https://github.com/MrDemonWolf/WolfWave.git
cd WolfWave
cp apps/native/WolfWave/Config.xcconfig.example apps/native/WolfWave/Config.xcconfig
```

`Config.xcconfig` is gitignored. Fill in your own
[Twitch Client ID](https://dev.twitch.tv/console/apps) and
[Discord Application ID](https://discord.com/developers/applications). The values
expand into `Info.plist` at build time.

> URL values in that file must escape `//` with `$()`, for example
> `DOCS_URL = https:/$()/example.com`. xcconfig treats a bare `//` as a comment and
> will silently truncate the value.

Then:

```bash
make open-xcode
```

Build and run with `Cmd+R`. The Debug product is a separate app (**WolfWave Dev**,
bundle ID `com.mrdemonwolf.wolfwave.dev`) so it can coexist with a real install.
Do not collapse the Debug and Release identities.

For the monorepo workspaces:

```bash
bun install
```

## Building and Testing

Native app:

```bash
make build
make test
```

`make test` prints the current file and pass count. Run it before opening a PR.
All `make test*` targets use the gitignored `DerivedData/Tests` directory so the
unsigned test host never replaces your signed Debug app.

Tests must never touch your real Keychain. Test hosts default `KeychainService`
to process-local storage before any suite setup; do not swap that back to the
system backend.

New test files are auto-discovered. `apps/native/WolfWaveTests/` is a synchronized
Xcode group, so dropping in a `.swift` file is enough. No project edit needed.

Workspaces:

```bash
bun run --filter streamdeck test    # Stream Deck plugin
bun run build --filter docs         # Docs site
bun run --filter widget build       # OBS widget
```

## Linting

Four lint gates run in CI. Two are blocking. Run them locally first:

```bash
make lint                # SwiftLint against the tracked baseline
make lint-crash-safety   # Blocking. No new force unwrap, try!, or as!
make lint-headers        # Blocking. Swift file-header convention
bun run ds:lint          # Design-system lint (no literal spacing or font sizes)
bun run ds:schema        # Validate tokens.json against tokens.schema.json
```

`make lint-baseline` regenerates `swiftlint-baseline.json`. It is a ratchet: the
baseline may only shrink. Do not regenerate it to silence a new warning.

## Code Conventions

The full list is in [`CLAUDE.md`](CLAUDE.md). The ones that fail review most often:

- **No force unwrapping.** No `!`, no `try!`, no `as!`. Use optionals and `guard`.
  This is enforced by a blocking CI job, not just a preference.
- **Credentials go through `KeychainService`**, never `UserDefaults`.
- **Swift 6.0 with async/await.** No `DispatchQueue` for new async work.
- **`@Observable` view models**, not `ObservableObject`.
- **MARK sections** in every file, DocC-style `///` comments on public APIs.
- **File header** on every `.swift` file, matching the Xcode template. Line 3 is
  the project name (`WolfWave`), even in the test target. Dates are ISO
  `YYYY-MM-DD` and reflect the file's creation date. `make lint-headers` checks this.
- **User-facing copy is short, punchy, and jargon-free.**

## Design System

[`design-system/tokens.json`](design-system/tokens.json) is the single source of
truth. The generator emits five platform outputs. **Never hand-edit a
`*.generated.*` file.**

```bash
bun run tokens
```

Never use literal numbers for font sizes, spacing, or padding. Use `DSFont.Size.*`,
`DSSpace.*`, `DSRadius.*`, `DSDimension.*`. Legacy literals are tracked in
`design-system/lint-allowlist.txt`; migrate them, do not add to them.

When you touch a component under `Views/Shared/`, `Views/Onboarding/Components/`,
or `Views/HistoryStats/`, update its entry in
[`design-system/components/`](design-system/components/) in the same change.
[`status-chip.md`](design-system/components/status-chip.md) is the quality bar.

## Keeping Docs in Sync

Documentation drift is treated as a bug. Match the change to what it touches:

| You changed | Also update |
|---|---|
| A feature or a bot command | `README.md`, the affected docs pages (`features.mdx`, `settings.mdx`, `bot-commands.mdx`), `CHANGELOG.md`, and `changelog.mdx` |
| A service, file name, or directory | `architecture.mdx` and the source-layout list in `CLAUDE.md` |
| A number (ports, sizes, theme counts, minimum macOS) | Every copy of it. Grep for the old value. |

Never hardcode a value that drifts. Read it from its source instead: test count
from `ls apps/native/WolfWaveTests/*.swift | wc -l`, app version from
`MARKETING_VERSION` in `project.pbxproj`, widget dimensions and themes from
`design-system/tokens.json`.

Two coupled pairs to watch:

- **OBS widget.** Source is `apps/widget/`; the shipped
  `apps/native/WolfWave/Resources/widget.html` is a generated artifact that **is**
  committed. Edit the source, run `make widget`, commit both. CI fails the PR on drift.
- **Stream Deck plugin.** `apps/streamdeck/src/wolfwave/` is the TypeScript mirror
  of `Services/WebSocket/StreamDeckCommand.swift`. Change one side, change the other,
  and bump `PROTOCOL_VERSION` on any breaking envelope change. CI fails the PR on drift.

## Submitting a Pull Request

1. Branch off `main`.
2. Keep the change focused. One concern per PR.
3. Run `make test` and the lint targets above.
4. Fill in the [PR template](.github/PULL_REQUEST_TEMPLATE.md) checklists honestly.
   They exist because these are the things that actually get missed.
5. Add a `CHANGELOG.md` entry under the top unreleased `## [x.y.z]` heading, and the
   matching block in `apps/docs/content/docs/changelog.mdx`. Contributor-only notes go
   under `### Developer`, which is stripped from the in-app release notes and is
   deliberately absent from the docs site.
6. Attach a screenshot or recording for any UI change.

Do not bump `CURRENT_PROJECT_VERSION`. It is a dev placeholder that CI overrides
from `scripts/version.sh`. The reasoning is in
[`docs/build-versioning-standard.md`](docs/build-versioning-standard.md).

## Reporting Bugs

Use the in-app flow when you can: **Settings > Advanced > Report a Bug** exports
your logs and opens a pre-filled GitHub issue with your build info already in it.
That is faster than filling in the template by hand and gives a far more useful report.

Include your macOS version, your WolfWave version, and whether you installed via
DMG or Homebrew.

## Security

Do not open a public issue for a vulnerability. Report it privately per
[`.github/SECURITY.md`](.github/SECURITY.md) or email security@mrdemonwolf.com.

---

Made with love by [MrDemonWolf, Inc.](https://www.mrdemonwolf.com)
