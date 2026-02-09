import Link from "next/link";

export default function HomePage() {
  return (
    <main className="flex-1 flex items-center justify-center px-6 py-20">
      <div className="max-w-4xl w-full text-center">
        {/* Main Branding Header */}
        <h1 className="text-5xl sm:text-6xl font-extrabold mb-6 leading-tight text-slate-900 dark:text-white">
          Your Music, Everywhere
        </h1>

        {/* Value Proposition */}
        <p className="text-xl mb-10 max-w-3xl mx-auto leading-relaxed text-slate-600 dark:text-slate-300">
          The professional macOS companion that bridges Apple Music with the
          platforms you use. Stream to Twitch chat, show on Discord, broadcast to
          overlays — all from your menu bar.
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

        {/* Feature Grid */}
        <section className="grid sm:grid-cols-2 lg:grid-cols-4 gap-8 text-left border-t border-slate-200 dark:border-slate-800 pt-12">
          {/* Feature 1: Apple Music */}
          <div className="p-4">
            <div
              className="mb-4 w-12 h-12 rounded-xl inline-flex items-center justify-center shadow-sm"
              style={{
                backgroundColor: "var(--fd-primary)",
                color: "var(--fd-primary-foreground)",
              }}
            >
              <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor">
                <path d="M12 3v10.55c-.59-.34-1.27-.55-2-.55-2.21 0-4 1.79-4 4s1.79 4 4 4 4-1.79 4-4V7h4V3h-6z" />
              </svg>
            </div>
            <h3 className="font-bold text-lg mb-2 text-slate-900 dark:text-white">
              Apple Music
            </h3>
            <p className="text-sm text-slate-600 dark:text-slate-400 leading-relaxed">
              Real-time track detection via ScriptingBridge. Artist, title, album,
              and artwork — instantly.
            </p>
          </div>

          {/* Feature 2: Twitch Bot */}
          <div className="p-4">
            <div
              className="mb-4 w-12 h-12 rounded-xl inline-flex items-center justify-center shadow-sm"
              style={{
                backgroundColor: "var(--fd-primary)",
                color: "var(--fd-primary-foreground)",
              }}
            >
              <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor">
                <path d="M11.5 2C6.81 2 3 5.81 3 10.5S6.81 19 11.5 19h.5v3l3-3h5c.55 0 1-.45 1-1v-9c0-4.69-3.81-8.5-8.5-8.5z" />
              </svg>
            </div>
            <h3 className="font-bold text-lg mb-2 text-slate-900 dark:text-white">
              Twitch Chat Bot
            </h3>
            <p className="text-sm text-slate-600 dark:text-slate-400 leading-relaxed">
              <code className="bg-slate-100 px-1 rounded dark:bg-slate-800 text-xs">
                !song
              </code>{" "}
              and{" "}
              <code className="bg-slate-100 px-1 rounded dark:bg-slate-800 text-xs">
                !lastsong
              </code>{" "}
              commands via modern EventSub + Helix API.
            </p>
          </div>

          {/* Feature 3: Discord Rich Presence */}
          <div className="p-4">
            <div
              className="mb-4 w-12 h-12 rounded-xl inline-flex items-center justify-center shadow-sm"
              style={{
                backgroundColor: "var(--fd-primary)",
                color: "var(--fd-primary-foreground)",
              }}
            >
              <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor">
                <path d="M20.317 4.37a19.791 19.791 0 00-4.885-1.515.074.074 0 00-.079.037c-.21.375-.444.864-.608 1.25a18.27 18.27 0 00-5.487 0 12.64 12.64 0 00-.617-1.25.077.077 0 00-.079-.037A19.736 19.736 0 003.677 4.37a.07.07 0 00-.032.027C.533 9.046-.32 13.58.099 18.057a.082.082 0 00.031.057 19.9 19.9 0 005.993 3.03.078.078 0 00.084-.028c.462-.63.874-1.295 1.226-1.994a.076.076 0 00-.041-.106 13.107 13.107 0 01-1.872-.892.077.077 0 01-.008-.128 10.2 10.2 0 00.372-.292.074.074 0 01.077-.01c3.928 1.793 8.18 1.793 12.062 0a.074.074 0 01.078.01c.12.098.246.198.373.292a.077.077 0 01-.006.127 12.299 12.299 0 01-1.873.892.077.077 0 00-.041.107c.36.698.772 1.362 1.225 1.993a.076.076 0 00.084.028 19.839 19.839 0 006.002-3.03.077.077 0 00.032-.054c.5-5.177-.838-9.674-3.549-13.66a.061.061 0 00-.031-.03z" />
              </svg>
            </div>
            <h3 className="font-bold text-lg mb-2 text-slate-900 dark:text-white">
              Discord Rich Presence
            </h3>
            <p className="text-sm text-slate-600 dark:text-slate-400 leading-relaxed">
              Show &ldquo;Listening to Apple Music&rdquo; on your Discord profile with
              dynamic album artwork.
            </p>
          </div>

          {/* Feature 4: WebSocket + Security */}
          <div className="p-4">
            <div
              className="mb-4 w-12 h-12 rounded-xl inline-flex items-center justify-center shadow-sm"
              style={{
                backgroundColor: "var(--fd-primary)",
                color: "var(--fd-primary-foreground)",
              }}
            >
              <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor">
                <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-1 14H9V8h2v8zm4 0h-2V8h2v8z" />
              </svg>
            </div>
            <h3 className="font-bold text-lg mb-2 text-slate-900 dark:text-white">
              WebSocket Streaming
            </h3>
            <p className="text-sm text-slate-600 dark:text-slate-400 leading-relaxed">
              Broadcast live playback data to OBS overlays and web tools via
              secure WebSocket connections.
            </p>
          </div>
        </section>
      </div>
    </main>
  );
}
