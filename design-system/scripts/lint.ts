#!/usr/bin/env bun
/**
 * WolfWave design-system lint.
 *
 * Greps Swift sources for raw literals that bypass the design-token system.
 * Exits non-zero with a file:line:col report on violation.
 *
 * Scope: apps/native/wolfwave/Views/ — excluding Onboarding/ (separate design
 * language) and *.generated.swift. Tests are also skipped.
 *
 * Allowlist: design-system/lint-allowlist.txt — one `path:line` per line,
 * `#` starts a comment. Use sparingly; prefer fixing the source.
 *
 * Rules:
 *  - font(.system(size: N))     → use DSFont.Size.*
 *  - spacing: N) / .padding(N)  → use DSSpace.* (with carve-outs for 0/1/6/etc.
 *                                  values that have no DSSpace equivalent)
 *  - Hand-rolled bordered icon buttons → use DSIconButton
 *  - Animation literal durations (.easeInOut(duration: N), .spring(response: N),
 *    .easeOut(duration: N), .easeIn(duration: N), .linear(duration: N))
 *                               → use DSMotion.Duration.* tokens
 */

import { readFileSync, readdirSync, statSync } from "node:fs";
import { resolve, join, relative } from "node:path";

const ROOT = resolve(import.meta.dir, "..", "..");
const SCAN_ROOT = resolve(ROOT, "apps/native/wolfwave/Views");
const ALLOWLIST_PATH = resolve(ROOT, "design-system/lint-allowlist.txt");

interface Violation {
  file: string;
  line: number;
  rule: string;
  excerpt: string;
}

const RULES: Array<{ name: string; pattern: RegExp; appliesToOnboarding: boolean }> = [
  {
    name: "raw-font-size",
    pattern: /\bfont\(\.system\(size:\s*\d+/,
    appliesToOnboarding: false,
  },
  {
    name: "raw-spacing",
    // matches `spacing: N)` or `spacing: N,` where N is a tokenized value
    pattern: /\bspacing:\s*(2|4|8|10|12|14|16|20|24|28|32|44)(?=[,)\s])/,
    appliesToOnboarding: false,
  },
  {
    name: "raw-padding",
    pattern: /\.padding\(\s*(2|4|8|10|12|14|16|20|24|28|32|44)\s*\)/,
    appliesToOnboarding: false,
  },
  {
    name: "raw-animation-duration",
    // matches `.easeInOut(duration: 0.2)`, `.spring(response: 0.35, …)`,
    // `.easeOut(duration: 0.4)`, `.linear(duration: 0.2)`, `Animation(…duration: 0.2)`.
    // Token-only mode: any numeric literal in duration:/response: is flagged.
    // Onboarding is opted in — its visual rhythm differs but motion tokens unify.
    pattern:
      /\.(easeInOut|easeIn|easeOut|linear|spring|interpolatingSpring|interactiveSpring)\([^)]*\b(duration|response):\s*\d+\.?\d*/,
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
console.error("Fix: replace literals with DSFont.Size.* / DSSpace.* / DSMotion.Duration.* tokens.");
console.error("See: design-system/components/README.md");
console.error("Allowlist exceptions: design-system/lint-allowlist.txt");
process.exit(1);
