import Link from "next/link";
import {
  ArrowRight,
  Download,
  Github,
  MessageSquare,
  Radio,
  Wifi,
  Shield,
  Music,
  Code2,
  Headphones,
  Twitch,
} from "lucide-react";

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

export default function HomePage() {
  return (
    <main className="ww-font ww-bg-base">
      {/* ═══════════════ HERO ═══════════════ */}
      <section className="relative overflow-hidden">
        <div className="ww-hero-glow" aria-hidden="true" />
        <div className="relative z-10 px-6 pt-24 pb-20 sm:pt-32 sm:pb-28">
          <div className="mx-auto max-w-4xl text-center">
            <p className="ww-reveal ww-reveal-1 ww-text-brand text-sm font-semibold mb-5">
              Now available · macOS 26+
            </p>
            <h1 className="ww-reveal ww-reveal-1 ww-display ww-text-1 text-5xl sm:text-7xl lg:text-[5.5rem]">
              Your music.
              <br />
              <span className="ww-text-brand">Everywhere you stream.</span>
            </h1>
            <p className="ww-reveal ww-reveal-2 ww-text-2 text-lg sm:text-xl mt-7 max-w-2xl mx-auto leading-relaxed">
              WolfWave is a tiny menu bar app for Mac. Play something in Apple
              Music — Twitch chat, your Discord profile, and your stream
              overlay all update on their own.
            </p>
            <div className="ww-reveal ww-reveal-3 mt-10 flex flex-col sm:flex-row items-center justify-center gap-3">
              <Link href="/download" className="ww-btn ww-btn-primary">
                <Download className="w-4 h-4" />
                Download for Mac
              </Link>
              <Link href="/docs" className="ww-btn ww-btn-secondary">
                Learn more
                <ArrowRight className="w-4 h-4" />
              </Link>
            </div>
            <p className="mt-5 text-sm ww-text-2">
              Free and open source · 3.7 MB · No account needed
            </p>
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
                body: "Viewers always know the track. !song, song requests, and a live overlay are ready the moment you finish setup.",
                href: "/docs/usage",
                cta: "Streaming guide",
              },
              {
                icon: Headphones,
                title: "For listeners",
                body: "Show friends what you're playing in Discord — album art, real progress, your full Apple Music library.",
                href: "/docs/features",
                cta: "What's included",
              },
              {
                icon: Code2,
                title: "For developers",
                body: "A local WebSocket exposes every play, pause, and skip. Build a custom overlay in roughly 20 lines.",
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
              Show what you're listening to.
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
              Drop it in OBS.
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

      {/* ═══════════════ DEVELOPERS ═══════════════ */}
      <section className="ww-bg-surface px-6 py-24 sm:py-32">
        <div className="mx-auto max-w-5xl">
          <SectionHead
            eyebrow="For developers"
            title={<>Native Swift. Open source.</>}
            sub={
              <>
                Zero external dependencies. The WebSocket feed is fully
                documented — wire it into your overlay, your Home Assistant
                dashboard, or a Stream Deck plugin.
              </>
            }
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

      {/* ═══════════════ CTA ═══════════════ */}
      <section className="ww-bg-surface px-6 py-28 sm:py-36">
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
          </div>
          <p className="mt-5 text-sm ww-text-2">
            Free forever · macOS 26+ · Built native
          </p>
        </div>
      </section>
    </main>
  );
}
