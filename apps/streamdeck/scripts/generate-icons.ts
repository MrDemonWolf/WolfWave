/**
 * Generates every image the manifest references into
 * `com.mrdemonwolf.wolfwave.sdPlugin/imgs/`.
 *
 * Elgato's required formats and sizes (docs.elgato.com/streamdeck/sdk/references/manifest):
 *
 * | Slot                | Format      | Sizes                  | Style                      |
 * |---------------------|-------------|------------------------|----------------------------|
 * | Action `Icon`       | PNG or SVG  | 20x20, 40x40 (@2x)     | monochrome #FFF, no bg     |
 * | State `Image` (key) | GIF/PNG/SVG | 72x72, 144x144 (@2x)   | free                       |
 * | `CategoryIcon`      | PNG or SVG  | 28x28, 56x56 (@2x)     | monochrome #FFF, no bg     |
 * | `Icon` (plugin)     | PNG only    | 256x256, 512x512 (@2x) | free                       |
 *
 * Everything that accepts SVG ships as a single SVG, so there is no @1x/@2x pair
 * to keep in sync. Only the plugin icon has to be raster, so it is the only thing
 * rendered through resvg.
 *
 * Run: bun run --filter streamdeck icons
 */
import { mkdirSync, writeFileSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { Resvg } from "@resvg/resvg-js";

const ROOT = join(import.meta.dir, "..");
const IMGS = join(ROOT, "com.mrdemonwolf.wolfwave.sdPlugin", "imgs");
const REPO_ROOT = join(ROOT, "..", "..");

/** Brand blue, `color.brand.500` in design-system/tokens.json. */
const BRAND = "#0A84FF";
/** Inactive key art. Readable on a black key without competing with the active state. */
const DIM = "#8E8E93";
const WHITE = "#FFFFFF";

/**
 * Glyphs are authored on a 24x24 grid and drawn with strokes, so one definition
 * scales to both the 20px action icon and the 72px key image without redrawing.
 * `fill` marks the parts that are solid rather than stroked.
 */
type Glyph = (color: string) => string;

const stroke = (d: string, color: string, width = 2) =>
  `<path d="${d}" fill="none" stroke="${color}" stroke-width="${width}" stroke-linecap="round" stroke-linejoin="round"/>`;
const solid = (d: string, color: string) => `<path d="${d}" fill="${color}"/>`;

const play: Glyph = (c) => solid("M9 6.5 18 12 9 17.5Z", c);
const pause: Glyph = (c) =>
  solid("M8.5 6.5h2.6v11H8.5Z", c) + solid("M12.9 6.5h2.6v11h-2.6Z", c);
const skip: Glyph = (c) => solid("M6.5 6.5 14 12 6.5 17.5Z", c) + stroke("M16.5 6.5v11", c, 2.4);
const check: Glyph = (c) => stroke("M5.5 12.5 10 17l8.5-9", c, 2.4);
const checkDim: Glyph = (c) => stroke("M5.5 12.5 10 17l8.5-9", c, 1.6);
const trash: Glyph = (c) =>
  stroke("M4.5 7h15", c, 2) +
  stroke("M9.5 7V5h5v2", c, 2) +
  stroke("M6.5 7.5 7.5 19h9l1-11.5", c, 2) +
  stroke("M10.5 10.5v5.5M13.5 10.5v5.5", c, 1.6);
const ban: Glyph = (c) =>
  `<circle cx="12" cy="12" r="7.6" fill="none" stroke="${c}" stroke-width="2"/>` +
  stroke("M6.6 6.6 17.4 17.4", c, 2);
const monitor: Glyph = (c) =>
  `<rect x="3.2" y="5" width="17.6" height="12" rx="2.2" fill="none" stroke="${c}" stroke-width="2"/>` +
  stroke("M9 20h6", c, 2);
const bubble: Glyph = (c) =>
  `<path d="M4 7.5a2.5 2.5 0 0 1 2.5-2.5h11A2.5 2.5 0 0 1 20 7.5v6a2.5 2.5 0 0 1-2.5 2.5H11l-4.5 3.5V16H6.5A2.5 2.5 0 0 1 4 13.5Z" fill="none" stroke="${c}" stroke-width="2" stroke-linejoin="round"/>` +
  solid("M9 10.5a1.3 1.3 0 1 1 0 2.6 1.3 1.3 0 0 1 0-2.6Z", c) +
  solid("M15 10.5a1.3 1.3 0 1 1 0 2.6 1.3 1.3 0 0 1 0-2.6Z", c);
const note: Glyph = (c) =>
  stroke("M10 17V5.5l8-1.5V15", c, 2) +
  `<ellipse cx="7.6" cy="17" rx="2.6" ry="2.2" fill="${c}"/>` +
  `<ellipse cx="15.6" cy="15" rx="2.6" ry="2.2" fill="${c}"/>`;
const theme: Glyph = (c) =>
  `<circle cx="12" cy="12" r="7.6" fill="none" stroke="${c}" stroke-width="2"/>` +
  `<path d="M12 4.4a7.6 7.6 0 0 1 0 15.2Z" fill="${c}"/>`;
const pulse: Glyph = (c) => stroke("M3.5 12h4L10 6.5l4 11 2.5-5.5h4", c, 2.2);
const hold: Glyph = pause;

/** One entry per `imgs/...` path the manifest references, minus the plugin icons. */
const KEYS: Array<{ path: string; glyph: Glyph; color: string }> = [
  // Action list icons: monochrome white, per Elgato's spec.
  { path: "actions/playpause/icon", glyph: play, color: WHITE },
  { path: "actions/skip/icon", glyph: skip, color: WHITE },
  { path: "actions/queuehold/icon", glyph: hold, color: WHITE },
  { path: "actions/approvenext/icon", glyph: check, color: WHITE },
  { path: "actions/clearqueue/icon", glyph: trash, color: WHITE },
  { path: "actions/blockcurrent/icon", glyph: ban, color: WHITE },
  { path: "actions/overlaytoggle/icon", glyph: monitor, color: WHITE },
  { path: "actions/discordtoggle/icon", glyph: bubble, color: WHITE },
  { path: "actions/musicsynctoggle/icon", glyph: note, color: WHITE },
  { path: "actions/cycletheme/icon", glyph: theme, color: WHITE },
  { path: "actions/status/icon", glyph: pulse, color: WHITE },

  // Key images. Brand blue reads as "this is on / this is live", grey as idle,
  // which is the only state cue a key has beyond its title.
  { path: "actions/playpause/key-playing", glyph: pause, color: BRAND },
  { path: "actions/playpause/key-paused", glyph: play, color: WHITE },
  { path: "actions/skip/key", glyph: skip, color: WHITE },
  { path: "actions/queuehold/key-running", glyph: hold, color: WHITE },
  { path: "actions/queuehold/key-held", glyph: play, color: BRAND },
  { path: "actions/approvenext/key-empty", glyph: checkDim, color: DIM },
  { path: "actions/approvenext/key-pending", glyph: check, color: BRAND },
  { path: "actions/clearqueue/key", glyph: trash, color: WHITE },
  { path: "actions/blockcurrent/key", glyph: ban, color: WHITE },
  { path: "actions/overlaytoggle/key-off", glyph: monitor, color: DIM },
  { path: "actions/overlaytoggle/key-on", glyph: monitor, color: BRAND },
  { path: "actions/discordtoggle/key-off", glyph: bubble, color: DIM },
  { path: "actions/discordtoggle/key-on", glyph: bubble, color: BRAND },
  { path: "actions/musicsynctoggle/key-off", glyph: note, color: DIM },
  { path: "actions/musicsynctoggle/key-on", glyph: note, color: BRAND },
  { path: "actions/cycletheme/key", glyph: theme, color: WHITE },
  { path: "actions/status/key-down", glyph: pulse, color: DIM },
  { path: "actions/status/key-up", glyph: pulse, color: BRAND },
];

/** Wraps a 24-grid glyph in an SVG sized for the slot it fills. */
function glyphSvg(glyph: Glyph, color: string, size: number, inset: number): string {
  const scale = (size - inset * 2) / 24;
  return [
    `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 ${size} ${size}">`,
    `<g transform="translate(${inset} ${inset}) scale(${scale.toFixed(4)})">`,
    glyph(color),
    `</g></svg>`,
  ].join("");
}

function write(relative: string, contents: string | Uint8Array): void {
  const target = join(IMGS, relative);
  mkdirSync(dirname(target), { recursive: true });
  writeFileSync(target, contents);
  console.log(`  ✓ imgs/${relative}`);
}

console.log("Generating Stream Deck plugin icons…");

for (const { path, glyph, color } of KEYS) {
  const isActionIcon = path.endsWith("/icon");
  // Action icons are 20px and need every pixel; key art sits on a 72px key with
  // generous padding so a user-set title still has room underneath.
  const svg = isActionIcon ? glyphSvg(glyph, color, 20, 1) : glyphSvg(glyph, color, 72, 16);
  write(`${path}.svg`, svg);
}

// Category icon: the wolf mark itself, monochrome white per spec.
const wolfSource = readFileSync(join(REPO_ROOT, "assets", "logo-mono.svg"), "utf8");
const wolfBody = wolfSource
  .replace(/^[\s\S]*?<svg[^>]*>/, "")
  .replace(/<\/svg>\s*$/, "")
  .replace(/<!--[\s\S]*?-->/g, "")
  .trim();
const wolfMark = (color: string, size: number, inset: number) => {
  const scale = (size - inset * 2) / 15;
  return [
    `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 ${size} ${size}">`,
    `<g transform="translate(${inset} ${inset}) scale(${scale.toFixed(4)})" fill="${color}" color="${color}">`,
    wolfBody,
    `</g></svg>`,
  ].join("");
};
write("plugin/category-icon.svg", wolfMark(WHITE, 28, 2));

// Plugin icon: PNG only, so this is the one thing that gets rasterized. Brand
// gradient tile behind a white wolf, matching the app icon and the DMG art.
const marketplaceSvg = (size: number) => {
  const wolfInset = size * 0.2;
  const wolfScale = (size - wolfInset * 2) / 15;
  return [
    `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 ${size} ${size}">`,
    `<defs><linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">`,
    `<stop offset="0" stop-color="#0A2540"/><stop offset="1" stop-color="#2563EB"/>`,
    `</linearGradient></defs>`,
    `<rect width="${size}" height="${size}" rx="${(size * 0.2237).toFixed(2)}" fill="url(#bg)"/>`,
    `<g transform="translate(${wolfInset} ${wolfInset}) scale(${wolfScale.toFixed(4)})" fill="${WHITE}" color="${WHITE}">`,
    wolfBody,
    `</g></svg>`,
  ].join("");
};
for (const [size, name] of [
  [256, "plugin/marketplace.png"],
  [512, "plugin/marketplace@2x.png"],
] as const) {
  const png = new Resvg(marketplaceSvg(size), {
    fitTo: { mode: "width", value: size },
  })
    .render()
    .asPng();
  write(name, png);
}

// Marketplace app icon: 288x288 PNG, uploaded in Maker Console rather than
// shipped in the bundle, so it lives outside the .sdPlugin directory.
const appIcon = new Resvg(marketplaceSvg(288), { fitTo: { mode: "width", value: 288 } })
  .render()
  .asPng();
const appIconPath = join(ROOT, "marketing", "app-icon.png");
mkdirSync(dirname(appIconPath), { recursive: true });
writeFileSync(appIconPath, appIcon);
console.log("  ✓ marketing/app-icon.png");

console.log("Done.");
