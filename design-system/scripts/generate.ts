#!/usr/bin/env bun
/**
 * WolfWave design token generator.
 *
 * Reads `design-system/tokens.json` and emits platform-specific outputs:
 *   - Swift        → apps/native/WolfWave/Core/DesignSystem/Tokens.generated.swift
 *   - CSS          → apps/docs/app/tokens.generated.css
 *   - Widget JS    → apps/native/WolfWave/Resources/widget-tokens.generated.js
 *   - Marketing TS → apps/marketing/shared/tokens.generated.ts
 *   - Docs TS      → apps/docs/app/(home)/_widgets/widget-themes.generated.ts
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
  "WolfWave Design System. GENERATED FILE. Do not edit by hand.",
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

/**
 * Parse a CSS color string into a Swift `Color` literal, or `null` when the
 * value is `transparent` / `none` / empty (the native preview renders those as
 * a `nil` optional and skips the layer). Supports `#hex`, `rgb()/rgba()`, and
 * `linear-gradient(...)` (the native preview is a flat approximation, so the
 * gradient's first color stop stands in for the whole fill).
 */
function cssColorToSwift(css: string): string | null {
  const v = (css || "").trim();
  if (v === "" || v === "transparent" || v === "none") return null;
  if (v.startsWith("#")) return swiftColor(v);

  const rgb = v.match(/rgba?\(\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)\s*(?:,\s*([\d.]+)\s*)?\)/);
  if (rgb) {
    const f = (n: number) => n.toFixed(3);
    const r = Number(rgb[1]) / 255;
    const g = Number(rgb[2]) / 255;
    const b = Number(rgb[3]) / 255;
    const a = rgb[4] === undefined ? 1 : Number(rgb[4]);
    if (a >= 0.999) return `Color(red: ${f(r)}, green: ${f(g)}, blue: ${f(b)})`;
    return `Color(red: ${f(r)}, green: ${f(g)}, blue: ${f(b)}, opacity: ${f(a)})`;
  }

  // Gradients / shorthand (e.g. "1px solid #00FFAA"): use the first color stop.
  const first = v.match(/#[0-9a-fA-F]{3,8}|rgba?\([^)]+\)/);
  if (first) return cssColorToSwift(first[0]);
  return null;
}

/** Emit a Swift `Color?` literal: `cssColorToSwift` result or `nil`. */
function swiftOptionalColor(css: string): string {
  return cssColorToSwift(css) ?? "nil";
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
  lines.push("    }", "");
  lines.push("    /// Named spring presets. Use via `.spring(DSMotion.Spring.snappy)`.");
  lines.push("    enum Spring {");
  for (const [k, v] of Object.entries(
    (tokens.motion.spring ?? {}) as Record<string, { response: number; damping: number }>
  )) {
    lines.push(
      `        static let ${k} = SwiftUI.Animation.spring(response: ${v.response}, dampingFraction: ${v.damping}, blendDuration: 0)`
    );
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
  lines.push("    }", "");
  lines.push("    enum About {");
  for (const [k, v] of Object.entries(tokens.dimension.about)) {
    lines.push(`        static let ${k}: CGFloat = ${v}`);
  }
  lines.push("    }", "");
  lines.push("    enum WhatsNew {");
  for (const [k, v] of Object.entries(tokens.dimension.whatsNew)) {
    lines.push(`        static let ${k}: CGFloat = ${v}`);
  }
  lines.push("    }", "");
  lines.push("    enum IconButton {");
  for (const [k, v] of Object.entries(tokens.dimension.iconButton)) {
    lines.push(`        static let ${k}: CGFloat = ${v}`);
  }
  lines.push("    }", "");
  lines.push("    enum HistoryStats {");
  for (const [k, v] of Object.entries(tokens.dimension.historyStats)) {
    lines.push(`        static let ${k}: CGFloat = ${v}`);
  }
  lines.push("    }", "}", "");

  // ── Widget theme palettes (mirrors `widget.html` so the native Settings
  //    preview matches what overlays render). Color strings are parsed to
  //    SwiftUI `Color`; `transparent`/`none`/gradients degrade gracefully. ──
  const widgetThemes = (tokens.widget?.themes ?? {}) as Record<
    string,
    Record<string, string | boolean>
  >;
  const widgetLayouts = (tokens.widget?.layouts ?? {}) as Record<
    string,
    { maxWidth: number; height: number }
  >;
  const customizable = new Set(["Default", "Glass"]);

  lines.push(
    "/// Generated widget theme palette. Mirrors `widget.html` so the in-app",
    "/// appearance preview matches what overlays render. `nil` color = the",
    "/// widget draws nothing for that layer (transparent background, no border).",
    "nonisolated struct DSWidgetTheme {",
    "    let containerBg: Color?",
    "    let borderColor: Color?",
    "    let cornerRadius: CGFloat",
    "    let overlayBg: Color?",
    "    let textPrimary: Color",
    "    let textSecondary: Color",
    "    let textMuted: Color",
    "    let progressTrack: Color",
    "    let progressFill: Color",
    "    let showArtworkBlur: Bool",
    "    /// `true` for themes whose text + background colors the user can override",
    "    /// (Default, Glass). Preset themes ship fixed palettes.",
    "    let userCustomizable: Bool",
    "}",
    ""
  );

  const themeLiteral = (t: Record<string, string | boolean>, name: string): string => {
    const radius = parseFloat(String(t.containerRadius ?? "12")) || 12;
    return [
      "DSWidgetTheme(",
      `        containerBg: ${swiftOptionalColor(String(t.containerBg ?? ""))},`,
      `        borderColor: ${swiftOptionalColor(String(t.containerBorder ?? ""))},`,
      `        cornerRadius: ${radius},`,
      `        overlayBg: ${swiftOptionalColor(String(t.overlayBg ?? ""))},`,
      `        textPrimary: ${cssColorToSwift(String(t.textPrimary ?? "#FFFFFF")) ?? "Color.white"},`,
      `        textSecondary: ${cssColorToSwift(String(t.textSecondary ?? "#FFFFFF")) ?? "Color.white"},`,
      `        textMuted: ${cssColorToSwift(String(t.textMuted ?? "#FFFFFF")) ?? "Color.white"},`,
      `        progressTrack: ${cssColorToSwift(String(t.progressTrackBg ?? "#FFFFFF")) ?? "Color.white"},`,
      `        progressFill: ${cssColorToSwift(String(t.progressFillBg ?? "#FFFFFF")) ?? "Color.white"},`,
      `        showArtworkBlur: ${t.showArtworkBlur === true},`,
      `        userCustomizable: ${customizable.has(name)}`,
      "    )",
    ].join("\n    ");
  };

  const visibleThemes = Object.entries(widgetThemes).filter(([, v]) => v.hidden !== true);
  const fallbackEntry = widgetThemes["Default"] ?? Object.values(widgetThemes)[0] ?? {};

  lines.push(
    "/// Generated widget theme + layout lookup for the appearance preview.",
    "nonisolated enum DSWidgetThemes {",
    `    /// Picker order, excluding \`hidden\` themes.`,
    `    static let order: [String] = [${visibleThemes.map(([k]) => `"${k}"`).join(", ")}]`,
    ""
  );
  lines.push("    static let all: [String: DSWidgetTheme] = [");
  for (const [name, t] of Object.entries(widgetThemes)) {
    lines.push(`        "${name}": ${themeLiteral(t, name)},`);
  }
  lines.push("    ]", "");
  lines.push(`    static let fallback = ${themeLiteral(fallbackEntry as Record<string, string | boolean>, "Default")}`);
  lines.push(
    "",
    "    /// Theme palette by name, falling back to Default for unknown names.",
    "    static func resolve(_ name: String) -> DSWidgetTheme { all[name] ?? fallback }",
    "}",
    ""
  );

  const fallbackLayout = widgetLayouts["Horizontal"] ?? { maxWidth: 500, height: 100 };
  lines.push(
    "/// Generated widget layout dimensions (points) used to size the preview.",
    "nonisolated enum DSWidgetLayouts {",
    "    static let sizes: [String: CGSize] = ["
  );
  for (const [name, dims] of Object.entries(widgetLayouts)) {
    lines.push(`        "${name}": CGSize(width: ${dims.maxWidth}, height: ${dims.height}),`);
  }
  lines.push("    ]", "");
  lines.push(
    `    static func size(_ name: String) -> CGSize { sizes[name] ?? CGSize(width: ${fallbackLayout.maxWidth}, height: ${fallbackLayout.height}) }`,
    "}",
    ""
  );

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
    defaultTheme: tokens.widget?.defaultTheme ?? "Default",
    defaultLayout: tokens.widget?.defaultLayout ?? "Horizontal",
  };
  return `${banner}\nwindow.WW_TOKENS = ${JSON.stringify(obj, null, 2)};\n`;
}

// ── Docs widget themes TS ───────────────────────────────────────────────────
// Typed module the docs site imports so its landing-page OBS-overlay preview
// stays in sync with the native app's themes + default. `USER_THEMES` excludes
// any theme marked `hidden` in tokens.json (matches the native picker list).
function generateDocsWidgetThemes(): string {
  const banner = `/*\n * ${BANNER_LINES.join("\n * ")}\n */`;
  const themes = (tokens.widget?.themes ?? {}) as Record<
    string,
    Record<string, unknown> & { hidden?: boolean }
  >;
  const layouts = tokens.widget?.layouts ?? {};
  const defaultTheme = tokens.widget?.defaultTheme ?? "Default";
  const defaultLayout = tokens.widget?.defaultLayout ?? "Horizontal";
  const userThemes = Object.entries(themes)
    .filter(([, v]) => !v.hidden)
    .map(([k]) => k);
  return [
    banner,
    "",
    `export const WIDGET_THEMES = ${JSON.stringify(themes, null, 2)} as const;`,
    "",
    `export const WIDGET_LAYOUTS = ${JSON.stringify(layouts, null, 2)} as const;`,
    "",
    "export type WidgetThemeName = keyof typeof WIDGET_THEMES;",
    "export type WidgetLayoutName = keyof typeof WIDGET_LAYOUTS;",
    "",
    "/** Themes shown in the picker (excludes `hidden` themes). */",
    `export const USER_THEMES: WidgetThemeName[] = ${JSON.stringify(userThemes)};`,
    "",
    `export const DEFAULT_THEME: WidgetThemeName = ${JSON.stringify(defaultTheme)};`,
    `export const DEFAULT_LAYOUT: WidgetLayoutName = ${JSON.stringify(defaultLayout)};`,
    "",
  ].join("\n");
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
  "apps/native/WolfWave/Core/DesignSystem/Tokens.generated.swift",
  generateSwift()
);
write("apps/docs/app/tokens.generated.css", generateCSS());
write(
  "apps/native/WolfWave/Resources/widget-tokens.generated.js",
  generateWidgetJS()
);
write("apps/marketing/shared/tokens.generated.ts", generateTS());
write(
  "apps/docs/app/(home)/_widgets/widget-themes.generated.ts",
  generateDocsWidgetThemes()
);
console.log("Done.");
