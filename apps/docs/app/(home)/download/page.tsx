import type { Metadata } from "next";
import Link from "next/link";
import {
  ArrowRight,
  Download,
  Github,
  Music2,
  Terminal,
} from "lucide-react";
import { CopyButton } from "./copy-button";

// ── Constants ────────────────────────────────────────────────
const REPO_URL = "https://github.com/MrDemonWolf/WolfWave";
const LATEST_RELEASE_URL = `${REPO_URL}/releases/latest`;
const BREW_CMD = "brew tap mrdemonwolf/den\nbrew install --cask wolfwave";

export const metadata: Metadata = {
  title: "Download WolfWave: Free for macOS 26+ (DMG or Homebrew)",
  description:
    "Download WolfWave free for macOS 26+ on Apple Silicon. Install the signed .dmg or run `brew install --cask mrdemonwolf/den/wolfwave`. Apple Music required. Free and open source.",
  keywords: [
    "download wolfwave",
    "wolfwave dmg",
    "brew install wolfwave",
    "brew tap mrdemonwolf/den",
    "apple music twitch bot download",
    "free macos streamer app",
  ],
  alternates: { canonical: "/download" },
  openGraph: {
    title: "Download WolfWave: Free for macOS 26+",
    description:
      "Free macOS app. Apple Music to Twitch chat, Discord Rich Presence, OBS overlay. DMG or Homebrew. Apple Silicon.",
  },
};

export default function DownloadPage() {
  return (
    <main className="ww-font ww-bg-base">
      {/* ═══════════════ HERO ═══════════════ */}
      <section className="relative overflow-hidden">
        <div className="ww-hero-glow" aria-hidden="true" />
        <div className="relative z-10 px-6 pt-20 pb-12 sm:pt-28">
          <div className="mx-auto max-w-3xl text-center">
            <span
              className="ww-reveal ww-reveal-1 ww-pill"
              style={{
                backgroundColor: "var(--brand-50)",
                color: "var(--brand-600)",
              }}
            >
              macOS 26+ · Apple Silicon · Apple Music
            </span>
            <h1 className="ww-reveal ww-reveal-1 ww-display ww-text-1 text-5xl sm:text-7xl mt-5">
              Download WolfWave
            </h1>
            <p className="ww-reveal ww-reveal-2 ww-text-2 text-lg sm:text-xl mt-5 max-w-md mx-auto leading-relaxed">
              Tiny menu bar app. Install in under a minute.
            </p>

            <div className="ww-reveal ww-reveal-3 mt-8 flex flex-col sm:flex-row items-center justify-center gap-3">
              <a
                href={LATEST_RELEASE_URL}
                target="_blank"
                rel="noopener noreferrer"
                className="ww-btn ww-btn-primary"
                style={{ padding: "1rem 1.75rem", fontSize: "1rem" }}
              >
                <Download className="w-4 h-4" />
                Download .dmg
              </a>
              <a
                href={REPO_URL}
                target="_blank"
                rel="noopener noreferrer"
                className="ww-btn ww-btn-ghost"
              >
                <Github className="w-4 h-4" />
                View on GitHub
              </a>
            </div>

            {/* Now-playing flourish — product identity in the hero */}
            <div
              className="ww-reveal ww-reveal-3 mt-10 inline-flex items-center gap-3 ww-pulse-ring"
              style={{
                padding: "0.6rem 1.1rem",
                borderRadius: "980px",
                backgroundColor: "var(--bg-surface)",
                border: "1px solid var(--hairline)",
              }}
            >
              <span
                className="inline-flex items-center justify-center"
                style={{
                  width: "1.6rem",
                  height: "1.6rem",
                  borderRadius: "999px",
                  backgroundColor: "var(--brand-50)",
                  color: "var(--brand-500)",
                }}
              >
                <Music2 className="w-3.5 h-3.5" aria-hidden />
              </span>
              <span className="ww-text-2 text-sm">
                <span className="ww-text-1 font-medium">Now playing</span>
                {" "}· streaming to Twitch chat
              </span>
            </div>

            <p className="mt-6 text-sm ww-text-2">
              Free · Open source · Signed and notarized by Apple
            </p>
          </div>
        </div>
      </section>

      {/* ═══════════════ INSTALL METHODS ═══════════════ */}
      <section className="ww-bg-base px-6 pb-16">
        <div className="mx-auto max-w-5xl">
          <div className="grid md:grid-cols-2 gap-5 items-stretch">
            {/* DMG */}
            <div
              className="ww-card ww-bg-surface flex flex-col h-full"
              style={{ border: "1px solid var(--hairline)" }}
            >
              <div className="flex items-center justify-between gap-3 mb-5">
                <div
                  className="w-11 h-11 rounded-xl inline-flex items-center justify-center"
                  style={{
                    backgroundColor: "var(--brand-50)",
                    color: "var(--brand-500)",
                  }}
                >
                  <Download className="w-5 h-5" />
                </div>
                <span
                  className="ww-pill"
                  style={{
                    backgroundColor: "var(--brand-50)",
                    color: "var(--brand-600)",
                  }}
                >
                  Recommended
                </span>
              </div>
              <h3 className="ww-display ww-text-1 text-xl mb-2">
                DMG installer
              </h3>
              <p className="ww-text-2 text-base leading-relaxed flex-1">
                Drag to Applications. Auto-updates via Sparkle.
              </p>
              <a
                href={LATEST_RELEASE_URL}
                target="_blank"
                rel="noopener noreferrer"
                className="ww-btn ww-btn-primary mt-6"
              >
                <Download className="w-4 h-4" />
                Download .dmg
              </a>
            </div>

            {/* Homebrew */}
            <div
              className="ww-card ww-bg-surface flex flex-col h-full"
              style={{ border: "1px solid var(--hairline)" }}
            >
              <div className="flex items-center justify-between gap-3 mb-5">
                <div
                  className="w-11 h-11 rounded-xl inline-flex items-center justify-center"
                  style={{
                    backgroundColor: "var(--bg-base)",
                    color: "var(--txt-1)",
                    border: "1px solid var(--hairline)",
                  }}
                >
                  <Terminal className="w-5 h-5" />
                </div>
                <span className="ww-pill">Homebrew</span>
              </div>
              <h3 className="ww-display ww-text-1 text-xl mb-2">
                Command line
              </h3>
              <p className="ww-text-2 text-base leading-relaxed mb-4">
                Auto-updates via <code className="ww-mono ww-text-1">brew upgrade --cask</code>.
              </p>
              <pre
                className="ww-code flex-1"
                style={{ margin: 0 }}
              >{BREW_CMD}</pre>
              <div className="mt-4 flex justify-end">
                <CopyButton value={BREW_CMD} label="Copy command" />
              </div>
            </div>
          </div>

          {/* ═══════════════ TRUST + REQUIREMENTS ═══════════════ */}
          <div className="mt-12 flex flex-wrap items-center justify-center gap-2">
            {["Notarized", "Sandboxed", "Keychain", "No telemetry", "MIT"].map(
              (label) => (
                <span key={label} className="ww-pill">
                  {label}
                </span>
              ),
            )}
          </div>
          <p className="ww-text-2 text-sm text-center mt-4 max-w-xl mx-auto">
            Requires macOS 26 Tahoe, Apple Silicon, and the Apple Music app. Intel Macs and Spotify are not supported.
          </p>

          <div className="mt-8 flex flex-wrap items-center justify-center gap-3">
            <Link href="/docs/installation" className="ww-btn ww-btn-ghost">
              Installation guide
              <ArrowRight className="w-3.5 h-3.5" />
            </Link>
            <Link href="/docs/usage" className="ww-btn ww-btn-ghost">
              Usage guide
              <ArrowRight className="w-3.5 h-3.5" />
            </Link>
          </div>
        </div>
      </section>
    </main>
  );
}
