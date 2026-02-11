import Link from "next/link";
import { Music, MessageSquare, Radio, Wifi, Shield, Cpu, Zap, Download, BookOpen, ArrowRight } from "lucide-react";

const features = [
  {
    icon: Music,
    title: "Apple Music",
    description: "Real-time track detection via ScriptingBridge. Artist, title, album, and artwork — instantly.",
    color: "text-rose-500 dark:text-rose-400",
    bg: "bg-rose-500/10 dark:bg-rose-500/10",
  },
  {
    icon: MessageSquare,
    title: "Twitch Chat Bot",
    description: "!song and !lastsong commands via Twitch's modern EventSub + Helix API. No deprecated IRC.",
    color: "text-violet-500 dark:text-violet-400",
    bg: "bg-violet-500/10 dark:bg-violet-500/10",
  },
  {
    icon: Radio,
    title: "Discord Rich Presence",
    description: "\"Listening to Apple Music\" on your Discord profile with dynamic album art and playback progress.",
    color: "text-blue-500 dark:text-blue-400",
    bg: "bg-blue-500/10 dark:bg-blue-500/10",
  },
  {
    icon: Wifi,
    title: "WebSocket Streaming",
    description: "Broadcast live now-playing data to OBS overlays and web tools via secure WebSocket connections.",
    color: "text-emerald-500 dark:text-emerald-400",
    bg: "bg-emerald-500/10 dark:bg-emerald-500/10",
  },
] as const;

const steps = [
  { number: "1", title: "Download", description: "Grab the latest DMG from GitHub Releases. Signed and notarized by Apple." },
  { number: "2", title: "Configure", description: "Follow the onboarding wizard to connect Twitch, Discord, and your overlays." },
  { number: "3", title: "Stream", description: "Play music and it appears on Twitch, Discord, and your overlays automatically." },
] as const;

const highlights = [
  { icon: Zap, title: "Zero Dependencies", description: "Built entirely with native Apple frameworks. No Electron, no bloat." },
  { icon: Shield, title: "Secure by Default", description: "All tokens in macOS Keychain. App Sandbox enabled. Signed and notarized." },
  { icon: Cpu, title: "Modern APIs", description: "Twitch EventSub + Helix, Discord IPC, and ScriptingBridge. No workarounds." },
] as const;

export default function HomePage() {
  return (
    <main className="flex-1">
      {/* Hero Section */}
      <section className="relative overflow-hidden px-6 pt-24 pb-20 sm:pt-32 sm:pb-28">
        <div className="hero-glow" aria-hidden="true" />
        <div className="mx-auto max-w-3xl text-center relative z-10">
          <h1 className="text-4xl sm:text-5xl lg:text-6xl font-extrabold tracking-tight leading-[1.1] mb-6">
            <span className="gradient-text">Your Music,</span>
            <br />
            <span className="text-slate-900 dark:text-white">Everywhere</span>
          </h1>
          <p className="text-base sm:text-lg text-slate-600 dark:text-slate-400 leading-relaxed max-w-2xl mx-auto mb-10">
            A native macOS menu bar app that bridges Apple Music with Twitch,
            Discord, and your stream overlays. Real-time, lightweight, zero dependencies.
          </p>
          <div className="flex flex-wrap justify-center gap-3">
            <Link
              href="/docs/installation"
              className="inline-flex items-center gap-2 bg-fd-primary text-fd-primary-foreground px-6 py-2.5 rounded-lg text-sm font-medium shadow-sm hover:opacity-90 transition-opacity"
            >
              <Download className="w-4 h-4" />
              Download
            </Link>
            <Link
              href="/docs"
              className="inline-flex items-center gap-2 border border-slate-200 dark:border-slate-700 text-slate-700 dark:text-slate-300 px-6 py-2.5 rounded-lg text-sm font-medium hover:bg-slate-50 dark:hover:bg-slate-800/50 transition-colors"
            >
              <BookOpen className="w-4 h-4" />
              Documentation
            </Link>
          </div>
        </div>
      </section>

      {/* Features Grid */}
      <section className="px-6 pb-20">
        <div className="mx-auto max-w-4xl">
          <div className="grid sm:grid-cols-2 gap-4">
            {features.map((feature) => (
              <div
                key={feature.title}
                className="feature-card group flex gap-4 items-start"
              >
                <div className={`shrink-0 w-10 h-10 rounded-lg ${feature.bg} ${feature.color} inline-flex items-center justify-center`}>
                  <feature.icon className="w-5 h-5" />
                </div>
                <div className="min-w-0">
                  <h3 className="font-semibold text-sm text-slate-900 dark:text-white mb-1">
                    {feature.title}
                  </h3>
                  <p className="text-sm text-slate-500 dark:text-slate-400 leading-relaxed">
                    {feature.description}
                  </p>
                </div>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Get Started Steps */}
      <section className="px-6 pb-20">
        <div className="mx-auto max-w-3xl">
          <h2 className="text-xl sm:text-2xl font-bold text-center mb-10 text-slate-900 dark:text-white">
            Get Started in 3 Steps
          </h2>
          <div className="grid sm:grid-cols-3 gap-6">
            {steps.map((step) => (
              <div key={step.number} className="text-center">
                <div className="w-10 h-10 rounded-full bg-fd-primary/10 text-fd-primary inline-flex items-center justify-center text-sm font-bold mb-3">
                  {step.number}
                </div>
                <h3 className="font-semibold text-sm mb-1 text-slate-900 dark:text-white">
                  {step.title}
                </h3>
                <p className="text-xs text-slate-500 dark:text-slate-400 leading-relaxed">
                  {step.description}
                </p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Why WolfWave */}
      <section className="px-6 pb-24 border-t border-slate-100 dark:border-slate-800/50 pt-16">
        <div className="mx-auto max-w-3xl">
          <h2 className="text-xl sm:text-2xl font-bold text-center mb-10 text-slate-900 dark:text-white">
            Why WolfWave?
          </h2>
          <div className="grid sm:grid-cols-3 gap-6">
            {highlights.map((item) => (
              <div key={item.title} className="text-center">
                <div className="w-10 h-10 rounded-lg bg-slate-100 dark:bg-slate-800 text-slate-600 dark:text-slate-400 inline-flex items-center justify-center mb-3">
                  <item.icon className="w-5 h-5" />
                </div>
                <h3 className="font-semibold text-sm mb-1 text-slate-900 dark:text-white">
                  {item.title}
                </h3>
                <p className="text-xs text-slate-500 dark:text-slate-400 leading-relaxed">
                  {item.description}
                </p>
              </div>
            ))}
          </div>
          <div className="text-center mt-12">
            <Link
              href="/docs"
              className="inline-flex items-center gap-1.5 text-sm text-fd-primary hover:underline font-medium"
            >
              Read the docs
              <ArrowRight className="w-3.5 h-3.5" />
            </Link>
          </div>
        </div>
      </section>
    </main>
  );
}
