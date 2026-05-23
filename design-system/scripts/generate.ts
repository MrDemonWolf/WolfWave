#!/usr/bin/env bun
/**
 * WolfWave design token generator.
 *
 * Reads `design-system/tokens.json` and emits platform-specific outputs:
 *   - Swift  → apps/native/wolfwave/Core/DesignSystem/Tokens.generated.swift
 *   - CSS    → apps/docs/app/tokens.generated.css
 *   - JS     → apps/native/wolfwave/Resources/widget-tokens.generated.js
 *   - TS     → apps/marketing/shared/tokens.generated.ts
 *
 * Idempotent: re-running produces identical files. CI may diff to detect drift.
 */

import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname, resolve } from "node:path";

const ROOT = resolve(import.meta.dir, "..", "..");
const tokens = JSON.parse(
  readFileSync(resolve(ROOT, "design-system/tokens.json"), "utf8")
);

const BANNER_LINES = [
  "WolfWave Design System — GENERATED FILE. Do not edit by hand.",
  "Source: design-system/tokens.json",
  "Run `bun run tokens` to regenerate.",
];

function hexToRGB(hex: string): { r: number; g: number; b: number; a: number } {
  let h = hex.replace("#", "").trim();
  if (h.length === 3) h = h.split("").map((c) => c + c).join("");
  if (h.length === 6) h = h + "FF";
  const r = parseInt(h.slice(0, 2), 16) / 255;
  const g = parseInt(h.slice(2, 4), 16) / 255;
  const b = parseInt(h.slice(4, 6), 16) / 255;
  const a = parseInt(h.slice(6, 8), 16) / 255;
  return { r, g, b, a };
}

function swiftColor(hex: string): string {
  const { r, g, b, a } = hexToRGB(hex);
  const f = (n: number) => n.toFixed(3);
  if (a >= 0.999) return `Color(red: ${f(r)}, green: ${f(g)}, blue: ${f(b)})`;
  return `Color(red: ${f(r)}, green: ${f(g)}, blue: ${f(b)}, opacity: ${f(a)})`;
}

function write(path: string, content: string) {
  const full = resolve(ROOT, path);
  mkdirSync(dirname(full), { recursive: true });
  writeFileSync(full, content);
  console.log(`  ✓ ${path}`);
}

// ── Swift ─────────────────────────────────────────────────────────────────
function generateSwift(): string {
  const banner = BANNER_LINES.map((l) => `// ${l}`).join("\n");
  const lines: string[] = [
    banner,
    "",
    "import SwiftUI",
    "import CoreGraphics",
    "",
    "// MARK: - Design System Tokens",
    "",
    "/// Generated color tokens. Use these instead of hardcoded `Color(red:…)` literals.",
    "nonisolated enum DSColor {",
    "    // MARK: Brand",
  ];
  for (const [k, v] of Object.entries(tokens.color.brand)) {
    lines.push(`    static let brand${k} = ${swiftColor(v as string)}`);
  }
  lines.push("", "    // MARK: Semantic");
  for (const [k, v] of Object.entries(tokens.color.semantic)) {
    lines.push(`    static let ${k} = ${swiftColor(v as string)}`);
  }
  lines.push("", "    // MARK: Surface (light)");
  for (const [k, v] of Object.entries(tokens.color.surface.light)) {
    lines.push(`    static let surface${cap(k)}Light = ${swiftColor(v as string)}`);
  }
  lines.push("", "    // MARK: Surface (dark)");
  for (const [k, v] of Object.entries(tokens.color.surface.dark)) {
    lines.push(`    static let surface${cap(k)}Dark = ${swiftColor(v as string)}`);
  }
  lines.push("", "    // MARK: Text (light)");
  for (const [k, v] of Object.entries(tokens.color.text.light)) {
    lines.push(`    static let text${cap(k)}Light = ${swiftColor(v as string)}`);
  }
  lines.push("", "    // MARK: Text (dark)");
  for (const [k, v] of Object.entries(tokens.color.text.dark)) {
    lines.push(`    static let text${cap(k)}Dark = ${swiftColor(v as string)}`);
  }
  lines.push("", "    // MARK: Partner");
  for (const [k, v] of Object.entries(tokens.color.partner)) {
    lines.push(`    static let partner${cap(k)} = ${swiftColor(v as string)}`);
  }
  lines.push("}", "");

  lines.push(
    "/// Generated typography sizes. CGFloat literals match prior hand-coded sizes.",
    "nonisolated enum DSFont {",
    "    enum Size {"
  );
  for (const [k, v] of Object.entries(tokens.font.size)) {
    lines.push(`        static let ${safeIdent(k)}: CGFloat = ${v}`);
  }
  lines.push("    }", "");
  lines.push("    enum Weight {");
  const weightMap: Record<string, string> = {
    regular: ".regular",
    medium: ".medium",
    semibold: ".semibold",
    bold: ".bold",
  };
  for (const k of Object.keys(tokens.font.weight)) {
    lines.push(`        static let ${k}: Font.Weight = ${weightMap[k]}`);
  }
  lines.push("    }", "}", "");

  lines.push("/// Generated spacing scale.", "nonisolated enum DSSpace {");
  for (const [k, v] of Object.entries(tokens.space)) {
    lines.push(`    static let s${k}: CGFloat = ${v}`);
  }
  lines.push("}", "");

  lines.push("/// Generated radius scale.", "nonisolated enum DSRadius {");
  for (const [k, v] of Object.entries(tokens.radius)) {
    lines.push(`    static let ${safeIdent(k)}: CGFloat = ${v}`);
  }
  lines.push("}", "");

  lines.push(
    "/// Generated motion tokens (durations in seconds for SwiftUI animations).",
    "nonisolated enum DSMotion {",
    "    enum Duration {"
  );
  for (const [k, v] of Object.entries(tokens.motion.duration)) {
    lines.push(`        static let ${k}: Double = ${(v as number) / 1000}`);
  }
  lines.push("    }", "}", "");

  lines.push(
    "/// Window and onboarding dimension tokens (preserves legacy AppConstants values).",
    "nonisolated enum DSDimension {",
    "    enum Settings {"
  );
  for (const [k, v] of Object.entries(tokens.dimension.settings)) {
    lines.push(`        static let ${k}: CGFloat = ${v}`);
  }
  lines.push("    }", "");
  lines.push("    enum Onboarding {");
  for (const [k, v] of Object.entries(tokens.dimension.onboarding)) {
    lines.push(`        static let ${k}: CGFloat = ${v}`);
  }
  lines.push("    }", "}", "");

  return lines.join("\n") + "\n";
}

// ── CSS ───────────────────────────────────────────────────────────────────
function generateCSS(): string {
  const banner = `/*\n * ${BANNER_LINES.join("\n * ")}\n */\n`;
  const lines: string[] = [banner, ":root {"];
  // Brand
  for (const [k, v] of Object.entries(tokens.color.brand)) {
    lines.push(`  --ds-color-brand-${k}: ${v};`);
  }
  for (const [k, v] of Object.entries(tokens.color.semantic)) {
    lines.push(`  --ds-color-${k}: ${v};`);
  }
  // Light surfaces / text
  for (const [k, v] of Object.entries(tokens.color.surface.light)) {
    lines.push(`  --ds-color-surface-${k}: ${v};`);
  }
  for (const [k, v] of Object.entries(tokens.color.text.light)) {
    lines.push(`  --ds-color-text-${k}: ${v};`);
  }
  for (const [k, v] of Object.entries(tokens.color.partner)) {
    lines.push(`  --ds-color-partner-${kebab(k)}: ${v};`);
  }
  for (const [k, v] of Object.entries(tokens.font.family)) {
    lines.push(`  --ds-font-family-${kebab(k)}: ${v};`);
  }
  for (const [k, v] of Object.entries(tokens.font.size)) {
    lines.push(`  --ds-font-size-${k}: ${v}px;`);
  }
  for (const [k, v] of Object.entries(tokens.font.weight)) {
    lines.push(`  --ds-font-weight-${k}: ${v};`);
  }
  for (const [k, v] of Object.entries(tokens.space)) {
    lines.push(`  --ds-space-${k}: ${v}px;`);
  }
  for (const [k, v] of Object.entries(tokens.radius)) {
    const out = k === "pill" ? "9999px" : `${v}px`;
    lines.push(`  --ds-radius-${k}: ${out};`);
  }
  for (const [k, v] of Object.entries(tokens.motion.duration)) {
    lines.push(`  --ds-motion-duration-${k}: ${v}ms;`);
  }
  for (const [k, v] of Object.entries(tokens.motion.easing)) {
    lines.push(`  --ds-motion-easing-${k}: ${v};`);
  }
  for (const [k, v] of Object.entries(tokens.shadow)) {
    lines.push(`  --ds-shadow-${k}: ${v};`);
  }
  lines.push("}", "");

  lines.push(".dark, [data-theme=\"dark\"] {");
  for (const [k, v] of Object.entries(tokens.color.brandDark)) {
    lines.push(`  --ds-color-brand-${k}: ${v};`);
  }
  for (const [k, v] of Object.entries(tokens.color.surface.dark)) {
    lines.push(`  --ds-color-surface-${k}: ${v};`);
  }
  for (const [k, v] of Object.entries(tokens.color.text.dark)) {
    lines.push(`  --ds-color-text-${k}: ${v};`);
  }
  lines.push("}", "");

  return lines.join("\n");
}

// ── Widget JS ─────────────────────────────────────────────────────────────
function generateWidgetJS(): string {
  const banner = `/*\n * ${BANNER_LINES.join("\n * ")}\n */`;
  const obj = {
    color: tokens.color,
    font: tokens.font,
    space: tokens.space,
    radius: tokens.radius,
    motion: tokens.motion,
    shadow: tokens.shadow,
    themes: tokens.widget?.themes ?? {},
    layouts: tokens.widget?.layouts ?? {},
  };
  return `${banner}\nwindow.WW_TOKENS = ${JSON.stringify(obj, null, 2)};\n`;
}

// ── Marketing TS ──────────────────────────────────────────────────────────
function generateTS(): string {
  const banner = `/*\n * ${BANNER_LINES.join("\n * ")}\n */`;
  return `${banner}\n\nexport const tokens = ${JSON.stringify(tokens, null, 2)} as const;\n\nexport type Tokens = typeof tokens;\n`;
}

// ── Helpers ───────────────────────────────────────────────────────────────
function cap(s: string): string {
  return s.charAt(0).toUpperCase() + s.slice(1);
}
function kebab(s: string): string {
  return s.replace(/[A-Z]/g, (m) => `-${m.toLowerCase()}`);
}
function safeIdent(s: string): string {
  // Swift identifiers cannot start with a digit. Prefix with "x" if needed.
  return /^[0-9]/.test(s) ? `x${s}` : s;
}

// ── Emit ──────────────────────────────────────────────────────────────────
console.log("Generating WolfWave design tokens…");
write(
  "apps/native/wolfwave/Core/DesignSystem/Tokens.generated.swift",
  generateSwift()
);
write("apps/docs/app/tokens.generated.css", generateCSS());
write(
  "apps/native/wolfwave/Resources/widget-tokens.generated.js",
  generateWidgetJS()
);
write("apps/marketing/shared/tokens.generated.ts", generateTS());
console.log("Done.");
