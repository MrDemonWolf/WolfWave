#!/usr/bin/env node
//
//  release-notes.mjs
//  WolfWave
//
//  Turns one version's section of CHANGELOG.md into a styled, self-contained
//  HTML file that Sparkle embeds in the appcast `<description>` and renders in
//  the in-app update dialog. The release workflow names the output to match the
//  DMG (e.g. WolfWave-2.0.0.html next to WolfWave-2.0.0.dmg) so `generate_appcast`
//  picks it up automatically.
//
//  The "Developer" subsection is dropped: the update dialog is for users, and
//  the full developer notes stay on the web changelog (linked in the footer and
//  via Sparkle's full-release-notes link).
//
//  Usage:
//    node scripts/release-notes.mjs <version> [outputPath]
//
//  Dependency-free ESM. Runs on the plain `node` preinstalled on the macOS CI
//  runner (and on `bun` locally). The CHANGELOG markdown is a constrained subset
//  (### headings, - bullets, **bold**, _italics_, `code`, [links](url)), so a
//  small renderer is enough and keeps the release pipeline free of npm installs.
//

import { readFileSync, writeFileSync } from "node:fs";

// MARK: - Args

const version = process.argv[2];
const outputPath = process.argv[3] ?? `WolfWave-${version}.html`;

if (!version) {
  console.error("usage: release-notes.mjs <version> [outputPath]");
  process.exit(1);
}

const CHANGELOG_URL = new URL("../CHANGELOG.md", import.meta.url);
const FULL_CHANGELOG_URL = "https://mrdemonwolf.github.io/wolfwave/docs/changelog";

// MARK: - Extract the version's section

/// Returns the lines of the `## [<version>] ...` block, exclusive of its own
/// heading and stopping before the next `## [` heading. Null if not found.
function extractSection(markdown, version) {
  const lines = markdown.split("\n");
  // Match `## [2.0.0]` exactly so 2.0.0 never grabs 2.0.0-beta or 12.0.0.
  const start = lines.findIndex((l) =>
    new RegExp(`^##\\s+\\[${escapeRegExp(version)}\\]`).test(l)
  );
  if (start === -1) return null;

  const rest = lines.slice(start + 1);
  let end = rest.findIndex((l) => /^##\s+\[/.test(l));
  if (end === -1) end = rest.length;
  return rest.slice(0, end);
}

/// Drops the `### Developer` subsection (heading + its blockquote + bullets)
/// up to the next `###` heading, leaving the user-facing categories intact.
function stripDeveloperSection(lines) {
  const dev = lines.findIndex((l) => /^###\s+Developer\b/i.test(l));
  if (dev === -1) return lines;

  const after = lines.slice(dev + 1);
  let next = after.findIndex((l) => /^###\s+/.test(l));
  if (next === -1) next = after.length;
  return [...lines.slice(0, dev), ...lines.slice(dev + 1 + next)];
}

function escapeRegExp(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

// MARK: - Markdown subset to HTML

function escapeHtml(s) {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

/// Applies bold and italic to already-escaped plain text. Never runs on code
/// span contents, so underscores in identifiers like `GITHUB_REPO_OWNER` and
/// asterisks inside code are left alone.
function renderEmphasis(escaped) {
  return escaped
    .replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>")
    .replace(/_([^_]+)_/g, "<em>$1</em>");
}

/// Inline rendering. Walks the text segment by segment: code spans and links
/// are emitted verbatim (content escaped, no emphasis), and the plain text
/// between them gets bold/italic. No placeholders, so nothing can collide with
/// real numbers or merge with adjacent characters.
function renderInline(text) {
  const re = /`([^`]+)`|\[([^\]]+)\]\(([^)]+)\)/g;
  let out = "";
  let last = 0;
  let m;
  while ((m = re.exec(text)) !== null) {
    if (m.index > last) {
      out += renderEmphasis(escapeHtml(text.slice(last, m.index)));
    }
    if (m[1] !== undefined) {
      out += `<code>${escapeHtml(m[1])}</code>`;
    } else {
      out += `<a href="${escapeHtml(m[3])}">${renderEmphasis(escapeHtml(m[2]))}</a>`;
    }
    last = re.lastIndex;
  }
  if (last < text.length) {
    out += renderEmphasis(escapeHtml(text.slice(last)));
  }
  return out;
}

/// Block rendering for the constrained CHANGELOG subset.
function renderBlocks(lines) {
  const out = [];
  let inList = false;
  const closeList = () => {
    if (inList) {
      out.push("</ul>");
      inList = false;
    }
  };

  for (const raw of lines) {
    const line = raw.replace(/\s+$/, "");
    if (line === "") {
      closeList();
      continue;
    }
    const heading = line.match(/^###\s+(.+)$/);
    if (heading) {
      closeList();
      out.push(`<h2>${renderInline(heading[1])}</h2>`);
      continue;
    }
    const quote = line.match(/^>\s?(.*)$/);
    if (quote) {
      closeList();
      out.push(`<blockquote>${renderInline(quote[1])}</blockquote>`);
      continue;
    }
    const bullet = line.match(/^-\s+(.+)$/);
    if (bullet) {
      if (!inList) {
        out.push("<ul>");
        inList = true;
      }
      out.push(`<li>${renderInline(bullet[1])}</li>`);
      continue;
    }
    closeList();
    out.push(`<p>${renderInline(line)}</p>`);
  }
  closeList();
  return out.join("\n");
}

// MARK: - Document shell

function document(version, bodyHtml) {
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  :root {
    --bg: #ffffff;
    --txt: #1d1d1f;
    --muted: #6e6e73;
    --brand: #7c5cff;
    --hairline: rgba(0, 0, 0, 0.1);
    --code-bg: rgba(124, 92, 255, 0.1);
  }
  @media (prefers-color-scheme: dark) {
    :root {
      --bg: #1c1c1e;
      --txt: #f5f5f7;
      --muted: #9a9aa0;
      --brand: #a78bff;
      --hairline: rgba(255, 255, 255, 0.12);
      --code-bg: rgba(167, 139, 255, 0.16);
    }
  }
  * { box-sizing: border-box; }
  html, body { margin: 0; padding: 0; }
  body {
    background: var(--bg);
    color: var(--txt);
    font: 13px/1.5 -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif;
    padding: 16px 20px 24px;
    -webkit-font-smoothing: antialiased;
  }
  header { margin-bottom: 4px; }
  .version {
    font-size: 20px;
    font-weight: 700;
    letter-spacing: -0.01em;
    margin: 0;
  }
  .tagline { color: var(--muted); margin: 2px 0 14px; font-size: 12px; }
  h2 {
    font-size: 11px;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    color: var(--brand);
    margin: 18px 0 6px;
    padding-top: 12px;
    border-top: 1px solid var(--hairline);
  }
  header + h2 { border-top: 0; padding-top: 0; margin-top: 8px; }
  ul { margin: 0 0 4px; padding-left: 18px; }
  li { margin: 5px 0; }
  p { margin: 8px 0; }
  blockquote {
    margin: 8px 0;
    padding-left: 12px;
    border-left: 2px solid var(--hairline);
    color: var(--muted);
  }
  strong { font-weight: 650; }
  code {
    font-family: "SF Mono", ui-monospace, Menlo, monospace;
    font-size: 0.88em;
    background: var(--code-bg);
    color: var(--brand);
    padding: 1px 5px;
    border-radius: 5px;
  }
  a { color: var(--brand); text-decoration: none; }
  a:hover { text-decoration: underline; }
  footer {
    margin-top: 22px;
    padding-top: 12px;
    border-top: 1px solid var(--hairline);
    font-size: 12px;
    color: var(--muted);
  }
</style>
</head>
<body>
<header>
  <p class="version">WolfWave ${escapeHtml(version)}</p>
  <p class="tagline">What's new in this release</p>
</header>
${bodyHtml}
<footer>
  Read the full changelog at
  <a href="${FULL_CHANGELOG_URL}">mrdemonwolf.github.io/wolfwave</a>.
</footer>
</body>
</html>
`;
}

/// Minimal fallback when a version has no CHANGELOG section yet. Keeps a release
/// from failing just because notes are missing; points users at the web list.
function fallbackDocument(version) {
  return document(
    version,
    `<p>This release is now available. See the full list of changes on the web changelog.</p>`
  );
}

// MARK: - Main

const markdown = readFileSync(CHANGELOG_URL, "utf8");
let section = extractSection(markdown, version);

let html;
if (!section) {
  console.warn(
    `release-notes: no "## [${version}]" section in CHANGELOG.md. Writing fallback notes.`
  );
  html = fallbackDocument(version);
} else {
  section = stripDeveloperSection(section);
  html = document(version, renderBlocks(section));
}

writeFileSync(outputPath, html, "utf8");
console.log(`release-notes: wrote ${outputPath} (${html.length} bytes)`);
