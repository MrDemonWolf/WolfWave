import Link from "next/link";
import { MessageSquare, Radio, Wifi, Shield, Download, ArrowRight, Github } from "lucide-react";
import { getAssetPath } from "@/lib/utils";

// Animated waveform bars — CSS-driven, no client JS needed
function WaveformBars() {
  const bars = [
    { peak: "18px", duration: "0.9s", delay: "0s" },
    { peak: "32px", duration: "1.1s", delay: "0.1s" },
    { peak: "40px", duration: "1.3s", delay: "0.05s" },
    { peak: "28px", duration: "0.8s", delay: "0.2s" },
    { peak: "44px", duration: "1.2s", delay: "0.15s" },
    { peak: "36px", duration: "1.0s", delay: "0.25s" },
    { peak: "44px", duration: "1.4s", delay: "0.0s" },
    { peak: "30px", duration: "0.95s", delay: "0.18s" },
    { peak: "40px", duration: "1.15s", delay: "0.08s" },
    { peak: "22px", duration: "1.05s", delay: "0.3s" },
    { peak: "34px", duration: "0.85s", delay: "0.12s" },
    { peak: "18px", duration: "1.25s", delay: "0.22s" },
  ];
  return (
    <div className="waveform" aria-hidden="true">
      {bars.map((bar, i) => (
        <div
          key={i}
          className="waveform-bar"
          style={
            {
              "--peak": bar.peak,
              "--duration": bar.duration,
              "--delay": bar.delay,
            } as React.CSSProperties
          }
        />
      ))}
    </div>
  );
}

// Pulsing "Now Playing" card mockup
function NowPlayingCard() {
  return (
    <div className="now-playing-pulse now-playing-card-bg rounded-2xl border border-violet-500/30 p-4 w-64 shrink-0">
      <div className="flex items-center gap-3 mb-3">
        {/* Album art placeholder */}
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
      {/* Progress bar */}
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

const features = [
  {
    icon: MessageSquare,
    title: "Twitch Chat Bot",
    description:
      "!song in chat shows exactly what's playing. Powered by Twitch's modern EventSub API.",
    accent: "#7c3aed",
  },
  {
    icon: Radio,
    title: "Discord Status",
    description:
      "Show \"Listening to Apple Music\" with album art and live progress. Like Spotify — but your library.",
    accent: "#22d3ee",
  },
  {
    icon: Wifi,
    title: "Stream Overlay",
    description:
      "Live now-playing data over WebSocket. Drop it into OBS, browser source, or your custom widget.",
    accent: "#a855f7",
  },
  {
    icon: Shield,
    title: "Privacy First",
    description:
      "All tokens in macOS Keychain. App Sandboxed. Nothing phoned home. Your music stays yours.",
    accent: "#7c3aed",
  },
] as const;

const steps = [
  {
    number: "1",
    title: "Download",
    description: "Grab the DMG from GitHub Releases. Under 10MB.",
  },
  {
    number: "2",
    title: "Connect",
    description: "One-time setup wizard links Twitch, Discord, and OBS.",
  },
  {
    number: "3",
    title: "Stream",
    description: "Hit play. Everything updates automatically.",
  },
] as const;

export default function HomePage() {
  return (
    <main className="flex-1 bg-midnight text-hero">
      {/* Hero */}
      <section className="relative overflow-hidden px-6 pt-24 pb-16 sm:pt-32 sm:pb-24">
        <div className="hero-glow" aria-hidden="true" />
        <div className="mx-auto max-w-5xl relative z-10">
          <div className="flex flex-col lg:flex-row items-center gap-12 lg:gap-16">
            {/* Left: text */}
            <div className="flex-1 text-center lg:text-left">
              {/* Version badge */}
              <div className="version-badge inline-flex items-center gap-2 rounded-full px-3 py-1 text-xs font-medium mb-6">
                <span className="w-1.5 h-1.5 rounded-full bg-violet-400 animate-pulse inline-block" />
                v1.2.0 — Free &amp; Open Source
              </div>

              <h1
                className="text-4xl sm:text-5xl lg:text-6xl font-extrabold tracking-tight leading-[1.08] mb-6"
                style={{ fontFamily: "var(--font-unbounded)" }}
              >
                <span className="gradient-text">Your Music,</span>
                <br />
                <span className="text-hero">Live Everywhere.</span>
              </h1>

              <p className="text-hero-muted text-lg leading-relaxed max-w-md mx-auto lg:mx-0 mb-8"
                style={{ fontFamily: "var(--font-instrument)" }}>
                macOS menu bar app. Apple Music plays — Twitch chat, Discord,
                and your stream overlay all update. Automatically.
              </p>

              <div className="flex flex-col sm:flex-row items-center justify-center lg:justify-start gap-3">
                <Link
                  href="/docs/installation"
                  className="btn-primary w-full sm:w-auto inline-flex items-center justify-center gap-2 px-7 py-3 rounded-xl text-sm font-semibold transition-all hover:scale-[1.02] active:scale-[0.98]"
                >
                  <Download className="w-4 h-4" />
                  Get Started Free
                </Link>
                <a
                  href="https://github.com/mrdemonwolf/wolfwave"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="btn-secondary w-full sm:w-auto inline-flex items-center justify-center gap-2 px-7 py-3 rounded-xl text-sm font-semibold transition-all hover:scale-[1.02]"
                >
                  <Github className="w-4 h-4" />
                  View on GitHub
                </a>
              </div>
            </div>

            {/* Right: visual */}
            <div className="flex flex-col items-center gap-6 shrink-0">
              <NowPlayingCard />
              <WaveformBars />
              <p className="text-xs text-hero-subtle tracking-wider uppercase">Live preview</p>
            </div>
          </div>
        </div>
      </section>

      {/* Proof bar */}
      <div className="proof-bar px-6 py-4">
        <div className="mx-auto max-w-5xl flex flex-wrap items-center justify-center gap-3">
          {["Free Forever", "macOS 26+", "No Account Needed", "~3.7MB", "Open Source"].map((pill) => (
            <span
              key={pill}
              className="proof-pill text-xs font-medium px-3 py-1 rounded-full"
            >
              {pill}
            </span>
          ))}
        </div>
      </div>

      {/* Features */}
      <section className="px-6 py-20 bg-midnight">
        <div className="mx-auto max-w-5xl">
          <h2
            className="text-2xl sm:text-3xl font-bold text-center mb-3 text-hero"
            style={{ fontFamily: "var(--font-unbounded)" }}
          >
            Everything a streamer needs
          </h2>
          <p className="text-center text-hero-subtle text-sm mb-12">
            One app. Four integrations. Zero monthly fees.
          </p>
          <div className="grid sm:grid-cols-2 lg:grid-cols-4 gap-5">
            {features.map((feature) => (
              <div
                key={feature.title}
                className="feature-card bg-midnight-card group p-5 rounded-2xl transition-all"
              >
                <div
                  className="w-10 h-10 rounded-xl inline-flex items-center justify-center mb-4"
                  style={{ backgroundColor: `${feature.accent}18`, color: feature.accent }}
                >
                  <feature.icon className="w-5 h-5" />
                </div>
                <h3 className="font-bold text-sm text-hero mb-2">
                  {feature.title}
                </h3>
                <p className="text-xs text-hero-subtle leading-relaxed"
                  style={{ fontFamily: "var(--font-instrument)" }}>
                  {feature.description}
                </p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* How it works */}
      <section className="px-6 py-20 bg-midnight-alt">
        <div className="mx-auto max-w-3xl">
          <h2
            className="text-2xl sm:text-3xl font-bold text-center mb-3 text-hero"
            style={{ fontFamily: "var(--font-unbounded)" }}
          >
            Up and running in 3 steps
          </h2>
          <p className="text-center text-hero-subtle text-sm mb-14">
            No terminal. No config files. Just click through the wizard.
          </p>
          <div className="grid sm:grid-cols-3 gap-8">
            {steps.map((step) => (
              <div key={step.number} className="text-center group">
                <div
                  className="step-badge w-14 h-14 rounded-2xl inline-flex items-center justify-center text-xl font-bold text-white mb-5 transition-transform group-hover:scale-110"
                  style={{ fontFamily: "var(--font-unbounded)" }}
                >
                  {step.number}
                </div>
                <h3 className="font-bold text-base text-hero mb-2"
                  style={{ fontFamily: "var(--font-unbounded)" }}>
                  {step.title}
                </h3>
                <p className="text-sm text-hero-subtle leading-relaxed"
                  style={{ fontFamily: "var(--font-instrument)" }}>
                  {step.description}
                </p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* For Developers */}
      <section className="px-6 py-20 bg-midnight">
        <div className="mx-auto max-w-3xl">
          <div className="dev-card rounded-2xl p-8">
            <div className="flex items-start gap-4">
              <div
                className="w-10 h-10 rounded-xl shrink-0 inline-flex items-center justify-center"
                style={{ background: "linear-gradient(135deg, #7c3aed, #22d3ee)" }}
              >
                <span className="text-white text-sm font-bold" style={{ fontFamily: "var(--font-unbounded)" }}>{"{}"}</span>
              </div>
              <div>
                <h2 className="font-bold text-hero text-lg mb-2"
                  style={{ fontFamily: "var(--font-unbounded)" }}>
                  For Developers
                </h2>
                <p className="text-hero-muted text-sm leading-relaxed mb-5"
                  style={{ fontFamily: "var(--font-instrument)" }}>
                  Open source, zero external dependencies, native Swift. The WebSocket API is
                  fully documented — build your own overlay, integrate with anything, or just
                  poke around.
                </p>
                <div className="flex flex-wrap gap-3">
                  <Link
                    href="/docs/architecture"
                    className="inline-flex items-center gap-1.5 text-xs font-semibold text-violet-500 dark:text-violet-400 hover:text-violet-600 dark:hover:text-violet-300 transition-colors"
                  >
                    Architecture
                    <ArrowRight className="w-3 h-3" />
                  </Link>
                  <Link
                    href="/docs/development"
                    className="inline-flex items-center gap-1.5 text-xs font-semibold text-violet-500 dark:text-violet-400 hover:text-violet-600 dark:hover:text-violet-300 transition-colors"
                  >
                    Development Guide
                    <ArrowRight className="w-3 h-3" />
                  </Link>
                  <Link
                    href="/docs/security"
                    className="inline-flex items-center gap-1.5 text-xs font-semibold text-violet-500 dark:text-violet-400 hover:text-violet-600 dark:hover:text-violet-300 transition-colors"
                  >
                    Security
                    <ArrowRight className="w-3 h-3" />
                  </Link>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* CTA Footer */}
      <section className="px-6 py-24 text-center bg-midnight-cta">
        <div className="mx-auto max-w-2xl">
          {/* Logo */}
          <div className="flex justify-center mb-6">
            <div
              className="rounded-2xl p-3"
              style={{ backgroundColor: "rgba(124,58,237,0.06)", border: "1px solid rgba(124,58,237,0.15)" }}
            >
              <img src={getAssetPath("/logo.svg")} alt="WolfWave" className="h-10 w-auto" />
            </div>
          </div>
          <h2
            className="text-3xl sm:text-4xl font-extrabold text-hero mb-4"
            style={{ fontFamily: "var(--font-unbounded)" }}
          >
            Start streaming smarter.
          </h2>
          <p className="text-hero-subtle text-base mb-10"
            style={{ fontFamily: "var(--font-instrument)" }}>
            Free forever. No account. Just music.
          </p>
          <div className="flex flex-col sm:flex-row items-center justify-center gap-3">
            <Link
              href="/docs/installation"
              className="btn-primary w-full sm:w-auto inline-flex items-center justify-center gap-2 px-8 py-3.5 rounded-xl text-sm font-semibold transition-all hover:scale-[1.02] active:scale-[0.98]"
            >
              <Download className="w-4 h-4" />
              Download WolfWave
            </Link>
            <Link
              href="/docs"
              className="btn-secondary w-full sm:w-auto inline-flex items-center justify-center gap-2 px-8 py-3.5 rounded-xl text-sm font-semibold transition-all hover:scale-[1.02]"
            >
              Read the Docs
              <ArrowRight className="w-4 h-4" />
            </Link>
          </div>
        </div>
      </section>
    </main>
  );
}
