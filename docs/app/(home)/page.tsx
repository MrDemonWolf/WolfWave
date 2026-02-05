import Link from "next/link";

export default function HomePage() {
  return (
    <main className="flex-1 flex items-center justify-center px-6 py-20">
      <div className="max-w-4xl w-full text-center">
        {/* Main Branding Header */}
        <h1 className="text-5xl sm:text-6xl font-extrabold mb-6 leading-tight text-slate-900 dark:text-white">
          WolfWave — Sync Your Soundtrack
        </h1>

        {/* Updated Value Proposition */}
        <p className="text-xl mb-10 max-w-3xl mx-auto leading-relaxed text-slate-600 dark:text-slate-300">
          The professional macOS companion for broadcasters. Seamlessly bridge
          Apple Music with your Twitch community using high-performance
          WebSockets and secure Helix API integration.
        </p>

        {/* Action Buttons */}
        <div className="flex flex-wrap justify-center gap-4 mb-16">
          <Link
            href="/docs/installation"
            className="inline-flex items-center gap-2 bg-blue-600 hover:bg-blue-700 text-white px-8 py-3 rounded-lg font-semibold shadow-lg hover:shadow-xl transition-all"
          >
            <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor">
              <path d="M19 9h-4V3H9v6H5l7 7 7-7zM5 18v2h14v-2H5z" />
            </svg>
            Download
          </Link>

          <Link
            href="/docs"
            className="inline-block border-2 border-slate-300 dark:border-slate-600 text-slate-700 dark:text-white px-8 py-3 rounded-lg font-semibold hover:bg-slate-100 dark:hover:bg-slate-800 transition-all"
          >
            Documentation
          </Link>

          <a
            href="https://github.com/MrDemonWolf/WolfWave"
            target="_blank"
            rel="noopener noreferrer"
            className="inline-flex items-center gap-2 border-2 border-slate-300 dark:border-slate-600 text-slate-700 dark:text-white px-8 py-3 rounded-lg font-semibold hover:bg-slate-100 dark:hover:bg-slate-800 transition-all"
          >
            <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor">
              <path d="M12 0c-6.626 0-12 5.373-12 12 0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576 4.765-1.589 8.199-6.086 8.199-11.386 0-6.627-5.373-12-12-12z" />
            </svg>
            GitHub
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
