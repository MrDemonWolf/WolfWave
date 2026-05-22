import type { Metadata } from "next";
import Link from "next/link";
import {
  ArrowRight,
  Cpu,
  Download,
  Github,
  Laptop,
  ShieldCheck,
  Sparkles,
  Terminal,
} from "lucide-react";

// ── Constants ────────────────────────────────────────────────
const REPO_URL = "https://github.com/MrDemonWolf/WolfWave";
const LATEST_RELEASE_URL = `${REPO_URL}/releases/latest`;

export const metadata: Metadata = {
  title: "Download",
  description:
    "Download WolfWave for macOS — free and open source. Install via the .dmg or Homebrew. Requires macOS 26+ on Apple Silicon.",
  alternates: { canonical: "/download" },
};

// ── Requirement row ──────────────────────────────────────────
function RequirementRow({
  icon: Icon,
  label,
  value,
}: {
  icon: React.ElementType;
  label: string;
  value: string;
}) {
  return (
    <div
      className="flex items-center gap-4 py-4 first:pt-0 last:pb-0"
      style={{ borderBottom: "1px solid var(--hairline)" }}
    >
      <div
        className="w-10 h-10 rounded-xl inline-flex items-center justify-center shrink-0"
        style={{ backgroundColor: "var(--brand-50)", color: "var(--brand-500)" }}
      >
        <Icon className="w-5 h-5" />
      </div>
      <div className="min-w-0">
        <p className="ww-text-2 text-xs font-semibold uppercase tracking-wide">
          {label}
        </p>
        <p className="ww-text-1 text-base font-medium">{value}</p>
      </div>
    </div>
  );
}

// ── Numbered step ────────────────────────────────────────────
function Step({ n, children }: { n: number; children: React.ReactNode }) {
  return (
    <li className="flex gap-3">
      <span
        className="w-6 h-6 rounded-full shrink-0 inline-flex items-center justify-center text-xs font-semibold"
        style={{ backgroundColor: "var(--brand-50)", color: "var(--brand-500)" }}
      >
        {n}
      </span>
      <span className="ww-text-2 text-base leading-relaxed">{children}</span>
    </li>
  );
}

export default function DownloadPage() {
  return (
    <main className="ww-font ww-bg-base">
      {/* ═══════════════ HERO ═══════════════ */}
      <section className="relative overflow-hidden">
        <div className="ww-hero-glow" aria-hidden="true" />
        <div className="relative z-10 px-6 pt-24 pb-16 sm:pt-32 sm:pb-20">
          <div className="mx-auto max-w-3xl text-center">
            <p className="ww-reveal ww-reveal-1 ww-text-brand text-sm font-semibold mb-5">
              macOS 26+ · Apple Silicon
            </p>
            <h1 className="ww-reveal ww-reveal-1 ww-display ww-text-1 text-5xl sm:text-7xl">
              Download WolfWave
            </h1>
            <p className="ww-reveal ww-reveal-2 ww-text-2 text-lg sm:text-xl mt-6 max-w-xl mx-auto leading-relaxed">
              A tiny menu bar app for your Mac. Grab the installer, drag it to
              Applications, and you're streaming your music in a minute.
            </p>
            <div className="ww-reveal ww-reveal-3 mt-9 flex flex-col sm:flex-row items-center justify-center gap-3">
              <a
                href={LATEST_RELEASE_URL}
                target="_blank"
                rel="noopener noreferrer"
                className="ww-btn ww-btn-primary"
              >
                <Download className="w-4 h-4" />
                Download for Mac
              </a>
              <a
                href={REPO_URL}
                target="_blank"
                rel="noopener noreferrer"
                className="ww-btn ww-btn-secondary"
              >
                <Github className="w-4 h-4" />
                View on GitHub
              </a>
            </div>
            <p className="mt-5 text-sm ww-text-2">
              Free and open source · No account needed
            </p>
          </div>
        </div>
      </section>

      {/* ═══════════════ SYSTEM REQUIREMENTS ═══════════════ */}
      <section className="ww-bg-surface px-6 py-20 sm:py-24">
        <div className="mx-auto max-w-2xl">
          <h2 className="ww-display ww-text-1 text-3xl sm:text-4xl text-center">
            What you need
          </h2>
          <div
            className="ww-card ww-bg-base mt-8"
            style={{ border: "1px solid var(--hairline)" }}
          >
            <RequirementRow
              icon={Laptop}
              label="Operating system"
              value="macOS 26.0 or later (Tahoe)"
            />
            <RequirementRow
              icon={Cpu}
              label="Processor"
              value="Apple Silicon — M1 or later"
            />
          </div>
          <p className="ww-text-2 text-sm text-center mt-4">
            Intel Macs are not supported.
          </p>
        </div>
      </section>

      {/* ═══════════════ INSTALL METHODS ═══════════════ */}
      <section className="ww-bg-base px-6 py-24 sm:py-32">
        <div className="mx-auto max-w-5xl">
          <div className="max-w-2xl mx-auto text-center">
            <p className="ww-text-brand text-sm font-semibold mb-3">
              Two ways to install
            </p>
            <h2 className="ww-display ww-text-1 text-4xl sm:text-5xl">
              Pick whatever fits you.
            </h2>
          </div>

          <div className="mt-14 grid md:grid-cols-2 gap-5 items-start">
            {/* DMG — recommended */}
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
                    color: "var(--brand-500)",
                  }}
                >
                  Recommended
                </span>
              </div>
              <h3 className="ww-display ww-text-1 text-xl mb-2">
                DMG installer
              </h3>
              <p className="ww-text-2 text-base leading-relaxed mb-5">
                The simplest path for most people.
              </p>
              <ol className="space-y-3 flex-1">
                <Step n={1}>
                  Download the latest <code className="ww-mono ww-text-1">.dmg</code>{" "}
                  from GitHub Releases.
                </Step>
                <Step n={2}>
                  Open the DMG and drag <strong className="ww-text-1">WolfWave</strong>{" "}
                  into Applications.
                </Step>
                <Step n={3}>
                  Launch WolfWave and follow the setup wizard.
                </Step>
              </ol>
              <a
                href={LATEST_RELEASE_URL}
                target="_blank"
                rel="noopener noreferrer"
                className="ww-btn ww-btn-primary mt-6"
              >
                <Download className="w-4 h-4" />
                Download for Mac
              </a>
            </div>

            {/* Homebrew — for developers */}
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
                <span className="ww-pill">For developers</span>
              </div>
              <h3 className="ww-display ww-text-1 text-xl mb-2">Homebrew</h3>
              <p className="ww-text-2 text-base leading-relaxed mb-5">
                Prefer the command line? Install the cask in one go.
              </p>
              <pre className="ww-code flex-1">
                {`brew tap mrdemonwolf/den
brew install --cask wolfwave`}
              </pre>
              <p className="ww-text-2 text-sm leading-relaxed mt-4">
                Updates come through{" "}
                <code className="ww-mono ww-text-1">brew upgrade --cask</code>{" "}
                instead of the in-app updater.
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* ═══════════════ NOTARIZED ═══════════════ */}
      <section className="ww-bg-surface px-6 py-24 sm:py-28">
        <div className="mx-auto max-w-3xl text-center">
          <div
            className="w-12 h-12 rounded-2xl inline-flex items-center justify-center mb-6"
            style={{
              backgroundColor: "var(--brand-50)",
              color: "var(--brand-500)",
            }}
          >
            <ShieldCheck className="w-5 h-5" />
          </div>
          <h2 className="ww-display ww-text-1 text-4xl sm:text-5xl">
            Signed and notarized by Apple.
          </h2>
          <p className="ww-text-2 text-lg mt-5 leading-relaxed">
            No Gatekeeper warnings, no "unidentified developer" prompt. WolfWave
            runs sandboxed, keeps your tokens in macOS Keychain, and sends no
            telemetry — there's nothing to send.
          </p>
          <div className="mt-8 flex flex-wrap items-center justify-center gap-2">
            {["Notarized", "Sandboxed", "Keychain", "No telemetry"].map(
              (label) => (
                <span key={label} className="ww-pill">
                  {label}
                </span>
              ),
            )}
          </div>
        </div>
      </section>

      {/* ═══════════════ AFTER YOU INSTALL ═══════════════ */}
      <section className="ww-bg-base px-6 py-24 sm:py-32">
        <div className="mx-auto max-w-3xl">
          <div className="text-center">
            <div
              className="w-12 h-12 rounded-2xl inline-flex items-center justify-center mb-6 mx-auto"
              style={{
                backgroundColor: "var(--brand-50)",
                color: "var(--brand-500)",
              }}
            >
              <Sparkles className="w-5 h-5" />
            </div>
            <h2 className="ww-display ww-text-1 text-4xl sm:text-5xl">
              After you install.
            </h2>
            <p className="ww-text-2 text-lg mt-5 leading-relaxed">
              WolfWave opens a quick setup wizard the first time you launch it.
            </p>
          </div>

          <ol className="mt-10 space-y-4 max-w-md mx-auto">
            <Step n={1}>
              Allow Apple Music access when macOS asks.
            </Step>
            <Step n={2}>
              Connect Twitch and Discord — both optional, both skippable.
            </Step>
            <Step n={3}>
              Turn on the OBS widget if you stream.
            </Step>
          </ol>

          <div className="mt-10 flex flex-wrap items-center justify-center gap-3">
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
