"use client";

import { useState } from "react";
import { AlbumArt } from "./AlbumArt";
import { formatTime } from "./sample-tracks";
import { useCyclingTrack } from "./useCyclingTrack";

/**
 * Theme dict ported verbatim from
 * `apps/native/WolfWave/Resources/widget-tokens.generated.js` so the
 * preview matches the real OBS browser-source output 1:1.
 */
const WW_THEMES = {
  WolfWave: {
    containerBg: "rgba(28,28,30,0.92)",
    containerBorder: "1px solid rgba(10,132,255,0.40)",
    containerShadow:
      "0 0 20px rgba(10,132,255,0.30), 0 8px 32px rgba(0,0,0,0.40)",
    containerRadius: "14px",
    backdropFilter: "blur(20px)",
    textPrimary: "#F5F5F7",
    textSecondary: "#A1A1A6",
    textShadow: "none",
    progressTrackBg: "rgba(10,132,255,0.15)",
    progressFillBg: "linear-gradient(90deg, #0A84FF, #409CFF)",
  },
  Glass: {
    containerBg: "rgba(0,0,0,0.30)",
    containerBorder: "1px solid rgba(255,255,255,0.10)",
    containerShadow: "0 8px 32px rgba(0,0,0,0.20)",
    containerRadius: "16px",
    backdropFilter: "blur(24px)",
    textPrimary: "#F5F5F7",
    textSecondary: "rgba(245,245,247,0.80)",
    textShadow: "none",
    progressTrackBg: "rgba(255,255,255,0.10)",
    progressFillBg: "#007AFF",
  },
  Neon: {
    containerBg: "rgba(10,10,30,0.85)",
    containerBorder: "1px solid #00FFAA",
    containerShadow:
      "0 0 20px rgba(0,255,170,0.30), 0 0 60px rgba(0,255,170,0.10)",
    containerRadius: "12px",
    backdropFilter: "none",
    textPrimary: "#00FFAA",
    textSecondary: "#00E5FF",
    textShadow: "0 0 8px rgba(0,255,170,0.50)",
    progressTrackBg: "rgba(0,255,170,0.15)",
    progressFillBg: "linear-gradient(90deg, #00FFAA, #00E5FF)",
  },
  Dark: {
    containerBg: "#0D0D0D",
    containerBorder: "1px solid rgba(255,255,255,0.08)",
    containerShadow: "0 4px 12px rgba(0,0,0,0.6)",
    containerRadius: "12px",
    backdropFilter: "none",
    textPrimary: "#E4E4E7",
    textSecondary: "#A1A1AA",
    textShadow: "none",
    progressTrackBg: "rgba(255,255,255,0.08)",
    progressFillBg: "#A78BFA",
  },
  Light: {
    containerBg: "rgba(255,255,255,0.92)",
    containerBorder: "1px solid rgba(0,0,0,0.08)",
    containerShadow: "0 4px 16px rgba(0,0,0,0.10)",
    containerRadius: "12px",
    backdropFilter: "blur(16px)",
    textPrimary: "#18181B",
    textSecondary: "#3F3F46",
    textShadow: "none",
    progressTrackBg: "rgba(0,0,0,0.08)",
    progressFillBg: "#3B82F6",
  },
} as const;

type ThemeName = keyof typeof WW_THEMES;
type LayoutName = "Horizontal" | "Vertical" | "Compact";

const THEMES: ThemeName[] = ["WolfWave", "Glass", "Neon", "Dark", "Light"];
const LAYOUTS: LayoutName[] = ["Horizontal", "Vertical", "Compact"];

/**
 * Recreation of the live WolfWave OBS browser-source overlay.
 *
 * The aesthetic and theme tokens come from
 * `apps/native/WolfWave/Resources/widget.html` +
 * `widget-tokens.generated.js`. Visitor can switch layouts (Horizontal /
 * Vertical / Compact) and themes (WolfWave / Glass / Neon / Dark /
 * Light) right on the marketing page — selling the widget's flexibility
 * better than any static screenshot could.
 */
export function OBSOverlayWidget() {
  const [theme, setTheme] = useState<ThemeName>("WolfWave");
  const [layout, setLayout] = useState<LayoutName>("Horizontal");

  return (
    <div style={{ width: "100%" }}>
      <ControlBar
        theme={theme}
        layout={layout}
        onThemeChange={setTheme}
        onLayoutChange={setLayout}
      />
      <div
        style={{
          minHeight: layout === "Vertical" ? 320 : 160,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          padding: 16,
        }}
      >
        <WidgetCard theme={WW_THEMES[theme]} layout={layout} />
      </div>
      <span className="sr-only">
        Interactive widget preview cycling fictional sample tracks. Use the
        layout and theme controls above to preview every combination.
      </span>
    </div>
  );
}

function WidgetCard({
  theme,
  layout,
}: {
  theme: (typeof WW_THEMES)[ThemeName];
  layout: LayoutName;
}) {
  const { track, elapsedSec, progress, motionEnabled } = useCyclingTrack();

  const base = {
    background: theme.containerBg,
    border: theme.containerBorder,
    boxShadow: theme.containerShadow,
    borderRadius: theme.containerRadius,
    backdropFilter: theme.backdropFilter,
    WebkitBackdropFilter: theme.backdropFilter,
    color: theme.textPrimary,
    textShadow: theme.textShadow,
    fontFamily:
      "'Instrument Sans', var(--ds-font-family-sans), system-ui, sans-serif",
    overflow: "hidden" as const,
    transition:
      "background 0.25s ease, border-color 0.25s ease, box-shadow 0.25s ease, border-radius 0.25s ease",
  };

  if (layout === "Compact") {
    return (
      <div
        role="group"
        aria-roledescription="OBS overlay demo"
        style={{
          ...base,
          width: "100%",
          maxWidth: 350,
          height: 56,
          padding: "8px 12px",
          display: "flex",
          alignItems: "center",
          gap: 10,
        }}
      >
        <AlbumArt
          gradient={track.gradient}
          glyph={track.glyph}
          size={40}
          radius={6}
        />
        <div style={{ minWidth: 0, flex: 1 }}>
          <div
            style={{
              fontSize: 13,
              fontWeight: 600,
              lineHeight: 1.2,
              whiteSpace: "nowrap",
              overflow: "hidden",
              textOverflow: "ellipsis",
            }}
          >
            {track.title}
          </div>
          <div
            style={{
              fontSize: 11,
              color: theme.textSecondary,
              marginTop: 1,
              whiteSpace: "nowrap",
              overflow: "hidden",
              textOverflow: "ellipsis",
            }}
          >
            {track.artist}
          </div>
        </div>
      </div>
    );
  }

  if (layout === "Vertical") {
    return (
      <div
        role="group"
        aria-roledescription="OBS overlay demo"
        style={{
          ...base,
          width: "100%",
          maxWidth: 220,
          padding: 14,
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          gap: 12,
        }}
      >
        <AlbumArt
          gradient={track.gradient}
          glyph={track.glyph}
          size={184}
          radius={10}
        />
        <div style={{ width: "100%", textAlign: "center" }}>
          <div
            style={{
              fontSize: 14,
              fontWeight: 600,
              lineHeight: 1.25,
              overflow: "hidden",
              textOverflow: "ellipsis",
              whiteSpace: "nowrap",
            }}
          >
            {track.title}
          </div>
          <div
            style={{
              fontSize: 12,
              color: theme.textSecondary,
              marginTop: 4,
              overflow: "hidden",
              textOverflow: "ellipsis",
              whiteSpace: "nowrap",
            }}
          >
            {track.artist}
          </div>
        </div>
        <ProgressBar
          theme={theme}
          elapsedSec={elapsedSec}
          durationSec={track.durationSec}
          progress={progress}
          motionEnabled={motionEnabled}
          showCounters
        />
      </div>
    );
  }

  // Horizontal (default)
  return (
    <div
      role="group"
      aria-roledescription="OBS overlay demo"
      style={{
        ...base,
        width: "100%",
        maxWidth: 500,
        height: 100,
        padding: 10,
        display: "grid",
        gridTemplateColumns: "80px 1fr",
        gap: 12,
        alignItems: "center",
      }}
    >
      <AlbumArt
        gradient={track.gradient}
        glyph={track.glyph}
        size={80}
        radius={8}
      />
      <div style={{ minWidth: 0, display: "flex", flexDirection: "column", gap: 6 }}>
        <div
          style={{
            fontSize: 15,
            fontWeight: 600,
            lineHeight: 1.2,
            whiteSpace: "nowrap",
            overflow: "hidden",
            textOverflow: "ellipsis",
          }}
        >
          {track.title}
        </div>
        <div
          style={{
            fontSize: 12,
            color: theme.textSecondary,
            whiteSpace: "nowrap",
            overflow: "hidden",
            textOverflow: "ellipsis",
          }}
        >
          {track.artist}
        </div>
        <ProgressBar
          theme={theme}
          elapsedSec={elapsedSec}
          durationSec={track.durationSec}
          progress={progress}
          motionEnabled={motionEnabled}
          showCounters
        />
      </div>
    </div>
  );
}

function ProgressBar({
  theme,
  elapsedSec,
  durationSec,
  progress,
  motionEnabled,
  showCounters,
}: {
  theme: (typeof WW_THEMES)[ThemeName];
  elapsedSec: number;
  durationSec: number;
  progress: number;
  motionEnabled: boolean;
  showCounters?: boolean;
}) {
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 4, width: "100%" }}>
      <div
        role="progressbar"
        aria-label="Track progress"
        aria-valuemin={0}
        aria-valuemax={durationSec}
        aria-valuenow={Math.round(elapsedSec)}
        style={{
          position: "relative",
          height: 4,
          background: theme.progressTrackBg,
          borderRadius: 9999,
          overflow: "hidden",
        }}
      >
        <div
          style={{
            position: "absolute",
            inset: 0,
            width: `${progress * 100}%`,
            background: theme.progressFillBg,
            borderRadius: 9999,
            transition: motionEnabled ? "width 100ms linear" : "none",
          }}
        />
      </div>
      {showCounters && (
        <div
          style={{
            display: "flex",
            justifyContent: "space-between",
            fontSize: 10,
            fontVariantNumeric: "tabular-nums",
            color: theme.textSecondary,
          }}
        >
          <span>{formatTime(elapsedSec)}</span>
          <span>{formatTime(durationSec)}</span>
        </div>
      )}
    </div>
  );
}

function ControlBar({
  theme,
  layout,
  onThemeChange,
  onLayoutChange,
}: {
  theme: ThemeName;
  layout: LayoutName;
  onThemeChange: (t: ThemeName) => void;
  onLayoutChange: (l: LayoutName) => void;
}) {
  return (
    <div
      role="group"
      aria-label="Widget preview controls"
      style={{
        display: "flex",
        alignItems: "center",
        justifyContent: "space-between",
        gap: 12,
        padding: "8px 12px 12px 12px",
        flexWrap: "wrap",
      }}
    >
      <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
        <span
          style={{
            fontSize: 11,
            textTransform: "uppercase",
            letterSpacing: "0.06em",
            color: "var(--txt-2)",
            fontWeight: 600,
          }}
        >
          Layout
        </span>
        <div
          style={{
            display: "inline-flex",
            padding: 2,
            borderRadius: 9999,
            border: "1px solid var(--hairline)",
            background: "var(--bg-surface)",
          }}
        >
          {LAYOUTS.map((l) => {
            const active = l === layout;
            return (
              <button
                key={l}
                type="button"
                onClick={() => onLayoutChange(l)}
                aria-pressed={active}
                style={{
                  padding: "4px 10px",
                  fontSize: 11,
                  fontWeight: 600,
                  letterSpacing: "0.02em",
                  color: active ? "#FFFFFF" : "var(--txt-2)",
                  background: active ? "var(--brand-500)" : "transparent",
                  border: "none",
                  borderRadius: 9999,
                  cursor: "pointer",
                  transition: "background 0.15s ease, color 0.15s ease",
                }}
              >
                {l}
              </button>
            );
          })}
        </div>
      </div>

      <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
        <label
          htmlFor="ww-overlay-theme"
          style={{
            fontSize: 11,
            textTransform: "uppercase",
            letterSpacing: "0.06em",
            color: "var(--txt-2)",
            fontWeight: 600,
          }}
        >
          Theme
        </label>
        <select
          id="ww-overlay-theme"
          value={theme}
          onChange={(e) => onThemeChange(e.target.value as ThemeName)}
          style={{
            padding: "5px 10px",
            fontSize: 12,
            fontWeight: 500,
            color: "var(--txt-1)",
            background: "var(--bg-surface)",
            border: "1px solid var(--hairline)",
            borderRadius: 8,
            cursor: "pointer",
          }}
        >
          {THEMES.map((t) => (
            <option key={t} value={t}>
              {t}
            </option>
          ))}
        </select>
      </div>
    </div>
  );
}
