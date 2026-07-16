export const siteUrl = "https://mrdemonwolf.github.io/wolfwave";

/**
 * Canonical GitHub URLs. Single source of truth so the homepage links and the
 * JSON-LD `url` fields never drift on casing. GitHub redirects on casing, but
 * structured-data consumers compare strings literally, so keep one spelling.
 */
export const orgUrl = "https://github.com/MrDemonWolf";
export const repoUrl = "https://github.com/MrDemonWolf/WolfWave";

export const basePath = (() => {
  const envValue = process.env.NEXT_PUBLIC_BASE_PATH;
  if (envValue === undefined) return "/wolfwave";
  if (envValue === "" || envValue === "/") return "";
  let path = envValue;
  try {
    path = new URL(envValue).pathname;
  } catch {}
  if (!path || path === "/") return "";
  const normalized = path.startsWith("/") ? path : `/${path}`;
  return normalized.endsWith("/") ? normalized.slice(0, -1) : normalized;
})();

/** Joins `path` onto the canonical site origin, yielding an absolute URL. */
export function absoluteUrl(path: string): string {
  const clean = path.startsWith("/") ? path : `/${path}`;
  return `${siteUrl}${clean === "/" ? "" : clean}`;
}

/**
 * Build-time fetch of the latest GitHub release tag, normalized to a bare
 * SemVer string (e.g. `2.0.0`). Returns `null` on any failure (rate limit,
 * offline, no releases) so callers can drop the field rather than ship a
 * stale hardcoded version. The static export bakes the result in per deploy.
 */
export async function getLatestVersion(): Promise<string | null> {
  try {
    const res = await fetch(`${repoUrl.replace("https://github.com", "https://api.github.com/repos")}/releases/latest`, {
      headers: {
        Accept: "application/vnd.github+json",
        "User-Agent": "wolfwave-docs",
      },
    });
    if (!res.ok) return null;
    const rel = await res.json();
    if (typeof rel?.tag_name !== "string") return null;
    return rel.tag_name.replace(/^v/, "") || null;
  } catch {
    return null;
  }
}

/**
 * Single source of truth for the homepage / root SEO + social-card copy.
 *
 * Every homepage-facing surface reads from this object so the page metadata,
 * the OG image, and the Twitter image can never drift apart:
 *  - `app/layout.tsx`        root `<title>`, openGraph, twitter, JSON-LD
 *  - `app/(home)/page.tsx`   homepage route metadata
 *  - `app/opengraph-image.tsx` + `app/twitter-image.tsx`  the social card
 *
 * Change the homepage pitch here once and all of the above update on the next
 * build. Per-page docs OG cards are driven separately by each MDX file's
 * frontmatter (see `app/og/docs/[...slug]/route.tsx`).
 */
export const homepageSeo = {
  /** Browser `<title>` and og/twitter title. Keep the keyword-rich phrasing. */
  title: "WolfWave. Free Apple Music to Twitch, Discord & OBS on Mac",

  /** Full meta description used for search snippets. Kept under ~160 chars so
   *  Google does not truncate it. */
  description:
    "Free Mac menu bar app built for Apple Music, not Spotify. Hit play and your Twitch chat, Discord Rich Presence, and OBS overlay stay in sync.",

  /** Shorter description for the social cards (og + twitter). */
  socialDescription:
    "Built for Apple Music, not Spotify. Hit play and your Twitch chat, Discord profile, and OBS overlay keep themselves in sync.",

  /** OG card eyebrow pill. */
  ogEyebrow: "Free & open source · macOS 26+",

  /** OG card headline. `ogAccentWord` is the substring rendered in brand blue. */
  ogTitle: "Apple Music, finally on your stream.",
  ogAccentWord: "on your stream.",

  /** OG card supporting line. Kept short so it lands in ~2 lines on the card. */
  ogCardDescription:
    "A tiny Mac menu bar app. Press play once. Twitch, Discord, and OBS keep up on their own.",

  /** OG card chips. Order matters; first chips read first when cropped. */
  ogChips: ["Twitch chat bot", "Discord Rich Presence", "OBS overlay", "Open source"],

  /** Alt text for the OG image. Describe the card, not just the brand. */
  ogImageAlt:
    "WolfWave. Apple Music now playing pushed to Twitch chat, Discord Rich Presence, and an OBS overlay on macOS.",

  /** Homepage SEO keywords (long-tail, Apple-Music-first). */
  keywords: [
    "apple music twitch chat bot mac",
    "apple music discord rich presence mac",
    "apple music obs overlay mac",
    "apple music song requests twitch",
    "free apple music twitch bot",
    "apple music now playing overlay",
    "macos menu bar music streamer",
    "twitch song requests without spotify premium",
  ],
} as const;
