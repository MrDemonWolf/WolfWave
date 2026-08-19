import { describe, expect, test } from "bun:test";

import { RULES } from "./lint";

const statusColor = RULES.find((r) => r.name === "raw-status-color");

function flags(line: string): boolean {
  if (!statusColor) throw new Error("raw-status-color rule is missing");
  return statusColor.pattern.test(line);
}

describe("raw-status-color", () => {
  test("the rule exists and covers Onboarding", () => {
    expect(statusColor).toBeDefined();
    // Status semantics are universal; Onboarding's separate visual language
    // does not extend to what "off" or "error" is tinted.
    expect(statusColor?.appliesToOnboarding).toBe(true);
  });

  // Every form the migration actually found in the codebase.
  test.each([
    ['StatusChip(text: "On", color: .green, systemImage: g)', "chip, green"],
    ['StatusChip(text: "Off", color: .secondary, systemImage: g)', "chip, translucent secondary"],
    ['StatusChip(text: "Paused", color: .orange)', "chip, no glyph"],
    ["case .stopped:   return .gray", "bare return is NOT caught"],
    ["statusColor: trackingEnabled ? .green : .gray", "ternary in a labeled arg"],
    ["color: Color.gray", "explicit Color. prefix"],
    ["statusColor: .red,", "trailing comma"],
    ["color: .yellow", "yellow"],
    ["color: .blue", "blue"],
  ])("flags %j (%s)", (line, label) => {
    // The bare-return case is the documented blind spot: it carries no argument
    // label, so a line-based rule cannot see it. Asserted here so the limit is
    // recorded rather than discovered later.
    const expected = !label.includes("NOT caught");
    expect(flags(line)).toBe(expected);
  });

  // Deliberate raw colors. A false positive here would force allowlist entries
  // for correct code, which is how a lint rule earns its way to being disabled.
  test.each([
    [".shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)", "shadow black"],
    [".shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 2)", "shadow, Color. prefix"],
    ['StatusChip(text: "Twitch", color: .purple)', "category tag, not a status"],
    ["if updateAvailable { return .accentColor }", "system accent"],
    ["case .stopped: return Color.white.opacity(0.35)", "fixed brand surface"],
    [".foregroundStyle(.secondary)", "body text"],
    ['Text(step).foregroundStyle(.red)', "not a color: label"],
    ["LinearGradient(colors: [.green, .blue], startPoint: .top, endPoint: .bottom)", "colors: is a different label"],
    [".shadow(color: glowColor.opacity(0.40), radius: 11)", "glowColor is not the color: label"],
    ["color: DSColor.neutral", "the fixed form"],
    ["statusColor: DSColor.success,", "the fixed form, labeled"],
  ])("ignores %j (%s)", (line) => {
    expect(flags(line)).toBe(false);
  });
});
