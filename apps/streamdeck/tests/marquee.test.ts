/**
 * The marquee is arithmetic, so it is testable without a device. What matters:
 * short text never scrolls, long text wraps seamlessly, and a track title full
 * of XML metacharacters cannot break the SVG it lands in.
 */

import { describe, expect, test } from "bun:test";
import {
  REPEAT_SEPARATOR,
  STEP_PX,
  cycleWidth,
  offsetAt,
  overflows,
  textWidth,
} from "../src/marquee.js";
import { escapeText, nowPlayingImage } from "../src/keyart.js";

const FONT = 14;
const KEY = 72;

describe("overflows", () => {
  test("a short title stays still", () => {
    // Scrolling "Home" back and forth forever is worse than not scrolling.
    expect(overflows("Home", FONT, KEY)).toBe(false);
  });

  test("a title wider than the key scrolls", () => {
    expect(overflows("Trapped at Midnight — Grey Wolf", FONT, KEY)).toBe(true);
  });

  test("an empty label never scrolls", () => {
    expect(overflows("", FONT, KEY)).toBe(false);
  });
});

describe("offsetAt", () => {
  const label = "Trapped at Midnight";

  test("starts at zero", () => {
    expect(offsetAt(0, label, FONT)).toBe(0);
  });

  test("advances by one step each tick", () => {
    expect(offsetAt(1, label, FONT)).toBe(STEP_PX);
    expect(offsetAt(2, label, FONT)).toBe(STEP_PX * 2);
  });

  test("wraps once a full cycle has passed, never running away", () => {
    const cycle = cycleWidth(label, FONT);
    for (const step of [50, 500, 5_000, 100_000]) {
      const offset = offsetAt(step, label, FONT);
      expect(offset).toBeGreaterThanOrEqual(0);
      expect(offset).toBeLessThan(cycle);
    }
  });

  test("the cycle leaves a gap, so the tail is not flush against the head", () => {
    expect(cycleWidth(label, FONT)).toBeGreaterThan(textWidth(label, FONT));
  });

  test("the wrap matches the separator the caller actually joins with", () => {
    // Two notions of the gap drift apart and the wrap visibly jumps: the offset
    // rolls over before the second copy has reached the left edge.
    expect(cycleWidth(label, FONT)).toBe(
      textWidth(label + REPEAT_SEPARATOR, FONT),
    );
  });
});

describe("escapeText", () => {
  test("escapes every XML metacharacter", () => {
    // One raw & makes the whole SVG unparseable and the key renders blank.
    expect(escapeText(`Rock & Roll <b> "x" 'y'`)).toBe(
      "Rock &amp; Roll &lt;b&gt; &quot;x&quot; &apos;y&apos;",
    );
  });

  test("leaves ordinary text alone", () => {
    expect(escapeText("Trapped at Midnight")).toBe("Trapped at Midnight");
  });
});

describe("nowPlayingImage", () => {
  test("embeds the album art when there is some", () => {
    const svg = nowPlayingImage({ art: "data:image/jpeg;base64,AAA", label: "x" });
    // xlink:href, not href: SVG 1.2 Tiny predates the plain-href shorthand.
    expect(svg).toContain('<image xlink:href="data:image/jpeg;base64,AAA"');
  });

  test("falls back to the note glyph with no art", () => {
    const svg = nowPlayingImage({ label: "x" });
    expect(svg).not.toContain("<image");
    expect(svg).toContain("<path");
  });

  test("draws one text run, positioned by the caller's offset", () => {
    // Clipping and wrap-around are JS-side (`visibleSlice`); the renderer only
    // ever sees one plain <text>, because QtSvg has no clipPath.
    const svg = nowPlayingImage({ label: "Long title here", offset: -10 });
    expect(svg.match(/<text/g)).toHaveLength(1);
    expect(svg).toContain('x="-10"');
  });

  test("stays within SVG 1.2 Tiny", () => {
    const svg = nowPlayingImage({ art: "data:image/jpeg;base64,AAA", label: "x" });
    expect(svg).not.toContain("<clipPath");
    expect(svg).not.toContain("clip-path");
    expect(svg.match(/<svg/g)).toHaveLength(1);
    expect(svg).toContain("xlink:href");
  });

  test("a hostile track title cannot break out of the SVG", () => {
    const svg = nowPlayingImage({ label: `</text><script>x</script>` });
    expect(svg).not.toContain("<script>");
    expect(svg).toContain("&lt;script&gt;");
  });
});
