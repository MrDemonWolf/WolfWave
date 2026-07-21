#!/usr/bin/env node
//
// Verifies every Swift file in the native app carries the canonical Xcode file
// header, matching what `WolfWave.xcodeproj/xcshareddata/IDETemplateMacros.plist`
// generates for a new file:
//
//     //
//     //  <FileName>.swift
//     //  WolfWave
//     //
//     //  Created by Nathanial Henniges on <YYYY-MM-DD>.
//     //  Copyright © <year> MrDemonWolf, Inc. All rights reserved.
//     //
//
// Line 3 is the PROJECT name, so test-target files say `WolfWave` too: the
// template uses ___PROJECTNAME___, not ___PACKAGENAME___.
//
// The date must equal the file's creation date per
// `git log --diff-filter=A --follow`. `--follow` is load-bearing: without it a
// file that was later moved reports the move commit instead of its birth.
//
// On a shallow clone (CI checks out with fetch-depth: 2) that history isn't
// present, so the date-equality check is skipped and only the ISO shape is
// enforced. Everything else still runs.
//
// Usage: node scripts/check-headers.mjs

import { execFileSync } from "node:child_process";
import { readdirSync, readFileSync } from "node:fs";
import { basename, join } from "node:path";

const ROOTS = ["apps/native/WolfWave", "apps/native/WolfWaveTests"];
const PROJECT_NAME = "WolfWave";
const AUTHOR = "Nathanial Henniges";
const COPYRIGHT = /^\/\/ {2}Copyright © \d{4} MrDemonWolf, Inc\. All rights reserved\.$/;
const CREATED = /^\/\/ {2}Created by (.+) on (\d{4}-\d{2}-\d{2})\.$/;
const isCI = Boolean(process.env.GITHUB_ACTIONS);

/** Collects every non-generated `.swift` file under `dir`, recursively. */
function collect(dir, out = []) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = join(dir, entry.name);
    if (entry.isDirectory()) collect(full, out);
    else if (entry.name.endsWith(".swift") && !entry.name.endsWith(".generated.swift")) out.push(full);
  }
  return out;
}

/** True when the repo lacks full history, so `--follow` can't be trusted. */
function isShallow() {
  try {
    return execFileSync("git", ["rev-parse", "--is-shallow-repository"], { encoding: "utf8" }).trim() === "true";
  } catch {
    return true;
  }
}

/** The date the file first entered the repo, following renames. */
function createdDate(file) {
  const out = execFileSync(
    "git",
    ["log", "--diff-filter=A", "--follow", "--format=%ad", "--date=short", "-1", "--", file],
    { encoding: "utf8" },
  ).trim();
  return out.split("\n")[0] || "";
}

const failures = [];
/** Records one violation, anchored to the offending line for clickable output. */
function fail(file, line, message) {
  failures.push({ file, line, message });
}

const skipDates = isShallow();
const files = ROOTS.flatMap((root) => collect(root));

for (const file of files) {
  const lines = readFileSync(file, "utf8").split("\n");
  const expectedName = basename(file);

  if (lines[0] !== "//") fail(file, 1, `expected "//", got ${JSON.stringify(lines[0] ?? "")}`);
  if (lines[1] !== `//  ${expectedName}`) {
    fail(file, 2, `expected "//  ${expectedName}", got ${JSON.stringify(lines[1] ?? "")}`);
  }
  if (lines[2] !== `//  ${PROJECT_NAME}`) {
    fail(file, 3, `expected "//  ${PROJECT_NAME}" (project name, not target), got ${JSON.stringify(lines[2] ?? "")}`);
  }
  if (lines[3] !== "//") fail(file, 4, `expected "//", got ${JSON.stringify(lines[3] ?? "")}`);

  const created = CREATED.exec(lines[4] ?? "");
  if (!created) {
    fail(file, 5, `expected "//  Created by ${AUTHOR} on YYYY-MM-DD.", got ${JSON.stringify(lines[4] ?? "")}`);
  } else {
    if (created[1] !== AUTHOR) fail(file, 5, `author must be "${AUTHOR}", got "${created[1]}"`);
    if (!skipDates) {
      const actual = createdDate(file);
      if (actual && created[2] !== actual) {
        fail(file, 5, `date is ${created[2]} but git says the file was created ${actual}`);
      }
    }
  }

  if (!COPYRIGHT.test(lines[5] ?? "")) {
    fail(file, 6, `expected "//  Copyright © <year> MrDemonWolf, Inc. All rights reserved.", got ${JSON.stringify(lines[5] ?? "")}`);
  }
  if (lines[6] !== "//") fail(file, 7, `expected "//", got ${JSON.stringify(lines[6] ?? "")}`);
}

if (skipDates) {
  console.log("note: shallow clone, skipping the date-matches-git check (header shape still enforced)");
}

if (failures.length === 0) {
  console.log(`✅ ${files.length} Swift files carry the canonical header.`);
  process.exit(0);
}

for (const { file, line, message } of failures) {
  console.log(isCI ? `::error file=${file},line=${line}::${message}` : `${file}:${line}: ${message}`);
}
console.log(
  `\n❌ ${failures.length} header problem(s) across ${new Set(failures.map((f) => f.file)).size} file(s).\n` +
    `The canonical header is documented in CLAUDE.md → Code Conventions.`,
);
process.exit(1);
