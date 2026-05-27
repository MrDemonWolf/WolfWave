# `apps/widget` — OBS Overlay Source

The OBS Browser Source widget that renders the now-playing card. Source of
truth for `apps/native/WolfWave/Resources/widget.html` — the file the native
app bundles and `WidgetHTTPService` serves.

## Architecture

```
            ┌──────────────────────────┐
            │ design-system/tokens.json│
            └────────────┬─────────────┘
                         │ bun run tokens
                         ▼
       apps/native/WolfWave/Resources/widget-tokens.generated.js
                         │
        ┌────────────────┼─────────────────┐
        │                │                 │
        ▼                ▼                 ▼
 src/widget.html  src/widget.css   (read at build)
        │                │
        │      tailwindcss CLI
        │                │
        │                ▼
        │         dist/widget.css ──┐
        │                           │
 src/widget.ts                      │
        │                           │
   Bun.build (IIFE)                 │
        │                           │
        ▼                           │
   dist/widget.js ──────────────────┤
                                    │
                          build.ts inlines all 3
                                    │
                                    ▼
       apps/native/WolfWave/Resources/widget.html (committed)
```

## Message contract

Frozen by the Swift tests `WebSocketServerServiceTests` /
`WidgetHTTPServiceTests` — adding fields server-side is safe; renaming
existing fields requires a coordinated change.

| Type | Payload | Cadence |
|------|---------|---------|
| `welcome` | `{}` | Once on connect |
| `now_playing` | `{ track, artist, album, duration, elapsed, isPlaying, artworkURL }` | Track change |
| `progress` | `{ elapsed, duration, isPlaying }` | ~1 Hz |
| `playback_state` | `{ isPlaying, track?, artist?, album? }` | State change |
| `widget_config` | `{ theme, layout, textColor, backgroundColor, fontFamily }` | Settings change |

## Themes + layouts

Both live in `design-system/tokens.json` under `widget.themes` and
`widget.layouts`. Edit there, then `bun run tokens` to regenerate the JS
bundle, then `bun run --filter widget build` to roll a new widget.html.

Runtime switching: themes are NOT compiled into utility variants. The OBS
user can change theme via `?theme=Glass` URL param without rebuilding.

## Dev loop

```bash
# regenerate tokens (only when tokens.json changes)
bun run tokens

# rebuild widget (from the repo root)
make widget
# …or equivalently:
bun run --filter widget build
```

The generated `apps/native/WolfWave/Resources/widget.html` is committed to the
repo and shipped by the native app as-is — Xcode no longer rebuilds it. Commit
the regenerated `widget.html` alongside any change under `apps/widget/`; CI
runs the build and fails the PR on drift.

Then open the generated HTML directly to spot-check:

```bash
open apps/native/WolfWave/Resources/widget.html
```

…or open `http://localhost:<port>/?theme=Glass&layout=Vertical` with the
native app running for a live WebSocket feed.

## Transitions

The container moves between four states (full machine documented in
`src/widget.ts → TRANSITIONS`):

| Trigger | From → To | Timing |
|---------|-----------|--------|
| play | hidden → entering → visible | 600ms, bouncy cubic-bezier |
| stop | visible → exiting → hidden | 500ms, calm cubic-bezier |
| skip (same playing state) | inner crossfade only | 280ms total |
| stop | progress bar drains to 0% | 400ms ease-out |

The container animation does **not** re-trigger on track skip — that's
deliberate, otherwise rapid skips strobe the stream.

## Code map

| File | Purpose |
|------|---------|
| `src/widget.html` | HTML shell with `%%TAILWIND_CSS%%` / `%%TOKENS_JS%%` / `%%WIDGET_JS%%` placeholders |
| `src/widget.css` | Tailwind directives + custom state classes (transitions, progress, decorative layers) |
| `src/widget.ts` | All runtime — state, transitions, WS, message dispatch, render |
| `tailwind.config.ts` | Token-driven theme extension; preflight + container disabled |
| `build.ts` | Bundles JS, runs Tailwind, inlines into the template, writes the output file |
