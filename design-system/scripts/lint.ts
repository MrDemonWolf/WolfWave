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

const RULES: Array<{ name: string; pattern: RegExp }> = [
  {
    name: "raw-font-size",
    pattern: /\bfont\(\.system\(size:\s*\d+/,
  },
  {
    name: "raw-spacing",
    // matches `spacing: N)` or `spacing: N,` where N is a tokenized value
    pattern: /\bspacing:\s*(2|4|8|10|12|14|16|20|24|28|32|44)(?=[,)\s])/,
  },
  {
    name: "raw-padding",
    pattern: /\.padding\(\s*(2|4|8|10|12|14|16|20|24|28|32|44)\s*\)/,
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

function* walk(dir: string): Generator<string> {
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    const st = statSync(full);
    if (st.isDirectory()) {
      if (entry === "Onboarding") continue;
      yield* walk(full);
    } else if (entry.endsWith(".swift") && !entry.endsWith(".generated.swift")) {
      yield full;
    }
  }
}

function scan(): Violation[] {
  const allowlist = loadAllowlist();
  const violations: Violation[] = [];
  for (const file of walk(SCAN_ROOT)) {
    const rel = relative(ROOT, file);
    const lines = readFileSync(file, "utf8").split("\n");
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      for (const rule of RULES) {
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
console.error("Fix: replace literals with DSFont.Size.* / DSSpace.* tokens.");
console.error("See: design-system/components/README.md");
console.error("Allowlist exceptions: design-system/lint-allowlist.txt");
process.exit(1);
