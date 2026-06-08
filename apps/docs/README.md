# WolfWave Docs Site

The public documentation site for WolfWave at
[mrdemonwolf.github.io/wolfwave](https://mrdemonwolf.github.io/wolfwave).
This is a Next.js app powered by [Fumadocs](https://fumadocs.dev) with
static export, deployed to GitHub Pages by `.github/workflows/docs.yml`.

For the product itself, see the [root README](../../README.md).

## Run locally

From the repo root:

```bash
bun install
bun run dev --filter docs
```

Open <http://localhost:3000>.

## Layout

| Path | What it is |
| --- | --- |
| `app/(home)` | Landing page and download page. |
| `app/docs` | Documentation layout. Fumadocs renders the MDX from `content/docs/`. |
| `app/api/search/route.ts` | Static search index. |
| `content/docs/` | All MDX content. Sidebar order is in `content/docs/meta.json`. |
| `app/global.css` + `app/tokens.generated.css` | Token-driven styling. Generated CSS comes from `design-system/tokens.json`; do not edit by hand. |

## Build

```bash
bun run build --filter docs
```

Outputs a static export to `apps/docs/out/`.
