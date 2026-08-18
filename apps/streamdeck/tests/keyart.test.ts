/**
 * Key art is pure string building, so it is testable without a device. What
 * matters here is what a streamer can actually see: the count, which dots are
 * lit, and whether the "on" treatment is the tile rather than a tinted glyph.
 */

import { describe, expect, test } from "bun:test";
import {
  KEY_SIZE,
  Palette,
  actionIcon,
  check,
  countKeyImage,
  hold,
  keyImage,
  play,
  statusImage,
  trash,
} from "../src/keyart.js";

/** The count is rendered as text; everything else in the key is paths/circles. */
function textNodes(svg: string): string[] {
  return [...svg.matchAll(/<text[^>]*>([^<]*)<\/text>/g)].map((m) => m[1] ?? "");
}

function isSingleRootSvg(svg: string): boolean {
  return (
    svg.startsWith("<svg ") &&
    svg.endsWith("</svg>") &&
    svg.indexOf("<svg", 1) === -1
  );
}

describe("keyImage", () => {
  test("is a single-root SVG at key size", () => {
    const svg = keyImage({ glyph: play });
    expect(isSingleRootSvg(svg)).toBe(true);
    expect(svg).toContain(`width="${KEY_SIZE}" height="${KEY_SIZE}"`);
  });

  test("an on state fills the whole key and knocks the glyph out white", () => {
    const svg = keyImage({ glyph: hold, tile: Palette.tile });
    expect(svg).toContain(
      `<rect width="${KEY_SIZE}" height="${KEY_SIZE}" fill="${Palette.tile}"`,
    );
    expect(svg).toContain(Palette.white);
  });

  test("an off state paints no field", () => {
    expect(keyImage({ glyph: hold })).not.toContain("<rect");
  });

  test("tint colours the glyph when there is no tile", () => {
    expect(keyImage({ glyph: trash, tint: Palette.danger })).toContain(
      Palette.danger,
    );
  });

  test("a titled key lifts the glyph clear of the title strip", () => {
    const titled = keyImage({ glyph: play, titled: true });
    const plain = keyImage({ glyph: play });
    expect(titled).not.toBe(plain);
    // Same glyph, smaller box placed higher up.
    expect(offsetY(titled)).toBeLessThan(offsetY(plain));
  });
});

describe("countKeyImage", () => {
  test("renders the count", () => {
    expect(textNodes(countKeyImage({ glyph: hold, count: 7 }))).toEqual(["7"]);
  });

  test("caps at 99+ so the numeral never overruns the key", () => {
    expect(textNodes(countKeyImage({ glyph: hold, count: 250 }))).toEqual([
      "99+",
    ]);
  });

  test("an empty queue degrades to the plain key rather than showing 0", () => {
    expect(countKeyImage({ glyph: hold, count: 0 })).toBe(
      keyImage({ glyph: hold }),
    );
  });

  test("a negative count cannot happen but must not print one", () => {
    expect(textNodes(countKeyImage({ glyph: check, count: -1 }))).toEqual([]);
  });

  test("the count inherits the tile's knocked-out white", () => {
    const svg = countKeyImage({
      glyph: check,
      count: 3,
      tile: Palette.warning,
      tint: Palette.dim,
    });
    expect(svg).toContain(`fill="${Palette.warning}"`);
    expect(svg).toContain(`fill="${Palette.white}"`);
    expect(svg).not.toContain(Palette.dim);
  });
});

describe("statusImage", () => {
  const down = {
    music: false,
    twitch: false,
    discord: false,
    overlay: false,
  };

  test("labels all four links", () => {
    expect(textNodes(statusImage(down))).toEqual(["M", "T", "D", "O"]);
  });

  test("lights only the links that are up", () => {
    const svg = statusImage({ ...down, twitch: true });
    expect(svg).toContain(Palette.twitch);
    expect(svg).not.toContain(Palette.discord);
    expect(svg).not.toContain(Palette.appleMusic);
  });

  test("every link down is still four readable dots, not a blank key", () => {
    const svg = statusImage(down);
    expect(svg.match(/<circle/g)).toHaveLength(4);
    expect(svg).toContain(Palette.dotOff);
  });

  test("each service keeps its own colour", () => {
    const svg = statusImage({
      music: true,
      twitch: true,
      discord: true,
      overlay: true,
    });
    for (const color of [
      Palette.appleMusic,
      Palette.twitch,
      Palette.discord,
      Palette.tile,
    ]) {
      expect(svg).toContain(color);
    }
  });
});

describe("actionIcon", () => {
  test("is monochrome white at 20px, per Elgato's action-list spec", () => {
    const svg = actionIcon(check);
    expect(isSingleRootSvg(svg)).toBe(true);
    expect(svg).toContain('width="20" height="20"');
    expect(svg).toContain(Palette.white);
    expect(svg).not.toContain("<rect");
    for (const color of [Palette.tile, Palette.danger, Palette.warning]) {
      expect(svg).not.toContain(color);
    }
  });
});

/** The y translate of the glyph group, i.e. how far down the key it sits. */
function offsetY(svg: string): number {
  const match = svg.match(/translate\(([\d.]+) ([\d.]+)\)/);
  return match ? Number(match[2]) : Number.NaN;
}
