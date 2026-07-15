# WolfWave: Native macOS App

This directory holds the native Swift / SwiftUI source for the WolfWave
menu bar app. It is not the project root. See the
[root README](../../../README.md) for product overview, install
instructions, and contribution guidelines.

## Quick links

- [Root README](../../../README.md): product overview, install, tech stack.
- [Documentation site](https://mrdemonwolf.github.io/wolfwave): usage, bot commands, architecture, security.
- [CLAUDE.md](../../../CLAUDE.md): internal architecture notes for contributors and Claude Code.
- [SECURITY.md](SECURITY.md): disclosure policy for security issues.

## Layout

```text
apps/native/
├── WolfWave/             # App source (Swift, SwiftUI, AppKit)
├── WolfWaveTests/        # Unit tests (run make test for the current pass count)
└── WolfWave.xcodeproj    # Xcode project
```

Open in Xcode with `make open-xcode` from the repo root, or run the test
suite with `make test`.
