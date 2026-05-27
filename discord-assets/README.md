# Discord Rich Presence Assets

`DiscordRPCService.buildActivity(...)` references these asset names in every
SET_ACTIVITY payload. The PNGs themselves are **not** bundled into the app
binary — they live on Discord's CDN once uploaded to the developer portal.

> **Fork maintainers:** If you run WolfWave with your own Discord application
> (different `DISCORD_CLIENT_ID` in `Config.xcconfig`), you **must** upload
> these assets to your portal yourself. Without them Rich Presence will fall
> back to broken/empty icons in the Discord client.

For product context, see the [root README](../README.md).

## How to upload

1. Go to <https://discord.com/developers/applications>
2. Select your WolfWave application
3. Click **Rich Presence** → **Art Assets**
4. Upload each file below with the exact asset name shown (lowercase, no
   extension on the portal side)
5. Wait ~10 minutes — Discord's asset CDN takes a few minutes to propagate

## Required assets

| File | Asset Name | Used when | Status |
|------|-----------|-----------|--------|
| `apple_music.png` | `apple_music` | Default `large_image` fallback when artwork URL is missing, and `small_image` "source" badge while playing | Required |
| `pause.png` | `pause` | `small_image` badge that replaces `apple_music` when the loaded track is paused (`small_text: "Paused"`, timestamps omitted) | Required |

Both files **must be** 512×512 PNG (square). Transparent or dark background
both work — the Discord client renders the asset on a dim chrome.

## Regenerating

Both shipped PNGs are rendered from inline SVG by [`generate.ts`](generate.ts):

```bash
bun run discord-assets/generate.ts
```

The script writes `pause.png` (final) and `apple_music_placeholder.png` (stand-in).
Replace `apple_music_placeholder.png` with the official Apple Music mark
(renamed to `apple_music.png`) before shipping a public build — see the next
section.

## Asset design notes

- **`apple_music`** — Apple Music logo (multi-color note on white/glass). Pull
  the official mark from the Apple Music Identity Guidelines. If you ship a
  fork that integrates with a different source, replace this asset and update
  the `"apple_music"` references in `DiscordRPCService.buildActivity`.
- **`pause`** — A white pause glyph (two vertical bars) centered on a solid
  dark-grey or transparent square. SF Symbol `pause.fill` exported at 512×512
  is the easiest source. Keep it high-contrast — the asset renders at ~16×16
  in the Discord client.

## Why both icons matter

Discord has no native paused-activity flag. We work around it by:

1. Omitting the `timestamps` block so the live ticker stops
2. Swapping `small_image` to `pause` so a visible glyph appears next to the
   album art

If either asset is missing from the portal, the small badge area falls back
to a broken icon — the rest of the presence (track text, large image) still
renders correctly, but the paused affordance is lost.
