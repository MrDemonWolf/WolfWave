export const siteUrl = "https://mrdemonwolf.github.io/wolfwave";

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

export function absoluteUrl(path: string): string {
  const clean = path.startsWith("/") ? path : `/${path}`;
  return `${siteUrl}${clean === "/" ? "" : clean}`;
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

  /** OG card supporting line. */
  ogCardDescription:
    "A tiny Mac menu bar app. Hit play once and your Twitch chat, Discord, and OBS overlay keep up on their own.",

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
