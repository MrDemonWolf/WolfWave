# wolfwave-announcement

Remotion-based video project for the WolfWave v1.0 launch announcement.

## Stack

- **Remotion** 4.x (React-based programmatic video)
- **React** 19, **TypeScript** 5.9
- **Google Fonts** via `@remotion/google-fonts`

## Commands

```bash
npm install          # Install dependencies
npm run studio       # Open Remotion Studio (visual editor)
npm run render       # Render final MP4 → out/wolfwave-v1-announcement.mp4
npm run preview      # Preview composition
```

## Structure

- `src/index.ts` — Remotion entry point, registers compositions
- `src/Root.tsx` — Root component wrapping all compositions
- `src/MainVideo.tsx` — Primary video composition
- `src/brand.ts` — Brand colors, fonts, and constants
- `src/scenes/` — Individual scene components for each video segment
- `public/` — Static assets (logos, images used in video)

## Output

Renders to `out/wolfwave-v1-announcement.mp4` (h264, jpeg quality 90).
The `out/` directory is gitignored.
