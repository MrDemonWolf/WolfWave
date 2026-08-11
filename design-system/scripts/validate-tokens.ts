#!/usr/bin/env bun
/**
 * WolfWave design-token schema check.
 *
 * Validates design-system/tokens.json against design-system/tokens.schema.json
 * and exits non-zero with a pointer-per-error report on failure.
 *
 * Why this is a gate and not just editor tooling: tokens.json is the single
 * source of truth for the generated platform outputs. A typo'd or missing
 * namespace breaks the app, the docs site, the OBS widget, and the marketing
 * projects at once, and generate.ts does not validate shape before emitting.
 * The schema only helps if something actually runs it.
 *
 * The schema uses `additionalProperties: false` at the root, so adding a new
 * top-level namespace to tokens.json deliberately fails here until the schema
 * is updated in the same change. That coupling is the point.
 */

import Ajv from "ajv";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const ROOT = resolve(import.meta.dir, "..", "..");
const TOKENS_PATH = resolve(ROOT, "design-system/tokens.json");
const SCHEMA_PATH = resolve(ROOT, "design-system/tokens.schema.json");

function readJSON(path: string, label: string): unknown {
  let raw: string;
  try {
    raw = readFileSync(path, "utf8");
  } catch (error) {
    console.error(`✘ token schema: cannot read ${label} at ${path}`);
    console.error(`  ${error instanceof Error ? error.message : String(error)}`);
    process.exit(1);
  }
  try {
    return JSON.parse(raw);
  } catch (error) {
    console.error(`✘ token schema: ${label} is not valid JSON`);
    console.error(`  ${error instanceof Error ? error.message : String(error)}`);
    process.exit(1);
  }
}

const schema = readJSON(SCHEMA_PATH, "tokens.schema.json");
const tokens = readJSON(TOKENS_PATH, "tokens.json");

// strict:false because the schema carries $schema/$id metadata keys that Ajv's
// strict mode flags as unknown. allErrors so one run reports every problem
// rather than making you fix them one at a time.
const ajv = new Ajv({ allErrors: true, strict: false });

let validate: ReturnType<typeof ajv.compile>;
try {
  validate = ajv.compile(schema as object);
} catch (error) {
  console.error("✘ token schema: tokens.schema.json is not a compilable JSON Schema");
  console.error(`  ${error instanceof Error ? error.message : String(error)}`);
  process.exit(1);
}

if (validate(tokens)) {
  console.log("✓ token schema: tokens.json matches tokens.schema.json");
  process.exit(0);
}

const errors = validate.errors ?? [];
console.error(`✘ token schema: ${errors.length} error(s) in design-system/tokens.json`);
console.error("");
for (const e of errors) {
  const where = e.instancePath || "(root)";
  const extra =
    e.params && Object.keys(e.params).length > 0
      ? `  ${JSON.stringify(e.params)}`
      : "";
  console.error(`  ${where}  ${e.message}${extra}`);
}
console.error("");
console.error("Fix tokens.json, or update design-system/tokens.schema.json if the shape");
console.error("genuinely changed. Adding a new top-level namespace requires both.");
process.exit(1);
