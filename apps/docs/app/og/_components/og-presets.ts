export interface OgPreset {
  eyebrow: string;
  chips: string[];
}

const PRESETS: Record<string, OgPreset> = {
  "": { eyebrow: "WolfWave Docs", chips: ["Twitch", "Discord", "OBS", "Apple Music"] },
  features: { eyebrow: "Features", chips: ["Twitch", "Discord", "OBS", "Apple Music"] },
  "getting-started": { eyebrow: "Getting Started", chips: ["Install", "Connect", "Stream", "Done"] },
  installation: { eyebrow: "Install Guide", chips: ["Homebrew", "DMG", "macOS 26+", "Free"] },
  usage: { eyebrow: "Usage", chips: ["Menu Bar", "Settings", "Now Playing", "Overlay"] },
  "bot-commands": { eyebrow: "Bot Commands", chips: ["!song", "!sr", "!queue", "!skip"] },
  changelog: { eyebrow: "Changelog", chips: ["Releases", "What's New"] },
  development: { eyebrow: "Development", chips: ["Swift", "SwiftUI", "Xcode", "Open Source"] },
  architecture: { eyebrow: "Architecture", chips: ["MVVM", "Services", "ScriptingBridge", "EventSub"] },
  security: { eyebrow: "Security", chips: ["Keychain", "Sandbox", "OAuth", "Audited"] },
  "privacy-policy": { eyebrow: "Privacy", chips: ["No Tracking", "Local-First", "Open Source"] },
  "terms-of-service": { eyebrow: "Terms", chips: ["MIT License", "Free", "Open Source"] },
};

export function presetForSlug(slug: string[] | undefined): OgPreset {
  const key = slug?.[0] ?? "";
  return PRESETS[key] ?? PRESETS[""];
}
