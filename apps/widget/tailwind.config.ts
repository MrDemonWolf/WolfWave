/**
 * Tailwind config for the OBS overlay widget.
 *
 * Why a workspace, not a one-off CSS file:
 *   The widget is a single .html file served by `WidgetHTTPService` (Swift) and
 *   also droppable directly into OBS as a Browser Source. We want utility-class
 *   styling without shipping the full Tailwind dev runtime — so we run the
 *   Tailwind CLI at build time over `src/widget.html` + `src/widget.ts`, then
 *   inline the minified CSS into the final output HTML (see `build.ts`).
 *
 * Themes are NOT compiled into utility variants — they stay as runtime CSS
 * custom properties (`--ww-*`) so the OBS user can flip themes via URL
 * params without rebuilding the bundle. Tailwind utilities resolve to those
 * CSS variables via `theme.extend` below.
 */
import type { Config } from "tailwindcss";

export default {
  content: ["./src/widget.html", "./src/widget.ts"],
  // We hand-pick CSS variable names that mirror the WW_TOKENS.themes payload
  // emitted from design-system/scripts/generate.ts. When applyTheme() sets
  // these on the root, every utility re-resolves automatically.
  theme: {
    extend: {
      colors: {
        "ww-primary": "var(--ww-text-primary)",
        "ww-secondary": "var(--ww-text-secondary)",
        "ww-muted": "var(--ww-text-muted)",
        "ww-track": "var(--ww-progress-track)",
        "ww-fill": "var(--ww-progress-fill)",
        "ww-overlay": "var(--ww-overlay-bg)",
      },
      fontSize: {
        "ww-xs": "10px",
        "ww-sm": "11px",
        "ww-body": "13px",
        "ww-md": "14px",
        "ww-lg": "18px",
      },
      borderRadius: {
        "ww-container": "var(--ww-radius-container)",
      },
      transitionTimingFunction: {
        "ww-enter": "cubic-bezier(0.34, 1.56, 0.64, 1)",
        "ww-exit": "cubic-bezier(0.4, 0, 0.2, 1)",
      },
      transitionDuration: {
        "ww-enter": "600ms",
        "ww-exit": "500ms",
        "ww-swap": "280ms",
        "ww-drain": "400ms",
      },
    },
  },
  corePlugins: {
    // Cuts ~50% of the unused CSS. Re-enable if a future view needs them.
    container: false,
    preflight: false,
  },
  plugins: [],
} satisfies Config;
