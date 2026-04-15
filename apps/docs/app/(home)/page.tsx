import Link from "next/link";
import {
  MessageSquare,
  Radio,
  Wifi,
  Shield,
  Download,
  ArrowRight,
  Github,
  Sparkles,
  Music,
} from "lucide-react";
import { getAssetPath } from "@/lib/utils";

// ── Pulsing "Now Playing" card mockup ──
function NowPlayingCard() {
  return (
    <div className="now-playing-pulse now-playing-card-bg rounded-2xl border border-violet-500/30 p-4 w-64 shrink-0">
      <div className="flex items-center gap-3 mb-3">
        <div
          className="w-12 h-12 rounded-lg shrink-0"
          style={{
            background: "linear-gradient(135deg, #7c3aed, #22d3ee)",
            opacity: 0.9,
          }}
        />
        <div className="min-w-0">
          <p className="text-hero text-sm font-semibold truncate font-[family-name:var(--font-unbounded)]">
            Kbps Plz
          </p>
          <p className="text-hero-muted text-xs truncate">DevBowzer</p>
        </div>
      </div>
      <div className="h-1 rounded-full bg-black/10 dark:bg-white/10">
        <div
          className="h-1 rounded-full"
          style={{
            width: "62%",
            background: "linear-gradient(to right, #7c3aed, #22d3ee)",
          }}
        />
      </div>
      <div className="flex justify-between mt-1">
        <span className="text-hero-subtle text-xs">2:07</span>
        <span className="text-hero-subtle text-xs">3:20</span>
      </div>
    </div>
  );
}

// ── Live wire waveform (hero backdrop) ──
function LiveWire() {
  return (
    <svg
      className="live-wire absolute inset-0 w-full h-full pointer-events-none"
      viewBox="0 0 800 400"
      preserveAspectRatio="none"
      aria-hidden="true"
    >
      <defs>
        <linearGradient id="wire-grad" x1="0" y1="0" x2="1" y2="0">
          <stop offset="0%" stopColor="#7c3aed" stopOpacity="0" />
          <stop offset="30%" stopColor="#a855f7" stopOpacity="0.7" />
          <stop offset="70%" stopColor="#22d3ee" stopOpacity="0.7" />
          <stop offset="100%" stopColor="#22d3ee" stopOpacity="0" />
        </linearGradient>
      </defs>
      <path
        d="M 0 200 Q 100 80, 200 200 T 400 200 T 600 200 T 800 200"
        stroke="url(#wire-grad)"
        strokeWidth="2"
        fill="none"
      />
      <path
        d="M 0 220 Q 120 340, 240 220 T 480 220 T 720 220 T 800 220"
        stroke="url(#wire-grad)"
        strokeWidth="1.5"
        fill="none"
        opacity="0.5"
      />
    </svg>
  );
}

// ── Bento feature data ──
const tickerItems = [
  "APPLE MUSIC",
  "TWITCH",
  "DISCORD",
  "OBS",
  "SONG REQUESTS",
  "WEBSOCKET API",
  "MENU BAR",
  "OPEN SOURCE",
];

const steps = [
  {
    number: "01",
    title: "Download",
    description: "Grab the DMG from GitHub Releases. 3.7MB — under a second on any connection.",
  },
  {
    number: "02",
    title: "Connect",
    description: "One-time wizard links Twitch, Discord, and your overlay. No terminal.",
  },
  {
    number: "03",
    title: "Stream",
    description: "Hit play in Apple Music. Chat, Discord, overlay — everything updates live.",
  },
] as const;

export default function HomePage() {
  return (
    <main className="flex-1 text-hero">
      {/* ═══════════════ HERO ═══════════════ */}
      <section className="mesh-bg grid-lines noise relative overflow-hidden">
        <LiveWire />
        <div className="relative z-10 px-6 pt-20 pb-24 sm:pt-28 sm:pb-32">
          <div className="mx-auto max-w-6xl">
            <div className="hero-stagger flex flex-col lg:grid lg:grid-cols-12 gap-10 lg:gap-16 items-start">
              {/* LEFT — type column */}
              <div className="lg:col-span-8">
                {/* Mono kicker */}
                <div className="mono-kicker flex flex-wrap items-center gap-3 text-violet-300 dark:text-violet-300 mb-8">
                  <span className="inline-flex items-center gap-2">
                    <span className="w-1.5 h-1.5 rounded-full bg-violet-400 animate-pulse" />
                    V1.2.0
                  </span>
                  <span className="opacity-40">/</span>
                  <span>MACOS 26+</span>
                  <span className="opacity-40">/</span>
                  <span>FREE FOREVER</span>
                  <span className="opacity-40">/</span>
                  <span>OPEN SOURCE</span>
                </div>

                {/* Kinetic headline */}
                <h1 className="kinetic-headline mb-8">
                  <span className="block text-hero">YOUR MUSIC,</span>
                  <span className="block">
                    <span className="kinetic-gradient">live</span>{" "}
                    <span className="serif-em text-hero">everywhere</span>
                    <span className="kinetic-gradient">.</span>
                  </span>
                </h1>

                {/* Sub */}
                <p
                  className="text-hero-muted text-lg sm:text-xl leading-relaxed max-w-xl mb-10"
                  style={{ fontFamily: "var(--font-instrument)" }}
                >
                  A tiny macOS menu bar app. Apple Music plays — Twitch chat, Discord
                  Rich Presence, and your stream overlay update automatically. No
                  account. No subscription. No phoning home.
                </p>

                {/* CTAs */}
                <div className="flex flex-col sm:flex-row items-stretch sm:items-center gap-3">
                  <Link
                    href="/docs/installation"
                    className="shimmer-btn btn-primary inline-flex items-center justify-center gap-2 px-7 py-3.5 rounded-xl text-sm font-semibold transition-transform hover:scale-[1.02] active:scale-[0.98]"
                  >
                    <Download className="w-4 h-4 relative z-10" />
                    <span className="relative z-10">Download — 3.7MB</span>
                  </Link>
                  <a
                    href="https://github.com/mrdemonwolf/wolfwave"
                    target="_blank"
                    rel="noopener noreferrer"
                    className="btn-secondary inline-flex items-center justify-center gap-2 px-7 py-3.5 rounded-xl text-sm font-semibold transition-all hover:scale-[1.02]"
                  >
                    <Github className="w-4 h-4" />
                    View on GitHub
                  </a>
                  <Link
                    href="/docs"
                    className="inline-flex items-center justify-center gap-1.5 px-4 py-3.5 text-sm font-semibold text-hero-muted hover:text-hero transition-colors"
                  >
                    Read the Docs
                    <ArrowRight className="w-3.5 h-3.5" />
                  </Link>
                </div>
              </div>

              {/* RIGHT — liquid glass showcase */}
              <div className="lg:col-span-4 w-full flex justify-center lg:justify-end">
                <div className="corners liquid-glass relative rounded-3xl p-6 w-full max-w-sm">
                  {/* Mono labels */}
                  <div className="flex items-center justify-between mb-5">
                    <span className="mono-label text-hero-muted inline-flex items-center gap-1.5">
                      <span className="w-1.5 h-1.5 rounded-full bg-cyan-400 animate-pulse" />
                      LIVE
                    </span>
                    <span className="mono-label text-hero-subtle">MENU.BAR</span>
                  </div>
                  <div className="flex justify-center mb-4">
                    <NowPlayingCard />
                  </div>
                  {/* Faux broadcast targets */}
                  <div className="flex items-center justify-between pt-4 mt-2 border-t border-white/5">
                    <div className="flex items-center gap-2">
                      <div className="w-7 h-7 rounded-lg bg-[#9146FF]/20 inline-flex items-center justify-center">
                        <MessageSquare className="w-3.5 h-3.5 text-[#9146FF]" />
                      </div>
                      <div className="w-7 h-7 rounded-lg bg-[#5865F2]/20 inline-flex items-center justify-center">
                        <Radio className="w-3.5 h-3.5 text-[#5865F2]" />
                      </div>
                      <div className="w-7 h-7 rounded-lg bg-cyan-400/20 inline-flex items-center justify-center">
                        <Wifi className="w-3.5 h-3.5 text-cyan-400" />
                      </div>
                    </div>
                    <span className="mono-label text-hero-subtle">→ 3 OUTPUTS</span>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* ═══════════════ TICKER ═══════════════ */}
      <div className="ticker bg-ink">
        <div className="ticker-track">
          {[...tickerItems, ...tickerItems, ...tickerItems].map((item, i) => (
            <span key={i} className="ticker-item">
              {item}
              <span className="ticker-dot" />
            </span>
          ))}
        </div>
      </div>

      {/* ═══════════════ BENTO FEATURES ═══════════════ */}
      <section className="bg-ink px-6 py-24 sm:py-32 relative">
        <div className="mx-auto max-w-6xl">
          {/* Section header */}
          <div className="mb-14 flex flex-col sm:flex-row sm:items-end sm:justify-between gap-4">
            <div>
              <div className="mono-kicker text-violet-400 mb-3">◉ 04 / FEATURES</div>
              <h2
                className="text-4xl sm:text-5xl lg:text-6xl font-extrabold tracking-tight leading-[0.95] text-hero max-w-2xl"
                style={{ fontFamily: "var(--font-unbounded)", letterSpacing: "-0.03em" }}
              >
                One app.<br />
                <span className="kinetic-gradient">Four integrations.</span><br />
                Zero fees.
              </h2>
            </div>
            <p
              className="text-hero-muted text-sm max-w-xs sm:text-right"
              style={{ fontFamily: "var(--font-instrument)" }}
            >
              Built native with Swift + AppKit. No Electron. No analytics. No
              cloud. Your music never leaves your Mac.
            </p>
          </div>

          {/* Bento grid */}
          <div className="grid grid-cols-1 md:grid-cols-12 gap-5">
            {/* WIDE — Twitch */}
            <div className="bento-card md:col-span-7 md:row-span-2 min-h-[280px] flex flex-col justify-between">
              <div>
                <div className="mono-label text-[#9146FF] mb-4 flex items-center gap-2">
                  <span className="w-1.5 h-1.5 rounded-full bg-[#9146FF] animate-pulse" />
                  TWITCH EVENTSUB
                </div>
                <h3
                  className="text-2xl sm:text-3xl font-bold text-hero mb-3"
                  style={{ fontFamily: "var(--font-unbounded)" }}
                >
                  Chat knows what you&apos;re playing.
                </h3>
                <p
                  className="text-hero-muted text-sm leading-relaxed max-w-md mb-6"
                  style={{ fontFamily: "var(--font-instrument)" }}
                >
                  Viewers type <code className="text-violet-300 bg-violet-500/10 px-1.5 py-0.5 rounded text-xs">!song</code>.
                  The bot answers with exactly what&apos;s playing in Apple Music — title,
                  artist, album. Under 100ms.
                </p>
              </div>
              {/* Chat mock */}
              <div
                className="rounded-xl bg-black/30 border border-white/5 p-4 font-mono text-xs space-y-2"
                style={{ fontFamily: "var(--font-mono)" }}
              >
                <div className="chat-line flex gap-2">
                  <span className="text-[#9146FF] font-bold">DevBowzer</span>
                  <span className="text-hero-muted">!song</span>
                </div>
                <div className="chat-line flex gap-2">
                  <span className="text-cyan-400 font-bold">WolfWave</span>
                  <span className="text-hero">
                    Now playing:{" "}
                    <span className="text-violet-300">Kbps Plz</span> — DevBowzer
                  </span>
                </div>
                <div className="chat-line flex gap-2">
                  <span className="text-[#9146FF] font-bold">viewer_42</span>
                  <span className="text-hero-muted">this slaps 🔥</span>
                </div>
              </div>
            </div>

            {/* TALL — Discord */}
            <div className="bento-card md:col-span-5 md:row-span-2 min-h-[280px] flex flex-col justify-between">
              <div>
                <div className="mono-label text-[#5865F2] mb-4 flex items-center gap-2">
                  <span className="w-1.5 h-1.5 rounded-full bg-[#5865F2] animate-pulse" />
                  DISCORD RPC
                </div>
                <h3
                  className="text-2xl sm:text-3xl font-bold text-hero mb-3"
                  style={{ fontFamily: "var(--font-unbounded)" }}
                >
                  Rich Presence, your library.
                </h3>
                <p
                  className="text-hero-muted text-sm leading-relaxed mb-6"
                  style={{ fontFamily: "var(--font-instrument)" }}
                >
                  Friends see &ldquo;Listening to Apple Music&rdquo; with album
                  art and live progress. Like Spotify — but your full library.
                </p>
              </div>
              {/* RPC mock */}
              <div className="rounded-xl bg-black/30 border border-white/5 p-4">
                <div className="mono-label text-hero-subtle mb-3">LISTENING TO APPLE MUSIC</div>
                <div className="flex gap-3 items-center">
                  <div
                    className="w-14 h-14 rounded-lg shrink-0"
                    style={{ background: "linear-gradient(135deg, #22d3ee, #7c3aed)" }}
                  />
                  <div className="min-w-0 flex-1">
                    <p className="text-hero text-sm font-semibold truncate">Kbps Plz</p>
                    <p className="text-hero-muted text-xs truncate">DevBowzer</p>
                    <div className="h-1 rounded-full bg-white/10 mt-2">
                      <div
                        className="h-1 rounded-full"
                        style={{
                          width: "62%",
                          background: "linear-gradient(to right, #5865F2, #22d3ee)",
                        }}
                      />
                    </div>
                  </div>
                </div>
              </div>
            </div>

            {/* SMALL — Overlay */}
            <div className="bento-card md:col-span-4">
              <div className="mono-label text-cyan-400 mb-4 flex items-center gap-2">
                <Wifi className="w-3 h-3" />
                WEBSOCKET
              </div>
              <h3
                className="text-lg font-bold text-hero mb-2"
                style={{ fontFamily: "var(--font-unbounded)" }}
              >
                Stream overlay
              </h3>
              <p
                className="text-hero-muted text-xs leading-relaxed"
                style={{ fontFamily: "var(--font-instrument)" }}
              >
                Drop into OBS. Browser source. Or roll your own widget in 20
                lines of HTML.
              </p>
            </div>

            {/* SMALL — Privacy */}
            <div className="bento-card md:col-span-4">
              <div className="mono-label text-violet-400 mb-4 flex items-center gap-2">
                <Shield className="w-3 h-3" />
                KEYCHAIN
              </div>
              <h3
                className="text-lg font-bold text-hero mb-2"
                style={{ fontFamily: "var(--font-unbounded)" }}
              >
                Privacy first
              </h3>
              <p
                className="text-hero-muted text-xs leading-relaxed"
                style={{ fontFamily: "var(--font-instrument)" }}
              >
                Tokens in macOS Keychain. App Sandboxed. No telemetry. Ever.
              </p>
            </div>

            {/* SMALL — Song Requests (v2 teaser) */}
            <div className="bento-card md:col-span-4 relative">
              <div className="absolute top-4 right-4 mono-label text-cyan-300 bg-cyan-400/10 border border-cyan-400/30 px-2 py-0.5 rounded-full">
                V2.0
              </div>
              <div className="mono-label text-cyan-400 mb-4 flex items-center gap-2">
                <Sparkles className="w-3 h-3" />
                INCOMING
              </div>
              <h3
                className="text-lg font-bold text-hero mb-2"
                style={{ fontFamily: "var(--font-unbounded)" }}
              >
                Song requests
              </h3>
              <p
                className="text-hero-muted text-xs leading-relaxed"
                style={{ fontFamily: "var(--font-instrument)" }}
              >
                Viewers queue tracks via chat. Approve, skip, block. Coming in
                v2.0.
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* ═══════════════ FLOW (3 steps) ═══════════════ */}
      <section className="bg-ink px-6 py-24 sm:py-32 relative border-t border-white/5">
        <div className="mx-auto max-w-6xl">
          <div className="mb-16 text-center">
            <div className="mono-kicker text-violet-400 mb-3">◉ 03 / GETTING STARTED</div>
            <h2
              className="text-4xl sm:text-5xl lg:text-6xl font-extrabold tracking-tight text-hero"
              style={{ fontFamily: "var(--font-unbounded)", letterSpacing: "-0.03em" }}
            >
              Running in{" "}
              <span className="serif-em kinetic-gradient" style={{ fontFamily: "var(--font-serif)", fontStyle: "italic", fontWeight: 400 }}>
                sixty
              </span>{" "}
              seconds.
            </h2>
          </div>

          <div className="grid md:grid-cols-3 gap-6 relative">
            {steps.map((step, i) => (
              <div
                key={step.number}
                className="bento-card"
                style={{ transform: i === 1 ? "translateY(1.5rem)" : i === 2 ? "translateY(3rem)" : undefined }}
              >
                <div
                  className="mono-kicker text-violet-400 mb-4"
                  style={{ fontSize: "3rem", letterSpacing: "-0.04em", opacity: 0.3, lineHeight: 1 }}
                >
                  {step.number}
                </div>
                <h3
                  className="text-xl font-bold text-hero mb-2"
                  style={{ fontFamily: "var(--font-unbounded)" }}
                >
                  {step.title}
                </h3>
                <p
                  className="text-sm text-hero-muted leading-relaxed"
                  style={{ fontFamily: "var(--font-instrument)" }}
                >
                  {step.description}
                </p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* ═══════════════ DEV TERMINAL ═══════════════ */}
      <section className="bg-ink px-6 py-24 sm:py-32 relative border-t border-white/5">
        <div className="mx-auto max-w-5xl">
          <div className="grid md:grid-cols-5 gap-10 items-center">
            <div className="md:col-span-2">
              <div className="mono-kicker text-violet-400 mb-3">◉ 05 / FOR DEVELOPERS</div>
              <h2
                className="text-3xl sm:text-4xl font-extrabold tracking-tight text-hero mb-4"
                style={{ fontFamily: "var(--font-unbounded)", letterSpacing: "-0.03em" }}
              >
                Hack the{" "}
                <span className="kinetic-gradient">signal</span>.
              </h2>
              <p
                className="text-hero-muted text-sm leading-relaxed mb-6"
                style={{ fontFamily: "var(--font-instrument)" }}
              >
                Native Swift. Zero external deps. The WebSocket feed is fully
                documented — build custom overlays, wire it into Home Assistant,
                or poke around the source.
              </p>
              <div className="flex flex-wrap gap-4">
                <Link
                  href="/docs/architecture"
                  className="inline-flex items-center gap-1.5 text-xs font-semibold text-violet-400 hover:text-violet-300 transition-colors"
                >
                  ARCHITECTURE
                  <ArrowRight className="w-3 h-3" />
                </Link>
                <Link
                  href="/docs/development"
                  className="inline-flex items-center gap-1.5 text-xs font-semibold text-violet-400 hover:text-violet-300 transition-colors"
                >
                  DEV GUIDE
                  <ArrowRight className="w-3 h-3" />
                </Link>
                <Link
                  href="/docs/security"
                  className="inline-flex items-center gap-1.5 text-xs font-semibold text-violet-400 hover:text-violet-300 transition-colors"
                >
                  SECURITY
                  <ArrowRight className="w-3 h-3" />
                </Link>
              </div>
            </div>

            <div className="md:col-span-3">
              <div className="terminal">
                <div className="terminal-bar">
                  <span className="terminal-dot r" />
                  <span className="terminal-dot y" />
                  <span className="terminal-dot g" />
                  <span className="mono-label text-hero-subtle ml-2">ws://localhost:8080/now-playing</span>
                </div>
                <pre
                  className="terminal-body m-0 overflow-x-auto"
                  dangerouslySetInnerHTML={{
                    __html: `<span class="c-c">// 20 lines of HTML — that's the whole overlay</span>
<span class="c-k">const</span> <span class="c-v">ws</span> = <span class="c-k">new</span> <span class="c-n">WebSocket</span>(<span class="c-s">"ws://localhost:8080/now-playing"</span>);

<span class="c-v">ws</span>.<span class="c-n">onmessage</span> = (<span class="c-v">event</span>) =&gt; {
  <span class="c-k">const</span> { <span class="c-v">title</span>, <span class="c-v">artist</span>, <span class="c-v">artwork</span> } = <span class="c-n">JSON</span>.<span class="c-n">parse</span>(<span class="c-v">event</span>.<span class="c-v">data</span>);
  <span class="c-n">document</span>.<span class="c-n">querySelector</span>(<span class="c-s">"#title"</span>).<span class="c-v">textContent</span> = <span class="c-v">title</span>;
};`,
                  }}
                />
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* ═══════════════ GIANT CTA ═══════════════ */}
      <section className="mesh-bg grid-lines noise relative overflow-hidden border-t border-white/5">
        <div className="relative z-10 px-6 py-28 sm:py-40 text-center">
          <div className="mx-auto max-w-5xl">
            <div className="mono-kicker text-violet-400 mb-6 inline-flex items-center gap-2">
              <Music className="w-3 h-3" />
              READY WHEN YOU ARE
            </div>
            <h2 className="giant-cta mb-8 text-hero">
              Press{" "}
              <span className="serif-em kinetic-gradient" style={{ fontFamily: "var(--font-serif)", fontStyle: "italic", fontWeight: 400 }}>
                play
              </span>.
              <br />
              We handle the rest.
            </h2>
            <div className="flex flex-col sm:flex-row items-center justify-center gap-3 mb-10">
              <Link
                href="/docs/installation"
                className="shimmer-btn btn-primary inline-flex items-center justify-center gap-2 px-8 py-4 rounded-xl text-sm font-semibold transition-transform hover:scale-[1.02] active:scale-[0.98]"
              >
                <Download className="w-4 h-4 relative z-10" />
                <span className="relative z-10">Download WolfWave — Free</span>
              </Link>
              <Link
                href="/docs"
                className="btn-secondary inline-flex items-center justify-center gap-2 px-8 py-4 rounded-xl text-sm font-semibold transition-all hover:scale-[1.02]"
              >
                Read the Docs
                <ArrowRight className="w-4 h-4" />
              </Link>
            </div>
            {/* Proof pills */}
            <div className="flex flex-wrap items-center justify-center gap-2">
              {["FREE FOREVER", "MACOS 26+", "NO ACCOUNT", "~3.7MB", "OPEN SOURCE"].map((pill) => (
                <span
                  key={pill}
                  className="proof-pill mono-label px-3 py-1.5 rounded-full"
                >
                  {pill}
                </span>
              ))}
            </div>
          </div>
        </div>
      </section>
    </main>
  );
}
