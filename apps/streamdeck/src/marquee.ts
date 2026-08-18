/**
 * Scrolling text for a 72px key.
 *
 * The Elgato title layer cannot scroll — it draws one static string and clips
 * it to the key, which is why a 14-character track title shows up as its own
 * middle. So the text is drawn into the image instead and stepped along by a
 * timer.
 *
 * The stepping is deliberately coarse. This repaints a key over the plugin
 * socket, and a smooth 30fps marquee would mean 30 image pushes per second per
 * key for the whole time a track plays. `STEP_MS` and `STEP_PX` are the two
 * knobs; the defaults read as movement without being a video feed.
 */

/** How often the text advances. */
export const STEP_MS = 120;
/** How far it advances each step, in the 72-unit key space. */
export const STEP_PX = 2;
/** Blank space between the end of the text and its repeat. */
const GAP = 18;

/**
 * Average glyph advance as a fraction of font size, for the sans-serif stack
 * the key art uses.
 *
 * An estimate rather than a measurement because the plugin has no text metrics:
 * Stream Deck renders the SVG, not us. Slightly over-estimating is the safe
 * direction — it scrolls a little further than strictly needed, where
 * under-estimating would clip the last character.
 */
const ADVANCE = 0.58;

/** Width the string will occupy at `fontSize`, in key units. */
export function textWidth(text: string, fontSize: number): number {
  return text.length * fontSize * ADVANCE;
}

/**
 * Whether this string needs scrolling at all.
 *
 * Short titles must stay still. A marquee that jiggles "Home" back and forth is
 * worse than no marquee, and it would repaint forever for nothing.
 */
export function overflows(text: string, fontSize: number, width: number): boolean {
  return textWidth(text, fontSize) > width;
}

/**
 * The x offset for a given step, wrapping once the text plus its gap has fully
 * passed. Callers draw the string twice, `cycle` apart, so the tail is followed
 * straight by the head with no visible jump.
 */
export function offsetAt(step: number, text: string, fontSize: number): number {
  const cycle = textWidth(text, fontSize) + GAP;
  if (cycle <= 0) return 0;
  return (step * STEP_PX) % cycle;
}

/** The distance between the two copies of the string. */
export function cycleWidth(text: string, fontSize: number): number {
  return textWidth(text, fontSize) + GAP;
}
