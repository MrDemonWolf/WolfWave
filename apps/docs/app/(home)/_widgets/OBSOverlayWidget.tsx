"use client";

import { useState } from "react";
import { AlbumArt } from "./AlbumArt";
import { formatTime } from "./sample-tracks";
import { useCyclingTrack } from "./useCyclingTrack";
import {
  WIDGET_THEMES,
  WIDGET_LAYOUTS,
  USER_THEMES,
  DEFAULT_THEME,
  DEFAULT_LAYOUT,
  type WidgetThemeName,
  type WidgetLayoutName,
} from "./widget-themes.generated";

/**
 * Theme + layout data comes from `widget-themes.generated.ts`, which the
 * design-token generator emits from `design-system/tokens.json`. That keeps
 * this preview in lockstep with the native app's themes and its shipped
 * default (Default / Horizontal) instead of a hand-copied dict that drifts.
 */
type ThemeName = WidgetThemeName;
type LayoutName = WidgetLayoutName;
type ThemeVals = (typeof WIDGET_THEMES)[ThemeName];

const THEMES: ThemeName[] = USER_THEMES;
const LAYOUTS = Object.keys(WIDGET_LAYOUTS) as LayoutName[];

/**
 * Recreation of the live WolfWave OBS browser-source overlay.
 *
 * The aesthetic and theme tokens come from
 * `apps/native/WolfWave/Resources/widget.html` +
 * `widget-tokens.generated.js`. Visitor can switch layouts (Horizontal /
 * Vertical / Compact) and themes (WolfWave / Glass / Neon / Dark /
 * Light) right on the marketing page, selling the widget's flexibility
 * better than any static screenshot could.
 */
export function OBSOverlayWidget({ controls = true }: { controls?: boolean } = {}) {
  const [theme, setTheme] = useState<ThemeName>(DEFAULT_THEME);
  const [layout, setLayout] = useState<LayoutName>(DEFAULT_LAYOUT);

  // Hero usage: no theme/layout switcher, render only the default overlay card.
  if (!controls) {
    return (
      <div style={{ width: "100%" }}>
        <WidgetCard theme={WIDGET_THEMES[DEFAULT_THEME]} layout={DEFAULT_LAYOUT} />
      </div>
    );
  }

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
        <WidgetCard theme={WIDGET_THEMES[theme]} layout={layout} />
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
  theme: ThemeVals;
  layout: LayoutName;
}) {
  const { track, elapsedSec, progress, motionEnabled } = useCyclingTrack();

  const dims = WIDGET_LAYOUTS[layout];
  const scrim = theme.overlayBg && theme.overlayBg !== "transparent";

  const shell = {
    position: "relative" as const,
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
    width: "100%",
    maxWidth: dims.maxWidth,
    transition:
      "background 0.25s ease, border-color 0.25s ease, box-shadow 0.25s ease, border-radius 0.25s ease",
  };

  // Transparent themes (Default) read against the OBS scene, not a card.
  // Mirror widget.html: a blurred copy of the artwork fills the frame with a
  // dark scrim over it so the text stays legible. Marketing art is a CSS
  // gradient, so we blur the gradient itself.
  const bgLayers = (
    <>
      {theme.showArtworkBlur ? (
        <div
          aria-hidden="true"
          style={{
            position: "absolute",
            inset: 0,
            background: track.gradient,
            transform: "scale(1.4)",
            filter: "blur(22px)",
            transition: "background 0.4s ease",
          }}
        />
      ) : null}
      {scrim ? (
        <div
          aria-hidden="true"
          style={{ position: "absolute", inset: 0, background: theme.overlayBg }}
        />
      ) : null}
    </>
  );

  if (layout === "Compact") {
    return (
      <div
        role="group"
        aria-roledescription="OBS overlay demo"
        style={{ ...shell, height: dims.height }}
      >
        {bgLayers}
        <div
          style={{
            position: "relative",
            zIndex: 1,
            height: "100%",
            display: "flex",
            alignItems: "center",
            gap: 10,
            padding: "8px 12px",
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
      </div>
    );
  }

  if (layout === "Vertical") {
    return (
      <div role="group" aria-roledescription="OBS overlay demo" style={shell}>
        {bgLayers}
        <div
          style={{
            position: "relative",
            zIndex: 1,
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
            gap: 12,
            padding: 14,
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
      </div>
    );
  }

  // Horizontal (default)
  return (
    <div
      role="group"
      aria-roledescription="OBS overlay demo"
      style={{ ...shell, height: dims.height }}
    >
      {bgLayers}
      <div
        style={{
          position: "relative",
          zIndex: 1,
          height: "100%",
          display: "grid",
          gridTemplateColumns: "80px 1fr",
          gap: 12,
          alignItems: "center",
          padding: 10,
        }}
      >
        <AlbumArt
          gradient={track.gradient}
          glyph={track.glyph}
          size={80}
          radius={8}
        />
        <div
          style={{ minWidth: 0, display: "flex", flexDirection: "column", gap: 6 }}
        >
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
  theme: ThemeVals;
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
