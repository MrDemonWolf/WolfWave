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
/** A pair of beamed notes. The fallback when album art can't be fetched. */
export const note: Glyph = (c, w = 1) =>
  stroke("M10 16.8V5.2l8.4-1.6v11.2", c, 2.2 * w) +
  `<ellipse cx="7.4" cy="17" rx="2.8" ry="2.4" fill="${c}"/>` +
  `<ellipse cx="15.8" cy="14.8" rx="2.8" ry="2.4" fill="${c}"/>`;

/** Speech bubble with a note in it: say what's playing. */
export const announce: Glyph = (c, w = 1) =>
  `<path d="M3.2 6.6A2.6 2.6 0 0 1 5.8 4h12.4A2.6 2.6 0 0 1 20.8 6.6v7.2a2.6 2.6 0 0 1-2.6 2.6H10l-4.8 3.6v-3.6A2.6 2.6 0 0 1 3.2 13.8Z" fill="none" stroke="${c}" stroke-width="${round(2.2 * w)}" stroke-linejoin="round"/>` +
  stroke("M11.4 13V7.4l4.4-.9v5", c, 1.9 * w) +
  `<ellipse cx="9.7" cy="13.1" rx="1.8" ry="1.5" fill="${c}"/>` +
  `<ellipse cx="14.1" cy="12.2" rx="1.8" ry="1.5" fill="${c}"/>`;

/**
 * A person struck through: block the requester, not the song.
 *
 * The slash crosses the whole figure rather than tucking into a corner. A short
 * stroke beside the shoulder reads as part of the body, not as a negation.
 */
export const personBlock: Glyph = (c, w = 1) =>
  `<circle cx="11" cy="7.4" r="3.5" fill="none" stroke="${c}" stroke-width="${round(2.1 * w)}"/>` +
  stroke("M4.6 20c0-3.6 2.9-6.2 6.4-6.2s6.4 2.6 6.4 6.2", c, 2.1 * w) +
  stroke("M3.4 21 20.6 3.8", c, 2.5 * w);

/** A person with a chevron: who is allowed to request, cycling tighter. */
export const audienceGate: Glyph = (c, w = 1) =>
  `<circle cx="9.4" cy="7.4" r="3.4" fill="none" stroke="${c}" stroke-width="${round(2.1 * w)}"/>` +
  stroke("M3 19.8c0-3.7 2.9-6.1 6.4-6.1 1.3 0 2.5.3 3.5.9", c, 2.1 * w) +
  stroke("M16 10.6 20.4 15 16 19.4", c, 2.2 * w);

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
/**
 * Queue list with an X: this request goes, the queue carries on.
 *
 * Its list is shorter than `queueLines` on purpose — the X needs its own column,
 * and a full-width top line runs straight into it.
 */
export const rejectRequest: Glyph = (c, w = 1) =>
  stroke("M3 6.4h11", c, 2.2 * w) +
  stroke("M3 12h11", c, 2.2 * w) +
  stroke("M3 17.6h7", c, 2.2 * w) +
  stroke("M14.8 13.4 21.4 20M21.4 13.4l-6.6 6.6", c, 2.4 * w);

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
  const { count } = options;
  if (count <= 0) return keyImage(options);
  return labelKeyImage({ ...options, label: count > 99 ? "99+" : String(count) });
}

/**
 * Glyph on top, short word underneath, both baked into the image.
 *
 * The word goes in the art rather than the Elgato title for the same reason the
 * counts do: the title strip is the streamer's to label the key with, and it
 * renders in whatever font and size they picked.
 */
export function labelKeyImage(
  options: KeyArtOptions & { label: string },
): string {
  const { glyph, tile, tint, label } = options;
  const ink = tile ? Palette.white : (tint ?? Palette.white);
  return svg(
    KEY_SIZE,
    (tile ? field(tile) : "") +
      place(glyph(ink, 1.1), 26, 19) +
      // Three characters is the widest that stays legible at this size, so the
      // type shrinks past two rather than overrunning the key.
      text(label, KEY_SIZE / 2, 61, label.length > 2 ? 26 : 34, ink),
  );
}

/**
 * A key showing album art with the track scrolling across the bottom.
 *
 * The art is an `<image>` carrying its own data URI, because `setImage` takes
 * one image and this key needs art *and* text. The text band is a solid strip
 * rather than a gradient: it has to stay readable over whatever the cover art
 * happens to be, including a white one.
 *
 * `offset` and `cycle` come from `marquee.ts`; the string is drawn twice, one
 * cycle apart, so the tail is followed straight by the head.
 */
export function nowPlayingImage(options: {
  art?: string;
  label: string;
  offset?: number;
  cycle?: number;
}): string {
  const { art, label, offset = 0, cycle = 0 } = options;
  const size = KEY_SIZE;
  const bandHeight = 22;
  const bandY = size - bandHeight;
  const fontSize = 14;
  const baseline = size - 6;

  const background = art
    ? `<image href="${art}" x="0" y="0" width="${size}" height="${size}" preserveAspectRatio="xMidYMid slice"/>`
    : field("#000000") + place(note(Palette.white, 1.1), 34, 24);

  const copies = cycle > 0
    ? scrollingText(label, -offset, baseline, fontSize) +
      scrollingText(label, -offset + cycle, baseline, fontSize)
    : `<text x="${size / 2}" y="${round(baseline)}" fill="${Palette.white}" font-family="Helvetica Neue, Helvetica, Arial, sans-serif" font-size="${fontSize}" font-weight="700" text-anchor="middle">${escapeText(label)}</text>`;

  return svg(
    size,
    background +
      `<rect x="0" y="${round(bandY)}" width="${size}" height="${bandHeight}" fill="#000000" fill-opacity="0.72"/>` +
      `<svg x="0" y="${round(bandY)}" width="${size}" height="${bandHeight}" viewBox="0 0 ${size} ${bandHeight}">${copies}</svg>`,
  );
}

/** One copy of the marquee string, positioned within the band's own viewport. */
function scrollingText(
  label: string,
  x: number,
  _baseline: number,
  fontSize: number,
): string {
  return (
    `<text x="${round(x)}" y="16" fill="${Palette.white}" font-family="Helvetica Neue, Helvetica, Arial, sans-serif"` +
    ` font-size="${fontSize}" font-weight="700">${escapeText(label)}</text>`
  );
}

/**
 * Track titles are arbitrary text off the internet and land inside an SVG
 * document, so the five XML metacharacters have to go. An unescaped `&` alone
 * makes the whole image unparseable and the key renders blank.
 */
export function escapeText(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;");
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
