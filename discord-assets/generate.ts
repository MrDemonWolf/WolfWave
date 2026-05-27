/**
 * Generate Discord Rich Presence art assets as 512×512 PNGs.
 *
 * Run from repo root:
 *   bun run discord-assets/generate.ts
 *
 * The PNGs are written into discord-assets/ alongside this script.
 * Upload them to https://discord.com/developers/applications →
 * <Your App> → Rich Presence → Art Assets with the asset names listed
 * in discord-assets/README.md.
 */

import { Resvg } from "@resvg/resvg-js";
import { writeFileSync } from "node:fs";
import { join } from "node:path";

const SIZE = 512;
const OUT_DIR = import.meta.dir;

function render(name: string, svg: string) {
  const png = new Resvg(svg, { fitTo: { mode: "width", value: SIZE } }).render().asPng();
  const path = join(OUT_DIR, `${name}.png`);
  writeFileSync(path, png);
  console.log(`wrote ${path} (${png.byteLength} bytes)`);
}

/**
 * pause.png — white pause glyph on a dark rounded square.
 * Used as Discord `small_image` when the loaded track is paused.
 */
const pauseSVG = `
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0%" stop-color="#1F2330"/>
      <stop offset="100%" stop-color="#0E1018"/>
    </linearGradient>
  </defs>
  <rect width="512" height="512" rx="96" fill="url(#bg)"/>
  <rect x="160" y="128" width="64" height="256" rx="20" fill="#FFFFFF"/>
  <rect x="288" y="128" width="64" height="256" rx="20" fill="#FFFFFF"/>
</svg>
`.trim();

/**
 * apple_music.png — placeholder fallback icon (white music note on the
 * WolfWave brand-blue gradient). REPLACE THIS with the official Apple Music
 * logo before shipping a public release — Apple's logo is trademarked and
 * the official mark is required by their identity guidelines.
 * See: https://developer.apple.com/apple-music/marketing-tools/
 */
const applePlaceholderSVG = `
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0%" stop-color="#FA243C"/>
      <stop offset="100%" stop-color="#B71228"/>
    </linearGradient>
  </defs>
  <rect width="512" height="512" rx="96" fill="url(#bg)"/>
  <g fill="#FFFFFF">
    <!-- Music note: stem + flag + filled head -->
    <path d="M310 128 L310 320
             a56 56 0 1 1 -32 -51
             L278 168
             L386 144
             L386 232
             a56 56 0 1 1 -32 -51
             L354 184
             L310 195
             Z"/>
  </g>
</svg>
`.trim();

render("pause", pauseSVG);
render("apple_music_placeholder", applePlaceholderSVG);

console.log("\nDone. Next steps:");
console.log("  1. Replace apple_music_placeholder.png with the official Apple Music logo");
console.log("     (renamed to apple_music.png) — Apple's mark is trademarked and the");
console.log("     placeholder is only a stand-in for local development.");
console.log("  2. Upload both PNGs to your Discord application's Art Assets page.");
console.log("     See discord-assets/README.md for the upload steps.");
