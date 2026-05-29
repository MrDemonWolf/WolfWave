import type { Metadata } from "next";
import Link from "next/link";
import { absoluteUrl } from "@/lib/site";
import {
  ArrowRight,
  BookOpen,
  Check,
  Download,
  Github,
  Minus,
  Radio,
  Shield,
  Music,
  Code2,
  Headphones,
  Terminal,
  Twitch,
  X as XIcon,
} from "lucide-react";
import { DeveloperTabs } from "./DeveloperTabs";
import { DiscordPresenceCard } from "./_widgets/DiscordPresenceCard";
import { HeroNowPlaying } from "./_widgets/HeroNowPlaying";
import { OBSOverlayWidget } from "./_widgets/OBSOverlayWidget";

export const metadata: Metadata = {
  title: "WolfWave. Free Apple Music to Twitch, Discord & OBS on Mac",
  description:
    "Every streaming music tool is built for Spotify. WolfWave is built for Apple Music. It puts your track into Twitch chat, Discord Rich Presence, and your OBS overlay on its own. Free, native macOS, open source.",
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
    title: "WolfWave. Free Apple Music to Twitch, Discord & OBS on Mac",
    description:
      "The streaming tool world is built for Spotify. WolfWave is built for Apple Music. It bridges your track to Twitch chat, Discord Rich Presence, and your stream overlay on its own.",
    images: [
      {
        url: absoluteUrl("/opengraph-image.png"),
        width: 1200,
        height: 630,
        alt: "WolfWave. Apple Music to Twitch, Discord, and OBS overlay on macOS",
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    site: "@mrdemonwolf",
    creator: "@mrdemonwolf",
    title: "WolfWave. Free Apple Music to Twitch, Discord & OBS on Mac",
    description:
      "The streaming tool world is built for Spotify. WolfWave is built for Apple Music. It bridges your track to Twitch chat, Discord Rich Presence, and your stream overlay on its own.",
    images: [absoluteUrl("/opengraph-image.png")],
  },
};


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
        <div className="relative z-10 px-6 pt-12 pb-16 sm:pt-20 sm:pb-24">
          <div className="mx-auto max-w-6xl grid lg:grid-cols-[1.05fr_0.95fr] gap-12 lg:gap-16 items-center">
            {/* Claim */}
            <div className="text-center lg:text-left">
              <p className="ww-reveal ww-reveal-1 ww-text-brand text-sm font-semibold mb-5">
                Built for Apple Music · macOS 26+
              </p>
              <h1 className="ww-reveal ww-reveal-1 ww-hero-headline ww-text-1">
                Streaming tools are built for Spotify.{" "}
                <span className="ww-text-brand">This one&apos;s for Apple Music.</span>
              </h1>
              <p className="ww-reveal ww-reveal-2 ww-text-2 text-lg sm:text-xl mt-6 max-w-xl mx-auto lg:mx-0 leading-relaxed">
                WolfWave is a tiny Mac menu bar app for the people who actually
                use Apple Music. Press play and your Twitch chat, your Discord
                profile, and your stream overlay all update on their own.
              </p>
              <div className="ww-reveal ww-reveal-3 mt-8 flex flex-col sm:flex-row items-center justify-center lg:justify-start gap-3">
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

              {/* Trust strip. Credibility badges, no fabricated quotes */}
              <div className="ww-reveal ww-reveal-3 mt-7 flex flex-wrap items-center justify-center lg:justify-start gap-2">
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

            {/* Product visual */}
            <div className="ww-reveal ww-reveal-2 relative flex justify-center lg:justify-end">
              <div
                aria-hidden="true"
                className="ww-hero-card-glow"
              />
              <div className="ww-hero-card-float relative">
                <HeroNowPlaying />
              </div>
            </div>
          </div>

        </div>
      </section>

      {/* ═══════════════ AUDIENCES ═══════════════ */}
      <section
        id="audiences"
        className="ww-bg-surface px-6 py-14 sm:py-20 lg:py-28 scroll-mt-20"
      >
        <div className="mx-auto max-w-6xl">
          <SectionHead
            eyebrow="Pick your lane"
            title={<>Three kinds of people. One wolf.</>}
            sub="Whatever you do with Apple Music, the tools have ignored you. Streamers, listeners, and developers all got built for Spotify first. WolfWave covers all three."
          />

          <div className="mt-14 grid md:grid-cols-3 gap-5">
            {[
              {
                icon: Twitch,
                title: "For streamers",
                body: "Stream on Apple Music without the workarounds. !song, song requests, and a live overlay are ready the moment you finish setup.",
                href: "/docs/usage",
                cta: "Streaming guide",
              },
              {
                icon: Headphones,
                title: "For listeners",
                body: "Spotify friends get Rich Presence. Now you do too. Album art, live progress, and your full Apple Music library on your Discord profile.",
                href: "/docs/features",
                cta: "What's included",
              },
              {
                icon: Code2,
                title: "For developers",
                body: "A real Apple Music feed to build on. A local WebSocket exposes every play, pause, and skip. Wire it up in roughly 20 lines.",
                href: "/docs/architecture",
                cta: "Read the architecture",
              },
            ].map(({ icon: Icon, title, body, href, cta }) => (
              <div
                key={title}
                className="ww-card ww-card-hover ww-glass flex flex-col"
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
      <section
        id="twitch"
        className="ww-bg-base px-6 py-14 sm:py-20 lg:py-28 scroll-mt-20"
      >
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
              WolfWave answers in under a second. Title, artist, album, straight
              from Apple Music. No bots to wire up. No browser tabs to babysit.
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
            className="ww-card ww-glass space-y-3 text-sm"
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
                Now playing: <strong>Midnight Routine</strong> by Local Maxima
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
      <section
        id="discord"
        className="ww-bg-surface px-6 py-14 sm:py-20 lg:py-28 scroll-mt-20"
      >
        <div className="mx-auto max-w-6xl grid md:grid-cols-2 gap-12 lg:gap-16 items-center">
          <figure
            className="order-2 md:order-1 mx-auto"
            style={{ width: "100%", maxWidth: 437 }}
            aria-label="Discord Rich Presence. Listening to WolfWave"
          >
            <DiscordPresenceCard />
          </figure>

          <div className="order-1 md:order-2">
            <p className="ww-text-brand text-sm font-semibold mb-3">
              Discord Rich Presence
            </p>
            <h2 className="ww-display ww-text-1 text-4xl sm:text-5xl">
              Your friends see what you're listening to.
            </h2>
            <p className="ww-text-2 text-lg mt-5 leading-relaxed">
              Spotify users have had this for years. Apple Music users never
              did. Real Rich Presence with album art, live progress, and a
              click-through to your library.
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
      <section
        id="overlay"
        className="ww-bg-base px-6 py-14 sm:py-20 lg:py-28 scroll-mt-20"
      >
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
              theme or write your own. Every track update streams in real time
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

          <figure
            className="rounded-2xl overflow-hidden mx-auto"
            style={{
              width: "100%",
              maxWidth: 560,
              border: "1px solid var(--hairline)",
              boxShadow: "0 24px 60px -18px rgba(0,0,0,0.35)",
            }}
            aria-label="WolfWave overlay rendered inside an OBS browser source"
          >
            <div
              className="px-4 py-2.5 flex items-center gap-2 text-xs ww-mono ww-text-2"
              style={{
                backgroundColor: "var(--bg-surface)",
                borderBottom: "1px solid var(--hairline)",
              }}
              aria-hidden="true"
            >
              <span
                className="w-2.5 h-2.5 rounded-full"
                style={{ background: "#ff5f57" }}
              />
              <span
                className="w-2.5 h-2.5 rounded-full"
                style={{ background: "#febc2e" }}
              />
              <span
                className="w-2.5 h-2.5 rounded-full"
                style={{ background: "#28c840" }}
              />
              <span className="ml-2">localhost:8080/now-playing</span>
            </div>
            <div
              style={{
                // Stage backdrop. Neutral checkerboard to read as "browser source"
                backgroundColor: "#0d0d0f",
                backgroundImage:
                  "linear-gradient(45deg, rgba(255,255,255,0.025) 25%, transparent 25%), linear-gradient(-45deg, rgba(255,255,255,0.025) 25%, transparent 25%), linear-gradient(45deg, transparent 75%, rgba(255,255,255,0.025) 75%), linear-gradient(-45deg, transparent 75%, rgba(255,255,255,0.025) 75%)",
                backgroundSize: "16px 16px",
                backgroundPosition: "0 0, 0 8px, 8px -8px, -8px 0",
              }}
            >
              <OBSOverlayWidget />
            </div>
          </figure>
        </div>
      </section>

      {/* ═══════════════ COMPARISON ═══════════════ */}
      <section
        id="compare"
        className="ww-bg-surface px-6 py-14 sm:py-20 lg:py-28 scroll-mt-20"
      >
        <div className="mx-auto max-w-6xl">
          <SectionHead
            eyebrow="Honest comparison"
            title={<>WolfWave vs. the rest.</>}
            sub="The rest target Spotify and treat Apple Music as an afterthought, if at all. WolfWave starts with Apple Music. Free, native, and yours to fork."
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
      <section
        id="developers"
        className="ww-bg-base px-6 py-14 sm:py-20 lg:py-28 scroll-mt-20 relative overflow-hidden"
        style={{
          backgroundImage:
            "radial-gradient(color-mix(in srgb, var(--hairline) 70%, transparent) 1px, transparent 1px)",
          backgroundSize: "32px 32px",
          backgroundPosition: "0 0",
        }}
      >
        <div className="mx-auto max-w-5xl relative">
          <SectionHead
            eyebrow="For developers"
            title={
              <>
                Built like a Swift app.
                <br />
                <span className="ww-text-brand">Hackable like a webhook.</span>
              </>
            }
            sub="A local WebSocket emits every play, pause, and skip. Wire it into your overlay, your Home Assistant dashboard, or a Stream Deck plugin. MIT-licensed. Read the code, fork it, ship your own build."
          />

          {/* Section ToC / jumpbar */}
          <nav
            aria-label="Developer section contents"
            className="mt-10 flex flex-wrap items-center justify-center gap-2"
          >
            {[
              { id: "dev-what", n: "01", label: "What" },
              { id: "dev-why", n: "02", label: "Why" },
              { id: "dev-how", n: "03", label: "How" },
              { id: "dev-docs", n: "04", label: "Docs" },
            ].map((step) => (
              <a
                key={step.id}
                href={`#${step.id}`}
                className="ww-mono inline-flex items-center gap-2 px-3 py-1.5 text-xs rounded-full transition-colors"
                style={{
                  border: "1px solid var(--hairline)",
                  color: "var(--txt-2)",
                  backgroundColor: "var(--bg-surface)",
                }}
              >
                <span style={{ color: "var(--brand-500)" }}>{step.n}</span>
                <span className="ww-text-1">{step.label}</span>
              </a>
            ))}
          </nav>

          {/* ── WHAT ─────────────────────────────────────────── */}
          <div id="dev-what" className="mt-20 scroll-mt-24">
            <p className="ww-mono text-xs ww-text-2 mb-4 text-center">
              01 · WHAT IT IS
            </p>
            <div className="grid md:grid-cols-3 gap-4">
              {[
                {
                  icon: Code2,
                  title: "Native Swift",
                  body: "A real macOS menu-bar app. Not an Electron wrapper, not a browser extension. Sandboxed, signed, and notarized.",
                },
                {
                  icon: Radio,
                  title: "Local WebSocket",
                  body: "ws://localhost:8080/now-playing streams every track change in milliseconds. JSON payload, no auth gymnastics for loopback.",
                },
                {
                  icon: Github,
                  title: "Open source, MIT",
                  body: "Read the whole codebase on GitHub. Fork it, audit the security model, ship a custom build for your stream.",
                },
              ].map(({ icon: Icon, title, body }) => (
                <div
                  key={title}
                  className="ww-card ww-bg-base"
                  style={{ border: "1px solid var(--hairline)" }}
                >
                  <div
                    className="w-10 h-10 rounded-xl inline-flex items-center justify-center mb-4"
                    style={{
                      backgroundColor: "var(--brand-50)",
                      color: "var(--brand-500)",
                    }}
                  >
                    <Icon className="w-5 h-5" />
                  </div>
                  <h3 className="ww-display ww-text-1 text-lg mb-2">{title}</h3>
                  <p className="ww-text-2 text-sm leading-relaxed">{body}</p>
                </div>
              ))}
            </div>
          </div>

          {/* ── WHY ──────────────────────────────────────────── */}
          <div id="dev-why" className="mt-20 scroll-mt-24">
            <p className="ww-mono text-xs ww-text-2 mb-4 text-center">
              02 · WHY YOU&apos;LL CARE
            </p>
            <div className="grid md:grid-cols-2 gap-4">
              <div
                className="ww-card ww-bg-surface"
                style={{ border: "1px solid var(--hairline)" }}
              >
                <p className="ww-mono text-xs ww-text-2 mb-3">WITHOUT WOLFWAVE</p>
                <ul className="space-y-2.5 text-sm ww-text-2">
                  {[
                    "Scraping Spotify Web Player to fake an Apple Music feed.",
                    "Browser-source overlays that flicker on every track change.",
                    "Twitch tokens copy-pasted into a Node script that crashes at 3am.",
                    "No Discord Rich Presence. Your friends never see what you're playing.",
                  ].map((item) => (
                    <li key={item} className="flex gap-2.5">
                      <XIcon
                        className="w-4 h-4 mt-0.5 shrink-0"
                        style={{ color: "var(--txt-2)" }}
                        aria-hidden="true"
                      />
                      <span>{item}</span>
                    </li>
                  ))}
                </ul>
              </div>

              <div
                className="ww-card ww-bg-base"
                style={{
                  border: "1px solid var(--hairline)",
                  borderLeft: "2px solid var(--brand-500)",
                }}
              >
                <p className="ww-mono text-xs ww-text-brand mb-3">WITH WOLFWAVE</p>
                <ul className="space-y-2.5 text-sm ww-text-1">
                  {[
                    "One menu-bar app reads Apple Music via ScriptingBridge.",
                    "One WebSocket feed drives your overlay. No polling, no flicker.",
                    "Tokens live in macOS Keychain. EventSub reconnects itself.",
                    "Discord Rich Presence ships in the box. Just sign in.",
                  ].map((item) => (
                    <li key={item} className="flex gap-2.5">
                      <Check
                        className="w-4 h-4 mt-0.5 shrink-0"
                        style={{ color: "var(--brand-500)" }}
                        aria-hidden="true"
                      />
                      <span>{item}</span>
                    </li>
                  ))}
                </ul>
              </div>
            </div>
          </div>

          {/* ── HOW ──────────────────────────────────────────── */}
          <div id="dev-how" className="mt-20 scroll-mt-24">
            <p className="ww-mono text-xs ww-text-2 mb-4 text-center">
              03 · HOW IT WIRES UP
            </p>
            <DeveloperTabs />
          </div>

          {/* ── DOCS ─────────────────────────────────────────── */}
          <div id="dev-docs" className="mt-20 scroll-mt-24">
            <p className="ww-mono text-xs ww-text-2 mb-4 text-center">
              04 · WHERE TO GO NEXT
            </p>
            <div className="grid sm:grid-cols-2 gap-4">
              {[
                {
                  icon: Terminal,
                  title: "Architecture",
                  body: "How the menu-bar app, services, and WebSocket feed fit together.",
                  href: "/docs/architecture",
                  external: false,
                },
                {
                  icon: BookOpen,
                  title: "Development guide",
                  body: "Build from source, run the test suite, contribute a PR.",
                  href: "/docs/development",
                  external: false,
                },
                {
                  icon: Shield,
                  title: "Security model",
                  body: "Keychain storage, code-signing, token validation, sandbox.",
                  href: "/docs/security",
                  external: false,
                },
                {
                  icon: Github,
                  title: "GitHub",
                  body: "Star the repo, fork it, or file an issue with reproduction steps.",
                  href: "https://github.com/MrDemonWolf/WolfWave",
                  external: true,
                },
              ].map(({ icon: Icon, title, body, href, external }) => {
                const inner = (
                  <>
                    <div className="flex items-start gap-4">
                      <div
                        className="w-10 h-10 rounded-xl inline-flex items-center justify-center shrink-0"
                        style={{
                          backgroundColor: "var(--brand-50)",
                          color: "var(--brand-500)",
                        }}
                      >
                        <Icon className="w-5 h-5" />
                      </div>
                      <div className="min-w-0 flex-1">
                        <h3 className="ww-display ww-text-1 text-lg mb-1">
                          {title}
                        </h3>
                        <p className="ww-text-2 text-sm leading-relaxed">
                          {body}
                        </p>
                        <span className="ww-text-brand mt-3 inline-flex items-center gap-1.5 text-sm font-semibold">
                          Read
                          <ArrowRight className="w-3.5 h-3.5" />
                        </span>
                      </div>
                    </div>
                  </>
                );
                const className = "ww-card ww-card-hover ww-bg-base block";
                const style = { border: "1px solid var(--hairline)" } as const;
                return external ? (
                  <a
                    key={title}
                    href={href}
                    target="_blank"
                    rel="noopener noreferrer"
                    className={className}
                    style={style}
                  >
                    {inner}
                  </a>
                ) : (
                  <Link
                    key={title}
                    href={href}
                    className={className}
                    style={style}
                  >
                    {inner}
                  </Link>
                );
              })}
            </div>
          </div>

          {/* ── Conversion footer ────────────────────────────── */}
          <div className="mt-16 text-center">
            <div className="flex flex-col sm:flex-row items-center justify-center gap-3">
              <Link href="#download" className="ww-btn ww-btn-primary">
                <Download className="w-4 h-4" />
                Download for macOS
              </Link>
              <Link href="/docs/changelog" className="ww-btn ww-btn-ghost">
                Read the changelog
                <ArrowRight className="w-4 h-4" />
              </Link>
            </div>
            <p className="mt-5 text-sm ww-text-2">
              MIT-licensed · macOS 26+ · Built by{" "}
              <a
                href="https://github.com/MrDemonWolf"
                target="_blank"
                rel="noopener noreferrer"
                className="ww-text-brand font-semibold"
              >
                @MrDemonWolf
              </a>
            </p>
          </div>
        </div>
      </section>

      {/* ═══════════════ BADGES ═══════════════ */}
      <section id="download" className="ww-bg-surface px-6 py-20 scroll-mt-20">
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
      <section
        id="privacy"
        className="ww-bg-base px-6 py-14 sm:py-20 lg:py-28 scroll-mt-20"
      >
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
            The app runs sandboxed. There's no telemetry. There's nothing to
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
      <section
        id="faq"
        className="ww-bg-surface px-6 py-14 sm:py-20 lg:py-28 scroll-mt-20"
      >
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
                  No, and that's the point. Spotify already has plenty of tools.
                  Apple Music had almost none, so that's what WolfWave was built
                  for. It reads Apple Music via ScriptingBridge, the same
                  framework Apple uses internally. If your setup is
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
                  No. The app is native, under 30 MB, and event-driven. It
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
                  Keychain. See the{" "}
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
                  WolfWave uses Sparkle with EdDSA-signed appcasts. Same
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
      <section id="cta" className="ww-bg-base px-6 py-28 sm:py-36 scroll-mt-20">
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
