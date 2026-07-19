/*
 * WolfWave Design System. GENERATED FILE. Do not edit by hand.
 * Source: design-system/tokens.json
 * Run `bun run tokens` to regenerate.
 */

export const WIDGET_THEMES = {
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
    "containerBg": "rgba(0,0,0,0.50)",
    "containerBorder": "1px solid rgba(255,255,255,0.10)",
    "containerShadow": "0 8px 32px rgba(0,0,0,0.20)",
    "containerRadius": "16px",
    "backdropFilter": "blur(24px)",
    "overlayBg": "transparent",
    "textPrimary": "#F5F5F7",
    "textSecondary": "rgba(245,245,247,0.80)",
    "textMuted": "rgba(245,245,247,0.60)",
    "textShadow": "0 1px 3px rgba(0,0,0,0.60)",
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
    "hidden": true,
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
} as const;

export const WIDGET_LAYOUTS = {
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
  },
  "Vinyl": {
    "maxWidth": 260,
    "height": 300
  },
  "Classic": {
    "maxWidth": 440,
    "height": 112
  }
} as const;

export type WidgetThemeName = keyof typeof WIDGET_THEMES;
export type WidgetLayoutName = keyof typeof WIDGET_LAYOUTS;

/** Themes shown in the picker (excludes `hidden` themes). */
export const USER_THEMES: WidgetThemeName[] = ["Default","Dark","Light","Glass","Neon"];

export const DEFAULT_THEME: WidgetThemeName = "Default";
export const DEFAULT_LAYOUT: WidgetLayoutName = "Horizontal";
