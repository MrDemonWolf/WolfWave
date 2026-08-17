/**
 * Every pixel the plugin draws, in one place.
 *
 * Two consumers share these definitions so the art can never drift:
 * `scripts/generate-icons.ts` bakes the static manifest images at build time,
 * and the actions in `src/actions/` compose live art at runtime via
 * `KeyAction.setImage()`, which accepts a raw SVG string.
 *
 * Design rules, all of them about reading a 72x72 key from across a room:
 *
 * - **On is a tile, not a colored glyph.** A brand-filled key with the glyph
 *   knocked out in white reads at a glance; a blue glyph on a black key does not.
 * - **Color is the second channel.** Destructive keys are red, "needs you" is
 *   amber, live is brand blue, everything else is white on black.
 * - **Numbers are the hero on counting keys.** A queue depth rendered as a big
 *   numeral beats the same digit squeezed into the Elgato title strip.
 */

/** Key images are authored at 72x72; Stream Deck scales for @2x displays. */
export const KEY_SIZE = 72;
/** Elgato's required size for the action-list icon. */
export const ACTION_ICON_SIZE = 20;

export const Palette = {
  /**
   * Active tile. `color.brand.600`, not `500` — the default white Elgato title
   * clears 4.5:1 on 600 and does not on 500.
   */
  tile: "#0066CC",
  white: "#FFFFFF",
  /** Unavailable, not merely off. */
  dim: "#8E8E93",
  danger: "#FF453A",
  warning: "#FF9F0A",
} as const;

/**
 * Glyphs are authored on a 24x24 grid and stroked, so one definition serves the
 * 20px action icon and the 72px key without redrawing. `weight` scales stroke
 * widths: strokes tuned for a 20px icon read thin blown up to key size.
 */
export type Glyph = (color: string, weight?: number) => string;

const stroke = (d: string, color: string, width: number) =>
  `<path d="${d}" fill="none" stroke="${color}" stroke-width="${round(width)}" stroke-linecap="round" stroke-linejoin="round"/>`;
const solid = (d: string, color: string) => `<path d="${d}" fill="${color}"/>`;

export const play: Glyph = (c) => solid("M8.5 5.8 18.6 12 8.5 18.2Z", c);
export const pause: Glyph = (c) =>
  solid("M8 5.8h3v12.4H8Z", c) + solid("M13 5.8h3v12.4h-3Z", c);
export const skip: Glyph = (c, w = 1) =>
  solid("M5.8 5.8 14.4 12 5.8 18.2Z", c) + stroke("M17.4 5.8v12.4", c, 2.6 * w);
export const check: Glyph = (c, w = 1) =>
  stroke("M4.6 12.4 9.8 17.6 19.4 6.6", c, 2.6 * w);
export const trash: Glyph = (c, w = 1) =>
  stroke("M4 6.8h16", c, 2.1 * w) +
  stroke("M9.2 6.8V4.6h5.6v2.2", c, 2.1 * w) +
  stroke("M6.2 7.4 7.3 19.6h9.4l1.1-12.2", c, 2.1 * w) +
  stroke("M10.4 10.4v5.8M13.6 10.4v5.8", c, 1.7 * w);
export const ban: Glyph = (c, w = 1) =>
  `<circle cx="12" cy="12" r="8" fill="none" stroke="${c}" stroke-width="${round(2.2 * w)}"/>` +
  stroke("M6.3 6.3 17.7 17.7", c, 2.2 * w);
export const monitor: Glyph = (c, w = 1) =>
  `<rect x="2.8" y="4.4" width="18.4" height="12.8" rx="2.2" fill="none" stroke="${c}" stroke-width="${round(2.2 * w)}"/>` +
  stroke("M8.6 20.4h6.8", c, 2.2 * w);
/**
 * The queue keys draw a list, not bare transport bars. Hold used to reuse the
 * pause glyph, which put an identical pair of bars on two keys that do very
 * different things — one pauses Apple Music, the other stops the request queue.
 */
const queueLines = (c: string, w: number) =>
  stroke("M3 6.4h18", c, 2.2 * w) +
  stroke("M3 12h10.5", c, 2.2 * w) +
  stroke("M3 17.6h10.5", c, 2.2 * w);
export const hold: Glyph = (c, w = 1) =>
  queueLines(c, w) + solid("M16 10.6h2.1v10.4H16Z", c) + solid("M19.4 10.6h2.1v10.4h-2.1Z", c);
export const resume: Glyph = (c, w = 1) =>
  queueLines(c, w) + solid("M16 10.4 22.8 15.8 16 21.2Z", c);

// MARK: - Composers

export interface KeyArtOptions {
  glyph: Glyph;
  /**
   * Fills the whole key. The glyph is knocked out in white on top of it, which
   * is the "this is on / this is live" treatment.
   */
  tile?: string;
  /** Glyph color when there is no tile. Defaults to white. */
  tint?: string;
  /**
   * Set when the key carries an Elgato title. Lifts the glyph clear of the
   * bottom title strip instead of letting the two collide.
   */
  titled?: boolean;
}

/** A plain key: optional tile, one glyph. */
export function keyImage({ glyph, tile, tint, titled }: KeyArtOptions): string {
  const box = titled ? 46 : 54;
  const centerY = titled ? 30 : KEY_SIZE / 2;
  return svg(
    KEY_SIZE,
    (tile ? field(tile) : "") +
      place(glyph(tile ? Palette.white : (tint ?? Palette.white), 1.25), box, centerY),
  );
}

/**
 * A key whose whole point is a number: small glyph up top, the count rendered
 * large underneath. A count of zero degrades to the plain key rather than
 * shouting "0" at the streamer.
 */
export function countKeyImage(
  options: KeyArtOptions & { count: number },
): string {
  const { glyph, tile, tint, count } = options;
  if (count <= 0) return keyImage(options);

  const label = count > 99 ? "99+" : String(count);
  const ink = tile ? Palette.white : (tint ?? Palette.white);
  return svg(
    KEY_SIZE,
    (tile ? field(tile) : "") +
      place(glyph(ink, 1.1), 26, 19) +
      text(label, KEY_SIZE / 2, 61, label.length > 2 ? 26 : 34, ink),
  );
}

/** The action-list icon: monochrome white, no background, per Elgato's spec. */
export function actionIcon(glyph: Glyph): string {
  const scale = (ACTION_ICON_SIZE - 2) / 24;
  return svg(
    ACTION_ICON_SIZE,
    `<g transform="translate(1 1) scale(${round(scale, 4)})">${glyph(Palette.white, 1)}</g>`,
  );
}

// MARK: - Private helpers

function svg(size: number, body: string): string {
  return (
    `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 ${size} ${size}">` +
    body +
    `</svg>`
  );
}

/** A solid field over the entire key. The key's own corner rounding clips it. */
function field(color: string): string {
  return `<rect width="${KEY_SIZE}" height="${KEY_SIZE}" fill="${color}"/>`;
}

/** Places a 24-grid glyph in a `box`-wide square centred at (36, centerY). */
function place(body: string, box: number, centerY: number): string {
  const scale = box / 24;
  const x = (KEY_SIZE - box) / 2;
  const y = centerY - box / 2;
  return `<g transform="translate(${round(x)} ${round(y)}) scale(${round(scale, 4)})">${body}</g>`;
}

function text(
  value: string,
  x: number,
  baseline: number,
  size: number,
  color: string,
): string {
  return (
    `<text x="${round(x)}" y="${round(baseline)}" fill="${color}" font-family="Helvetica Neue, Helvetica, Arial, sans-serif"` +
    ` font-size="${round(size)}" font-weight="700" text-anchor="middle">${value}</text>`
  );
}

/** Keeps generated SVG byte-stable so the CI drift check stays meaningful. */
function round(value: number, places = 2): string {
  return String(Number(value.toFixed(places)));
}
