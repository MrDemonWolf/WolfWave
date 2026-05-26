export interface OgPreset {
  eyebrow: string;
  chips: string[];
}

const PRESETS: Record<string, OgPreset> = {
  "": { eyebrow: "Free for macOS 26+", chips: ["Apple Music", "Twitch", "Discord", "OBS"] },
  features: { eyebrow: "All-in-one", chips: ["!song bot", "Discord RPC", "OBS Overlay", "Song Requests"] },
  "getting-started": { eyebrow: "Build from source", chips: ["Xcode 16", "Swift 5.9", "macOS 26", "Open Source"] },
  installation: { eyebrow: "Install in 2 minutes", chips: ["DMG", "Homebrew", "Apple Silicon", "Free"] },
  usage: { eyebrow: "5-minute setup", chips: ["Twitch", "Discord", "OBS", "Apple Music"] },
  "bot-commands": { eyebrow: "For Apple Music", chips: ["!song", "!sr", "!queue", "!voteskip"] },
  changelog: { eyebrow: "What's new", chips: ["Releases", "Auto-update"] },
  development: { eyebrow: "Contribute", chips: ["Swift", "SwiftUI", "Xcode", "1218 tests"] },
  architecture: { eyebrow: "Under the hood", chips: ["MVVM", "EventSub", "ScriptingBridge", "WebSocket"] },
  security: { eyebrow: "Tokens stay safe", chips: ["Keychain", "App Sandbox", "OAuth", "EdDSA"] },
  "privacy-policy": { eyebrow: "Local-first", chips: ["No Tracking", "No Servers", "Open Source"] },
  "terms-of-service": { eyebrow: "MIT license", chips: ["Free", "Open Source", "No Warranty"] },
  support: { eyebrow: "Support WolfWave", chips: ["GitHub Sponsors", "MIT", "Free Forever"] },
  "design-system": { eyebrow: "Design System", chips: ["Tokens", "Components", "Brand", "Liquid Glass"] },
};

export function presetForSlug(slug: string[] | undefined): OgPreset {
  const key = slug?.[0] ?? "";
  return PRESETS[key] ?? PRESETS[""];
}
