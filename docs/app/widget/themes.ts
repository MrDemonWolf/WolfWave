// MARK: - Types

export interface WidgetConfigData {
  theme: string;
  layout: string;
  textColor: string;
  backgroundColor: string;
  fontFamily: string;
}

export interface ResolvedThemeStyles {
  containerBg: string;
  containerBorder: string;
  containerShadow: string;
  containerRadius: string;
  backdropFilter: string;
  overlayBg: string;
  textPrimary: string;
  textSecondary: string;
  textMuted: string;
  textShadow: string;
  fontFamily: string;
  progressTrackBg: string;
  progressFillBg: string;
  showArtworkBlur: boolean;
}

export interface LayoutDimensions {
  maxWidth: number;
  height: number;
}

// MARK: - Font Map

const fontMap: Record<string, string> = {
  // Built-in
  System: '-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif',
  Monospaced: '"SF Mono", "Fira Code", monospace',
  Rounded: 'ui-rounded, "SF Pro Rounded", system-ui',
  Serif: '"New York", "Iowan Old Style", Georgia, serif',
  // Google Fonts
  Montserrat: '"Montserrat", sans-serif',
  Roboto: '"Roboto", sans-serif',
  "Open Sans": '"Open Sans", sans-serif',
  Lato: '"Lato", sans-serif',
  Poppins: '"Poppins", sans-serif',
  "Fira Code": '"Fira Code", monospace',
  "JetBrains Mono": '"JetBrains Mono", monospace',
  Oswald: '"Oswald", sans-serif',
  "Bebas Neue": '"Bebas Neue", sans-serif',
  Raleway: '"Raleway", sans-serif',
  "Press Start 2P": '"Press Start 2P", monospace',
  "Permanent Marker": '"Permanent Marker", cursive',
};

const googleFonts = new Set([
  "Montserrat",
  "Roboto",
  "Open Sans",
  "Lato",
  "Poppins",
  "Fira Code",
  "JetBrains Mono",
  "Oswald",
  "Bebas Neue",
  "Raleway",
  "Press Start 2P",
  "Permanent Marker",
]);

export function preloadAllGoogleFonts() {
  const id = "gfonts-preload";
  if (document.getElementById(id)) return;
  const families = Array.from(googleFonts)
    .map((f) => `family=${encodeURIComponent(f)}:wght@400;700`)
    .join("&");
  const link = document.createElement("link");
  link.id = id;
  link.rel = "stylesheet";
  link.href = `https://fonts.googleapis.com/css2?${families}&display=swap`;
  document.head.appendChild(link);
}

// MARK: - Theme Presets

const themePresets: Record<string, ResolvedThemeStyles> = {
  Default: {
    containerBg: "transparent",
    containerBorder: "none",
    containerShadow: "0 0 4px rgba(0,0,0,1)",
    containerRadius: "12px",
    backdropFilter: "none",
    overlayBg: "rgba(0,0,0,0.50)",
    textPrimary: "#FFFFFF",
    textSecondary: "rgba(255,255,255,0.90)",
    textMuted: "rgba(255,255,255,0.70)",
    textShadow: "2px 2px 2px rgb(0 0 0)",
    fontFamily: fontMap.System,
    progressTrackBg: "rgba(255,255,255,0.20)",
    progressFillBg: "#FFFFFF",
    showArtworkBlur: true,
  },
  Dark: {
    containerBg: "#0D0D0D",
    containerBorder: "1px solid rgba(255,255,255,0.08)",
    containerShadow: "0 4px 12px rgba(0,0,0,0.6)",
    containerRadius: "12px",
    backdropFilter: "none",
    overlayBg: "transparent",
    textPrimary: "#E4E4E7",
    textSecondary: "#A1A1AA",
    textMuted: "#71717A",
    textShadow: "none",
    fontFamily: fontMap.System,
    progressTrackBg: "rgba(255,255,255,0.08)",
    progressFillBg: "#A78BFA",
    showArtworkBlur: false,
  },
  Light: {
    containerBg: "rgba(255,255,255,0.92)",
    containerBorder: "1px solid rgba(0,0,0,0.08)",
    containerShadow: "0 4px 16px rgba(0,0,0,0.10)",
    containerRadius: "12px",
    backdropFilter: "blur(16px)",
    overlayBg: "transparent",
    textPrimary: "#18181B",
    textSecondary: "#3F3F46",
    textMuted: "#71717A",
    textShadow: "none",
    fontFamily: fontMap.System,
    progressTrackBg: "rgba(0,0,0,0.08)",
    progressFillBg: "#3B82F6",
    showArtworkBlur: false,
  },
  Transparent: {
    containerBg: "transparent",
    containerBorder: "none",
    containerShadow: "none",
    containerRadius: "12px",
    backdropFilter: "none",
    overlayBg: "transparent",
    textPrimary: "#FFFFFF",
    textSecondary: "rgba(255,255,255,0.90)",
    textMuted: "rgba(255,255,255,0.70)",
    textShadow: "1px 1px 4px rgba(0,0,0,0.9), 0 0 8px rgba(0,0,0,0.5)",
    fontFamily: fontMap.System,
    progressTrackBg: "rgba(255,255,255,0.20)",
    progressFillBg: "#FFFFFF",
    showArtworkBlur: false,
  },
  "Glass (Light)": {
    containerBg: "rgba(255,255,255,0.15)",
    containerBorder: "1px solid rgba(255,255,255,0.20)",
    containerShadow: "0 8px 32px rgba(0,0,0,0.08)",
    containerRadius: "16px",
    backdropFilter: "blur(24px)",
    overlayBg: "transparent",
    textPrimary: "#1D1D1F",
    textSecondary: "#3F3F46",
    textMuted: "#71717A",
    textShadow: "none",
    fontFamily: fontMap.System,
    progressTrackBg: "rgba(0,0,0,0.08)",
    progressFillBg: "#007AFF",
    showArtworkBlur: false,
  },
  "Glass (Dark)": {
    containerBg: "rgba(0,0,0,0.30)",
    containerBorder: "1px solid rgba(255,255,255,0.10)",
    containerShadow: "0 8px 32px rgba(0,0,0,0.20)",
    containerRadius: "16px",
    backdropFilter: "blur(24px)",
    overlayBg: "transparent",
    textPrimary: "#F5F5F7",
    textSecondary: "rgba(245,245,247,0.80)",
    textMuted: "rgba(245,245,247,0.50)",
    textShadow: "none",
    fontFamily: fontMap.System,
    progressTrackBg: "rgba(255,255,255,0.10)",
    progressFillBg: "#007AFF",
    showArtworkBlur: false,
  },
  Neon: {
    containerBg: "rgba(10,10,30,0.85)",
    containerBorder: "1px solid #00FFAA",
    containerShadow: "0 0 20px rgba(0,255,170,0.30), 0 0 60px rgba(0,255,170,0.10)",
    containerRadius: "12px",
    backdropFilter: "none",
    overlayBg: "transparent",
    textPrimary: "#00FFAA",
    textSecondary: "#00E5FF",
    textMuted: "rgba(0,255,170,0.50)",
    textShadow: "0 0 8px rgba(0,255,170,0.50)",
    fontFamily: fontMap.Monospaced,
    progressTrackBg: "rgba(0,255,170,0.15)",
    progressFillBg: "linear-gradient(90deg, #00FFAA, #00E5FF)",
    showArtworkBlur: false,
  },
  Techy: {
    containerBg: "rgba(15,23,42,0.90)",
    containerBorder: "1px solid rgba(56,189,248,0.30)",
    containerShadow: "0 4px 16px rgba(0,0,0,0.40)",
    containerRadius: "8px",
    backdropFilter: "none",
    overlayBg: "transparent",
    textPrimary: "#E2E8F0",
    textSecondary: "#94A3B8",
    textMuted: "#64748B",
    textShadow: "none",
    fontFamily: fontMap.Monospaced,
    progressTrackBg: "rgba(56,189,248,0.15)",
    progressFillBg: "#38BDF8",
    showArtworkBlur: false,
  },
};

// MARK: - Layout Dimensions

export const layoutDimensions: Record<string, LayoutDimensions> = {
  Horizontal: { maxWidth: 500, height: 100 },
  Vertical: { maxWidth: 220, height: 280 },
  Compact: { maxWidth: 350, height: 56 },
};

// MARK: - Default Config

export const defaultWidgetConfig: WidgetConfigData = {
  theme: "Default",
  layout: "Horizontal",
  textColor: "#FFFFFF",
  backgroundColor: "#1A1A2E",
  fontFamily: "System",
};

// MARK: - Resolver

export function resolveTheme(config: WidgetConfigData): ResolvedThemeStyles {
  const preset = themePresets[config.theme] ?? themePresets.Default;
  const resolved = { ...preset };

  // Font always comes from the config setting
  resolved.fontFamily = fontMap[config.fontFamily] ?? fontMap.System;

  // For Default theme, allow custom text/background color overrides
  if (config.theme === "Default") {
    if (config.textColor && config.textColor !== "#FFFFFF") {
      resolved.textPrimary = config.textColor;
      resolved.textSecondary = config.textColor;
      resolved.progressFillBg = config.textColor;
    }
    if (config.backgroundColor && config.backgroundColor !== "#1A1A2E") {
      resolved.overlayBg = config.backgroundColor;
    }
  }

  return resolved;
}
