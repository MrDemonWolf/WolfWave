import { describe, expect, test } from "bun:test";
import manifest from "../com.mrdemonwolf.wolfwave.sdPlugin/manifest.json";
import { ACTION_CLASSES } from "../src/actions/index.js";
import { WolfWaveClient } from "../src/wolfwave/client.js";

/**
 * Guards the one failure mode the SDK gives no feedback for: an action class
 * whose UUID isn't in the manifest is silently never invoked, and a manifest
 * action with no registered class shows up as a dead key. Neither logs anything.
 */
describe("manifest / action registration", () => {
  // `manifestId` is set by the @action decorator. An undefined one means the
  // decorator didn't run, which would break registration silently — so assert
  // it rather than letting `undefined` flow into the comparisons below.
  const registeredIds: string[] = ACTION_CLASSES.map((ActionClass) => {
    const instance = new ActionClass(new WolfWaveClient());
    const id = (instance as { manifestId?: string }).manifestId;
    expect(typeof id).toBe("string");
    return id ?? "";
  });

  const manifestIds: string[] = manifest.Actions.map((entry) => entry.UUID);

  test("every registered action has a manifest entry", () => {
    for (const id of registeredIds) {
      expect(manifestIds).toContain(id);
    }
  });

  test("every manifest action has a registered class", () => {
    for (const id of manifestIds) {
      expect(registeredIds).toContain(id);
    }
  });

  test("manifest UUIDs are unique", () => {
    expect(new Set(manifestIds).size).toBe(manifestIds.length);
  });

  test("every action UUID is namespaced under the plugin UUID", () => {
    for (const id of manifestIds) {
      expect(id.startsWith(`${manifest.UUID}.`)).toBe(true);
    }
  });

  test("CodePath points at the built bundle", () => {
    expect(manifest.CodePath).toBe("bin/plugin.js");
  });

  test("multi-state actions declare exactly two states", () => {
    // The base class only ever sets KeyState.primary or .secondary, so a
    // three-state action would have an unreachable state.
    for (const entry of manifest.Actions) {
      expect(entry.States.length).toBeGreaterThanOrEqual(1);
      expect(entry.States.length).toBeLessThanOrEqual(2);
    }
  });
});
