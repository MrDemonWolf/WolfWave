/*
 * WolfWave Design System — GENERATED FILE. Do not edit by hand.
 * Source: design-system/tokens.json
 * Run `bun run tokens` to regenerate.
 */

export const tokens = {
  "$schema": "./tokens.schema.json",
  "meta": {
    "name": "WolfWave Design System",
    "version": "1.0.0",
    "description": "Canonical design tokens for WolfWave. Source of truth — do not edit generated files."
  },
  "color": {
    "brand": {
      "50": "#F0F7FF",
      "100": "#D9ECFF",
      "200": "#B0D6FF",
      "300": "#7FB8FF",
      "400": "#4A9CFF",
      "500": "#0A84FF",
      "600": "#0066CC",
      "700": "#004E9F",
      "800": "#003A78",
      "900": "#002551"
    },
    "brandDark": {
      "500": "#0A84FF",
      "600": "#409CFF"
    },
    "semantic": {
      "success": "#34C759",
      "warning": "#FF9F0A",
      "error": "#FF453A",
      "info": "#0A84FF"
    },
    "surface": {
      "light": {
        "base": "#FFFFFF",
        "surface": "#F5F5F7",
        "elev": "#FBFBFD",
        "hairline": "#D2D2D7"
      },
      "dark": {
        "base": "#000000",
        "surface": "#1C1C1E",
        "elev": "#0A0A0C",
        "hairline": "#2C2C2E"
      }
    },
    "text": {
      "light": {
        "primary": "#1D1D1F",
        "secondary": "#6E6E73",
        "muted": "#A1A1A6"
      },
      "dark": {
        "primary": "#F5F5F7",
        "secondary": "#A1A1A6",
        "muted": "#6E6E73"
      }
    },
    "partner": {
      "twitch": "#9146FF",
      "discord": "#5865F2",
      "appleMusicStart": "#FF5D8B",
      "appleMusicEnd": "#FA233B",
      "obsStart": "#2C2C2E",
      "obsEnd": "#1A1A1C"
    }
  },
  "font": {
    "family": {
      "display": "Unbounded, -apple-system, BlinkMacSystemFont, system-ui, sans-serif",
      "sans": "\"Instrument Sans\", -apple-system, BlinkMacSystemFont, system-ui, sans-serif",
      "serif": "\"Instrument Serif\", ui-serif, Georgia, serif",
      "mono": "\"JetBrains Mono\", ui-monospace, \"SF Mono\", Menlo, monospace",
      "systemAppleDisplay": "-apple-system, BlinkMacSystemFont, \"SF Pro Display\", system-ui, sans-serif"
    },
    "size": {
      "9": 9,
      "15": 15,
      "16": 16,
      "18": 18,
      "24": 24,
      "26": 26,
      "28": 28,
      "36": 36,
      "xs": 10,
      "sm": 11,
      "body": 12,
      "base": 13,
      "md": 14,
      "lg": 17,
      "xl": 20,
      "2xl": 22
    },
    "weight": {
      "regular": 400,
      "medium": 500,
      "semibold": 600,
      "bold": 700
    }
  },
  "space": {
    "0": 2,
    "1": 4,
    "2": 8,
    "3": 10,
    "4": 12,
    "5": 14,
    "6": 16,
    "7": 20,
    "8": 24,
    "9": 28,
    "10": 32,
    "11": 44
  },
  "radius": {
    "xs": 4,
    "sm": 6,
    "md": 8,
    "lg": 10,
    "xl": 14,
    "2xl": 16,
    "pill": 9999
  },
  "motion": {
    "duration": {
      "fast": 150,
      "base": 220,
      "slow": 320
    },
    "easing": {
      "standard": "cubic-bezier(0.4, 0.0, 0.2, 1)",
      "emphasized": "cubic-bezier(0.2, 0.0, 0, 1)"
    }
  },
  "shadow": {
    "xs": "0 1px 2px rgba(0,0,0,0.08)",
    "sm": "0 2px 4px rgba(0,0,0,0.08)",
    "md": "0 4px 12px rgba(0,0,0,0.10)",
    "lg": "0 8px 32px rgba(0,0,0,0.20)",
    "glow": "0 0 20px rgba(10,132,255,0.30)"
  },
  "dimension": {
    "settings": {
      "minWidth": 820,
      "minHeight": 600,
      "idealWidth": 1180,
      "idealHeight": 740,
      "maxContentWidth": 720,
      "contentPaddingH": 28,
      "contentPaddingV": 22,
      "sectionSpacing": 24,
      "cardPadding": 16,
      "cardCornerRadius": 14
    },
    "onboarding": {
      "windowWidth": 600,
      "windowHeight": 480,
      "primaryButtonHeight": 32,
      "primaryButtonMinWidth": 200,
      "navButtonMinWidth": 80,
      "stepContentMinHeight": 220,
      "brandTileSize": 56,
      "brandTileRadius": 14,
      "primaryButtonRadius": 8
    }
  },
  "widget": {
    "layouts": {
      "Horizontal": {
        "maxWidth": 500,
        "height": 100
      },
      "Vertical": {
        "maxWidth": 220,
        "height": 280
      },
      "Compact": {
        "maxWidth": 350,
        "height": 56
      }
    },
    "themes": {
      "Default": {
        "containerBg": "transparent",
        "containerBorder": "none",
        "containerShadow": "0 0 4px rgba(0,0,0,1)",
        "containerRadius": "12px",
        "backdropFilter": "none",
        "overlayBg": "rgba(0,0,0,0.50)",
        "textPrimary": "#FFFFFF",
        "textSecondary": "rgba(255,255,255,0.90)",
        "textMuted": "rgba(255,255,255,0.70)",
        "textShadow": "2px 2px 2px rgb(0 0 0)",
        "progressTrackBg": "rgba(255,255,255,0.20)",
        "progressFillBg": "#FFFFFF",
        "showArtworkBlur": true
      },
      "Dark": {
        "containerBg": "#0D0D0D",
        "containerBorder": "1px solid rgba(255,255,255,0.08)",
        "containerShadow": "0 4px 12px rgba(0,0,0,0.6)",
        "containerRadius": "12px",
        "backdropFilter": "none",
        "overlayBg": "transparent",
        "textPrimary": "#E4E4E7",
        "textSecondary": "#A1A1AA",
        "textMuted": "#71717A",
        "textShadow": "none",
        "progressTrackBg": "rgba(255,255,255,0.08)",
        "progressFillBg": "#A78BFA",
        "showArtworkBlur": false
      },
      "Light": {
        "containerBg": "rgba(255,255,255,0.92)",
        "containerBorder": "1px solid rgba(0,0,0,0.08)",
        "containerShadow": "0 4px 16px rgba(0,0,0,0.10)",
        "containerRadius": "12px",
        "backdropFilter": "blur(16px)",
        "overlayBg": "transparent",
        "textPrimary": "#18181B",
        "textSecondary": "#3F3F46",
        "textMuted": "#71717A",
        "textShadow": "none",
        "progressTrackBg": "rgba(0,0,0,0.08)",
        "progressFillBg": "#3B82F6",
        "showArtworkBlur": false
      },
      "Glass": {
        "containerBg": "rgba(0,0,0,0.30)",
        "containerBorder": "1px solid rgba(255,255,255,0.10)",
        "containerShadow": "0 8px 32px rgba(0,0,0,0.20)",
        "containerRadius": "16px",
        "backdropFilter": "blur(24px)",
        "overlayBg": "transparent",
        "textPrimary": "#F5F5F7",
        "textSecondary": "rgba(245,245,247,0.80)",
        "textMuted": "rgba(245,245,247,0.50)",
        "textShadow": "none",
        "progressTrackBg": "rgba(255,255,255,0.10)",
        "progressFillBg": "#007AFF",
        "showArtworkBlur": false
      },
      "Neon": {
        "containerBg": "rgba(10,10,30,0.85)",
        "containerBorder": "1px solid #00FFAA",
        "containerShadow": "0 0 20px rgba(0,255,170,0.30), 0 0 60px rgba(0,255,170,0.10)",
        "containerRadius": "12px",
        "backdropFilter": "none",
        "overlayBg": "transparent",
        "textPrimary": "#00FFAA",
        "textSecondary": "#00E5FF",
        "textMuted": "rgba(0,255,170,0.50)",
        "textShadow": "0 0 8px rgba(0,255,170,0.50)",
        "progressTrackBg": "rgba(0,255,170,0.15)",
        "progressFillBg": "linear-gradient(90deg, #00FFAA, #00E5FF)",
        "showArtworkBlur": false
      },
      "WolfWave": {
        "containerBg": "rgba(28,28,30,0.92)",
        "containerBorder": "1px solid rgba(10,132,255,0.40)",
        "containerShadow": "0 0 20px rgba(10,132,255,0.30), 0 8px 32px rgba(0,0,0,0.40)",
        "containerRadius": "14px",
        "backdropFilter": "blur(20px)",
        "overlayBg": "transparent",
        "textPrimary": "#F5F5F7",
        "textSecondary": "#A1A1A6",
        "textMuted": "#6E6E73",
        "textShadow": "none",
        "progressTrackBg": "rgba(10,132,255,0.15)",
        "progressFillBg": "linear-gradient(90deg, #0A84FF, #409CFF)",
        "showArtworkBlur": true
      }
    }
  }
} as const;

export type Tokens = typeof tokens;
