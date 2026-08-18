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
 * The art itself lives in `src/keyart.ts`, shared with the runtime so a key
 * repainted live by `setImage` matches the static image it replaces.
 *
 * Run: bun run --filter streamdeck icons
 */
import { mkdirSync, writeFileSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { Resvg } from "@resvg/resvg-js";
import {
  Palette,
  actionIcon,
  ban,
  check,
  hold,
  keyImage,
  monitor,
  play,
  pause,
  resume,
  skip,
  trash,
  type Glyph,
} from "../src/keyart.js";

const ROOT = join(import.meta.dir, "..");
const IMGS = join(ROOT, "com.mrdemonwolf.wolfwave.sdPlugin", "imgs");
const REPO_ROOT = join(ROOT, "..", "..");

const WHITE = Palette.white;

/** The action-list icon for each action, monochrome white per Elgato's spec. */
const ACTION_ICONS: Array<[string, Glyph]> = [
  ["playpause", play],
  ["skip", skip],
  ["queuehold", hold],
  ["approvenext", check],
  ["clearqueue", trash],
  ["blockcurrent", ban],
  ["overlaytoggle", monitor],
];

/**
 * Key images. A brand tile means "on / live", a red glyph means the key does
 * something destructive, amber means it wants the streamer's attention, and
 * plain white means an available control that is currently off.
 *
 * `titled` marks the keys that also carry an Elgato title, so the glyph sits
 * clear of the bottom title strip rather than colliding with it.
 */
const KEY_IMAGES: Array<[string, string]> = [
  ["actions/playpause/key-paused", keyImage({ glyph: play, titled: true })],
  [
    "actions/playpause/key-playing",
    keyImage({ glyph: pause, tile: Palette.tile, titled: true }),
  ],
  ["actions/skip/key", keyImage({ glyph: skip })],
  ["actions/queuehold/key-running", keyImage({ glyph: hold })],
  ["actions/queuehold/key-held", keyImage({ glyph: resume, tile: Palette.tile })],
  ["actions/approvenext/key-empty", keyImage({ glyph: check, tint: Palette.dim })],
  [
    "actions/approvenext/key-pending",
    keyImage({ glyph: check, tile: Palette.warning }),
  ],
  ["actions/clearqueue/key", keyImage({ glyph: trash, tint: Palette.danger })],
  ["actions/blockcurrent/key", keyImage({ glyph: ban, tint: Palette.danger })],
  ["actions/overlaytoggle/key-off", keyImage({ glyph: monitor })],
  [
    "actions/overlaytoggle/key-on",
    keyImage({ glyph: monitor, tile: Palette.tile }),
  ],
];

function write(relative: string, contents: string | Uint8Array): void {
  const target = join(IMGS, relative);
  mkdirSync(dirname(target), { recursive: true });
  writeFileSync(target, contents);
  console.log(`  ✓ imgs/${relative}`);
}

console.log("Generating Stream Deck plugin icons…");

for (const [name, glyph] of ACTION_ICONS) {
  write(`actions/${name}/icon.svg`, actionIcon(glyph));
}
for (const [path, svg] of KEY_IMAGES) {
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
