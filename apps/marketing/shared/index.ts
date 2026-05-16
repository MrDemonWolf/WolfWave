/**
 * WolfWave marketing brand kit.
 *
 * Re-exports generated design tokens plus high-level brand helpers for use
 * inside Remotion compositions. Edits to `tokens.generated.ts` are overwritten
 * by `bun run tokens` — change `design-system/tokens.json` upstream instead.
 */

export { tokens, type Tokens } from "./tokens.generated";
import { tokens } from "./tokens.generated";

/** Hex color shortcuts used by Remotion scenes. */
export const brand = {
  primary: tokens.color.brand[500],
  primaryDark: tokens.color.brandDark[600],
  surfaceLight: tokens.color.surface.light.base,
  surfaceDark: tokens.color.surface.dark.base,
  textLight: tokens.color.text.light.primary,
  textDark: tokens.color.text.dark.primary,
  partner: tokens.color.partner,
} as const;

/** Font families ready to drop into Remotion `style.fontFamily`. */
export const fonts = tokens.font.family;
