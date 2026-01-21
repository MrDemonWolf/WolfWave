import Link from "next/link";

export default function HomePage() {
  return (
    <main className="flex-1 flex items-center justify-center px-6 py-20">
      <div className="max-w-4xl w-full text-center">
        {/* Main Branding Header */}
        <h1
          className="text-5xl sm:text-6xl font-extrabold mb-6 text-slate-900 dark:text-white leading-tight"
          style={{ color: "var(--heading-color)" }}
        >
          WolfWave — Sync Your Soundtrack
        </h1>

        {/* Updated Value Proposition */}
        <p className="text-xl text-slate-700 dark:text-slate-300 mb-10 max-w-3xl mx-auto leading-relaxed">
          The professional macOS companion for broadcasters. Seamlessly bridge
          Apple Music with your Twitch community using high-performance
          WebSockets and secure Helix API integration.
        </p>

        {/* Action Buttons */}
        <div className="flex justify-center gap-4 mb-16">
          <Link
            href="/docs"
            className="brand-btn-primary px-8 py-3 rounded-lg font-semibold shadow-md hover:opacity-95 transition-all"
          >
            Get Started
          </Link>

          <a
            href="https://github.com/MrDemonWolf/WolfWave"
            target="_blank"
            rel="noopener noreferrer"
            className="inline-block border border-slate-700 text-slate-700 dark:text-slate-200 px-8 py-3 rounded-lg font-semibold hover:bg-slate-100 dark:hover:bg-slate-800 transition-all"
          >
            View on GitHub
          </a>
        </div>

        {/* Refined Feature Grid */}
        <section className="grid sm:grid-cols-3 gap-8 text-left border-t border-slate-200 dark:border-slate-800 pt-12">
          {/* Feature 1: Real-time Data */}
          <div className="p-4">
            <div
              className="mb-4 w-12 h-12 rounded-xl inline-flex items-center justify-center shadow-sm"
              style={{
                backgroundColor: "var(--fd-primary)",
                color: "var(--fd-primary-foreground)",
              }}
            >
              <svg
                width="20"
                height="20"
                viewBox="0 0 24 24"
                fill="currentColor"
              >
                <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-1 14H9V8h2v8zm4 0h-2V8h2v8z" />
              </svg>
            </div>
            <h3 className="font-bold text-lg mb-2 text-slate-900 dark:text-white">
              WebSocket Broadcast
            </h3>
            <p className="text-sm text-slate-600 dark:text-slate-400 leading-relaxed">
              Stream live playback metadata to OBS overlays and web tools via
              secure, high-speed WebSocket connections.
            </p>
          </div>

          {/* Feature 2: Twitch Interaction */}
          <div className="p-4">
            <div
              className="mb-4 w-12 h-12 rounded-xl inline-flex items-center justify-center shadow-sm"
              style={{
                backgroundColor: "var(--fd-primary)",
                color: "var(--fd-primary-foreground)",
              }}
            >
              <svg
                width="20"
                height="20"
                viewBox="0 0 24 24"
                fill="currentColor"
              >
                <path d="M11.5 2C6.81 2 3 5.81 3 10.5S6.81 19 11.5 19h.5v3l3-3h5c.55 0 1-.45 1-1v-9c0-4.69-3.81-8.5-8.5-8.5z" />
              </svg>
            </div>
            <h3 className="font-bold text-lg mb-2 text-slate-900 dark:text-white">
              Twitch Bot Integration
            </h3>
            <p className="text-sm text-slate-600 dark:text-slate-400 leading-relaxed">
              Automate{" "}
              <code className="bg-slate-100 px-1 rounded dark:bg-slate-800 text-xs">
                !song
              </code>{" "}
              commands using Twitch EventSub and Helix for a modern chat
              experience.
            </p>
          </div>

          {/* Feature 3: Native Security */}
          <div className="p-4">
            <div
              className="mb-4 w-12 h-12 rounded-xl inline-flex items-center justify-center shadow-sm"
              style={{
                backgroundColor: "var(--fd-primary)",
                color: "var(--fd-primary-foreground)",
              }}
            >
              <svg
                width="20"
                height="20"
                viewBox="0 0 24 24"
                fill="currentColor"
              >
                <path d="M18 8h-1V6c0-2.76-2.24-5-5-5S7 3.24 7 6v2H6c-1.1 0-2 .9-2 2v10c0 1.1.9 2 2 2h12c1.1 0 2-.9 2-2V10c0-1.1-.9-2-2-2zM9 6c0-1.66 1.34-3 3-3s3 1.34 3 3v2H9V6z" />
              </svg>
            </div>
            <h3 className="font-bold text-lg mb-2 text-slate-900 dark:text-white">
              Native Security
            </h3>
            <p className="text-sm text-slate-600 dark:text-slate-400 leading-relaxed">
              Engineered for macOS with direct ScriptingBridge access and
              encrypted Keychain credential storage.
            </p>
          </div>
        </section>
      </div>
    </main>
  );
}
