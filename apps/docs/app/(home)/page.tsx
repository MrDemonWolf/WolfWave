import type { Metadata } from "next";
import Link from "next/link";
import { absoluteUrl, homepageSeo, repoUrl } from "@/lib/site";
import {
  ArrowRight,
  BookOpen,
  Check,
  Download,
  Github,
  Radio,
  Shield,
  Music,
  Code2,
  DollarSign,
  EyeOff,
  Scale,
  Headphones,
  Star,
  Terminal,
  Twitch,
  X as XIcon,
} from "lucide-react";
import { DeveloperTabs } from "./DeveloperTabs";
import { DiscordPresenceCard } from "./_widgets/DiscordPresenceCard";
import { OBSOverlayWidget } from "./_widgets/OBSOverlayWidget";
import { TwitchChatPreview } from "./_widgets/TwitchChatPreview";
import { BackToTop } from "./_widgets/BackToTop";
import { ComparisonTable } from "./_widgets/ComparisonTable";

const REPO_URL = repoUrl;
const DISCORD_URL = "https://mrdwolf.net/discord";

// Homepage SEO is centralized in `homepageSeo` (lib/site.ts) so the page meta,
// the OG image, and the Twitter image always tell the same story.
export const metadata: Metadata = {
  title: homepageSeo.title,
  description: homepageSeo.description,
  keywords: [...homepageSeo.keywords],
  alternates: { canonical: absoluteUrl("/") },
  openGraph: {
    type: "website",
    url: absoluteUrl("/"),
    siteName: "WolfWave",
    title: homepageSeo.title,
    description: homepageSeo.socialDescription,
    images: [
      {
        url: absoluteUrl("/opengraph-image.png"),
        width: 1200,
        height: 630,
        alt: homepageSeo.ogImageAlt,
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    site: "@mrdemonwolf",
    creator: "@mrdemonwolf",
    title: homepageSeo.title,
    description: homepageSeo.socialDescription,
    images: [absoluteUrl("/opengraph-image.png")],
  },
};

// ── Section kicker ───────────────────────────────────────────
// One numbered anchor tag, shared by every section, so the whole page
// reads with a single consistent spine: 01 · For streamers, 02 · Twitch …
function Kicker({
  index,
  children,
}: {
  index: string;
  children: React.ReactNode;
}) {
  return (
    <span className="ww-kicker">
      <span className="ww-kicker-num">{index}</span>
      {children}
    </span>
  );
}

// ── Centered section heading (kicker + title + sub) ──────────
function CenterHead({
  index,
  kicker,
  title,
  sub,
}: {
  index: string;
  kicker: string;
  title: React.ReactNode;
  sub?: React.ReactNode;
}) {
  return (
    <div className="max-w-3xl mx-auto text-center">
      <div className="flex justify-center mb-5">
        <Kicker index={index}>{kicker}</Kicker>
      </div>
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

// Build-time GitHub stats for the native trust chips. Fetched once when the
// site is statically generated, so the star count and latest release stay
// current per deploy without shipping third-party shields.io images. Any
// failure (rate limit, offline) falls back to label-only chips.
interface RepoStats {
  stars: number | null;
  latest: string | null;
}

async function getRepoStats(): Promise<RepoStats> {
  const headers = {
    Accept: "application/vnd.github+json",
    "User-Agent": "wolfwave-docs",
  };
  try {
    const [repoRes, relRes] = await Promise.all([
      fetch("https://api.github.com/repos/MrDemonWolf/WolfWave", { headers }),
      fetch("https://api.github.com/repos/MrDemonWolf/WolfWave/releases/latest", {
        headers,
      }),
    ]);
    const repo = repoRes.ok ? await repoRes.json() : null;
    const rel = relRes.ok ? await relRes.json() : null;
    return {
      stars:
        typeof repo?.stargazers_count === "number"
          ? repo.stargazers_count
          : null,
      latest: typeof rel?.tag_name === "string" ? rel.tag_name : null,
    };
  } catch {
    return { stars: null, latest: null };
  }
}

function fmtStars(n: number): string {
  return n >= 1000 ? `${(n / 1000).toFixed(1).replace(/\.0$/, "")}k` : String(n);
}

export default async function HomePage() {
  const { stars, latest } = await getRepoStats();
  return (
    <main id="nd-page" tabIndex={-1} className="ww-font ww-bg-base">
      {/* ═══════════════ HERO ═══════════════ */}
      <section className="relative overflow-hidden">
        <div className="ww-hero-glow" aria-hidden="true" />
        <div className="relative z-10 px-[10%] md:px-6 pt-12 pb-16 sm:pt-20 sm:pb-24">
          <div className="mx-auto max-w-6xl grid lg:grid-cols-2 gap-12 lg:gap-8 items-center">
            {/* Claim */}
            <div className="text-center lg:text-left">
              <p className="ww-reveal ww-reveal-1 ww-text-brand text-sm font-semibold mb-5">
                Built for Apple Music, not Spotify · macOS 26+
              </p>
              <h1 className="ww-reveal ww-reveal-1 ww-hero-headline ww-text-1">
                Apple Music,{" "}
                <span className="ww-text-brand">live on your stream.</span>
              </h1>
              <p className="ww-reveal ww-reveal-2 ww-text-2 text-lg sm:text-xl mt-6 max-w-xl mx-auto lg:mx-0 leading-relaxed">
                A free Mac menu bar app. Press play once and your song shows up
                in your Twitch chat, your Discord profile, and your OBS overlay.
              </p>
              <div className="ww-reveal ww-reveal-3 mt-8 flex flex-col sm:flex-row items-center justify-center lg:justify-start gap-3">
                <Link
                  href="/download"
                  className="ww-btn ww-btn-primary w-full sm:w-auto"
                >
                  <Download className="w-4 h-4" />
                  Download for Mac
                </Link>
                <Link
                  href="/docs"
                  className="ww-btn ww-btn-secondary w-full sm:w-auto"
                >
                  See how it works
                  <ArrowRight className="w-4 h-4" />
                </Link>
              </div>
              {/* Pre-click reassurance, right under the button. */}
              <p className="ww-reveal ww-reveal-3 mt-4 text-sm ww-text-2">
                <span className="ww-text-1 font-semibold">Free</span> · Open
                source
              </p>

              {/* Secondary trust + platform facts. */}
              <div className="ww-reveal ww-reveal-3 mt-6 flex flex-wrap items-center justify-center lg:justify-start gap-2">
                <a
                  href={REPO_URL}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="ww-pill min-h-[40px]"
                  aria-label="View WolfWave on GitHub"
                >
                  <Github className="w-3 h-3" /> Open source · GPL-3.0
                </a>
                <span className="ww-pill">macOS 26+ · Apple Silicon</span>
                <span className="ww-pill">Under 30 MB</span>
              </div>
            </div>

            {/* Product cluster: real widgets in a staggered, non-overlapping
                column. Decorative duplicates of the section widgets below, so
                aria-hidden. Mobile shows the Discord + Twitch cards, centered. */}
            <div className="ww-reveal ww-reveal-2 ww-hero-cluster">
              <div aria-hidden="true" className="ww-hero-card-glow" />
              <div className="ww-hc-discord" aria-hidden="true">
                <DiscordPresenceCard />
              </div>
              <div className="ww-hc-obs" aria-hidden="true">
                <OBSOverlayWidget controls={false} />
              </div>
              <div className="ww-hc-twitch" aria-hidden="true">
                <TwitchChatPreview viewportHeight={150} />
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* ═══════════════ 01 · AUDIENCES ═══════════════ */}
      <section
        id="audiences"
        className="ww-bg-surface px-[10%] md:px-6 py-16 sm:py-24 lg:py-28 scroll-mt-20"
      >
        <div className="mx-auto max-w-6xl">
          <CenterHead
            index="01"
            kicker="Pick your lane"
            title={<>Three kinds of people. One wolf.</>}
            sub="Every streaming tool got built for Spotify first, so Apple Music users got skipped. Streamers, listeners, builders. WolfWave covers all three."
          />

          <div className="mt-14 grid md:grid-cols-3 gap-5">
            {[
              {
                icon: Twitch,
                title: "For streamers",
                body: "Go live on Apple Music without the hacks. !song replies, chat song requests, and a real-time overlay are ready the minute setup ends.",
                href: "/docs/usage",
                cta: "Streaming guide",
              },
              {
                icon: Headphones,
                title: "For listeners",
                body: "Spotify friends always had Rich Presence. Now you do too. Album art, live progress, and your full Apple Music library on your Discord profile.",
                href: "/docs/features",
                cta: "What's included",
              },
              {
                icon: Code2,
                title: "For developers",
                body: "A real Apple Music feed to build on. A local WebSocket streams every play, pause, and skip. Wire it into anything in about 20 lines.",
                href: "/docs/architecture",
                cta: "Read the architecture",
              },
            ].map(({ icon: Icon, title, body, href, cta }) => (
              <div
                key={title}
                className="ww-glass ww-card-hover flex flex-col p-8"
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

      {/* ═══════════════ 02 · TWITCH ═══════════════ */}
      <section
        id="twitch"
        className="ww-bg-base px-[10%] md:px-6 py-16 sm:py-24 lg:py-28 scroll-mt-20"
      >
        <div className="mx-auto max-w-6xl grid md:grid-cols-2 gap-12 lg:gap-16 items-center">
          <div className="text-center md:text-left">
            <Kicker index="02">Twitch integration</Kicker>
            <h2 className="ww-display ww-text-1 text-4xl sm:text-5xl mt-5">
              Chat that knows the song.
            </h2>
            <p className="ww-text-2 text-lg mt-5 leading-relaxed">
              Viewers type <code className="ww-mono ww-text-1">!song</code> and
              WolfWave answers in under a second. Title, artist, and album,
              straight from Apple Music. No third-party bot to host. No browser
              tab to babysit.
            </p>
            <Link
              href="/docs/bot-commands"
              className="ww-text-brand mt-6 inline-flex items-center gap-1.5 text-sm font-semibold"
            >
              Bot commands reference
              <ArrowRight className="w-3.5 h-3.5" />
            </Link>
          </div>

          <TwitchChatPreview />
        </div>
      </section>

      {/* ═══════════════ 03 · DISCORD ═══════════════ */}
      <section
        id="discord"
        className="ww-bg-surface px-[10%] md:px-6 py-16 sm:py-24 lg:py-28 scroll-mt-20"
      >
        <div className="mx-auto max-w-6xl grid md:grid-cols-2 gap-12 lg:gap-16 items-center">
          <figure
            className="order-2 md:order-1 mx-auto"
            style={{ width: "100%", maxWidth: 437 }}
          >
            <DiscordPresenceCard />
          </figure>

          <div className="order-1 md:order-2 text-center md:text-left">
            <Kicker index="03">Discord Rich Presence</Kicker>
            <h2 className="ww-display ww-text-1 text-4xl sm:text-5xl mt-5">
              Your friends see what you&apos;re playing.
            </h2>
            <p className="ww-text-2 text-lg mt-5 leading-relaxed">
              Spotify users had this for years. Apple Music users got nothing.
              WolfWave puts real Rich Presence on your profile, with album art,
              live progress, and a tap through to the track.
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

      {/* ═══════════════ 04 · OVERLAY ═══════════════ */}
      <section
        id="overlay"
        className="ww-bg-base px-[10%] md:px-6 py-16 sm:py-24 lg:py-28 scroll-mt-20"
      >
        <div className="mx-auto max-w-6xl grid md:grid-cols-2 gap-12 lg:gap-16 items-center">
          <div className="text-center md:text-left">
            <Kicker index="04">Stream overlay</Kicker>
            <h2 className="ww-display ww-text-1 text-4xl sm:text-5xl mt-5">
              A now-playing card for OBS in 30 seconds.
            </h2>
            <p className="ww-text-2 text-lg mt-5 leading-relaxed">
              Add one browser source in OBS, pick a theme or build your own, and
              every track change shows up on stream the instant it happens.
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
              boxShadow: "0 10px 28px -18px rgba(0,0,0,0.22)",
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

      {/* ═══════════════ 05 · COMPARISON ═══════════════ */}
      <section
        id="compare"
        className="ww-bg-surface px-[10%] md:px-6 py-16 sm:py-24 lg:py-28 scroll-mt-20"
      >
        <div className="mx-auto max-w-6xl">
          <CenterHead
            index="05"
            kicker="Honest comparison"
            title={<>WolfWave vs. the rest.</>}
            sub="Most tools chase Spotify and bolt on Apple Music later, if ever. WolfWave starts with Apple Music. Free, native, and yours to fork."
          />

          <ComparisonTable />

          <p className="mt-5 text-center text-xs ww-text-2">
            Partial means &quot;depends on the tool / depends on your plan.&quot;
            See the{" "}
            <Link href="/docs/features" className="ww-text-brand font-semibold">
              full feature breakdown
            </Link>
            .
          </p>
        </div>
      </section>

      {/* ═══════════════ 06 · OPEN & TRUSTED (proof band) ═══════════════ */}
      <section
        id="download"
        className="ww-bg-surface px-[10%] md:px-6 py-16 sm:py-24 lg:py-28 scroll-mt-20"
      >
        <div className="mx-auto max-w-5xl">
          <CenterHead
            index="06"
            kicker="Open & trusted"
            title={<>Free, open, and yours to fork.</>}
            sub="No paywall, no telemetry. Read every line on GitHub, audit the security model, or ship your own build."
          />

          <div className="ww-proof mt-12">
            <div className="grid gap-5 sm:gap-6 lg:grid-cols-[1.05fr_1fr] lg:items-stretch">
              {/* Download card: the primary action, with platform facts and
                  the live star count baked in from getRepoStats at build time. */}
              <div className="ww-download-card">
                <div>
                  <p className="ww-download-eyebrow">Get WolfWave</p>
                  <p className="ww-download-headline">Free for macOS.</p>
                </div>
                <div className="ww-download-actions">
                  <Link
                    href="/download"
                    className="ww-btn ww-btn-primary ww-btn-lg"
                  >
                    <Download className="w-4 h-4" />
                    Download for Mac
                  </Link>
                  <p className="ww-download-meta">
                    <span>
                      latest{" "}
                      <b className="ww-chip-strong">{latest ?? "release"}</b>
                    </span>
                    <span className="ww-download-sep" aria-hidden="true">
                      ·
                    </span>
                    <span>Under 30 MB</span>
                    <span className="ww-download-sep" aria-hidden="true">
                      ·
                    </span>
                    <span>macOS 26+ · Apple Silicon</span>
                  </p>
                  <a
                    href={REPO_URL}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="ww-btn ww-btn-ghost"
                    aria-label={
                      stars != null
                        ? `Star WolfWave on GitHub, ${stars} stars`
                        : "Star WolfWave on GitHub"
                    }
                  >
                    <Star className="w-4 h-4" />
                    {stars != null ? (
                      <>
                        <b className="ww-chip-strong">{fmtStars(stars)}</b> · Star
                        on GitHub
                      </>
                    ) : (
                      "Star on GitHub"
                    )}
                  </a>
                </div>
              </div>

              {/* Proof grid: the trust facts. One column on the narrowest
                  phones (the value strings clip in a 2-up cell under ~400px),
                  2-up once there's room. */}
              <div className="grid grid-cols-1 min-[420px]:grid-cols-2 gap-3 sm:gap-4">
                {[
                  {
                    Icon: DollarSign,
                    value: "$0",
                    label: "Free forever. No tiers, no upsell.",
                  },
                  {
                    Icon: Scale,
                    value: "GPL-3.0",
                    label: "Open source. Fork it freely.",
                  },
                  {
                    Icon: EyeOff,
                    value: "0",
                    label: "Trackers, servers, or telemetry.",
                  },
                  {
                    Icon: Shield,
                    value: "Signed",
                    label: "Notarized by Apple.",
                  },
                ].map(({ Icon, value, label }) => (
                  <div key={label} className="ww-stat">
                    <Icon className="ww-stat-icon w-5 h-5" aria-hidden="true" />
                    <span className="ww-stat-value">{value}</span>
                    <span className="ww-stat-label">{label}</span>
                  </div>
                ))}
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* ═══════════════ 07 · DEVELOPERS ═══════════════ */}
      <section
        id="developers"
        className="ww-bg-base ww-dev-dot-grid px-[10%] md:px-6 py-16 sm:py-24 lg:py-28 scroll-mt-20 relative overflow-hidden"
        style={{
          backgroundSize: "32px 32px",
          backgroundPosition: "0 0",
        }}
      >
        <div className="mx-auto max-w-5xl relative">
          <CenterHead
            index="07"
            kicker="For developers"
            title={
              <>
                Built like a Swift app.
                <br />
                <span className="ww-text-brand">Hackable like a webhook.</span>
              </>
            }
            sub="A local WebSocket emits every play, pause, and skip. Point it at your overlay, your Home Assistant dashboard, or a Stream Deck plugin. GPL-3.0 licensed, so read the code, fork it, and ship your own build."
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
                className="ww-mono inline-flex items-center gap-2 px-3.5 py-2 min-h-[40px] text-[13px] rounded-lg transition-colors"
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
          <div id="dev-what" className="mt-20 scroll-mt-20">
            <h3 className="ww-mono text-xs ww-text-2 mb-4 text-center">
              01 · WHAT IT IS
            </h3>
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
                  title: "Open source, GPL-3.0",
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
                  <h4 className="ww-display ww-text-1 text-lg mb-2">{title}</h4>
                  <p className="ww-text-2 text-sm leading-relaxed">{body}</p>
                </div>
              ))}
            </div>
          </div>

          {/* ── WHY ──────────────────────────────────────────── */}
          <div id="dev-why" className="mt-20 scroll-mt-20">
            <h3 className="ww-mono text-xs ww-text-2 mb-4 text-center">
              02 · THE OLD WAY VS. WOLFWAVE
            </h3>
            <div className="grid md:grid-cols-2 gap-4">
              <div
                className="ww-card ww-bg-surface"
                style={{ border: "1px solid var(--hairline)" }}
              >
                <p className="ww-mono text-xs ww-text-2 mb-3">THE OLD WAY</p>
                <ul className="space-y-2.5 text-sm ww-text-2">
                  {[
                    "Bolt on a third-party app or paid web service just to get your song on screen.",
                    "Switch your whole stream to Spotify or YouTube because nothing reads Apple Music.",
                    "Overlays that flicker or freeze every time the track changes.",
                    "No clean way to put Apple Music on your Discord profile.",
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
                    "One menu-bar app reads Apple Music straight from your Mac.",
                    "One live feed powers the overlay. No flicker, no refresh.",
                    "Sign in once. Tokens are stored safely and reconnect on their own.",
                    "Discord “Listening to” status is built in. Just sign in.",
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
          <div id="dev-how" className="mt-20 scroll-mt-20">
            <h3 className="ww-mono text-xs ww-text-2 mb-4 text-center">
              03 · HOW IT WIRES UP
            </h3>
            <DeveloperTabs />
          </div>

          {/* ── DOCS ─────────────────────────────────────────── */}
          <div id="dev-docs" className="mt-20 scroll-mt-20">
            <h3 className="ww-mono text-xs ww-text-2 mb-4 text-center">
              04 · WHERE TO GO NEXT
            </h3>
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
                  href: REPO_URL,
                  external: true,
                },
              ].map(({ icon: Icon, title, body, href, external }) => {
                const inner = (
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
                      <h4 className="ww-display ww-text-1 text-lg mb-1">
                        {title}
                      </h4>
                      <p className="ww-text-2 text-sm leading-relaxed">{body}</p>
                      <span className="ww-text-brand mt-3 inline-flex items-center gap-1.5 text-sm font-semibold">
                        Read
                        <ArrowRight className="w-3.5 h-3.5" />
                      </span>
                    </div>
                  </div>
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
        </div>
      </section>

      {/* ═══════════════ 08 · PRIVACY ═══════════════ */}
      <section
        id="privacy"
        className="ww-bg-base px-[10%] md:px-6 py-16 sm:py-24 lg:py-28 scroll-mt-20"
      >
        <div className="mx-auto max-w-3xl text-center">
          <div className="flex justify-center mb-5">
            <Kicker index="08">Private by default</Kicker>
          </div>
          <h2 className="ww-display ww-text-1 text-4xl sm:text-5xl">
            Your music stays on your Mac.
          </h2>
          <p className="ww-text-2 text-lg mt-5 leading-relaxed">
            Nothing about what you play leaves your machine. Tokens sit in the
            macOS Keychain. The app runs sandboxed. No telemetry, nothing to
            phone home.
          </p>
          <div className="mt-8 flex flex-wrap items-center justify-center gap-2">
            {["Sandboxed", "Keychain", "No telemetry", "GPL-3.0 licensed"].map(
              (label) => (
                <span key={label} className="ww-pill">
                  {label}
                </span>
              ),
            )}
          </div>
        </div>
      </section>

      {/* ═══════════════ 09 · FAQ ═══════════════ */}
      <section
        id="faq"
        className="ww-bg-surface px-[10%] md:px-6 py-16 sm:py-24 lg:py-28 scroll-mt-20"
      >
        <div className="mx-auto max-w-3xl">
          <CenterHead
            index="09"
            kicker="Questions, answered"
            title={<>Anything else?</>}
            sub="The short answers. Longer ones live in the docs."
          />

          <div className="mt-12 space-y-3">
            <FaqRow
              q="Does it work with Spotify?"
              a={
                <>
                  No, and that&apos;s the point. Spotify already has plenty of
                  tools. Apple Music had almost none, so that&apos;s what
                  WolfWave was built for. It reads Apple Music via
                  ScriptingBridge, the same framework Apple uses internally. If
                  your setup is Spotify-first, this is not the right tool.
                </>
              }
            />
            <FaqRow
              q="Will my viewers see ads or upsells?"
              a={
                <>
                  Never. WolfWave is free and open source. No ads, no premium
                  tier, no upsell screens. If you want to give back,{" "}
                  <Link
                    href="/docs/support"
                    className="ww-text-brand font-semibold"
                  >
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
                  reacts to Apple Music&apos;s own notifications with a 2-second
                  fallback poll. CPU and memory impact are negligible during a
                  stream.
                </>
              }
            />
            <FaqRow
              q="Is my Twitch token safe?"
              a={
                <>
                  Yes. WolfWave uses Twitch&apos;s OAuth Device Code flow, stores
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
                  No. WolfWave requires Apple Silicon (M1 or later) running macOS
                  26 (Tahoe) or newer. Intel Macs are not supported.
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
                  <Link
                    href="/docs/security"
                    className="ww-text-brand font-semibold"
                  >
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
                  framework Things, Tower, and many other Mac apps use. Homebrew
                  installs are managed by Homebrew instead, and you&apos;ll get
                  notified when a new release lands.
                </>
              }
            />
            <FaqRow
              q="Is it really free?"
              a={
                <>
                  Yes. GPL-3.0 licensed, no paywall, no premium tier. The whole
                  source is on{" "}
                  <a
                    href={REPO_URL}
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
              href={DISCORD_URL}
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
      <section id="cta" className="ww-bg-base px-[10%] md:px-6 py-28 sm:py-36 scroll-mt-20">
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
            <span className="ww-text-brand">We&apos;ll handle the rest.</span>
          </h2>
          <div className="mt-10 flex flex-col sm:flex-row items-center justify-center gap-3">
            <Link
              href="/download"
              className="ww-btn ww-btn-primary w-full sm:w-auto"
            >
              <Download className="w-4 h-4" />
              Download WolfWave
            </Link>
            <Link
              href="/docs"
              className="ww-btn ww-btn-secondary w-full sm:w-auto"
            >
              Read the docs
              <ArrowRight className="w-4 h-4" />
            </Link>
            <a
              href={REPO_URL}
              target="_blank"
              rel="noopener noreferrer"
              className="ww-btn ww-btn-ghost w-full sm:w-auto"
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

      {/* Landing-only floating back-to-top */}
      <BackToTop />
    </main>
  );
}
