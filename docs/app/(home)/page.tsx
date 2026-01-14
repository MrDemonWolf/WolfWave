import Link from "next/link";

export default function HomePage() {
  return (
    <main className="flex-1 flex items-center justify-center px-6 py-20">
      <div className="max-w-3xl w-full text-center">
        <h1
          className="text-4xl sm:text-5xl font-extrabold mb-4 text-slate-900 dark:text-white"
          style={{ color: "var(--heading-color)" }}
        >
          WolfWave — Share Your Sound
        </h1>

        <p className="text-lg text-slate-700 dark:text-slate-300 mb-8 max-w-2xl mx-auto">
          Streamline your Twitch presence with a privacy-first "Now Playing"
          companion for macOS. Show what you're listening to, let chat ask for
          the current track, and broadcast updates to overlays — all secured by
          the macOS Keychain.
        </p>

        <div className="flex justify-center gap-4 mb-10">
          <Link
            href="/docs"
            className="brand-btn-primary px-6 py-2 rounded-md font-medium shadow-sm hover:opacity-95"
          >
            Explore Docs
          </Link>

          <a
            href="https://github.com/MrDemonWolf/WolfWave"
            target="_blank"
            rel="noopener noreferrer"
            className="inline-block border border-slate-700 text-slate-700 dark:text-slate-200 px-6 py-2 rounded-md font-medium hover:bg-slate-100 dark:hover:bg-slate-800"
          >
            View on GitHub
          </a>
        </div>

        <section className="grid sm:grid-cols-3 gap-6 text-left">
          <div className="p-4">
            <div
              className="mx-auto mb-3 w-10 h-10 rounded-full inline-flex items-center justify-center"
              style={{
                backgroundColor: "var(--fd-primary)",
                color: "var(--fd-primary-foreground)",
              }}
            >
              <svg
                width="16"
                height="16"
                viewBox="0 0 24 24"
                fill="currentColor"
                aria-hidden="true"
              >
                <path d="M4 2v20l18-10L4 2z" />
              </svg>
            </div>
            <h3
              className="font-semibold mb-2 text-slate-900 dark:text-white"
              style={{ color: "var(--heading-color)" }}
            >
              Live Overlays
            </h3>
            <p className="text-sm text-slate-600 dark:text-slate-400">
              Push now-playing data to overlays and tools in real time.
            </p>
          </div>

          <div className="p-4">
            <div
              className="mx-auto mb-3 w-10 h-10 rounded-full inline-flex items-center justify-center"
              style={{
                backgroundColor: "var(--fd-primary)",
                color: "var(--fd-primary-foreground)",
              }}
            >
              <svg
                width="16"
                height="16"
                viewBox="0 0 24 24"
                fill="currentColor"
                aria-hidden="true"
              >
                <path d="M21 6h-2v9H7v2a1 1 0 0 1-1 1H4l-1 1V6a1 1 0 0 1 1-1h17a1 1 0 0 1 1 1v0zM6 11h12V8H6v3z" />
              </svg>
            </div>
            <h3
              className="font-semibold mb-2 text-slate-900 dark:text-white"
              style={{ color: "var(--heading-color)" }}
            >
              Chat Commands
            </h3>
            <p className="text-sm text-slate-600 dark:text-slate-400">
              Support{" "}
              <code className="bg-slate-100 px-1 rounded text-[0.8125rem] dark:bg-slate-800">
                !song
              </code>{" "}
              and related commands with secure bot auth.
            </p>
          </div>

          <div className="p-4">
            <div
              className="mx-auto mb-3 w-10 h-10 rounded-full inline-flex items-center justify-center"
              style={{
                backgroundColor: "var(--fd-primary)",
                color: "var(--fd-primary-foreground)",
              }}
            >
              <svg
                width="16"
                height="16"
                viewBox="0 0 24 24"
                fill="currentColor"
                aria-hidden="true"
              >
                <path d="M12 1l8 4v6c0 5.523-3.582 10.74-8 12-4.418-1.26-8-6.477-8-12V5l8-4zM11 11h2v5h-2v-5z" />
              </svg>
            </div>
            <h3
              className="font-semibold mb-2 text-slate-900 dark:text-white"
              style={{ color: "var(--heading-color)" }}
            >
              Privacy-First
            </h3>
            <p className="text-sm text-slate-600 dark:text-slate-400">
              All credentials stored in Keychain — no plaintext tokens.
            </p>
          </div>
        </section>
      </div>
    </main>
  );
}
