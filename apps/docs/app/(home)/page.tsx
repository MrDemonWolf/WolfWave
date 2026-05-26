import type { Metadata } from "next";
import Link from "next/link";
import { absoluteUrl } from "@/lib/site";
import {
  ArrowRight,
  Check,
  Download,
  Github,
  Minus,
  Radio,
  Wifi,
  Shield,
  Music,
  Code2,
  Headphones,
  Twitch,
  X as XIcon,
} from "lucide-react";

export const metadata: Metadata = {
  title: "WolfWave — Free Apple Music to Twitch, Discord & OBS on Mac",
  description:
    "Stop telling chat what song is playing. WolfWave puts your Apple Music track into Twitch chat, Discord Rich Presence, and your OBS overlay — automatically. Free, native macOS, open source.",
  keywords: [
    "apple music twitch chat bot mac",
    "apple music discord rich presence mac",
    "apple music obs overlay mac",
    "apple music song requests twitch",
    "free apple music twitch bot",
    "spotchbot alternative apple music",
    "macos menu bar music streamer",
    "twitch song requests without spotify premium",
  ],
  alternates: { canonical: absoluteUrl("/") },
  openGraph: {
    type: "website",
    url: absoluteUrl("/"),
    siteName: "WolfWave",
    title: "WolfWave — Free Apple Music to Twitch, Discord & OBS on Mac",
    description:
      "Stop telling chat what song is playing. WolfWave bridges Apple Music with Twitch chat, Discord Rich Presence, and your stream overlay — automatically.",
    images: [
      {
        url: absoluteUrl("/opengraph-image.png"),
        width: 1200,
        height: 630,
        alt: "WolfWave — Apple Music to Twitch, Discord, and OBS overlay on macOS",
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    site: "@mrdemonwolf",
    creator: "@mrdemonwolf",
    title: "WolfWave — Free Apple Music to Twitch, Discord & OBS on Mac",
    description:
      "Stop telling chat what song is playing. WolfWave bridges Apple Music with Twitch chat, Discord Rich Presence, and your stream overlay — automatically.",
    images: [absoluteUrl("/opengraph-image.png")],
  },
};

// ── Now Playing mock (used in hero) ──────────────────────────
function NowPlayingMock() {
  return (
    <div className="ww-pulse-ring ww-card w-full max-w-md mx-auto">
      <div className="flex items-center gap-4">
        <div
          className="w-16 h-16 rounded-xl shrink-0"
          style={{ background: "linear-gradient(135deg, #0A84FF, #5AC8FA)" }}
          aria-hidden="true"
        />
        <div className="min-w-0 flex-1">
          <p className="ww-text-1 text-base font-semibold truncate">Kbps Plz</p>
          <p className="ww-text-2 text-sm truncate">DevBowzer · Album Vol. 2</p>
          <div
            className="h-1 rounded-full mt-3"
            style={{ backgroundColor: "var(--hairline)" }}
          >
            <div
              className="h-1 rounded-full"
              style={{ width: "62%", backgroundColor: "var(--brand-500)" }}
            />
          </div>
          <div className="flex justify-between mt-1.5 text-xs ww-text-2">
            <span>2:07</span>
            <span>3:20</span>
          </div>
        </div>
      </div>
      <div
        className="mt-5 pt-4 flex items-center justify-between border-t"
        style={{ borderColor: "var(--hairline)" }}
      >
        <div className="flex items-center gap-2">
          <span className="ww-pill">
            <Twitch className="w-3 h-3" /> Twitch
          </span>
          <span className="ww-pill">
            <Radio className="w-3 h-3" /> Discord
          </span>
          <span className="ww-pill">
            <Wifi className="w-3 h-3" /> Overlay
          </span>
        </div>
      </div>
    </div>
  );
}

// ── Section heading helper ───────────────────────────────────
function SectionHead({
  eyebrow,
  title,
  sub,
  align = "center",
}: {
  eyebrow?: string;
  title: React.ReactNode;
  sub?: React.ReactNode;
  align?: "center" | "left";
}) {
  return (
    <div className={`max-w-3xl ${align === "center" ? "mx-auto text-center" : ""}`}>
      {eyebrow ? (
        <p
          className="ww-text-brand text-sm font-semibold mb-3"
          style={{ letterSpacing: "-0.005em" }}
        >
          {eyebrow}
        </p>
      ) : null}
      <h2 className="ww-display ww-text-1 text-4xl sm:text-5xl lg:text-6xl">
        {title}
      </h2>
      {sub ? (
        <p className="ww-text-2 text-lg sm:text-xl mt-5 leading-relaxed">
          {sub}
        </p>
      ) : null}
    </div>
  );
}

// ── Comparison cell ──────────────────────────────────────────
type CellState = "yes" | "no" | "partial";

function CompareCell({ state, label }: { state: CellState; label?: string }) {
  const tone =
    state === "yes"
      ? { bg: "var(--brand-50)", color: "var(--brand-500)" }
      : state === "partial"
        ? { bg: "var(--bg-surface)", color: "var(--txt-2)" }
        : { bg: "var(--bg-surface)", color: "var(--txt-2)" };
  const Icon = state === "yes" ? Check : state === "partial" ? Minus : XIcon;
  return (
    <div className="flex items-center justify-center gap-1.5">
      <span
        className="inline-flex items-center justify-center w-7 h-7 rounded-full"
        style={{ backgroundColor: tone.bg, color: tone.color }}
        aria-label={state === "yes" ? "Yes" : state === "no" ? "No" : "Partial"}
      >
        <Icon className="w-3.5 h-3.5" aria-hidden="true" />
      </span>
      {label ? <span className="text-xs ww-text-2">{label}</span> : null}
    </div>
  );
}

// ── FAQ row (native details/summary, token-styled) ───────────
function FaqRow({ q, a }: { q: string; a: React.ReactNode }) {
  return (
    <details
      className="group ww-card ww-bg-base"
      style={{ border: "1px solid var(--hairline)" }}
    >
      <summary
        className="cursor-pointer list-none flex items-center justify-between gap-4"
        style={{ fontWeight: 600 }}
      >
        <span className="ww-text-1 text-base sm:text-lg">{q}</span>
        <span
          className="ww-text-2 text-2xl leading-none transition-transform group-open:rotate-45"
          aria-hidden="true"
        >
          +
        </span>
      </summary>
      <div className="mt-4 ww-text-2 text-base leading-relaxed">{a}</div>
    </details>
  );
}

export default function HomePage() {
  return (
    <main className="ww-font ww-bg-base">
      {/* ═══════════════ HERO ═══════════════ */}
      <section className="relative overflow-hidden">
        <div className="ww-hero-glow" aria-hidden="true" />
        <div className="relative z-10 px-6 pt-24 pb-20 sm:pt-32 sm:pb-28">
          <div className="mx-auto max-w-4xl text-center">
            <p className="ww-reveal ww-reveal-1 ww-text-brand text-sm font-semibold mb-5">
              Now available · macOS 26+ · Apple Music
            </p>
            {/*
              Hero headline — primary live, alternate kept for A/B reference.
              Alt: "Stop announcing every song you play."
            */}
            <h1 className="ww-reveal ww-reveal-1 ww-display ww-text-1 text-5xl sm:text-7xl lg:text-[5.5rem]">
              Stop telling chat
              <br />
              <span className="ww-text-brand">what song is playing.</span>
            </h1>
            <p className="ww-reveal ww-reveal-2 ww-text-2 text-lg sm:text-xl mt-7 max-w-2xl mx-auto leading-relaxed">
              WolfWave is a tiny Mac menu bar app. Play something in Apple
              Music — your Twitch chat, your Discord profile, and your stream
              overlay all update on their own.
            </p>
            <div className="ww-reveal ww-reveal-3 mt-10 flex flex-col sm:flex-row items-center justify-center gap-3">
              <Link href="/download" className="ww-btn ww-btn-primary">
                <Download className="w-4 h-4" />
                Download for Mac
              </Link>
              <Link href="/docs" className="ww-btn ww-btn-secondary">
                See how it works
                <ArrowRight className="w-4 h-4" />
              </Link>
            </div>
            <p className="mt-5 text-sm ww-text-2">
              Free and open source · ~10 MB · No account needed · macOS 26+ · Apple Silicon
            </p>

            {/* Trust strip — credibility badges, no fabricated quotes */}
            <div className="ww-reveal ww-reveal-3 mt-8 flex flex-wrap items-center justify-center gap-2">
              <a
                href="https://github.com/MrDemonWolf/WolfWave"
                target="_blank"
                rel="noopener noreferrer"
                className="ww-pill"
                aria-label="View WolfWave on GitHub"
              >
                <Github className="w-3 h-3" /> Open source · MIT
              </a>
              <span className="ww-pill">
                <Shield className="w-3 h-3" /> Signed &amp; notarized by Apple
              </span>
              <a
                href="https://mrdwolf.net/discord"
                target="_blank"
                rel="noopener noreferrer"
                className="ww-pill"
                aria-label="Join the Discord community"
              >
                <Radio className="w-3 h-3" /> Discord community
              </a>
            </div>
          </div>

          <div className="mt-16 sm:mt-20 ww-reveal ww-reveal-3">
            <NowPlayingMock />
          </div>
        </div>
      </section>

      {/* ═══════════════ AUDIENCES ═══════════════ */}
      <section className="ww-bg-surface px-6 py-24 sm:py-32">
        <div className="mx-auto max-w-6xl">
          <SectionHead
            eyebrow="Made for everyone"
            title={<>Three people. One app.</>}
            sub="Whether you stream, listen, or build, WolfWave fits the way you already work."
          />

          <div className="mt-14 grid md:grid-cols-3 gap-5">
            {[
              {
                icon: Twitch,
                title: "For streamers",
                body: "Chat answers itself. !song, song requests, and a live overlay are ready the moment you finish setup.",
                href: "/docs/usage",
                cta: "Streaming guide",
              },
              {
                icon: Headphones,
                title: "For listeners",
                body: "Friends see your taste — album art, live progress, and your full Apple Music library right on your Discord profile.",
                href: "/docs/features",
                cta: "What's included",
              },
              {
                icon: Code2,
                title: "For developers",
                body: "Real-time data, your overlay. A local WebSocket exposes every play, pause, and skip — wire it up in roughly 20 lines.",
                href: "/docs/architecture",
                cta: "Read the architecture",
              },
            ].map(({ icon: Icon, title, body, href, cta }) => (
              <div
                key={title}
                className="ww-card ww-card-hover ww-bg-base flex flex-col"
                style={{
                  border: "1px solid var(--hairline)",
                }}
              >
                <div
                  className="w-11 h-11 rounded-xl inline-flex items-center justify-center mb-5"
                  style={{
                    backgroundColor: "var(--brand-50)",
                    color: "var(--brand-500)",
                  }}
                >
                  <Icon className="w-5 h-5" />
                </div>
                <h3 className="ww-display ww-text-1 text-xl mb-2">{title}</h3>
                <p className="ww-text-2 text-base leading-relaxed flex-1">
                  {body}
                </p>
                <Link
                  href={href}
                  className="ww-text-brand mt-5 inline-flex items-center gap-1.5 text-sm font-semibold"
                >
                  {cta}
                  <ArrowRight className="w-3.5 h-3.5" />
                </Link>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* ═══════════════ TWITCH ═══════════════ */}
      <section className="ww-bg-base px-6 py-24 sm:py-32">
        <div className="mx-auto max-w-6xl grid md:grid-cols-2 gap-12 lg:gap-16 items-center">
          <div>
            <p className="ww-text-brand text-sm font-semibold mb-3">
              Twitch integration
            </p>
            <h2 className="ww-display ww-text-1 text-4xl sm:text-5xl">
              Chat that knows the song.
            </h2>
            <p className="ww-text-2 text-lg mt-5 leading-relaxed">
              When viewers type <code className="ww-mono ww-text-1">!song</code>,
              WolfWave answers in under a second. Title, artist, album —
              straight from Apple Music. No bots to set up. No browser tabs to
              babysit.
            </p>
            <Link
              href="/docs/bot-commands"
              className="ww-text-brand mt-6 inline-flex items-center gap-1.5 text-sm font-semibold"
            >
              Bot commands reference
              <ArrowRight className="w-3.5 h-3.5" />
            </Link>
          </div>

          <div
            className="ww-card ww-bg-surface space-y-3 text-sm"
            aria-label="Twitch chat preview"
          >
            <div className="flex gap-2">
              <span className="font-semibold" style={{ color: "#9146FF" }}>
                viewer_42
              </span>
              <span className="ww-text-2">!song</span>
            </div>
            <div className="flex gap-2">
              <span className="font-semibold ww-text-brand">WolfWave</span>
              <span className="ww-text-1">
                Now playing: <strong>Kbps Plz</strong> by DevBowzer · Album Vol. 2
              </span>
            </div>
            <div className="flex gap-2">
              <span className="font-semibold" style={{ color: "#9146FF" }}>
                streamer_dev
              </span>
              <span className="ww-text-2">this slaps 🔥</span>
            </div>
          </div>
        </div>
      </section>

      {/* ═══════════════ DISCORD ═══════════════ */}
      <section className="ww-bg-surface px-6 py-24 sm:py-32">
        <div className="mx-auto max-w-6xl grid md:grid-cols-2 gap-12 lg:gap-16 items-center">
          <div
            className="ww-card ww-bg-base order-2 md:order-1"
            style={{ border: "1px solid var(--hairline)" }}
          >
            <p className="ww-mono text-xs ww-text-2 mb-3">
              LISTENING TO APPLE MUSIC
            </p>
            <div className="flex gap-3 items-center">
              <div
                className="w-16 h-16 rounded-lg shrink-0"
                style={{ background: "linear-gradient(135deg, #5865F2, #0A84FF)" }}
                aria-hidden="true"
              />
              <div className="min-w-0 flex-1">
                <p className="ww-text-1 text-base font-semibold truncate">
                  Kbps Plz
                </p>
                <p className="ww-text-2 text-sm truncate">DevBowzer</p>
                <div
                  className="h-1 rounded-full mt-3"
                  style={{ backgroundColor: "var(--hairline)" }}
                >
                  <div
                    className="h-1 rounded-full"
                    style={{
                      width: "62%",
                      background: "linear-gradient(to right, #5865F2, #0A84FF)",
                    }}
                  />
                </div>
              </div>
            </div>
          </div>

          <div className="order-1 md:order-2">
            <p className="ww-text-brand text-sm font-semibold mb-3">
              Discord Rich Presence
            </p>
            <h2 className="ww-display ww-text-1 text-4xl sm:text-5xl">
              Your friends see what you're listening to.
            </h2>
            <p className="ww-text-2 text-lg mt-5 leading-relaxed">
              Real Rich Presence — album art, live progress, and a click-through
              to your library. Like Spotify, but for everything you actually own
              in Apple Music.
            </p>
            <Link
              href="/docs/features"
              className="ww-text-brand mt-6 inline-flex items-center gap-1.5 text-sm font-semibold"
            >
              See every feature
              <ArrowRight className="w-3.5 h-3.5" />
            </Link>
          </div>
        </div>
      </section>

      {/* ═══════════════ OVERLAY ═══════════════ */}
      <section className="ww-bg-base px-6 py-24 sm:py-32">
        <div className="mx-auto max-w-6xl grid md:grid-cols-2 gap-12 lg:gap-16 items-center">
          <div>
            <p className="ww-text-brand text-sm font-semibold mb-3">
              Stream overlay
            </p>
            <h2 className="ww-display ww-text-1 text-4xl sm:text-5xl">
              A now-playing card for OBS in 30 seconds.
            </h2>
            <p className="ww-text-2 text-lg mt-5 leading-relaxed">
              Add a browser source pointing at your Mac's local server. Pick a
              theme or write your own — every track update streams in real time
              over WebSocket.
            </p>
            <Link
              href="/docs/usage"
              className="ww-text-brand mt-6 inline-flex items-center gap-1.5 text-sm font-semibold"
            >
              Set up the overlay
              <ArrowRight className="w-3.5 h-3.5" />
            </Link>
          </div>

          <div
            className="rounded-2xl overflow-hidden"
            style={{ border: "1px solid var(--hairline)" }}
          >
            <div
              className="px-4 py-2.5 flex items-center gap-2 text-xs ww-mono ww-text-2"
              style={{
                backgroundColor: "var(--bg-surface)",
                borderBottom: "1px solid var(--hairline)",
              }}
            >
              <span className="w-2.5 h-2.5 rounded-full" style={{ background: "#ff5f57" }} />
              <span className="w-2.5 h-2.5 rounded-full" style={{ background: "#febc2e" }} />
              <span className="w-2.5 h-2.5 rounded-full" style={{ background: "#28c840" }} />
              <span className="ml-2">localhost:8080/now-playing</span>
            </div>
            <div className="ww-bg-surface p-6 flex items-center gap-4">
              <div
                className="w-14 h-14 rounded-lg shrink-0"
                style={{ background: "linear-gradient(135deg, #0A84FF, #5AC8FA)" }}
              />
              <div className="min-w-0">
                <p className="ww-text-1 text-sm font-semibold truncate">
                  Kbps Plz
                </p>
                <p className="ww-text-2 text-xs truncate">DevBowzer</p>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* ═══════════════ COMPARISON ═══════════════ */}
      <section className="ww-bg-surface px-6 py-24 sm:py-32">
        <div className="mx-auto max-w-6xl">
          <SectionHead
            eyebrow="Honest comparison"
            title={<>WolfWave vs. the rest.</>}
            sub="Built for people who use Apple Music — not Spotify. Free, native, and yours to fork."
          />

          <div className="mt-12 overflow-x-auto">
            <div
              className="ww-card ww-bg-base min-w-[640px]"
              style={{ border: "1px solid var(--hairline)" }}
            >
              <table className="w-full text-sm">
                <thead>
                  <tr
                    style={{
                      borderBottom: "1px solid var(--hairline)",
                    }}
                  >
                    <th
                      className="text-left py-4 pr-4 ww-text-2 font-medium"
                      scope="col"
                    >
                      Feature
                    </th>
                    <th
                      className="text-center py-4 px-3 ww-text-brand font-semibold"
                      scope="col"
                    >
                      WolfWave
                    </th>
                    <th
                      className="text-center py-4 px-3 ww-text-2 font-medium"
                      scope="col"
                    >
                      Browser source widgets
                    </th>
                    <th
                      className="text-center py-4 pl-3 ww-text-2 font-medium"
                      scope="col"
                    >
                      Spotify-only bots
                    </th>
                  </tr>
                </thead>
                <tbody>
                  {[
                    {
                      feature: "Apple Music support",
                      ww: "yes",
                      browser: "partial",
                      spotify: "no",
                    },
                    {
                      feature: "Native macOS app",
                      ww: "yes",
                      browser: "no",
                      spotify: "no",
                    },
                    {
                      feature: "Free, no paywall",
                      ww: "yes",
                      browser: "partial",
                      spotify: "partial",
                    },
                    {
                      feature: "Chat song requests",
                      ww: "yes",
                      browser: "no",
                      spotify: "yes",
                    },
                    {
                      feature: "Stream overlay included",
                      ww: "yes",
                      browser: "yes",
                      spotify: "no",
                    },
                    {
                      feature: "Discord Rich Presence",
                      ww: "yes",
                      browser: "no",
                      spotify: "no",
                    },
                    {
                      feature: "Open source",
                      ww: "yes",
                      browser: "partial",
                      spotify: "no",
                    },
                  ].map((row, i, arr) => (
                    <tr
                      key={row.feature}
                      style={
                        i < arr.length - 1
                          ? { borderBottom: "1px solid var(--hairline)" }
                          : undefined
                      }
                    >
                      <td className="py-4 pr-4 ww-text-1">{row.feature}</td>
                      <td className="py-4 px-3">
                        <CompareCell state={row.ww as CellState} />
                      </td>
                      <td className="py-4 px-3">
                        <CompareCell state={row.browser as CellState} />
                      </td>
                      <td className="py-4 pl-3">
                        <CompareCell state={row.spotify as CellState} />
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>

          <p className="mt-5 text-center text-xs ww-text-2">
            Partial means "depends on the tool / depends on your plan." See the{" "}
            <Link href="/docs/features" className="ww-text-brand font-semibold">
              full feature breakdown
            </Link>
            .
          </p>
        </div>
      </section>

      {/* ═══════════════ DEVELOPERS ═══════════════ */}
      <section className="ww-bg-base px-6 py-24 sm:py-32">
        <div className="mx-auto max-w-5xl">
          <SectionHead
            eyebrow="For developers"
            title={<>Native Swift. Open source.</>}
            sub="The WebSocket feed is fully documented — wire it into your overlay, your Home Assistant dashboard, or a Stream Deck plugin."
          />

          <div className="mt-12">
            <pre
              className="ww-code"
              dangerouslySetInnerHTML={{
                __html: `<span style="color: var(--txt-2)">// Subscribe to every track change in real time.</span>
<span style="color: var(--brand-500)">const</span> ws = <span style="color: var(--brand-500)">new</span> WebSocket(<span style="color: var(--brand-500)">"ws://localhost:8080/now-playing"</span>);

ws.onmessage = (event) =&gt; {
  <span style="color: var(--brand-500)">const</span> { title, artist, artwork } = JSON.parse(event.data);
  document.querySelector(<span style="color: var(--brand-500)">"#title"</span>).textContent = title;
};`,
              }}
            />
          </div>

          <div className="mt-10 flex flex-wrap items-center justify-center gap-3">
            <Link href="/docs/architecture" className="ww-btn ww-btn-ghost">
              Architecture
            </Link>
            <Link href="/docs/development" className="ww-btn ww-btn-ghost">
              Development guide
            </Link>
            <Link href="/docs/security" className="ww-btn ww-btn-ghost">
              Security model
            </Link>
            <a
              href="https://github.com/MrDemonWolf/WolfWave"
              target="_blank"
              rel="noopener noreferrer"
              className="ww-btn ww-btn-ghost"
            >
              <Github className="w-4 h-4" />
              GitHub
            </a>
          </div>
        </div>
      </section>

      {/* ═══════════════ BADGES ═══════════════ */}
      <section className="ww-bg-surface px-6 py-20">
        <div className="mx-auto max-w-5xl">
          <div
            className="ww-card ww-bg-base flex flex-wrap items-center justify-center gap-3"
            style={{ border: "1px solid var(--hairline)" }}
          >
            <a
              href="https://github.com/MrDemonWolf/WolfWave"
              target="_blank"
              rel="noopener noreferrer"
              aria-label="GitHub stars"
            >
              <img
                src="https://img.shields.io/github/stars/MrDemonWolf/WolfWave?style=flat&color=0A84FF&labelColor=1C1C1E&logo=github"
                alt="GitHub stars"
                height={28}
              />
            </a>
            <a
              href="https://github.com/MrDemonWolf/WolfWave/blob/main/LICENSE"
              target="_blank"
              rel="noopener noreferrer"
              aria-label="MIT license"
            >
              <img
                src="https://img.shields.io/github/license/MrDemonWolf/WolfWave?color=0A84FF&labelColor=1C1C1E"
                alt="MIT license"
                height={28}
              />
            </a>
            <a
              href="https://github.com/MrDemonWolf/WolfWave/releases/latest"
              target="_blank"
              rel="noopener noreferrer"
              aria-label="Latest release"
            >
              <img
                src="https://img.shields.io/github/v/release/MrDemonWolf/WolfWave?color=0A84FF&labelColor=1C1C1E&label=latest"
                alt="Latest release"
                height={28}
              />
            </a>
            <a
              href="https://mrdwolf.net/discord"
              target="_blank"
              rel="noopener noreferrer"
              aria-label="Discord community"
            >
              <img
                src="https://img.shields.io/badge/discord-community-0A84FF?labelColor=1C1C1E&logo=discord&logoColor=white"
                alt="Discord community"
                height={28}
              />
            </a>
            <span className="ww-pill">
              <Shield className="w-3 h-3" /> Signed by Apple
            </span>
            <span className="ww-pill">macOS 26+ · Apple Silicon</span>
          </div>
        </div>
      </section>

      {/* ═══════════════ PRIVACY ═══════════════ */}
      <section className="ww-bg-base px-6 py-24 sm:py-32">
        <div className="mx-auto max-w-3xl text-center">
          <div
            className="w-12 h-12 rounded-2xl inline-flex items-center justify-center mb-6"
            style={{
              backgroundColor: "var(--brand-50)",
              color: "var(--brand-500)",
            }}
          >
            <Shield className="w-5 h-5" />
          </div>
          <h2 className="ww-display ww-text-1 text-4xl sm:text-5xl">
            Private by default.
          </h2>
          <p className="ww-text-2 text-lg mt-5 leading-relaxed">
            Your music never leaves your Mac. Tokens live in macOS Keychain.
            The app runs sandboxed. There's no telemetry — there's nothing to
            send.
          </p>
          <div className="mt-8 flex flex-wrap items-center justify-center gap-2">
            {["Sandboxed", "Keychain", "No telemetry", "MIT licensed"].map(
              (label) => (
                <span key={label} className="ww-pill">
                  {label}
                </span>
              ),
            )}
          </div>
        </div>
      </section>

      {/* ═══════════════ FAQ ═══════════════ */}
      <section className="ww-bg-surface px-6 py-24 sm:py-32">
        <div className="mx-auto max-w-3xl">
          <SectionHead
            eyebrow="Questions, answered"
            title={<>Anything else?</>}
            sub="The short answers. Longer ones live in the docs."
          />

          <div className="mt-12 space-y-3">
            <FaqRow
              q="Does it work with Spotify?"
              a={
                <>
                  No. WolfWave reads Apple Music via ScriptingBridge — the same
                  framework Apple uses internally. If your streaming setup is
                  Spotify-first, this is not the right tool.
                </>
              }
            />
            <FaqRow
              q="Will my viewers see ads or upsells?"
              a={
                <>
                  Never. WolfWave is free and open source. No ads, no premium
                  tier, no upsell screens. If you want to give back,{" "}
                  <Link href="/docs/support" className="ww-text-brand font-semibold">
                    sponsor the project
                  </Link>
                  .
                </>
              }
            />
            <FaqRow
              q="Does it slow down my stream?"
              a={
                <>
                  No. The app is native, under 30 MB, and event-driven — it
                  reacts to Apple Music's own notifications with a 2-second
                  fallback poll. CPU and memory impact are negligible during a
                  stream.
                </>
              }
            />
            <FaqRow
              q="Is my Twitch token safe?"
              a={
                <>
                  Yes. WolfWave uses Twitch's OAuth Device Code flow, stores
                  tokens in macOS Keychain (the same place Safari and Mail keep
                  your passwords), and never writes them to disk in plaintext.
                  The app is sandboxed and notarized by Apple.
                </>
              }
            />
            <FaqRow
              q="Does it work on Intel Macs?"
              a={
                <>
                  No. WolfWave requires Apple Silicon (M1 or later) running
                  macOS 26 (Tahoe) or newer. Intel Macs are not supported.
                </>
              }
            />
            <FaqRow
              q="Can I use it on a second-PC OBS setup?"
              a={
                <>
                  Yes. The local WebSocket binds to all interfaces, so an OBS
                  machine on the same LAN can connect to your Mac as a browser
                  source. Every connection presents a per-install token from
                  Keychain — see the{" "}
                  <Link href="/docs/security" className="ww-text-brand font-semibold">
                    security docs
                  </Link>
                  .
                </>
              }
            />
            <FaqRow
              q="How do updates work?"
              a={
                <>
                  WolfWave uses Sparkle with EdDSA-signed appcasts — same
                  framework Things, Tower, and many other Mac apps use.
                  Homebrew installs are managed by Homebrew instead, and you'll
                  get notified when a new release lands.
                </>
              }
            />
            <FaqRow
              q="Is it really free?"
              a={
                <>
                  Yes. MIT licensed, no paywall, no premium tier. The whole
                  source is on{" "}
                  <a
                    href="https://github.com/MrDemonWolf/WolfWave"
                    target="_blank"
                    rel="noopener noreferrer"
                    className="ww-text-brand font-semibold"
                  >
                    GitHub
                  </a>
                  .
                </>
              }
            />
          </div>

          <p className="mt-10 text-center text-sm ww-text-2">
            More questions?{" "}
            <Link href="/docs/faq" className="ww-text-brand font-semibold">
              Read the full FAQ
            </Link>{" "}
            or{" "}
            <a
              href="https://mrdwolf.net/discord"
              target="_blank"
              rel="noopener noreferrer"
              className="ww-text-brand font-semibold"
            >
              ask in Discord
            </a>
            .
          </p>
        </div>
      </section>

      {/* ═══════════════ CTA ═══════════════ */}
      <section className="ww-bg-base px-6 py-28 sm:py-36">
        <div className="mx-auto max-w-4xl text-center">
          <div
            className="w-12 h-12 rounded-2xl inline-flex items-center justify-center mb-6 mx-auto"
            style={{
              backgroundColor: "var(--brand-50)",
              color: "var(--brand-500)",
            }}
          >
            <Music className="w-5 h-5" />
          </div>
          <h2 className="ww-display ww-text-1 text-5xl sm:text-6xl lg:text-7xl">
            Press play.
            <br />
            <span className="ww-text-brand">We'll handle the rest.</span>
          </h2>
          <div className="mt-10 flex flex-col sm:flex-row items-center justify-center gap-3">
            <Link href="/download" className="ww-btn ww-btn-primary">
              <Download className="w-4 h-4" />
              Download WolfWave
            </Link>
            <Link href="/docs" className="ww-btn ww-btn-secondary">
              Read the docs
              <ArrowRight className="w-4 h-4" />
            </Link>
            <a
              href="https://github.com/MrDemonWolf/WolfWave"
              target="_blank"
              rel="noopener noreferrer"
              className="ww-btn ww-btn-ghost"
            >
              <Github className="w-4 h-4" />
              Star on GitHub
            </a>
          </div>
          <p className="mt-5 text-sm ww-text-2">
            Free forever · macOS 26+ · Apple Music
          </p>
        </div>
      </section>
    </main>
  );
}
