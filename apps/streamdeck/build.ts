/**
 * Bundles the plugin into the `.sdPlugin` folder Stream Deck loads.
 *
 * Stream Deck runs `CodePath` under its own bundled Node, not under Bun, so the
 * output targets Node and every dependency is bundled in — the `.sdPlugin` a
 * user installs has no `node_modules` beside it.
 *
 * Mirrors `apps/widget/build.ts`: a plain Bun script rather than a bundler
 * config, so there is one less tool to keep current.
 */

import { rm } from "node:fs/promises";

const PLUGIN_DIR = "com.mrdemonwolf.wolfwave.sdPlugin";
const OUT_DIR = `${PLUGIN_DIR}/bin`;

const watch = process.argv.includes("--watch");

async function build(): Promise<void> {
  // Clear stale output: a renamed entry point would otherwise leave the old
  // bundle behind and Stream Deck would happily keep running it.
  await rm(OUT_DIR, { recursive: true, force: true });

  const result = await Bun.build({
    entrypoints: ["src/plugin.ts"],
    outdir: OUT_DIR,
    target: "node",
    format: "esm",
    naming: "[dir]/[name].js",
    // Stream Deck surfaces plugin stack traces in its own log viewer, so a
    // readable trace is worth more here than a few saved kilobytes.
    minify: false,
    sourcemap: "linked",
  });

  if (!result.success) {
    for (const log of result.logs) console.error(log);
    throw new Error("streamdeck: bundle failed");
  }

  console.log(`streamdeck: built ${OUT_DIR}/plugin.js`);
}

await build();

if (watch) {
  console.log("streamdeck: watching src/…");
  const watcher = (await import("node:fs")).watch(
    "src",
    { recursive: true },
    () => {
      void build().catch((error) => console.error(error));
    },
  );
  process.on("SIGINT", () => {
    watcher.close();
    process.exit(0);
  });
}
