#!/usr/bin/env bun
/**
 * WolfWave design-system lint.
 *
 * Greps Swift sources for raw literals that bypass the design-token system.
 * Exits non-zero with a file:line:col report on violation.
 *
 * Scope: apps/native/WolfWave/Views/ (excluding Onboarding/ (separate design
 * language) and *.generated.swift). Tests are also skipped.
 *
 * Allowlist: design-system/lint-allowlist.txt; one `path:line` per line,
 * `#` starts a comment. Use sparingly; prefer fixing the source.
 *
 * Rules:
 *  - font(.system(size: N))     → use DSFont.Size.*
 *  - spacing: N) / .padding(N)  → use DSSpace.* (with carve-outs for 0/1/etc.
 *                                  values that have no DSSpace equivalent; 6 = DSSpace.s1h)
 *  - Hand-rolled bordered icon buttons → use DSIconButton
 *  - Animation literal durations (.easeInOut(duration: N), .spring(response: N),
 *    .easeOut(duration: N), .easeIn(duration: N), .linear(duration: N))
 *                               → use DSMotion.Duration.* tokens
 *  - Raw system colors in a `color:` / `statusColor:` argument
 *                               → use DSColor.success/.warning/.error/.info/.neutral
 */

import { readFileSync, readdirSync, statSync } from "node:fs";
import { resolve, join, relative } from "node:path";

const ROOT = resolve(import.meta.dir, "..", "..");
const SCAN_ROOT = resolve(ROOT, "apps/native/WolfWave/Views");
const ALLOWLIST_PATH = resolve(ROOT, "design-system/lint-allowlist.txt");

interface Violation {
  file: string;
  line: number;
  rule: string;
  excerpt: string;
}

export const RULES: Array<{ name: string; pattern: RegExp; appliesToOnboarding: boolean }> = [
  {
    name: "raw-font-size",
    pattern: /\bfont\(\.system\(size:\s*\d+/,
    appliesToOnboarding: false,
  },
  {
    name: "raw-spacing",
    // matches `spacing: N)` or `spacing: N,` where N is a tokenized value
    pattern: /\bspacing:\s*(2|4|6|8|10|12|14|16|20|24|28|32|44)(?=[,)\s])/,
    appliesToOnboarding: false,
  },
  {
    name: "raw-padding",
    pattern: /\.padding\(\s*(2|4|6|8|10|12|14|16|20|24|28|32|44)\s*\)/,
    appliesToOnboarding: false,
  },
  {
    name: "raw-animation-duration",
    // matches `.easeInOut(duration: 0.2)`, `.spring(response: 0.35, …)`,
    // `.easeOut(duration: 0.4)`, `.linear(duration: 0.2)`, `Animation(…duration: 0.2)`.
    // Token-only mode: any numeric literal in duration:/response: is flagged.
    // Onboarding is opted in; its visual rhythm differs but motion tokens unify.
    pattern:
      /\.(easeInOut|easeIn|easeOut|linear|spring|interpolatingSpring|interactiveSpring)\([^)]*\b(duration|response):\s*\d+\.?\d*/,
    appliesToOnboarding: true,
  },
  {
    name: "raw-status-color",
    // A `StatusChip` / `SectionHeaderWithStatus` state tint must come from a
    // token, so an "Off" pill renders the same wash in every pane. The gap that
    // made this necessary: DSColor had no neutral until 2026-08, so 13 sites
    // passed raw `.gray` / `Color.secondary`. `Color.secondary` is the worst of
    // them, being translucent: the chip's own `color.opacity(0.1)` background
    // then lands near-invisible beside opaque siblings.
    //
    // Scoped to the `color:` / `statusColor:` argument labels rather than to
    // bare colors, because `.foregroundStyle(.secondary)` on body text is
    // correct and must not be flagged. `[^,)]*` reaches across a ternary
    // (`statusColor: on ? .green : .gray`) while stopping at the next argument.
    //
    // Not in the banned set, on purpose: `.black` / `.white` (shadows, and the
    // Discord preview's off dot on its fixed brand surface, where DSColor.neutral
    // reads at 1.9:1), `.purple` (a non-status category tag on the dot-fallback
    // form), and `.accentColor` (Software Update's "update available", which
    // should follow the user's system accent).
    pattern:
      /\b(?:color|statusColor):[^,)]*(?<![A-Za-z0-9_])(?:Color)?\.(green|orange|red|yellow|blue|gray|grey|secondary|mint|teal|cyan|indigo|pink|brown)\b/,
    appliesToOnboarding: true,
  },
];

function loadAllowlist(): Set<string> {
  try {
    const raw = readFileSync(ALLOWLIST_PATH, "utf8");
    return new Set(
      raw
        .split("\n")
        .map((l) => l.replace(/#.*/, "").trim())
        .filter(Boolean)
    );
  } catch {
    return new Set();
  }
}

interface WalkEntry {
  path: string;
  inOnboarding: boolean;
}

function* walk(dir: string, inOnboarding = false): Generator<WalkEntry> {
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    const st = statSync(full);
    if (st.isDirectory()) {
      yield* walk(full, inOnboarding || entry === "Onboarding");
    } else if (entry.endsWith(".swift") && !entry.endsWith(".generated.swift")) {
      yield { path: full, inOnboarding };
    }
  }
}

function scan(): Violation[] {
  const allowlist = loadAllowlist();
  const violations: Violation[] = [];
  for (const { path, inOnboarding } of walk(SCAN_ROOT)) {
    const rel = relative(ROOT, path);
    const lines = readFileSync(path, "utf8").split("\n");
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      for (const rule of RULES) {
        if (inOnboarding && !rule.appliesToOnboarding) continue;
        if (rule.pattern.test(line)) {
          const key = `${rel}:${i + 1}`;
          if (allowlist.has(key)) continue;
          violations.push({
            file: rel,
            line: i + 1,
            rule: rule.name,
            excerpt: line.trim(),
          });
        }
      }
    }
  }
  return violations;
}

/// Runs the scan and reports. Split out of the module body so `lint.test.ts`
/// can import `RULES` without the import itself linting and calling
/// `process.exit`.
function runLint(): never {
  const violations = scan();
  if (violations.length === 0) {
    console.log("✓ design-system lint: clean");
    process.exit(0);
  }

  console.error(`✘ design-system lint: ${violations.length} violation(s)`);
  console.error("");
  for (const v of violations) {
    console.error(`  ${v.file}:${v.line}  [${v.rule}]  ${v.excerpt}`);
  }
  console.error("");
  console.error(
    "Fix: replace literals with DSFont.Size.* / DSSpace.* / DSMotion.Duration.* / DSColor.* tokens."
  );
  console.error("See: design-system/components/README.md");
  console.error("Allowlist exceptions: design-system/lint-allowlist.txt");
  process.exit(1);
}

if (import.meta.main) {
  runLint();
}
