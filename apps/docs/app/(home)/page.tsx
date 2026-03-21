import Link from "next/link";
import { Music, MessageSquare, Radio, Wifi, Shield, Cpu, Zap, Download, BookOpen, ArrowRight } from "lucide-react";
import { getAssetPath } from "@/lib/utils";

const features = [
  {
    icon: Music,
    title: "Apple Music",
    description: "Real-time track detection via ScriptingBridge. Artist, title, album, and artwork — instantly.",
    color: "text-sky-500 dark:text-sky-400",
    bg: "bg-sky-500/10 dark:bg-sky-500/10",
  },
  {
    icon: MessageSquare,
    title: "Twitch Chat Bot",
    description: "!song and !lastsong commands via Twitch's modern EventSub + Helix API. No deprecated IRC.",
    color: "text-blue-500 dark:text-blue-400",
    bg: "bg-blue-500/10 dark:bg-blue-500/10",
  },
  {
    icon: Radio,
    title: "Discord Rich Presence",
    description: "\"Listening to Apple Music\" on your Discord profile with dynamic album art and playback progress.",
    color: "text-indigo-500 dark:text-indigo-400",
    bg: "bg-indigo-500/10 dark:bg-indigo-500/10",
  },
  {
    icon: Wifi,
    title: "Now-Playing Widget",
    description: "Live now-playing data for OBS overlays, web widgets, and custom integrations via WebSocket.",
    color: "text-cyan-500 dark:text-cyan-400",
    bg: "bg-cyan-500/10 dark:bg-cyan-500/10",
  },
] as const;

const steps = [
  { number: "1", title: "Download", description: "Grab the latest DMG from GitHub Releases." },
  { number: "2", title: "Configure", description: "Follow the onboarding wizard to connect Twitch, Discord, and your overlays." },
  { number: "3", title: "Enjoy", description: "Play music and it shows up on Twitch, Discord, and your widgets automatically." },
] as const;

const highlights = [
  { icon: Zap, title: "Zero Dependencies", description: "Built entirely with native Apple frameworks. No Electron, no bloat." },
  { icon: Shield, title: "Secure by Default", description: "All tokens in macOS Keychain. App Sandbox enabled. Hardened Runtime." },
  { icon: Cpu, title: "Modern APIs", description: "Twitch EventSub + Helix, Discord IPC, and ScriptingBridge. No workarounds." },
] as const;

export default function HomePage() {
  return (
    <main className="flex-1">
      {/* Hero Section */}
      <section className="relative overflow-hidden px-6 pt-24 pb-20 sm:pt-32 sm:pb-32">
        <div className="hero-glow" aria-hidden="true" />
        <div className="mx-auto max-w-4xl text-center relative z-10">
          <div className="mb-8 flex justify-center">
             <div className="rounded-2xl bg-slate-900/5 dark:bg-white/5 p-4 backdrop-blur-sm ring-1 ring-slate-900/10 dark:ring-white/10 shadow-xl">
               <img src={getAssetPath("/logo.svg")} alt="WolfWave Logo" className="h-16 w-auto" />
             </div>
          </div>
          <h1 className="text-4xl sm:text-6xl lg:text-7xl font-extrabold tracking-tight leading-[1.05] mb-8">
            <span className="gradient-text">Your Music,</span>
            <br />
            <span className="text-slate-900 dark:text-white">Everywhere.</span>
          </h1>
          <p className="text-lg sm:text-xl text-slate-600 dark:text-slate-400 leading-relaxed max-w-2xl mx-auto mb-12">
            Native macOS menu bar app that shares your Apple Music with Twitch,
            Discord, and now-playing widgets. Fast, lightweight, and private.
          </p>
          <div className="flex flex-col sm:flex-row items-center justify-center gap-4">
            <Link
              href="/docs/installation"
              className="w-full sm:w-auto inline-flex items-center justify-center gap-2 bg-fd-primary text-fd-primary-foreground px-8 py-3 rounded-xl text-base font-semibold shadow-lg hover:shadow-fd-primary/20 hover:scale-[1.02] active:scale-[0.98] transition-all"
            >
              <Download className="w-5 h-5" />
              Get WolfWave
            </Link>
            <Link
              href="/docs"
              className="w-full sm:w-auto inline-flex items-center justify-center gap-2 border-2 border-slate-200 dark:border-slate-800 text-slate-700 dark:text-slate-300 px-8 py-3 rounded-xl text-base font-semibold hover:bg-slate-50 dark:hover:bg-slate-800/50 hover:border-slate-300 dark:hover:border-slate-700 transition-all"
            >
              <BookOpen className="w-5 h-5" />
              Documentation
            </Link>
          </div>
        </div>
      </section>

      {/* Features Grid */}
      <section className="px-6 pb-24">
        <div className="mx-auto max-w-5xl">
          <div className="grid sm:grid-cols-2 lg:grid-cols-4 gap-6">
            {features.map((feature) => (
              <div
                key={feature.title}
                className="feature-card group bg-white/50 dark:bg-white/5 backdrop-blur-sm p-6 rounded-2xl border border-slate-200 dark:border-slate-800 hover:border-fd-primary/50 dark:hover:border-fd-primary/50 transition-all duration-300"
              >
                <div className={`shrink-0 w-12 h-12 rounded-xl ${feature.bg} ${feature.color} inline-flex items-center justify-center mb-4 group-hover:scale-110 transition-transform`}>
                  <feature.icon className="w-6 h-6" />
                </div>
                <div className="min-w-0">
                  <h3 className="font-bold text-base text-slate-900 dark:text-white mb-2">
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
      <section className="px-6 pb-24 bg-slate-50/50 dark:bg-slate-900/20 py-20">
        <div className="mx-auto max-w-4xl">
          <h2 className="text-2xl sm:text-3xl font-bold text-center mb-12 text-slate-900 dark:text-white">
            Get Started in Minutes
          </h2>
          <div className="grid sm:grid-cols-3 gap-8">
            {steps.map((step) => (
              <div key={step.number} className="relative text-center group">
                <div className="w-12 h-12 rounded-2xl bg-fd-primary text-fd-primary-foreground inline-flex items-center justify-center text-lg font-bold mb-4 shadow-lg shadow-fd-primary/20 group-hover:rotate-3 transition-transform">
                  {step.number}
                </div>
                <h3 className="font-bold text-lg mb-2 text-slate-900 dark:text-white">
                  {step.title}
                </h3>
                <p className="text-sm text-slate-500 dark:text-slate-400 leading-relaxed px-4">
                  {step.description}
                </p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Why WolfWave */}
      <section className="px-6 py-24 border-t border-slate-100 dark:border-slate-800/50">
        <div className="mx-auto max-w-4xl">
          <h2 className="text-2xl sm:text-3xl font-bold text-center mb-12 text-slate-900 dark:text-white">
            Built for Performance
          </h2>
          <div className="grid sm:grid-cols-3 gap-10">
            {highlights.map((item) => (
              <div key={item.title} className="text-center group">
                <div className="w-14 h-14 rounded-2xl bg-slate-100 dark:bg-slate-800 text-slate-600 dark:text-slate-400 inline-flex items-center justify-center mb-4 group-hover:bg-fd-primary group-hover:text-white transition-colors duration-300">
                  <item.icon className="w-7 h-7" />
                </div>
                <h3 className="font-bold text-lg mb-2 text-slate-900 dark:text-white">
                  {item.title}
                </h3>
                <p className="text-sm text-slate-500 dark:text-slate-400 leading-relaxed">
                  {item.description}
                </p>
              </div>
            ))}
          </div>
          <div className="text-center mt-16">
            <Link
              href="/docs"
              className="inline-flex items-center gap-2 text-base text-fd-primary hover:gap-3 transition-all font-semibold"
            >
              Explore the documentation
              <ArrowRight className="w-5 h-5" />
            </Link>
          </div>
        </div>
      </section>
    </main>
  );
}
