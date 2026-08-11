# wolfwave-announcement

Remotion-based video project for the WolfWave **v1.0** launch announcement (shipped
2026-03-30).

> Scope note: this project is pinned to the v1.0 launch. The app has shipped 2.0 and 2.1
> since, and nothing here has been re-cut for them. Treat it as an archived render, not as
> current marketing. A new release video should be a new project under `apps/marketing/`
> rather than an edit of this one, so the v1.0 render stays reproducible.

## Stack

- **Remotion** 4.x (React-based programmatic video)
- **React** 19, **TypeScript** 5.9
- **Google Fonts** via `@remotion/google-fonts`

## Commands

```bash
bun install          # Install dependencies
bun run studio       # Open Remotion Studio (visual editor)
bun run render       # Render final MP4 → out/wolfwave-v1-announcement.mp4
bun run preview      # Preview composition
```

## Structure

- `src/index.ts`: Remotion entry point, registers compositions
- `src/Root.tsx`: Root component wrapping all compositions
- `src/MainVideo.tsx`: Primary video composition
- `src/brand.ts`: Brand colors, fonts, and constants
- `src/scenes/`: Individual scene components for each video segment
- `public/`: Static assets (logos, images used in video)

## Output

Renders to `out/wolfwave-v1-announcement.mp4` (h264, jpeg quality 90).
The `out/` directory is gitignored.
