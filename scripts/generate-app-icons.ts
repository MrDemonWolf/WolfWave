#!/usr/bin/env bun
/**
 * Derives the Debug app icon from the Release one.
 *
 *   apps/native/WolfWave/Resources/AppIcon.icon      (source of truth, hand-authored)
 *     -> apps/native/WolfWave/Resources/AppIcon-Dev.icon   (generated, do not hand-edit)
 *
 * Both configs ship the same brand-blue WolfWave mark. The only thing Debug adds
 * is a `DEV` badge, so the two builds stay distinguishable in the Dock and the
 * app switcher without maintaining a second colour design.
 *
 * The Release manifest is carried through verbatim - background fill, the logo
 * layer with its light/dark `fill-specializations` and scale, the group shadow
 * and translucency, `supported-platforms` - and the badge is appended as its own
 * group. `Assets/logo.svg` is copied rather than duplicated by hand, so a change
 * to the wolf mark only has to land in the Release bundle.
 *
 * The badge matches the iconwolf development-badge convention already shipping
 * in ConPaws (`apps/native/assets/images/ConPaws-development.icon`): a fixed
 * bottom-centre pill with the lettering drawn as a grid of 16pt squares. It is
 * deliberately NOT SVG `<text>` - a text node depends on a font being installed
 * and resolving identically wherever the icon is compiled, while rectangles
 * render the same everywhere.
 *
 * Pure string assembly: no rasterisation, no fonts, so the output is
 * byte-identical on every host and CI can diff it for drift.
 *
 * Idempotent. Run: `make icons` (or `bun run icons`).
 */
import { copyFileSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";

const ROOT = resolve(import.meta.dir, "..");
const RESOURCES = join(ROOT, "apps/native/WolfWave/Resources");
const SOURCE = join(RESOURCES, "AppIcon.icon");
const DEST = join(RESOURCES, "AppIcon-Dev.icon");

/** Icon Composer canvas, in points. */
const CANVAS = 1024;

const BADGE_TEXT = "DEV";
/** `semantic.error` from design-system/tokens.json. Reads as "not the real app". */
const BADGE_FILL = "#FF453A";
const BADGE_TEXT_FILL = "#FFFFFF";
const BADGE_NAME = "iconwolf-development-badge";

/**
 * Pill geometry, copied from the ConPaws badge so the two apps' dev icons read
 * as the same convention. The pill is a fixed size regardless of how long the
 * word is; the lettering is centred inside it.
 */
const BADGE = { x: 304, y: 724, width: 416, height: 176, radius: 44 };

/** One "pixel" of the lettering, in points. */
const CELL = 16;
/** Gap between two letters, in points. */
const LETTER_GAP = 8;

/**
 * 5x7 pixel font, one string per row, `#` = filled. Only the glyphs the badge
 * words need. Add a letter here rather than reaching for `<text>`.
 */
const GLYPHS: Record<string, string[]> = {
  D: ["####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####."],
  E: ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
  V: ["#...#", "#...#", "#...#", "#...#", ".#.#.", ".#.#.", "..#.."],
};

interface IconLayer {
  "image-name": string;
  name: string;
  position: { scale: number; "translation-in-points": [number, number] };
}

interface IconGroup {
  name?: string;
  layers: IconLayer[];
  shadow?: { kind: string; opacity: number };
  translucency?: { enabled: boolean; value: number };
}

interface IconManifest {
  groups: IconGroup[];
}

/** Render `text` as a grid of squares, centred inside the badge pill. */
function renderGlyphs(text: string): string {
  const rows = 7;
  const letters = [...text].map((char) => {
    const glyph = GLYPHS[char];
    if (!glyph) {
      throw new Error(
        `No glyph for "${char}". Add it to GLYPHS as a 5x7 pixel grid.`,
      );
    }
    return glyph;
  });

  const width =
    letters.reduce((sum, glyph) => sum + glyph[0].length * CELL, 0) +
    (letters.length - 1) * LETTER_GAP;
  let x = Math.round(BADGE.x + (BADGE.width - width) / 2);
  const top = Math.round(BADGE.y + (BADGE.height - rows * CELL) / 2);

  const squares: string[] = [];
  for (const glyph of letters) {
    glyph.forEach((row, rowIndex) => {
      [...row].forEach((cell, colIndex) => {
        if (cell !== "#") return;
        squares.push(
          `<rect x="${x + colIndex * CELL}" y="${top + rowIndex * CELL}" ` +
            `width="${CELL}" height="${CELL}" fill="${BADGE_TEXT_FILL}"/>`,
        );
      });
    });
    x += glyph[0].length * CELL + LETTER_GAP;
  }
  return squares.join("");
}

function createBadgeSvg(text: string): string {
  return (
    `<svg xmlns="http://www.w3.org/2000/svg" width="${CANVAS}" height="${CANVAS}" ` +
    `viewBox="0 0 ${CANVAS} ${CANVAS}">` +
    `<rect x="${BADGE.x}" y="${BADGE.y}" width="${BADGE.width}" ` +
    `height="${BADGE.height}" rx="${BADGE.radius}" fill="${BADGE_FILL}"/>` +
    renderGlyphs(text) +
    `</svg>`
  );
}

const manifest = JSON.parse(
  readFileSync(join(SOURCE, "icon.json"), "utf8"),
) as IconManifest;

if (!manifest.groups?.[0]?.layers?.length) {
  throw new Error(`${SOURCE}/icon.json has no layers to derive from.`);
}
if (manifest.groups.some((group) => group.name === BADGE_NAME)) {
  throw new Error(
    `${SOURCE}/icon.json already has a "${BADGE_NAME}" group. The Release icon ` +
      `is the source of truth and must stay badge-free.`,
  );
}

// The badge is its own group so it keeps its own, lighter depth treatment and
// does not inherit the logo group's shadow.
//
// It goes FIRST because Icon Composer draws the first group on top, and the
// wolf fills the canvas: appended last, the badge renders behind the mark and
// the lettering comes out struck through by the waveform leg. Verified by
// building both orders and reading the compiled .icns, not assumed.
//
// The colours are baked into the SVG and deliberately carry no
// `fill-specializations` - the badge must not follow the logo's light/dark swap.
manifest.groups.unshift({
  name: BADGE_NAME,
  layers: [
    {
      "image-name": `${BADGE_NAME}.svg`,
      name: BADGE_NAME,
      position: { scale: 1, "translation-in-points": [0, 0] },
    },
  ],
  shadow: { kind: "neutral", opacity: 0.35 },
  translucency: { enabled: true, value: 0.2 },
});

mkdirSync(join(DEST, "Assets"), { recursive: true });
copyFileSync(join(SOURCE, "Assets/logo.svg"), join(DEST, "Assets/logo.svg"));
writeFileSync(
  join(DEST, `Assets/${BADGE_NAME}.svg`),
  createBadgeSvg(BADGE_TEXT) + "\n",
);

// Icon Composer writes `icon.json` with two-space indent and a space before the
// key colon. Matching it keeps the diff against an Xcode-touched file readable.
writeFileSync(
  join(DEST, "icon.json"),
  JSON.stringify(manifest, null, 2).replace(/^(\s*)"([^"]+)":/gm, '$1"$2" :') +
    "\n",
);

console.log(`✅ Generated ${DEST.replace(ROOT + "/", "")} from AppIcon.icon`);
