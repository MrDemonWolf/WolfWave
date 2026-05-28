/**
 * WolfWave OBS Widget — Build script.
 *
 * Pipeline:
 *   1. Compile src/widget.ts → dist/widget.js (esbuild via Bun.build, IIFE, minified).
 *   2. Run Tailwind CLI on src/widget.css using src/widget.html + src/widget.ts
 *      as content sources → dist/widget.css (minified, purged).
 *   3. Read the generated design-system tokens (widget-tokens.generated.js).
 *   4. Substitute the three placeholders in src/widget.html and write the
 *      single self-contained result to apps/native/WolfWave/Resources/widget.html.
 *
 * Why a homegrown script instead of webpack/vite/parcel?
 *   We need a single static .html with everything inlined. No code splitting,
 *   no asset linkage, no dev server. The bundlers all want to emit multi-file
 *   apps; coercing them into one-file mode is more configuration than just
 *   writing this script.
 */

import { readFile, writeFile, mkdir, rm } from "node:fs/promises";
import { existsSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn } from "node:child_process";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(__dirname, "../..");
const SRC = resolve(__dirname, "src");
const DIST = resolve(__dirname, "dist");
const OUT_HTML = resolve(ROOT, "apps/native/WolfWave/Resources/widget.html");
const TOKENS_JS = resolve(ROOT, "apps/native/WolfWave/Resources/widget-tokens.generated.js");

function log(step: string, detail = ""): void {
  console.log(`[widget:build] ${step}${detail ? " — " + detail : ""}`);
}

function run(cmd: string, args: string[]): Promise<void> {
  return new Promise((resolvePromise, rejectPromise) => {
    const child = spawn(cmd, args, { stdio: "inherit", cwd: __dirname });
    child.on("error", rejectPromise);
    child.on("exit", (code) => {
      if (code === 0) resolvePromise();
      else rejectPromise(new Error(`${cmd} exited with code ${code}`));
    });
  });
}

async function buildJS(): Promise<string> {
  log("bundling widget.ts");
  const result = await Bun.build({
    entrypoints: [resolve(SRC, "widget.ts")],
    outdir: DIST,
    format: "iife",
    target: "browser",
    minify: true,
    sourcemap: "none",
    naming: "widget.js",
  });
  if (!result.success) {
    for (const m of result.logs) console.error(m);
    throw new Error("widget.ts bundle failed");
  }
  const jsPath = resolve(DIST, "widget.js");
  return await readFile(jsPath, "utf8");
}

/**
 * Resolve the locally-installed tailwindcss binary.
 *
 * Do NOT shell out to `bunx tailwindcss` — when the package isn't installed
 * locally (fresh worktree, CI cache miss) bunx silently fetches the latest
 * remote, which is Tailwind v4. v4 moved the CLI into a separate
 * `@tailwindcss/cli` package, so the bare `tailwindcss` package has no bin and
 * the build dies with a cryptic "could not determine executable to run for
 * package tailwindcss". Pin to the local bin and fail loud instead.
 *
 * bun's workspace install may hoist the bin to the root node_modules or keep
 * it widget-local depending on the dependency tree, so check both.
 */
function resolveTailwindBin(): string {
  const candidates = [
    resolve(__dirname, "node_modules/.bin/tailwindcss"),
    resolve(ROOT, "node_modules/.bin/tailwindcss"),
  ];
  const bin = candidates.find((p) => existsSync(p));
  if (!bin) {
    throw new Error(
      "tailwindcss CLI not found — run `bun install` first " +
        `(looked in: ${candidates.join(", ")})`,
    );
  }
  return bin;
}

async function buildCSS(): Promise<string> {
  log("running tailwind CLI");
  await mkdir(DIST, { recursive: true });
  await run(resolveTailwindBin(), [
    "-c",
    resolve(__dirname, "tailwind.config.ts"),
    "-i",
    resolve(SRC, "widget.css"),
    "-o",
    resolve(DIST, "widget.css"),
    "--minify",
  ]);
  return await readFile(resolve(DIST, "widget.css"), "utf8");
}

async function readTokens(): Promise<string> {
  if (!existsSync(TOKENS_JS)) {
    log(
      "tokens missing",
      "widget-tokens.generated.js not found — run `bun run tokens` first",
    );
    throw new Error("tokens not generated");
  }
  return await readFile(TOKENS_JS, "utf8");
}

async function emit(): Promise<void> {
  const [css, js, tokens] = await Promise.all([
    buildCSS(),
    buildJS(),
    readTokens(),
  ]);
  const template = await readFile(resolve(SRC, "widget.html"), "utf8");

  const banner = "<!-- GENERATED — edit apps/widget/src/widget.html — run `bun run --filter widget build` to rebuild. -->\n";

  // String.replace would interpret $ sequences in the replacement (e.g. $1).
  // Splitting + joining is safer for arbitrary CSS/JS payloads.
  const out =
    banner +
    template
      .split("%%TAILWIND_CSS%%")
      .join(css)
      .split("%%TOKENS_JS%%")
      .join(tokens)
      .split("%%WIDGET_JS%%")
      .join(js);

  await mkdir(dirname(OUT_HTML), { recursive: true });
  await writeFile(OUT_HTML, out, "utf8");
  log("wrote", OUT_HTML.replace(ROOT + "/", ""));
}

async function main(): Promise<void> {
  await rm(DIST, { recursive: true, force: true });
  await mkdir(DIST, { recursive: true });
  await emit();
  log("done");
}

main().catch((err) => {
  console.error("[widget:build] failed:", err);
  process.exit(1);
});
